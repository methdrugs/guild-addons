-- Bokföring's mailbox (Zach 9/11). Two things:
--
-- His own sales, read from the auction house's "sold" mails whenever the
-- mailbox is open: proof of what sells, unlike the market estimate from
-- scans. A mail has no number of its own, so each is known by its subject,
-- money, item and the hour it expires, and counted once.
--
-- The gold coin in the mailbox's corner (Collect sales) takes the coin from every
-- sold mail, one at a time, and leaves every other mail and all items
-- where they are. A button he clicks, never on its own.

local _, ns = ...

-- 90 days for the history (Zach 9/11).
local KEEP_DAYS = 90

local function Seen(subject, money, itemName, daysLeft)
	local expires = math.floor((time() + (daysLeft or 0) * 86400) / 3600)
	return string.format("%s|%d|%s|%d", subject or "", money or 0, itemName or "", expires)
end

-- The game's "Auction successful: %s" as a pattern for the item name.
local function SoldPattern()
	local text = AUCTION_SOLD_MAIL_SUBJECT or "Auction successful: %s"
	return "^" .. text:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
end

-- The sold mails in the inbox: index, item name, count and money. Forever's
-- sold mail had no invoice (09/11, /bok test: kind none), so the subject
-- counts too.
local function SoldMails()
	local out = {}
	if not GetInboxNumItems or not GetInboxHeaderInfo then return out end
	local pattern = SoldPattern()
	for i = 1, GetInboxNumItems() do
		local _, _, _, subject, money, _, daysLeft, itemCount = GetInboxHeaderInfo(i)
		local invoiceType, itemName, count, deposit
		if GetInboxInvoiceInfo then
			local info = { GetInboxInvoiceInfo(i) }
			invoiceType, itemName, count, deposit = info[1], info[2], info[11], info[6]
		end
		local fromSubject = subject and subject:match(pattern)
		if not invoiceType and fromSubject then invoiceType, itemName = "seller", fromSubject end
		if invoiceType == "seller" and money and money > 0 and (itemCount or 0) == 0 then
			-- The deposit back is his own money; the rest pays guild tax
			-- (Tungan Lingonsson 11/11).
			table.insert(out, { index = i, item = itemName, count = count or 1, money = (money - (deposit or 0)) * (1 - ns.TaxRate()), gross = money,
				key = Seen(subject, money, itemName, daysLeft) })
		end
	end
	return out
end

-- Auctions that came back (Zach 10/11): expired or cancelled, the item
-- attached; for On AH in the history.
local function Pattern(text)
	return "^" .. text:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
