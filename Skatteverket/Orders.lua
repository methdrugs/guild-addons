-- Skatteverket, arbetsordrar (Zach 9/11): order a craft from a member
-- through Yrken. The order says how many, whose materials, how long the
-- one ordering can wait, and a note. A line in guild chat,
-- "@Namn du har en ny arbetsorder!", reaches the crafter on Discord too,
-- online or not, with what was ordered (Zach 9/11). Only for members with
-- the citizen rank or higher, both ends (Zach 9/11: a privilege for good,
-- honest members). The crafter accepts, declines with a reason, or marks it
-- done; the one ordering can cancel. An unanswered order runs out when the
-- wait is over. No prices: those are agreed in a whisper, and nothing here
-- moves gold. The minimap bolt shows a hammer while orders wait for you.
--
-- Whispers, hidden:
--   O;id;from;to;key;count;mats;until;stamp;state;reason;note
--        the whole order, sent to the other party and to the leader, who
--        keeps it for whoever is offline
--   D;id;state;reason;stamp     a new state: accepterad, klar, avböjd, avbruten
-- Guild channel:
--   X        at login: send me my orders; whoever holds some answers by whisper

local _, ns = ...

local DAY = 86400
local KEEP_DAYS = 14
local WAITS = { 1, 2, 3, 7 }
local REASONS = { "Har inte materialet", "För dyrt", "Inte nu" }
local STATE = { ny = "Ny", accepterad = "Accepterad", klar = "Klar", ["avböjd"] = "Avböjd", avbruten = "Avbruten", ["utgången"] = "Utgången" }
local OPEN = { ny = true, accepterad = true }
-- Whose materials (Zach 9/11): the crafter's, against a tip of a tenth of
-- what the reagents cost, so nobody orders without putting in their share.
local MATS = { e = "Beställaren skickar materialet", h = "Hantverkaren löser materialet, mot 10 % dricks" }
local TIP = 0.10

local function Orders()
	ns.db.orders = ns.db.orders or {}
	return ns.db.orders
end

local function Clean(text)
	return ((text or ""):gsub("[;|\n]", " ")):sub(1, 80)
end

-- Open orders past their wait are out of date, for everyone alike.
local function State(o)
	if OPEN[o.state] and ns.Now() > o["until"] then return "utgången" end
	return o.state
end

local function Pack(o)
	return table.concat({ "O", o.id, o.from, o.to, o.key, o.count, o.mats, o["until"], o.stamp, o.state, o.reason or "", Clean(o.note), o.tip or "" }, ";")
end

-- To the other party, and to the leader who keeps it for the offline.
local function Share(o, msg)
	local me = ns.Me()
	for _, target in ipairs({ o.from, o.to, ns.Leader() }) do
		if target and target ~= me then ns.SendTo(target, msg) end
	end
end

local function Changed()
	if ns.RefreshOrderBadge then ns.RefreshOrderBadge() end
	if ns.RefreshWindow then ns.RefreshWindow("yrken") end
end

-- Orders waiting for this character to act on: new or accepted, to them.
function ns.OrdersToDo()
	if ns.Locked() then return 0 end
	local me, n = ns.Me(), 0
	for _, o in pairs(Orders()) do
		if o.to == me and OPEN[State(o)] then n = n + 1 end
	end
	return n
end

local function RecipeName(key)
	return ns.RecipeName and ns.RecipeName(key) or key
end

-- Ordering --------------------------------------------------------------

-- What the reagents of count crafts cost on the auction house, from
-- Auctionator's prices where it is installed; nil when unknown.
local function ReagentCost(key, count)
	local d = ns.RecipeData and ns.RecipeData(key)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not d or not d.reagents or #d.reagents == 0 or not (api and api.GetAuctionPriceByItemID) then return end
	local total = 0
	for _, r in ipairs(d.reagents) do
		local ok, price = pcall(api.GetAuctionPriceByItemID, "Skatteverket", r.itemID)
		if not ok or not price then return end
		total = total + price * r.count * count
	end
	return total
end

