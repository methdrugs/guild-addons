-- Swedbank: guild loans for THÖNDERSTÖRM on WoW Forever. Its pages live in
-- the THÖNDERSTÖRM panel that Skatteverket owns (0.10, Zach 8/11).
-- A member fills in an application (amount, reason, repay by). It goes by
-- hidden whisper to the guild leader only, never over the guild channel.
-- The leader approves it with a weekly rate, sends the gold by mail, logs
-- repayments and marks the loan repaid. A borrower can also pay back
-- straight into the guild bank from My loans (Zach 6/11); the payment
-- reaches the leader by whisper, waiting while the leader is offline.
-- Interest is simple and weekly, on what is left of the loan, from the
-- day the gold is sent. A borrower sees only their own loans; nobody else
-- sees any.
--
-- Messages (all whispers):
--   member -> leader  APP;id;amount;repay by;applied at;reason
--                     PAY;loan id;payment id;amount;paid at (paid into the guild bank)
--                     SYNC (send me my loans)
--   leader -> member  ACK;id
--                     PACK;payment id
--                     UPD;id;status;amount;rate;sent at;repay by;left;interest;as of;paid;closed at;unverified
--                     END (no more updates for now)
--
-- Saved data survives new versions as long as the folder and the names
-- SwedbankDB and SwedbankCharDB never change. When the shape of the data
-- changes, raise ns.SCHEMA and add a step to Migrate().

local _, ns = ...

ns.GUILD = "THÖNDERSTÖRM"
ns.VERSION = "0.10"
ns.SCHEMA = 2
ns.PREFIX = "SWEDBANK"
ns.WEEK = 7 * 86400
ns.REASON_BYTES = 120

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Swedbank:|r " .. text)
end
ns.Print = Print

function ns.Money(copper)
	copper = math.floor(copper or 0)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return string.format("%s%dg %ds %dc", sign, g, s, c) end
	if s > 0 then return string.format("%s%ds %dc", sign, s, c) end
	return string.format("%s%dc", sign, c)
end

-- "2g50s", "75s", "10c", "2" (gold), "2.5" or "2,5" (gold, with or without
-- g); nil for anything else. The whole text must parse, so "1g50" and
-- "2.5g" can never turn into another amount (review 6/11).
function ns.ParseMoney(text)
	text = (text or ""):lower():gsub("%s+", "")
	if text == "" then return nil end
	local whole, frac = text:match("^(%d+)[%.,](%d+)g?$")
	if whole then return math.floor(tonumber(whole .. "." .. frac) * 10000 + 0.5) end
	local gold = text:match("^(%d+)g?$")
	if gold then return tonumber(gold) * 10000 end
	local total, rest = 0, text
	for _, unit in ipairs({ { "g", 10000 }, { "s", 100 }, { "c", 1 } }) do
		local n, after = rest:match("^(%d+)" .. unit[1] .. "(.*)$")
		if n then
			total = total + tonumber(n) * unit[2]
			rest = after
		end
	end
	if rest ~= "" then return nil end
	return total
end

-- "24/12" as 23:59 that day, the next such day if it has passed; nil if unreadable.
function ns.ParseDate(text)
	local d, m = (text or ""):match("^(%d%d?)/(%d%d?)$")
	if not d then return nil end
	d, m = tonumber(d), tonumber(m)
	if m < 1 or m > 12 or d < 1 or d > 31 then return nil end
	local year = date("*t").year
	local t = time({ year = year, month = m, day = d, hour = 23, min = 59 })
	if t < time() then t = time({ year = year + 1, month = m, day = d, hour = 23, min = 59 }) end
	-- A day the month does not have (31/02) rolls over into the next month; refuse it (review 6/11).
	if date("*t", t).day ~= d then return nil end
	return t
end

function ns.Day(t)
	return (t and t > 0) and date("%d/%m", t) or "-"
end

-- At most maxBytes of text without cutting a letter like å in half; no pipes,
-- which the chat system treats as escape codes.
function ns.Trim(text, maxBytes)
	local out, n = {}, 0
	for ch in (text or ""):gsub("|", "/"):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		if n + #ch > maxBytes then break end
		table.insert(out, ch)
		n = n + #ch
	end
	return table.concat(out)
end

function ns.Short(name)
	if not name then return nil end
	if Ambiguate then return Ambiguate(name, "none") end
	return (name:gsub("%-.*", ""))
end

function ns.InOurGuild()
	return GetGuildInfo("player") == ns.GUILD
end

function ns.RequestRoster()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

-- The guild master's name and whether they are online, or nil before the roster loads.
function ns.Leader()
	for i = 1, GetNumGuildMembers() do
		local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
		if rankIndex == 0 and name then return ns.Short(name), online and true or false end
	end
end

-- nil if not in the guild, otherwise whether they are online.
function ns.Online(who)
	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
		if name and ns.Short(name) == who then return online and true or false end
	end