end
local function ReturnMails()
	local out = {}
	if not GetInboxNumItems or not GetInboxHeaderInfo then return out end
	local patterns = { Pattern(AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s"), Pattern(AUCTION_REMOVED_MAIL_SUBJECT or "Auction cancelled: %s") }
	for i = 1, GetInboxNumItems() do
		local _, _, _, subject, _, _, daysLeft, itemCount = GetInboxHeaderInfo(i)
		local name
		for _, p in ipairs(patterns) do name = name or (subject and subject:match(p)) end
		if name and (itemCount or 0) > 0 then
			local count = GetInboxItem and select(4, GetInboxItem(i, 1)) or 1
			table.insert(out, { item = name, count = count or 1, money = 0, key = Seen(subject, count, name, daysLeft) })
		end
	end
	return out
end

-- Note every sold (and returned) mail not seen before; drop what is older
-- than 90 days. Mails of the same item at the same price in the same hour
-- look alike (Zach 10/11: 82 Deadly Blunderbuss crafted, 11 counted sold,
-- since each such batch was taken for one sale), so the inbox's count of
-- each kind is kept: more than before is new; fewer within one visit is
-- mail taken, which makes room for the next ones that look the same.
local visit = {}
local function Note(mails, store, counts, now)
	local db = ns.db
	local here, first = {}, {}
	for _, m in ipairs(mails) do
		if m.item then
			here[m.key] = (here[m.key] or 0) + 1
			first[m.key] = first[m.key] or m
		end
	end
	for key, n in pairs(here) do
		-- Seen by an older version: one of them.
		local had = db.salesSeenN[key] or (db.salesSeen[key] and 1 or 0)
		local m = first[key]
		for _ = had + 1, n do
			store[m.item] = store[m.item] or {}
			table.insert(store[m.item], { at = now, count = m.count, money = m.money, taxed = true })
		end
		db.salesSeenN[key] = math.max(had, n)
		db.salesSeen[key] = db.salesSeen[key] or now
		counts[key] = n
	end
end

local function Drop(store, now)
	for item, list in pairs(store) do
		for i = #list, 1, -1 do
			if now - list[i].at > KEEP_DAYS * 86400 then table.remove(list, i) end
		end
		if #list == 0 then store[item] = nil end
	end
end

local function ReadSales()
	local db = ns.db
	db.sales = db.sales or {}
	db.returns = db.returns or {}
	db.salesSeen = db.salesSeen or {}
	db.salesSeenN = db.salesSeenN or {}
	local now, counts = time(), {}
	local sold, back = SoldMails(), ReturnMails()
	-- Taken since the last look in this visit.
	local here = {}
	for _, m in ipairs(sold) do here[m.key] = (here[m.key] or 0) + 1 end
	for _, m in ipairs(back) do here[m.key] = (here[m.key] or 0) + 1 end
	for key, before in pairs(visit) do
		local taken = before - (here[key] or 0)
		if taken > 0 and db.salesSeenN[key] then db.salesSeenN[key] = math.max(0, db.salesSeenN[key] - taken) end
	end
	Note(sold, db.sales, counts, now)
	Note(back, db.returns, counts, now)
	visit = counts
	Drop(db.sales, now)
	Drop(db.returns, now)
	for key, at in pairs(db.salesSeen) do
		if now - at > (KEEP_DAYS + 31) * 86400 then
			db.salesSeen[key] = nil
			db.salesSeenN[key] = nil
		end
	end
end

-- His own sales of an item over the last days: count and money, or nil.
function ns.MySales(item, days)
	local name = ns.ItemName(item)
	local list = ns.db.sales and ns.db.sales[name]
	if not list then return end
	local since, count, money = time() - (days or 7) * 86400, 0, 0
	for _, s in ipairs(list) do
		if s.at >= since then count, money = count + s.count, money + s.money end
	end
	if count > 0 then return count, money end
end

-- Collect sales: the coin of one sold mail, then the next once the inbox
-- has caught up; from the bottom so the indexes still ahead do not move.
local collecting, taken
local function CollectNext()
	if not collecting then return end
	if not (MailFrame and MailFrame:IsShown()) then
		collecting = false
		return
	end
	ReadSales()
	local mails = SoldMails()
	local m = mails[#mails]
	if not m then
		collecting = false
		ns.Print(string.format("collected %s from sold auctions; other mail left as it was.", ns.Money(taken)))
		return
	end
	taken = taken + m.gross
	TakeInboxMoney(m.index)
	C_Timer.After(0.4, CollectNext)
end

local function Collect()
	if collecting then return end
	if #SoldMails() == 0 then
		ns.Print("no sold auctions in the mailbox.")
		return
	end
	collecting, taken = true, 0
	CollectNext()
end

-- A gold coin in the mailbox's top right corner (Zach 9/11), not a text button.
local button
local function ShowButton()
	if button or not MailFrame then return end
	-- On the inbox only, not Send Mail (Zach 10/11): it hides with that tab.
	button = CreateFrame("Button", nil, InboxFrame or MailFrame)
	button:SetSize(26, 26)
	-- Inside the mailbox, top right under the close button, in the dark band
	-- above the mail list (Zach 9/11, screenshot); on its left side it was
	-- off screen.
	-- 5 higher again (Zach 9/11, screenshot: still touching the list).
	button:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -12, -28)
	button:SetNormalTexture("Interface\\Icons\\INV_Misc_Coin_01")
	button:SetPushedTexture("Interface\\Icons\\INV_Misc_Coin_01")
	button:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	border:SetPoint("CENTER")
	border:SetSize(45, 45)
	-- A soft gold glow while sold auctions wait (Zach 9/11).
	local glow = button:CreateTexture(nil, "BACKGROUND")
	glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(1, 0.82, 0.2)
	glow:SetPoint("CENTER")
	glow:SetSize(52, 52)
	glow:Hide()
	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.3)
	fade:SetToAlpha(1)
	fade:SetDuration(0.9)
	fade:SetSmoothing("IN_OUT")
	button.glow, button.pulse = glow, pulse
	button:SetScript("OnClick", Collect)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Collect sales")
		GameTooltip:AddLine("Takes the coin from every sold auction mail. Items and all other mail stay in the mailbox.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Glow()
	if not button then return end
	if #SoldMails() > 0 then
		button.glow:Show()
		if not button.pulse:IsPlaying() then button.pulse:Play() end
	else
		button.pulse:Stop()
		button.glow:Hide()
	end
end

-- For /bok test: what the inbox holds, as Bokföring sees it.
function ns.MailTest()
	if not (MailFrame and MailFrame:IsShown()) then return "open the mailbox first" end
	local total = GetInboxNumItems and GetInboxNumItems() or 0
	local kinds = {}
	for i = 1, total do
		local kind = GetInboxInvoiceInfo and GetInboxInvoiceInfo(i) or "none"
		kinds[kind] = (kinds[kind] or 0) + 1
	end
	local parts = {}
	for kind, n in pairs(kinds) do table.insert(parts, kind .. " " .. n) end
	local subject = total > 0 and select(4, GetInboxHeaderInfo(1)) or nil
	return string.format("%d mails shown, %d sold auctions; invoice kinds: %s; first subject: %s", total, #SoldMails(), table.concat(parts, ", "), tostring(subject))
end

-- "A buyer has been found for your auction of ..." (Zach 9/11): the game
-- puts it in the main chat window only, whatever a window's System
-- Messages setting says. A copy goes to every other window showing System
-- Messages, with the price Bokföring expected for one. Caught as it is
-- written into the main window, whichever way it got there (09/11: a hook
-- on the game's "system message in primary" missed it), and without
-- anchors, since chat timestamps come first.
local function SoldNotice(text)
	-- In battlegrounds and instances chat text can be secret (Zach 9/11,
	-- Arathi Basin): reading it is an error, and no sale notice comes there.
	if issecretvalue and issecretvalue(text) then return end
	if type(text) ~= "string" or not ERR_AUCTION_SOLD_S then return end
	local pattern = ERR_AUCTION_SOLD_S:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.-)")
	local ok, item = pcall(string.match, text, pattern)
	if not ok or not item then return end
	ns.lastNotice = text
	local each = ns.ExpectedEach and ns.ExpectedEach(item)
	local copy = text .. (each and string.format(" |cffffd100Bokföring expected %s each.|r", ns.Money(each)) or "")
	local info = ChatTypeInfo and ChatTypeInfo.SYSTEM or { r = 1, g = 1, b = 0 }
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local chat = _G["ChatFrame" .. i]
		if chat and chat ~= DEFAULT_CHAT_FRAME and ChatFrame_ContainsMessageGroup and ChatFrame_ContainsMessageGroup(chat, "SYSTEM") then
			chat:AddMessage(copy, info.r, info.g, info.b)
		end
	end
end
if DEFAULT_CHAT_FRAME then hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", function(_, text) SoldNotice(text) end) end

-- For /bok test.
function ns.NoticeTest()
	local windows = {}
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local chat = _G["ChatFrame" .. i]
		if chat and chat ~= DEFAULT_CHAT_FRAME and ChatFrame_ContainsMessageGroup and ChatFrame_ContainsMessageGroup(chat, "SYSTEM") then
			table.insert(windows, (GetChatWindowInfo and GetChatWindowInfo(i)) or ("ChatFrame" .. i))
		end
	end
	return string.format("windows with System Messages: %s; last sold notice: %s",
		#windows > 0 and table.concat(windows, ", ") or "none besides the main one", ns.lastNotice or "none this session")
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
	if not ns.db then return end
	if event == "MAIL_CLOSED" then
		collecting = false
	elseif event == "MAIL_SHOW" then
		visit = {}
		ShowButton()
		ReadSales()
		Glow()
	else
		ReadSales()
		Glow()
	end
end)