function ns.PlaceOrder(to, key, count, mats, days, note)
	local me = ns.Me()
	if not me or not to or to == me or ns.Locked() then return end
	if not ns.IsCitizen(to) then
		ns.Print(to .. " är inte " .. ns.CITIZEN_RANK .. " och kan inte ta emot arbetsordrar.")
		return
	end
	local now = ns.Now()
	local o = { id = string.format("%x%03x", now, math.random(0, 4095)), from = me, to = to, key = key, count = count, mats = mats,
		["until"] = now + days * DAY, stamp = now, state = "ny", note = Clean(note), at = now }
	if mats == "h" then
		local cost = ReagentCost(key, count)
		if cost then o.tip = math.floor(cost * TIP) end
	end
	Orders()[o.id] = o
	Share(o, Pack(o))
	-- In guild chat so Discord passes it on, online or offline (Zach 9/11).
	SendChatMessage(string.format("@%s du har en ny arbetsorder: %s x%d! Titta under Arbetsorder i Yrken (/yrken).", to, RecipeName(key), count), "GUILD")
	ns.Print(string.format("arbetsorder skickad till %s: %s x%d.", to, RecipeName(key), count))
	-- Sending the materials (Zach 9/11): Bokföring lists what to buy.
	local d = ns.RecipeData and ns.RecipeData(key)
	if mats == "e" and d and d.reagents and BokforingAPI and BokforingAPI.ShopForOrder then
		local reagents = {}
		for _, r in ipairs(d.reagents) do table.insert(reagents, { r.itemID, r.count }) end
		BokforingAPI.ShopForOrder(RecipeName(key), reagents, count, to)
	end
	Changed()
end

local function SetState(o, state, reason)
	o.state, o.reason, o.stamp = state, reason, ns.Now()
	Share(o, table.concat({ "D", o.id, state, reason or "", o.stamp }, ";"))
	Changed()
end

-- Receiving -------------------------------------------------------------

local function Tell(o, old)
	local me = ns.Me()
	if o.to == me and not old then
		ns.Print(string.format("ny arbetsorder från %s: %s x%d, %s. Titta under Arbetsorder i Yrken.", o.from, RecipeName(o.key), o.count, MATS[o.mats] or "?"))
	elseif o.from == me and old and old.state ~= o.state then
		ns.Print(string.format("%s: din arbetsorder %s x%d är nu %s%s.", o.to, RecipeName(o.key), o.count, STATE[o.state]:lower(),
			o.reason and o.reason ~= "" and (" (" .. o.reason .. ")") or ""))
	end
end

function ns.OnOrder(sender, parts)
	local o = { id = parts[2], from = parts[3], to = parts[4], key = parts[5], count = tonumber(parts[6]), mats = parts[7],
		["until"] = tonumber(parts[8]), stamp = tonumber(parts[9]), state = parts[10], reason = parts[11] ~= "" and parts[11] or nil, note = parts[12], tip = tonumber(parts[13]) }
	if not (o.id and o.from and o.to and o.key and o.count and o["until"] and o.stamp and STATE[o.state]) then return end
	-- Nobody outside the guild roster, and only citizens.
	if ns.Online(sender) == nil or not ns.IsCitizen(sender) or ns.Locked() then return end
	-- Only a party to the order, or the leader passing it on, may send it.
	if sender ~= o.from and sender ~= o.to and sender ~= ns.Leader() then return end
	local old = Orders()[o.id]
	if old and old.stamp >= o.stamp then return end
	o.at = old and old.at or ns.Now()
	Orders()[o.id] = o
	Tell(o, old)
	Changed()
end

function ns.OnOrderState(sender, parts)
	local o = Orders()[parts[2]]
	local state, stamp = parts[3], tonumber(parts[5])
	if not o or not STATE[state] or not stamp or stamp <= o.stamp or ns.Online(sender) == nil then return end
	if sender ~= o.from and sender ~= o.to and sender ~= ns.Leader() then return end
	local old = { state = o.state }
	o.state, o.reason, o.stamp = state, parts[4] ~= "" and parts[4] or nil, stamp
	Tell(o, old)
	Changed()
end

-- Someone logged in: the orders they are part of, from whoever holds them.
function ns.OnOrderRequest(sender)
	if not ns.IsCitizen(sender) then return end
	local now = ns.Now()
	for _, o in pairs(Orders()) do
		if (o.to == sender or o.from == sender) and now - o.stamp < KEEP_DAYS * DAY then ns.SendTo(sender, Pack(o)) end
	end
end