end

-- This character's full name as the guild sees it. Forever names have two
-- words ("Boohbas Bonks"): the roster and addon messages use both, but
-- UnitName gives only the first, and first names are not unique (Zach
-- 6/11). Found by GUID in the roster, else by a single first-name match;
-- nil until the roster has loaded.
local myName
function ns.Me()
	if myName then return myName end
	local guid, first = UnitGUID("player"), UnitName("player")
	local match, count = nil, 0
	for i = 1, GetNumGuildMembers() do
		local info = { GetGuildRosterInfo(i) }
		local name = ns.Short(info[1])
		if name and guid and info[17] == guid then
			myName = name
			return name
		end
		if name and name:match("^(%S+)") == first then
			match, count = name, count + 1
		end
	end
	if count == 1 then
		myName = match
		return match
	end
end

function ns.Whisper(target, msg)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(ns.PREFIX, msg, "WHISPER", target)
	elseif SendAddonMessage then
		SendAddonMessage(ns.PREFIX, msg, "WHISPER", target)
	end
end

function ns.PaidBack(loan)
	local total = 0
	for _, p in ipairs(loan.payments or {}) do
		if p.verified ~= false then total = total + p.amount end
	end
	return total
end

-- A payment the borrower reports from the guild bank is only a claim:
-- anyone can send that message with a macro. It stays unverified
-- (verified = false) until the bank log or the leader confirms it, and
-- until then it counts for nothing here.
function ns.Unverified(loan)
	local total = 0
	for _, p in ipairs(loan.payments or {}) do
		if p.verified == false then total = total + p.amount end
	end
	return total
end

-- Interest on what is left of the loan; a payment goes to unpaid interest
-- first, then to the loan. Returns what is left of the loan, the unpaid
-- interest, and the two together.
function ns.Due(loan, now)
	if not loan.sentAt then return loan.amount, 0, loan.amount end
	now = now or time()
	local stop = loan.closedAt and math.min(now, loan.closedAt) or now
	local left, interest, t = loan.amount, 0, loan.sentAt
	for _, p in ipairs(loan.payments or {}) do
		if p.verified ~= false then
			local at = math.max(p.t, t)
			interest = interest + left * loan.rate * (at - t) / ns.WEEK
			t = at
			local toInterest = math.min(p.amount, interest)
			interest = interest - toInterest
			left = math.max(0, left - (p.amount - toInterest))
		end
	end
	if stop > t then interest = interest + left * loan.rate * (stop - t) / ns.WEEK end
	interest = math.floor(interest)
	return left, interest, left + interest
end

-- Bookmark tabs on the right edge of the THÖNDERSTÖRM panel, like the
-- spellbook's (Zach 8/11: Swedbank's pages on the side). entries are
-- { icon, tooltip }; onClick(i). Parented to page, so they hide with it.
function ns.SideTabs(page, panel, entries, onClick)
	local tabs = {}
	for i, entry in ipairs(entries) do
		local tab = CreateFrame("CheckButton", nil, page)
		tab:SetSize(32, 32)
		tab:SetPoint("TOPLEFT", panel, "TOPRIGHT", 0, -60 - (i - 1) * 48)
		local back = tab:CreateTexture(nil, "BACKGROUND")
		back:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
		back:SetSize(64, 64)
		back:SetPoint("TOPLEFT", -3, 11)
		tab:SetNormalTexture("Interface\\Icons\\" .. entry[1])
		-- Glow textures by hand with additive blending, as on the scroll:
		-- given by path the checked one drew plain (Skatteverket, 7/11).
		local glow = tab:CreateTexture(nil, "HIGHLIGHT")
		glow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
		glow:SetBlendMode("ADD")
		glow:SetAllPoints()
		local checked = tab:CreateTexture(nil, "OVERLAY")
		checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		checked:SetBlendMode("ADD")
		checked:SetAllPoints()
		tab:SetCheckedTexture(checked)
		tab:SetScript("OnClick", function()
			onClick(i)
			if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end
		end)
		tab:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(entry[2])
			GameTooltip:Show()
		end)
		tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
		tabs[i] = tab
	end
	function tabs.Select(n)
		for i, tab in ipairs(tabs) do tab:SetChecked(i == n) end
	end
	return tabs
end

function ns.Text(parent, template, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetPoint(...)
	fs:SetJustifyH("LEFT")
	return fs
end

function ns.Button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

function ns.Input(parent, width, onEnter)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", function()
		if onEnter then onEnter() end
		box:ClearFocus()
	end)
	return box
end

