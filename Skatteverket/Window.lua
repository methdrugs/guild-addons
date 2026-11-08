-- The THÖNDERSTÖRM panel (Zach 8/11), owned by Skatteverket: a classic
-- panel with tabs (Zach 7/11): Skatt, Yrken, Swedbank, Nytt and
-- Inställningar. The Swedbank tab is built by the Swedbank addon
-- (SwedbankPanel), which has no window of its own. Skatt has your own tax at the top and everyone's standing below.
-- Members see no amounts of others, so a low level contributes as much as
-- a high one (Zach 6/11). Everyone's list, the leader's too, is ranked by
-- standing: favourites #1-3, then good, neutral, negative (Zach 7/11). The
-- guild leader also sees paid, owed, income, the bank log and last seen,
-- with paid deciding the order within a standing, and can set the rate,
-- give credit or forgive the selected member, and guild repairs paid from
-- the bank set against what each member has paid (Zach 8/11). Yrken is in
-- Registry.lua, Nytt in News.lua.

local _, ns = ...

local ROWS, ROW_H = 14, 18
local MEMBER_COLS = { { "Namn", 140 }, { "Ställning", 170 }, { "Senast betalt", 90 } }
local LEADER_COLS = { { "Betalt totalt", 110 }, { "Reparerat", 90 }, { "Skyldig", 90 }, { "Inkomst", 100 }, { "Banklogg", 90 }, { "Senast sedd", 75 }, { "Medborgare", 140 } }
local MEMBER_W, LEADER_W, FRAME_H = 520, 1130, 560
local ORDER = { top = 1, good = 2, neutral = 3, negative = 4 }

local COLS = {}
for _, col in ipairs(MEMBER_COLS) do table.insert(COLS, col) end
for _, col in ipairs(LEADER_COLS) do table.insert(COLS, col) end

local frame, rows, headers, sorted = nil, {}, {}, {}
local offset, selected, leaderMode, tab = 0, nil, false, 1

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

-- An unknown template does not always raise an error, it can give a bare
-- frame; ask the client first where it can tell.
local function HasTemplate(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then return C_XMLUtil.GetTemplateInfo(name) ~= nil end
	return true
end

-- The classic panel (Zach 7/11): portrait, title bar and a recessed inset,
-- like the Character and Social windows. Falls back to the old dialog
-- look if a client lacks the template.
local function Panel()
	local ok, f = false, nil
	if HasTemplate("ButtonFrameTemplate") then ok, f = pcall(CreateFrame, "Frame", "SkatteverketFrame", UIParent, "ButtonFrameTemplate") end
	if ok and f then
		-- The guild's lightning bolt, as on the minimap button (Media/Bolt.tga,
		-- art/bolt.sh, Zach 8/11). The first portrait try left an empty
		-- circle (screenshot 7/11), so every way the template versions name
		-- the portrait is tried.
		local art = "Interface\\AddOns\\Skatteverket\\Media\\Bolt"
		local portrait = f.portrait or f.Portrait or (f.PortraitContainer and f.PortraitContainer.portrait)
			or _G["SkatteverketFramePortrait"]
		if f.SetPortraitToAsset then
			f:SetPortraitToAsset(art)
		elseif portrait then
			portrait:SetTexture(art)
		end
		if portrait then portrait:Show() end
		local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
		if title then title:SetText(ns.GUILD) end
		return f, true
	end
	f = CreateFrame("Frame", "SkatteverketFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	local header = f:CreateTexture(nil, "ARTWORK")
	header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	header:SetSize(320, 64)
	header:SetPoint("TOP", 0, 12)
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", header, "TOP", 0, -14)
	title:SetText(ns.GUILD)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	return f, false
end

-- The page each tab button opens: tab 1 Skatt, 2 Yrken (page 3, Min
-- anmälan, sits under it), 3 Swedbank (page 6), 4 Nytt (page 4), 5
-- Inställningar (page 5).
local TAB_PAGE = { 1, 2, 6, 4, 5 }
local PAGE_TAB = { 1, 2, 2, 4, 5, 3 }

-- Tabs along the bottom edge, as on the Character window.
local function Tab(i, label)
	local name = "SkatteverketFrameTab" .. i
	local button
	for _, template in ipairs({ "CharacterFrameTabButtonTemplate", "PanelTabButtonTemplate" }) do
		if HasTemplate(template) then
			local ok, b = pcall(CreateFrame, "Button", name, frame, template)
			if ok and b then button = b break end
		end
	end
	button = button or Button(frame, label, 90)
	button:SetID(i)
	button:SetText(label)
	if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, button, 0) end
	button:SetScript("OnClick", function() ns.ShowTab(TAB_PAGE[i]) if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end end)
	return button