local function Prune()
	local now = ns.Now()
	for id, o in pairs(Orders()) do
		if now - math.max(o.stamp, o["until"]) > KEEP_DAYS * DAY then Orders()[id] = nil end
	end
end

-- The order dialog, from Yrken's recipe window ----------------------------

local dialog

local function HasTemplate(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then return C_XMLUtil.GetTemplateInfo(name) ~= nil end
	return true
end

local function Radio(parent, label, x, y)
	local b = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
	b:SetPoint("TOPLEFT", x, y)
	local text = b.text or b.Text or b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:ClearAllPoints()
	text:SetPoint("LEFT", b, "RIGHT", 4, 0)
	text:SetFontObject("GameFontHighlight")
	text:SetText(label)
	b.label = text
	return b
end

local function Label(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

-- The tip line under "Detta löser du!": a tenth of the reagents, in money
-- where Auctionator knows the prices.
local function TipText()
	local count = tonumber(dialog.count:GetText()) or 1
	local cost = ReagentCost(dialog.key, math.max(count, 1))
	return cost and string.format("dricks 10 %% av reagenskostnaden, ungefär %s", ns.Money(cost * TIP)) or "dricks 10 % av reagenskostnaden"
end

-- A classic panel like the other THÖNDERSTÖRM windows (Zach 9/11: the first
-- was a bare box), with the recipe's icon as portrait.
local function BuildDialog()
	local ok
	if HasTemplate("ButtonFrameTemplate") then ok, dialog = pcall(CreateFrame, "Frame", "SkatteverketOrderDialog", UIParent, "ButtonFrameTemplate") end
	if not ok or not dialog then
		dialog = CreateFrame("Frame", "SkatteverketOrderDialog", UIParent, BackdropTemplateMixin and "BackdropTemplate")
		dialog:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
	end
	dialog:SetSize(380, 360)
	dialog:SetPoint("CENTER")
	dialog:SetFrameStrata("DIALOG")
	dialog:SetToplevel(true)
	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
	tinsert(UISpecialFrames, "SkatteverketOrderDialog")
	dialog.titleText = dialog.TitleText or (dialog.TitleContainer and dialog.TitleContainer.TitleText)
	dialog.portraitTexture = dialog.portrait or dialog.Portrait or (dialog.PortraitContainer and dialog.PortraitContainer.portrait)

	-- Beside the portrait: what is ordered, and from whom.
	dialog.recipe = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	dialog.recipe:SetPoint("TOPLEFT", 66, -34)
	dialog.recipe:SetWidth(290)
	dialog.recipe:SetJustifyH("LEFT")

	Label(dialog, "Antal", 24, -74)
	dialog.count = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	dialog.count:SetSize(50, 20)
	dialog.count:SetPoint("TOPLEFT", 140, -70)
	dialog.count:SetAutoFocus(false)
	dialog.count:SetNumeric(true)
	dialog.count:SetMaxLetters(3)
	dialog.count:SetScript("OnTextChanged", function() if dialog.theirs then dialog.tip:SetText(TipText()) end end)

	Label(dialog, "Material", 24, -106)
	dialog.own = Radio(dialog, "Jag skickar materialet", 136, -100)
	dialog.theirs = Radio(dialog, "Detta löser du!", 136, -124)
	dialog.tip = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	dialog.tip:SetPoint("TOPLEFT", 162, -146)
	dialog.tip:SetWidth(200)
	dialog.tip:SetJustifyH("LEFT")
	dialog.own:SetScript("OnClick", function() dialog.mats = "e" dialog.own:SetChecked(true) dialog.theirs:SetChecked(false) end)
	dialog.theirs:SetScript("OnClick", function() dialog.mats = "h" dialog.theirs:SetChecked(true) dialog.own:SetChecked(false) end)

	-- How long the one ordering can wait (Zach 9/11).
	Label(dialog, "Jag kan vänta", 24, -186)
	dialog.waits = {}
	for k, days in ipairs(WAITS) do
		local b = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
		b:SetSize(52, 22)
		b:SetPoint("TOPLEFT", 136 + (k - 1) * 56, -182)
		b:SetText(days == 1 and "1 dag" or (days .. " dgr"))
		b:SetScript("OnClick", function()
			dialog.days = days
			for _, other in ipairs(dialog.waits) do other:UnlockHighlight() end
			b:LockHighlight()
		end)
		b.days = days
		dialog.waits[k] = b
	end

	Label(dialog, "Anteckning", 24, -222)
	dialog.note = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	dialog.note:SetSize(214, 20)
	dialog.note:SetPoint("TOPLEFT", 140, -218)
	dialog.note:SetAutoFocus(false)
	dialog.note:SetMaxLetters(80)

	dialog.warn = dialog:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
	dialog.warn:SetPoint("BOTTOM", 0, 40)

	-- Buttons in the strip under the inset, as on the Social window.
	local cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	cancel:SetSize(100, 22)
	cancel:SetPoint("BOTTOMRIGHT", -8, 4)
	cancel:SetText("Avbryt")
	cancel:SetScript("OnClick", function() dialog:Hide() end)
	local send = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	send:SetSize(100, 22)
	send:SetPoint("RIGHT", cancel, "LEFT", -4, 0)
	send:SetText("Beställ")
	send:SetScript("OnClick", function()
		local count = tonumber(dialog.count:GetText())
		if not count or count < 1 then dialog.warn:SetText("Skriv hur många.") return end
		-- The crafter must know what to expect (Zach 9/11): no default.
		if not dialog.mats then dialog.warn:SetText("Välj vem som står för materialet.") return end
		ns.PlaceOrder(dialog.to, dialog.key, count, dialog.mats, dialog.days, dialog.note:GetText())
		dialog:Hide()
	end)
	dialog:Hide()
end

function ns.OrderDialog(to, key)
	if not dialog then BuildDialog() end
	dialog.to, dialog.key, dialog.mats, dialog.days = to, key, nil, 7
	if dialog.titleText then dialog.titleText:SetText("Arbetsorder till " .. to) end
	local d = ns.RecipeData and ns.RecipeData(key)
	local icon = (d and d.icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
	if dialog.SetPortraitToAsset then dialog:SetPortraitToAsset(icon)
	elseif dialog.portraitTexture then dialog.portraitTexture:SetTexture(icon) end
	dialog.recipe:SetText(RecipeName(key))
	dialog.count:SetText("1")
	dialog.own:SetChecked(false)
	dialog.theirs:SetChecked(false)
	dialog.tip:SetText(TipText())
	dialog.note:SetText("")
	dialog.warn:SetText("")
	for _, b in ipairs(dialog.waits) do
		if b.days == dialog.days then b:LockHighlight() else b:UnlockHighlight() end
	end
	dialog:Show()
end

-- The Arbetsorder page, a side tab of the Yrken window (Zach 9/11) ---------

local page, rows, offset = nil, {}, 0
local ROWS, ROW_H = 16, 22

local function Act(o, state, reason)
	SetState(o, state, reason)
end

local function Decline(owner, o)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		Act(o, "avböjd", REASONS[3])
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Avböj, därför att:")
		for _, reason in ipairs(REASONS) do root:CreateButton(reason, function() Act(o, "avböjd", reason) end) end
	end)
end

function ns.BuildOrders(parent)
	page = parent
	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 24, -70)
	title:SetText("Arbetsorder")
	page.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	page.empty:SetPoint("TOPLEFT", 24, -100)
	page.empty:SetWidth(390)
	page.empty:SetJustifyH("LEFT")
	page.empty:SetText("Inga arbetsordrar. Beställ från någon under Yrken: öppna deras recept, välj ett och tryck Beställ.")
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, parent)
		row:SetSize(400, ROW_H)
		row:SetPoint("TOPLEFT", 20, -90 - (i - 1) * ROW_H)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", 4, 0)
		row.text:SetWidth(230)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row.a = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.a:SetSize(76, 20)
		row.a:SetPoint("RIGHT", -84, 0)
		row.b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.b:SetSize(76, 20)
		row.b:SetPoint("RIGHT", -4, 0)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			local o = self.order
			if not o then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(string.format("%s x%d", RecipeName(o.key), o.count))
			GameTooltip:AddLine(string.format("Från %s till %s", o.from, o.to), 1, 1, 1)
			GameTooltip:AddLine(MATS[o.mats] or "?", 1, 1, 1)
			if o.tip then GameTooltip:AddLine("Dricks: ungefär " .. ns.Money(o.tip), 1, 0.82, 0) end
			GameTooltip:AddLine("Väntar till " .. date("%d/%m %H:%M", o["until"]), 1, 1, 1)
			if o.note and o.note ~= "" then GameTooltip:AddLine("Anteckning: " .. o.note, 1, 1, 1, true) end
			GameTooltip:AddLine("Status: " .. STATE[State(o)] .. (o.reason and (" (" .. o.reason .. ")") or ""), 1, 0.82, 0)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = row
	end
	parent:EnableMouseWheel(true)
	parent:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, offset - delta * 3)
		ns.RefreshOrders()
	end)