-- A list of rows with cells laid out by a column spec { { title, width }, ... }.
function ns.List(parent, top, count, maxCols, width)
	local list = { rows = {}, headers = {} }
	for c = 1, maxCols do
		list.headers[c] = ns.Text(parent, "GameFontNormalSmall", "TOPLEFT", 24, top)
	end
	for i = 1, count do
		local row = CreateFrame("Button", nil, parent)
		row:SetSize(width - 40, 18)
		row:SetPoint("TOPLEFT", 20, top - 14 - (i - 1) * 18)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.cells = {}
		for c = 1, maxCols do
			row.cells[c] = ns.Text(row, "GameFontHighlightSmall", "LEFT", 4, 0)
			row.cells[c]:SetWordWrap(false)
		end
		list.rows[i] = row
	end
	function list:SetColumns(cols)
		local x = 0
		for c = 1, maxCols do
			local col = cols[c]
			local header, shown = self.headers[c], col ~= nil
			if shown then
				header:ClearAllPoints()
				header:SetPoint("TOPLEFT", parent, "TOPLEFT", 24 + x, top)
				header:SetText(col[1])
				header:Show()
			else
				header:Hide()
			end
			for _, row in ipairs(self.rows) do
				local cell = row.cells[c]
				if shown then
					cell:ClearAllPoints()
					cell:SetPoint("LEFT", row, "LEFT", 4 + x, 0)
					cell:SetWidth(col[2] - 6)
					cell:Show()
				else
					cell:Hide()
				end
			end
			if col then x = x + col[2] end
		end
	end
	return list
end

local db, char

local function Migrate()
	-- Steps go here, oldest first. Never drop loans, payments or dates:
	-- they are the record the leader follows up.
	if (db.schema or 1) < 2 then
		-- 0.5 and 0.6 took reported guild bank payments on trust; on loans
		-- still running they now wait for the bank log or the leader.
		for _, loan in pairs(db.loans) do
			if loan.status == "approved" then
				for _, p in ipairs(loan.payments or {}) do
					if p.via == "bank" and p.verified == nil then p.verified = false end
				end
			end
		end
	end
	db.schema, char.schema = ns.SCHEMA, ns.SCHEMA
end

local function Init()
	SwedbankDB = SwedbankDB or {}
	db = SwedbankDB
	db.loans = db.loans or {}
	SwedbankCharDB = SwedbankCharDB or {}
	char = SwedbankCharDB
	char.loans = char.loans or {}
	ns.db, ns.char = db, char
	Migrate()
end

local events = CreateFrame("Frame")
ns.events = events
for _, event in ipairs({
	"ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_CLOSED", "PLAYER_MONEY",
	"GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "GUILDBANKLOG_UPDATE", "MAIL_FAILED",
}) do
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "Swedbank" then Init() end
		return
	end
	if not char then return end
	if event == "PLAYER_LOGIN" then
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(ns.PREFIX) end
		ns.RequestRoster()
		-- The roster says when the leader comes online; ask for it now and then.
		C_Timer.NewTicker(60, ns.RequestRoster)
		C_Timer.After(20, function()
			if ns.OnLogin then ns.OnLogin() end
			if ns.OnBankerLogin then ns.OnBankerLogin() end
		end)
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, msg, channel, sender = ...
		if prefix ~= ns.PREFIX or channel ~= "WHISPER" or not ns.InOurGuild() then return end
		sender = ns.Short(sender)
		if IsGuildLeader() and ns.OnBankerMessage then ns.OnBankerMessage(sender, msg) end
		if sender == ns.Leader() and ns.OnMemberMessage then ns.OnMemberMessage(msg) end
	else
		if ns.OnMemberEvent then ns.OnMemberEvent(event, ...) end
		if ns.OnBankerEvent then ns.OnBankerEvent(event, ...) end
	end
end)

SLASH_SWEDBANK1 = "/swedbank"
-- Swedbank has no window of its own since 0.10: its pages are the Swedbank
-- tab of the THÖNDERSTÖRM panel, which Skatteverket owns (Zach 8/11).
-- Skatteverket builds the tab with SwedbankPanel when the panel first opens.
SwedbankPanel = {}
function SwedbankPanel.Build(page, panel)
	ns.BuildMember(page, panel)
	ns.BuildBanker(page, panel)
end
-- The leader's pages or the member's, whichever this character needs now.
function SwedbankPanel.Refresh()
	local leader = IsGuildLeader()
	ns.ShowBanker(leader)
	ns.ShowMember(not leader)
	if leader then ns.RefreshBanker() else ns.RefreshMember() end
end
SwedbankPanel.VERSION = ns.VERSION
function SwedbankPanel.HasLoan() return ns.HasLoan() end

-- /swedbank opens the panel on the Swedbank tab, /swedbank nytt on Nytt.
SlashCmdList.SWEDBANK = function(msg)
	local news = (msg or ""):lower():match("^%s*nytt%s*$")
	if not ns.InOurGuild() then
		Print("den här karaktären är inte med i " .. ns.GUILD .. ".")
	elseif not SkatteverketAPI then
		Print("Swedbank kräver Skatteverket.")
	else
		SkatteverketAPI.Toggle(news and "news" or "swedbank")
	end
end
