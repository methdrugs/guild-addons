-- Skatteverket, the /skatt window in the old dialog style: your own tax at
-- the top, everyone's standing below. Members see no amounts of others, so
-- a low level contributes as much as a high one (Zach 6/11); their list is
-- sorted by standing. The guild leader also sees paid, owed, income, the
-- bank log and last seen, sorted by paid, and can set the rate, give
-- credit or forgive the selected member.

local _, ns = ...

local ROWS, ROW_H = 14, 18
local MEMBER_COLS = { { "Namn", 140 }, { "Ställning", 170 }, { "Senast betalt", 90 } }
local LEADER_COLS = { { "Betalt totalt", 110 }, { "Skyldig", 90 }, { "Inkomst", 100 }, { "Banklogg", 90 }, { "Senast sedd", 75 }, { "Medborgare", 140 } }
local MEMBER_W, LEADER_W = 520, 1040
local ORDER = { top = 1, good = 2, neutral = 3, negative = 4 }

local COLS = {}
for _, col in ipairs(MEMBER_COLS) do table.insert(COLS, col) end
for _, col in ipairs(LEADER_COLS) do table.insert(COLS, col) end

local frame, rows, headers, sorted = nil, {}, {}, {}
local offset, selected, leaderMode = 0, nil, false

local function Text(parent, template, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetPoint(...)
	fs:SetJustifyH("LEFT")
	return fs
end

local function Button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local function Input(parent, width, onEnter)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", function() onEnter() box:ClearFocus() end)
	return box
end

local function SetShown(region, shown)
	if shown then region:Show() else region:Hide() end
end

local function Build()
	frame = CreateFrame("Frame", "SkatteverketFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetSize(MEMBER_W, 520)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "SkatteverketFrame")

	local header = frame:CreateTexture(nil, "ARTWORK")
	header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	header:SetSize(320, 64)
	header:SetPoint("TOP", 0, 12)
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", header, "TOP", 0, -14)
	title:SetText("Skatteverket")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	Text(frame, "GameFontNormal", "TOPLEFT", 24, -34):SetText("Din skatt")
	frame.mine1 = Text(frame, "GameFontHighlight", "TOPLEFT", 24, -54)
	frame.mine2 = Text(frame, "GameFontHighlight", "TOPLEFT", 24, -72)
	frame.mine3 = Text(frame, "GameFontHighlight", "TOPLEFT", 24, -90)

	Text(frame, "GameFontNormal", "TOPLEFT", 24, -118):SetText("Ställning i " .. ns.GUILD)
	local x = 24
	for c, col in ipairs(COLS) do
		headers[c] = Text(frame, "GameFontNormalSmall", "TOPLEFT", x, -138)
		headers[c]:SetText(col[1])
		x = x + col[2]
	end

	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", 20, -152 - (i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.cells = {}
		local cx = 4
		for c, col in ipairs(COLS) do
			local fs = Text(row, "GameFontHighlightSmall", "LEFT", cx, 0)
			fs:SetWidth(col[2] - 6)
			row.cells[c] = fs
			cx = cx + col[2]
		end
		row:SetScript("OnClick", function()
			if leaderMode then
				selected = row.name
				ns.RefreshWindow()
			end
		end)
		rows[i] = row
	end

	frame.count = Text(frame, "GameFontDisableSmall", "TOPLEFT", 24, -410)
	frame.leaderInfo = Text(frame, "GameFontHighlightSmall", "TOPLEFT", 24, -426)
	frame.leaderInfo:SetWidth(LEADER_W - 48)

	-- Guild leader controls, one line above the buttons.
	local lead = CreateFrame("Frame", nil, frame)
	lead:SetPoint("BOTTOMLEFT", 24, 46)
	lead:SetSize(LEADER_W - 48, 24)
	local rateLabel = Text(lead, "GameFontNormalSmall", "LEFT", 0, 0)
	rateLabel:SetText("Skatt %")
	lead.rate = Input(lead, 40, function() ns.LeaderCommand("rate", lead.rate:GetText()) end)
	lead.rate:SetPoint("LEFT", 50, 0)
	local setRate = Button(lead, "Sätt skatt", 90, function()
		ns.LeaderCommand("rate", lead.rate:GetText())
		lead.rate:ClearFocus()
	end)
	setRate:SetPoint("LEFT", lead.rate, "RIGHT", 8, 0)
	lead.selected = Text(lead, "GameFontHighlightSmall", "LEFT", setRate, "RIGHT", 24, 0)
	lead.selected:SetWidth(170)
	local function GiveCredit()
		local amount = ns.ParseMoney(lead.amount:GetText())
		if not selected then ns.Print("klicka på en medlem först.") return end
		if not amount then ns.Print("skriv ett belopp, till exempel 2g50s.") return end
		ns.Adjust(selected, "C", amount)
		lead.amount:SetText("")
	end
	lead.amount = Input(lead, 70, GiveCredit)
	lead.amount:SetPoint("LEFT", lead.selected, "RIGHT", 8, 0)
	local give = Button(lead, "Ge kredit", 100, function() GiveCredit() lead.amount:ClearFocus() end)
	give:SetPoint("LEFT", lead.amount, "RIGHT", 8, 0)
	local forgive = Button(lead, "Efterskänk", 100, function()
		if not selected then ns.Print("klicka på en medlem först.") return end
		ns.Adjust(selected, "F", 0)
	end)
	forgive:SetPoint("LEFT", give, "RIGHT", 8, 0)
	local promote = Button(lead, "Ge Medborgare", 120, function()
		if not selected then ns.Print("klicka på en medlem först.") return end
		ns.PromoteToCitizen(selected)
	end)
	promote:SetPoint("LEFT", forgive, "RIGHT", 8, 0)
	frame.lead = lead

	frame.pay = Button(frame, "Betala nu", 100, ns.Pay)
	frame.pay:SetPoint("BOTTOMLEFT", 24, 18)
	local refresh = Button(frame, "Uppdatera", 100, function() ns.RequestBoard() ns.RefreshWindow() end)
	refresh:SetPoint("LEFT", frame.pay, "RIGHT", 8, 0)
	local professions = Button(frame, "Yrken", 100, ns.ToggleRegistry)
	professions:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
	local closeButton = Button(frame, "Stäng", 100, function() frame:Hide() end)
	closeButton:SetPoint("BOTTOMRIGHT", -24, 18)

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta, #sorted - ROWS))
		ns.RefreshWindow()
	end)
	-- Ages and the Pay button change with time; refresh once a second.
	frame:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed > 1 then
			self.elapsed = 0
			ns.RefreshWindow()
		end
	end)
	pcall(ns.events.RegisterEvent, ns.events, "GUILD_ROSTER_UPDATE")
	-- A new frame starts shown; hide it so the first /skatt opens it instead of closing it.
	frame:Hide()