end

local function Button(b, label, onClick)
	if not label then
		b:Hide()
		return
	end
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	b:Show()
end

-- Three sections: to you, from you, then to yourself, Bokföring's shopping
-- lists still on the go (Zach 9/11); open ones first, newest first.
function ns.RefreshOrders()
	if not page then return end
	local me = ns.Me()
	local lines = {}
	for _, section in ipairs({ { "to", "Till dig" }, { "from", "Från dig" } }) do
		local list = {}
		for _, o in pairs(Orders()) do
			if o[section[1]] == me then table.insert(list, o) end
		end
		table.sort(list, function(a, b)
			local oa, ob = OPEN[State(a)] and 1 or 0, OPEN[State(b)] and 1 or 0
			if oa ~= ob then return oa > ob end
			return a.at > b.at
		end)
		if #list > 0 then
			table.insert(lines, { header = section[2] })
			for _, o in ipairs(list) do table.insert(lines, { order = o, incoming = section[1] == "to" }) end
		end
	end
	local own = BokforingAPI and BokforingAPI.Work and BokforingAPI.Work() or {}
	if #own > 0 then
		table.insert(lines, { header = "Till dig själv" })
		for _, w in ipairs(own) do table.insert(lines, { work = w }) end
	end
	page.empty:SetShown(#lines == 0)
	offset = math.max(0, math.min(offset, #lines - ROWS))
	for i, row in ipairs(rows) do
		local line = lines[i + offset]
		row.order = line and line.order
		if not line then
			row:Hide()
		elseif line.work then
			local w = line.work
			row.text:SetText(string.format("|cffffffff%s|r  %d av %d gjorda%s", w.name, w.made, w.crafts,
				w.missing > 0 and string.format(", |cffff4040%d reagenser saknas|r", w.missing) or ""))
			Button(row.a, nil)
			Button(row.b, "Bokföring", function() BokforingAPI.ShowWork() end)
			row:Show()
		elseif line.header then
			row.text:SetText("|cffffd100" .. line.header .. "|r")
			row.a:Hide()
			row.b:Hide()
			row:Show()
		else
			local o, state = line.order, State(line.order)
			local who = line.incoming and o.from or o.to
			local colour = OPEN[state] and "|cffffffff" or "|cff808080"
			-- To the crafter: whose materials, in their words.
			local mats = line.incoming and (o.mats == "e" and "deras material, " or ("ditt material" .. (o.tip and (" +" .. ns.Money(o.tip)) or "") .. ", ")) or ""
			row.text:SetText(string.format("%s%s x%d|r  %s, %s%s", colour, RecipeName(o.key), o.count, who, mats, STATE[state]:lower()))
			if line.incoming and state == "ny" then
				Button(row.a, "Acceptera", function() Act(o, "accepterad") end)
				Button(row.b, "Avböj", function(self) Decline(self, o) end)
			elseif line.incoming and state == "accepterad" then
				Button(row.a, "Avböj", function(self) Decline(self, o) end)
				Button(row.b, "Klar", function() Act(o, "klar") end)
			elseif not line.incoming and OPEN[state] then
				Button(row.a, nil)
				Button(row.b, "Avbryt", function() Act(o, "avbruten") end)
			else
				Button(row.a, nil)
				Button(row.b, nil)
			end
			row:Show()
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	C_Timer.After(45, function()
		if not ns.db or not ns.InOurGuild() then return end
		Prune()
		ns.Send("X")
		Changed()
	end)
	-- Orders run out with time; the badge follows.
	C_Timer.NewTicker(60, function() if ns.db and ns.RefreshOrderBadge then ns.RefreshOrderBadge() end end)
end)