end

local function Build()
	local classic
	frame, classic = Panel()
	frame:SetSize(MEMBER_W, FRAME_H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "SkatteverketFrame")

	-- Beside the portrait, above the inset: the guild bank's last known balance.
	frame.bank = Text(frame, "GameFontHighlightSmall", "TOPLEFT", classic and 66 or 24, -34)

	-- Page 1: Skatt.
	local tax = CreateFrame("Frame", nil, frame)
	tax:SetAllPoints()
	frame.tax = tax
	Text(tax, "GameFontNormal", "TOPLEFT", 24, -70):SetText("Din skatt")
	frame.mine1 = Text(tax, "GameFontHighlight", "TOPLEFT", 24, -90)
	frame.mine2 = Text(tax, "GameFontHighlight", "TOPLEFT", 24, -108)
	frame.mine3 = Text(tax, "GameFontHighlight", "TOPLEFT", 24, -126)

	Text(tax, "GameFontNormal", "TOPLEFT", 24, -154):SetText("Ställning i " .. ns.GUILD)
	local x = 24
	for c, col in ipairs(COLS) do
		headers[c] = Text(tax, "GameFontNormalSmall", "TOPLEFT", x, -174)
		headers[c]:SetText(col[1])
		x = x + col[2]
	end

	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, tax)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", 20, -188 - (i - 1) * ROW_H)
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

	frame.count = Text(tax, "GameFontDisableSmall", "TOPLEFT", 24, -194 - ROWS * ROW_H)
	frame.leaderInfo = Text(tax, "GameFontHighlightSmall", "TOPLEFT", frame.count, "BOTTOMLEFT", 0, -4)
	frame.leaderInfo:SetWidth(LEADER_W - 48)

	-- Guild leader controls, inside the inset just above its bottom edge.
	local lead = CreateFrame("Frame", nil, tax)
	lead:SetPoint("BOTTOMLEFT", 24, 34)
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

	-- Buttons in the strip under the inset, as on the Social window.
	frame.pay = Button(tax, "Betala nu", 100, ns.Pay)
	frame.pay:SetPoint("BOTTOMLEFT", 8, 4)
	local refresh = Button(tax, "Uppdatera", 100, function() ns.RequestBoard() ns.RefreshWindow() end)
	refresh:SetPoint("LEFT", frame.pay, "RIGHT", 4, 0)
	local closeButton = Button(frame, "Stäng", 90, function() frame:Hide() end)
	closeButton:SetPoint("BOTTOMRIGHT", -8, 4)

	tax:EnableMouseWheel(true)
	tax:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta, #sorted - ROWS))
		ns.RefreshWindow()
	end)

	-- Page 2: Yrken, built in Registry.lua.
	frame.professions = CreateFrame("Frame", nil, frame)
	frame.professions:SetAllPoints()
	ns.BuildRegistry(frame.professions)

	-- Page 5: Nytt, built in News.lua; open to everyone, signed or not.
	frame.news = CreateFrame("Frame", nil, frame)
	frame.news:SetAllPoints()
	ns.BuildNews(frame.news)

	-- Page 6: Swedbank, built by the Swedbank addon; closed like Skatt.
	frame.swed = CreateFrame("Frame", nil, frame)
	frame.swed:SetAllPoints()
	if SwedbankPanel then
		SwedbankPanel.Build(frame.swed, frame)
	else
		Text(frame.swed, "GameFontHighlight", "TOP", 0, -140):SetText("Swedbank är inte installerat.")
	end

	-- Inställningar, built in Options.lua; open to everyone too.
	frame.options = CreateFrame("Frame", nil, frame)
	frame.options:SetAllPoints()
	ns.BuildOptions(frame.options)

	-- Page 4: closed until the character has signed (Zach 7/11).
	local locked = CreateFrame("Frame", nil, frame)
	locked:SetAllPoints()
	frame.locked = locked
	locked.title = Text(locked, "GameFontNormalLarge", "TOP", 0, -120)
	locked.why = Text(locked, "GameFontHighlight", "TOP", 0, -156)
	locked.why:SetWidth(400)
	locked.why:SetJustifyH("CENTER")
	locked.sign = Button(locked, "Anmäl dig", 140, function() frame:Hide() ns.ShowScroll() end)
	locked.sign:SetPoint("TOP", -74, -236)
	local help = Button(locked, "Villkor och hjälp", 140, function() frame:Hide() ns.ShowHelp() end)
	help:SetPoint("LEFT", locked.sign, "RIGHT", 8, 0)

	-- Page 3: Min anmälan, opened from the Yrken tab; Yrken stays the selected tab.
	frame.mine = CreateFrame("Frame", nil, frame)
	frame.mine:SetAllPoints()
	ns.BuildMine(frame.mine)

	frame.tabs = { Tab(1, "Skatt"), Tab(2, "Yrken"), Tab(3, "Swedbank"), Tab(4, "Nytt"), Tab(5, "Inställningar") }
	frame.tabs[1]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, classic and 2 or 6)
	frame.tabs[2]:SetPoint("LEFT", frame.tabs[1], "RIGHT", -15, 0)
	frame.tabs[3]:SetPoint("LEFT", frame.tabs[2], "RIGHT", -15, 0)
	frame.tabs[4]:SetPoint("LEFT", frame.tabs[3], "RIGHT", -15, 0)
	frame.tabs[5]:SetPoint("LEFT", frame.tabs[4], "RIGHT", -15, 0)
	frame.Tabs = frame.tabs
	if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(frame, #frame.tabs) end

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
	-- Both tabs keep the same size, so switching does not jump (Zach 7/11).
	local width = (leaderMode and not ns.Locked()) and LEADER_W or MEMBER_W
	frame:SetWidth(width)
	frame.count:SetWidth(width - 48)
	for c, fs in ipairs(headers) do SetShown(fs, c <= #MEMBER_COLS or leaderMode) end
	for _, row in ipairs(rows) do
		row:SetWidth(width - 40)
		for c, fs in ipairs(row.cells) do SetShown(fs, c <= #MEMBER_COLS or leaderMode) end
	end
	SetShown(frame.lead, leaderMode)
	SetShown(frame.leaderInfo, leaderMode)
	local locked = ns.Locked()
	frame.lockState = locked
	-- Nytt and Inställningar are open to everyone; the other tabs show the lock page.
	-- Someone not approved who has a loan running still gets Swedbank, to
	-- see and pay it back; applying stays closed (Zach 8/11).
	local swedOpen = not locked or (SwedbankPanel and SwedbankPanel.HasLoan and SwedbankPanel.HasLoan())
	frame.swedOpen = swedOpen
	local open = tab == 4 or tab == 5 or (tab == 6 and swedOpen)
	SetShown(frame.locked, locked and not open)
	if locked == "unsigned" then
		frame.locked.title:SetText("Anmälan saknas")
		frame.locked.why:SetText("Skatteverket visar bara uppgifter för godkända medborgare. Signera din anmälan, så öppnas allt här när guildledaren har gett dig rangen " .. ns.CITIZEN_RANK .. ": din skatt, guildets ställning, yrken och receptsök.")
		frame.locked.sign:Enable()
	elseif locked == "waiting" then
		frame.locked.title:SetText("Väntar på godkännande")
		frame.locked.why:SetText("Din anmälan är mottagen. Allt här öppnas när guildledaren har gett dig rangen " .. ns.CITIZEN_RANK .. ".")
		frame.locked.sign:Disable()
	end
	SetShown(frame.tax, tab == 1 and not locked)
	SetShown(frame.professions, tab == 2 and not locked)
	SetShown(frame.mine, tab == 3 and not locked)
	SetShown(frame.news, tab == 4)
	SetShown(frame.options, tab == 5)
	SetShown(frame.swed, tab == 6 and swedOpen)
	ns.LayoutRegistry(width)
	ns.LayoutNews(width)
	local selectedTab = PAGE_TAB[tab]
	if PanelTemplates_SetTab then
		PanelTemplates_SetTab(frame, selectedTab)
	else
		for i, b in ipairs(frame.tabs) do if i == selectedTab then b:Disable() else b:Enable() end end
	end
end

-- "Guildbanken: 1234g 5s 0c (läst av Namn 07/11 20:44)". Anyone can send
-- a balance, so it always says who read it.
local function BankText()
	local bank = ns.db.bank
	if not bank then return "Guildbanken: inte läst än. Saldot visas när någon med addonen öppnar banken." end
	return string.format("Guildbanken: |cffffffff%s|r  (läst av %s %s)", ns.Money(bank.amount),
		bank.by or "okänd", date("%d/%m %H:%M", bank.at))
end

-- Guild repairs from the bank (Leader.lua), red when more than paid in tax.
local function Repaired(name, m)
	local repaired = ns.db.repairs and ns.db.repairs[name]
	if not repaired or repaired < 1 then return "-" end
	return (repaired > (m.paid or 0) and "|cffff4040" or "") .. ns.Money(repaired) .. (repaired > (m.paid or 0) and "|r" or "")
end

function ns.RefreshWindow()
	if not frame or not frame:IsShown() then return end
	local db, char = ns.db, ns.char
	-- Promoted while the window is open: it opens up at once.
	if ns.Locked() ~= frame.lockState then Layout() end
	if tab >= 4 then
		frame.bank:SetText(frame.lockState and "" or BankText())
		if tab == 4 then ns.RefreshNews()
		elseif tab == 5 then ns.RefreshOptions()
		elseif frame.swedOpen and SwedbankPanel then SwedbankPanel.Refresh() end
		return
	end
	if frame.lockState then
		frame.bank:SetText("")
		return
	end
	frame.bank:SetText(BankText())
	if tab == 2 then
		ns.RefreshRegistry()
		return
	elseif tab == 3 then
		ns.RefreshMine()
		return
	end
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
		local ra, rb = Rank(a), Rank(b)
		if ra ~= rb then return ra < rb end
		if top[a] and top[b] then return top[a] < top[b] end
		if leaderMode then
			local pa, pb = db.members[a].paid or 0, db.members[b].paid or 0
			if pa ~= pb then return pa > pb end
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
				name, standing, ns.Day(m.lastDeposit), ns.Money(m.paid), Repaired(name, m),
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

function ns.ShowTab(n)
	if not frame then Build() end
	tab = n
	if n == 3 then ns.ResetMine() end
	if not frame:IsShown() then
		leaderMode = IsGuildLeader() and ns.InOurGuild()
		frame:Show()
		if leaderMode then frame.lead.rate:SetText(string.format("%g", ns.db.rate * 100)) end
		ns.RequestRoster()
		ns.RequestBoard()
	end
	Layout()
	ns.RefreshWindow()
end

-- /skatt and /skatt yrken: open on that tab, or close if it is already showing.
function ns.ToggleWindow(n)
	n = n or 1
	if frame and frame:IsShown() and tab == n then frame:Hide() return end
	ns.ShowTab(n)
end

-- For the Swedbank addon, which draws its pages in this panel (Zach 8/11).
local PAGES = { tax = 1, professions = 2, swedbank = 6, news = 4, options = 5 }
SkatteverketAPI = {
	-- Open the panel on that page, or close it if it is already showing.
	Toggle = function(page) ns.ToggleWindow(PAGES[page] or 1) end,
	-- This character's standing: "good", "neutral", "negative", or nil outside the guild.
	Standing = function()
		if not ns.char or not ns.InOurGuild() then return nil end
		return ns.Standing(ns.char)
	end,
	-- Why this character cannot use the panel yet: "unsigned", "waiting", or nil.
	Locked = function() return ns.Locked() end,
	-- A member's standing as last seen, or nil if unknown.
	MemberStanding = function(name)
		local m = ns.db and ns.db.members[name]
		return m and ns.Standing(m) or nil
	end,
}