end

local function Layout()
	local width = leaderMode and LEADER_W or MEMBER_W
	frame:SetWidth(width)
	frame.count:SetWidth(width - 48)
	for c, fs in ipairs(headers) do SetShown(fs, c <= #MEMBER_COLS or leaderMode) end
	for _, row in ipairs(rows) do
		row:SetWidth(width - 40)
		for c, fs in ipairs(row.cells) do SetShown(fs, c <= #MEMBER_COLS or leaderMode) end
	end
	SetShown(frame.lead, leaderMode)
	SetShown(frame.leaderInfo, leaderMode)
end

function ns.RefreshWindow()
	if not frame or not frame:IsShown() then return end
	local db, char = ns.db, ns.char
	local top = ns.TopPayers()

	if ns.InOurGuild() then
		local place = top[ns.Me() or ""]
		local standing = place and ns.TopLabel(place) or ns.LABELS[ns.Standing(char)]
		frame.mine1:SetText(string.format("Ställning: %s     Skattesats: %g %%", standing, db.rate * 100))
		frame.mine2:SetText(string.format("Skyldig nu: %s     Inkomst sedan senaste insättningen: %s", ns.Money(math.max(char.owed, 0)), ns.Money(char.incomeSince)))
		local credit = char.owed <= -1 and ("     Kredit: " .. ns.Money(-char.owed)) or ""
		frame.mine3:SetText(string.format("Betalt totalt: %s     Senaste insättning: %s%s", ns.Money(char.paid), ns.Day(char.lastDeposit), credit))
	else
		frame.mine1:SetText("Den här karaktären är inte med i " .. ns.GUILD .. "; inget beskattas.")
		frame.mine2:SetText("")
		frame.mine3:SetText("")
	end
	if ns.BankOpen() and char.owed >= 1 and not ns.Paying() then frame.pay:Enable() else frame.pay:Disable() end

	wipe(sorted)
	-- Only people in the guild now: not those who left, nor rows kept under
	-- a first name only by 0.6 and older.
	local roster = ns.RosterNames()
	for name in pairs(db.members) do
		if not roster or roster[name] then table.insert(sorted, name) end
	end
	local function Rank(name)
		return top[name] and 0 or ORDER[ns.Standing(db.members[name])]
	end
	table.sort(sorted, function(a, b)
		if leaderMode then
			local pa, pb = db.members[a].paid or 0, db.members[b].paid or 0
			if pa ~= pb then return pa > pb end
		else
			local ra, rb = Rank(a), Rank(b)
			if ra ~= rb then return ra < rb end
			if top[a] and top[b] then return top[a] < top[b] end
		end
		return a < b
	end)
	offset = math.max(0, math.min(offset, #sorted - ROWS))

	local log = db.bankLog and db.bankLog.sums or {}
	-- Leader: has the member signed, and do they have the rank Medborgare yet (Zach 7/11)?
	local ranks, citizen = ns.RosterRanks(), ns.CitizenRankIndex()
	local CITIZEN = {
		ok = "|cff40ff40%s, klar|r",
		promote = "|cffff8000%s, befordra|r",
		norank = "%s",
	}
	local promote = {}
	for i, row in ipairs(rows) do
		local name = sorted[i + offset]
		local m = name and db.members[name]
		row.name = name
		if m then
			local standing = top[name] and ns.TopLabel(top[name]) or ns.LABELS[ns.Standing(m)]
			local status = ns.CitizenStatus(name, ranks, citizen)
			local values = {
				name, standing, ns.Day(m.lastDeposit), ns.Money(m.paid),
				ns.Money(math.max(m.owed or 0, 0)), ns.Money(m.incomeTotal), log[name] and ns.Money(log[name]) or "-", ns.Day(m.lastSeen),
				status and string.format(CITIZEN[status], ns.Number(m.number)) or "|cff808080inte anmäld|r",
			}
			for c, fs in ipairs(row.cells) do fs:SetText(values[c]) end
			if leaderMode and name == selected then row:LockHighlight() else row:UnlockHighlight() end
			row:Show()
		else
			row:Hide()
		end
	end

	if #sorted == 0 then
		frame.count:SetText("Inga rapporter än. Tryck Uppdatera eller vänta tills medlemmar loggar in.")
	else
		frame.count:SetText(string.format("Visar %d-%d av %d (scrolla med mushjulet). God: inget obetalt över 48 timmar. Neutral: upp till en vecka. Negativ: en vecka eller mer. Skatteverkets favorit: längst obruten tid i god ställning.",
			offset + 1, math.min(offset + ROWS, #sorted), #sorted))
	end

	if leaderMode then
		frame.lead.selected:SetText(selected and ("Vald: " .. selected) or "Klicka på en medlem")
		local missing = {}
		for i = 1, GetNumGuildMembers() do
			local name = ns.Short(GetGuildRosterInfo(i))
			if name and not db.members[name] then table.insert(missing, name) end
		end
		local shown = table.concat(missing, ", ", 1, math.min(#missing, 12))
		if #missing > 12 then shown = shown .. string.format(" och %d till", #missing - 12) end
		-- Everyone signed but not yet Medborgare, not only the rows on screen.
		for name in pairs(db.members) do
			if ranks[name] and ns.CitizenStatus(name, ranks, citizen) == "promote" then table.insert(promote, name) end
		end
		table.sort(promote)
		local citizenText = not citizen and ("Ingen rang heter " .. ns.CITIZEN_RANK .. " i guildet.")
			or #promote > 0 and ("Befordra till " .. ns.CITIZEN_RANK .. ": " .. table.concat(promote, ", ") .. ".")
			or ""
		frame.leaderInfo:SetText(string.format("Banklogg %s (bara de senaste insättningarna; öppna banken för att läsa den). Utan addon: %s. %s",
			db.bankLog and ("läst " .. date("%d/%m %H:%M", db.bankLog.readAt)) or "inte läst än",
			#missing == 0 and "inga" or shown, citizenText))
	end
end

function ns.ToggleWindow()
	if not frame then Build() end
	if frame:IsShown() then frame:Hide() return end
	leaderMode = IsGuildLeader() and ns.InOurGuild()
	Layout()
	frame:Show()
	if leaderMode then frame.lead.rate:SetText(string.format("%g", ns.db.rate * 100)) end
	ns.RequestRoster()
	ns.RequestBoard()
	ns.RefreshWindow()
end
