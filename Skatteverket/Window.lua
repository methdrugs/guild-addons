-- The THÖNDERSTÖRM windows (Zach 9/11), owned by Skatteverket: one window
-- per job instead of one panel for everything, since two panels on top of
-- each other could not be brought to the front. Skatt (your own tax and
-- everyone's standing), Yrken (professions, recipes and Arbetsorder, with
-- Min anmälan), Swedbank (built by the Swedbank addon, SwedbankPanel), and
-- Nytt and Inställningar, reached from the minimap button's right-click
-- list. Each is a classic panel with the bolt as portrait, comes to the
-- front when clicked and remembers where it was left.
--
-- Skatt: members see no amounts of others, so a low level contributes as
-- much as a high one (Zach 6/11). Everyone's list, the leader's too, is
-- ranked by standing: favourites #1-3, then good, neutral, negative (Zach
-- 7/11). The guild leader also sees paid, owed, income, the bank log and
-- last seen, with paid deciding the order within a standing, and can set the
-- rate, give credit or forgive the selected member, and guild repairs paid
-- from the bank set against what each member has paid (Zach 8/11). Yrken is
-- in Registry.lua, Arbetsorder in Orders.lua, Nytt in News.lua.

local _, ns = ...

local ROWS, ROW_H = 14, 18
local MEMBER_COLS = { { "Namn", 140 }, { "Ställning", 170 }, { "Senast betalt", 90 } }
local LEADER_COLS = { { "Betalt totalt", 110 }, { "Reparerat", 90 }, { "Skyldig", 90 }, { "Inkomst", 100 }, { "Banklogg", 90 }, { "Senast sedd", 75 }, { "Medborgare", 140 } }
local MEMBER_W, LEADER_W, FRAME_H = 520, 1130, 560
local ORDER = { top = 1, good = 2, neutral = 3, negative = 4 }

local COLS = {}
for _, col in ipairs(MEMBER_COLS) do table.insert(COLS, col) end
for _, col in ipairs(LEADER_COLS) do table.insert(COLS, col) end

-- The windows: global name, title, size, whether only citizens get in
-- (locked), and whether the guild bank's balance shows under the title.
-- Pages, as numbered since 0.12: 1 Skatt, 2 Yrken, 3 Min anmälan, 4 Nytt,
-- 5 Inställningar, 6 Swedbank, 7 Prestationer, 8 Arbetsorder.
local WINDOWS = {
	-- A gold crown on a pile of coins, the king takes his share (Zach 9/11;
	-- Media/Crown.tga, art/crown.sh; a hand taking a coin looked stiff in
	-- game). The bolt stays on the minimap button.
	skatt = { name = "SkatteverketFrame", title = "Skatteverket", h = FRAME_H, locked = true, bank = true, art = "Interface\\AddOns\\Skatteverket\\Media\\Crown" },
	-- Portraits (Zach 9/11): a gold anvil and
	-- hammer for Yrken and a gold bank for Swedbank, drawn in the bolt's
	-- style (Media/Anvil.tga, Bank.tga; art/anvil.sh, bank.sh), the gear for
	-- Inställningar and the paper scroll for Nytt.
	yrken = { name = "SkatteverketYrkenFrame", title = "Yrken", w = 440, h = 480, locked = true, art = "Interface\\AddOns\\Skatteverket\\Media\\Anvil" },
	swedbank = { name = "SkatteverketSwedbankFrame", title = "Swedbank", h = FRAME_H, locked = true, bank = true, art = "Interface\\AddOns\\Skatteverket\\Media\\Bank" },
	nytt = { name = "SkatteverketNyttFrame", title = "Nytt", w = MEMBER_W, h = FRAME_H, art = "Interface\\Icons\\INV_Misc_Note_01" },
	options = { name = "SkatteverketOptionsFrame", title = "Inställningar", w = MEMBER_W, h = 480, art = "Interface\\Icons\\INV_Misc_Gear_01" },
	prestationer = { name = "SkatteverketPrestationerFrame", title = "Prestationer", w = MEMBER_W, h = FRAME_H },
}
-- Min anmälan sits with Inställningar (Zach 9/11): that is where things are changed.
-- 9: Lämnat, the leader's tab of the Skatt window (Zach 10/11).
local PAGE_WINDOW = { "skatt", "yrken", "options", "nytt", "options", "swedbank", "prestationer", "yrken", "skatt", "nytt" }

local frame, rows, headers, sorted = nil, {}, {}, {}
local offset, selected, leaderMode = 0, nil, false
local wins = {}

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
local function Panel(name, titleText, art)
	local ok, f = false, nil
	if HasTemplate("ButtonFrameTemplate") then ok, f = pcall(CreateFrame, "Frame", name, UIParent, "ButtonFrameTemplate") end
	if ok and f then
		-- The guild's lightning bolt, as on the minimap button (Media/Bolt.tga,
		-- art/bolt.sh, Zach 8/11). The first portrait try left an empty
		-- circle (screenshot 7/11), so every way the template versions name
		-- the portrait is tried.
		art = art or "Interface\\AddOns\\Skatteverket\\Media\\Bolt"
		local portrait = f.portrait or f.Portrait or (f.PortraitContainer and f.PortraitContainer.portrait)
			or _G[name .. "Portrait"]
		if f.SetPortraitToAsset then
			f:SetPortraitToAsset(art)
		elseif portrait then
			portrait:SetTexture(art)
		end
		if portrait then portrait:Show() end
		local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
		if title then title:SetText(titleText) end
		return f, true
	end
	f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
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
	title:SetText(titleText)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	return f, false
end

-- Where each window was left (Zach 9/11), saved for the account.
local function Place(id, f)
	local saved = ns.db.windows and ns.db.windows[id]
	f:ClearAllPoints()
	if saved then
		f:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
	else
		f:SetPoint("CENTER")
	end
end

local function Remember(id, f)
	local point, _, relative, x, y = f:GetPoint(1)
	ns.db.windows = ns.db.windows or {}
	ns.db.windows[id] = { point, relative, x, y }
end

-- A bookmark tab on a window's right edge, like the spellbook's.
local function SideTab(parent, k, icon, tip, onClick)
	local tab = CreateFrame("CheckButton", nil, parent)
	tab:SetSize(32, 32)
	tab:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, -48 - (k - 1) * 48)
	local back = tab:CreateTexture(nil, "BACKGROUND")
	back:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
	back:SetSize(64, 64)
	back:SetPoint("TOPLEFT", -3, 11)
	tab:SetNormalTexture("Interface\\Icons\\" .. icon)
	-- Glows by hand with additive blending; given by path the checked one
	-- drew plain and the icon went black (7/11).
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
		onClick()
		if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end
	end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(tip)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return tab
end

-- The page shown to those who have not signed, or wait for the rank.
local function LockedPage(f)
	local locked = CreateFrame("Frame", nil, f)
	locked:SetAllPoints()
	locked.title = Text(locked, "GameFontNormalLarge", "TOP", 0, -120)
	locked.why = Text(locked, "GameFontHighlight", "TOP", 0, -156)
	locked.why:SetWidth(380)
	locked.why:SetJustifyH("CENTER")
	locked.sign = Button(locked, "Anmäl dig", 140, function() f:Hide() ns.ShowScroll() end)
	locked.sign:SetPoint("TOP", -74, -236)
	local help = Button(locked, "Villkor och hjälp", 140, function() f:Hide() ns.ShowHelp() end)
	help:SetPoint("LEFT", locked.sign, "RIGHT", 8, 0)
	locked:Hide()
	return locked
end

-- Page 1: Skatt.
local function BuildTax()
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

end

-- Every command (Zach 10/11), for the ? on each window and the help page;
-- leader = true only for the guild leader.
ns.HELP = {
	{ "/skatt", "din skatt och allas ställning" },
	{ "/skatt betala", "betala vid guildbanken" },
	{ "/skatt info", "din skatt i chatten" },
	{ "/skatt anmälan", "din anmälan" },
	{ "/yrken", "Yrken och Arbetsorder" },
	{ "/swedbank", "låna guld av guildet" },
	{ "/bok", "Bokföring, om du har den" },
	{ "/skatt nytt", "vad som är nytt, och vem som kör vilken version" },
	{ "/skatt version", "dina versioner, och om en nyare har setts i guildet" },
	{ "/skatt lämnat", "vem som har lämnat guildet de senaste 30 dagarna" },
	{ "/skatt hjälp", "villkor och vanliga frågor" },
	{ "/skatt sats 5", "sätt skattesatsen", leader = true },
	{ "/swedbank kvitt", "nollställ guildbankens utlägg efter en flytt för hand", leader = true },
	{ "/skatt ikontest", "visa blixtens fyra lägen", leader = true },
}

local function HelpButton(f)
	local help = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	help:SetSize(22, 20)
	help:SetPoint("TOPRIGHT", -28, -1)
	help:SetText("?")
	help:SetFrameLevel(f:GetFrameLevel() + 10)
	help:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:AddLine("THÖNDERSTÖRM: kommandon")
		for _, line in ipairs(ns.HELP) do
			if not line.leader or IsGuildLeader() then GameTooltip:AddDoubleLine(line[1], line[2], 1, 0.82, 0, 1, 1, 1) end
		end
		GameTooltip:AddLine("Klicka för att skriva dem i chatten.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	help:SetScript("OnLeave", function() GameTooltip:Hide() end)
	help:SetScript("OnClick", function()
		ns.Print("kommandon:")
		for _, line in ipairs(ns.HELP) do
			if not line.leader or IsGuildLeader() then ns.Print("  " .. line[1] .. ": " .. line[2]) end
		end
	end)
end

local function Build(id)
	local def = WINDOWS[id]
	local f, classic = Panel(def.name, def.title, def.art)
	local w = { id = id, frame = f, page = nil }
	wins[id] = w
	f:SetSize(def.w or MEMBER_W, def.h)
	-- The same layer as Bokföring's and the recipe window, and to the front
	-- when clicked (Zach 9/11: one stuck behind the other).
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Remember(id, self)
	end)
	tinsert(UISpecialFrames, def.name)
	Place(id, f)
	HelpButton(f)
	if def.bank then
		-- Beside the portrait, above the inset: the guild bank's last known balance.
		f.bank = Text(f, "GameFontHighlightSmall", "TOPLEFT", classic and 66 or 24, -34)
	end

	if id == "skatt" then
		frame = f
		BuildTax()
		f.left = CreateFrame("Frame", nil, f)
		f.left:SetAllPoints()
		ns.BuildLeavers(f.left)
		f.sideTabs = {
			SideTab(f, 1, "INV_Misc_Coin_02", "Ställning", function() ns.ShowTab(1) end),
			SideTab(f, 2, "Ability_Rogue_Sprint", "Lämnat", function() ns.ShowTab(9) end),
		}
	elseif id == "yrken" then
		f.professions = CreateFrame("Frame", nil, f)
		f.professions:SetAllPoints()
		ns.BuildRegistry(f.professions)
		-- Arbetsorder (Zach 9/11): orders between members live with the
		-- professions.
		f.orders = CreateFrame("Frame", nil, f)
		f.orders:SetAllPoints()
		ns.BuildOrders(f.orders)
		f.sideTabs = {
			-- A book for the members' professions; the anvil is the portrait.
			SideTab(f, 1, "INV_Misc_Book_11", "Yrken", function() ns.ShowTab(2) end),
			SideTab(f, 2, "INV_Letter_15", "Arbetsorder", function() ns.ShowTab(8) end),
		}
	elseif id == "swedbank" then
		f.swed = CreateFrame("Frame", nil, f)
		f.swed:SetAllPoints()
		if SwedbankPanel then
			SwedbankPanel.Build(f.swed, f)
		else
			Text(f.swed, "GameFontHighlight", "TOP", 0, -140):SetText("Swedbank är inte installerat.")
		end
	elseif id == "nytt" then
		f.news = CreateFrame("Frame", nil, f)
		f.news:SetAllPoints()
		ns.BuildNews(f.news)
		ns.LayoutNews(def.w)
		-- Nytt and Versioner (Zach 11/11); the note is also the bolt's
		-- update badge.
		f.sideTabs = {
			SideTab(f, 1, "INV_Misc_Note_01", "Nytt", function() ns.ShowTab(4) end),
			SideTab(f, 2, "INV_Misc_Head_Human_01", "Versioner", function() ns.ShowTab(10) end),
		}
	elseif id == "options" then
		f.options = CreateFrame("Frame", nil, f)
		f.options:SetAllPoints()
		ns.BuildOptions(f.options)
		f.mine = CreateFrame("Frame", nil, f)
		f.mine:SetAllPoints()
		ns.BuildMine(f.mine)
		f.sideTabs = {
			SideTab(f, 1, "INV_Misc_Gear_01", "Inställningar", function() ns.ShowTab(5) end),
			SideTab(f, 2, "INV_Scroll_03", "Min anmälan", function() ns.ShowTab(3) end),
		}
	elseif id == "prestationer" then
		f.achievements = CreateFrame("Frame", nil, f)
		f.achievements:SetAllPoints()
		ns.BuildAchievements(f.achievements)
	end
	if def.locked then f.locked = LockedPage(f) end

	-- Ages and the Pay button change with time; refresh once a second.
	f:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed > 1 then
			self.elapsed = 0
			ns.RefreshWindow(id)
		end
	end)
	pcall(ns.events.RegisterEvent, ns.events, "GUILD_ROSTER_UPDATE")
	-- A new frame starts shown; hide it so the first open shows it instead of closing it.
	f:Hide()
	return w
end

-- What a window shows: its page, or the lock page for those not let in.
local function Layout(w)
	local f, def, page = w.frame, WINDOWS[w.id], w.page
	local locked = def.locked and ns.Locked()
	w.lockState = locked
	-- Someone not approved who has a loan running still gets Swedbank, to
	-- see and pay it back; applying stays closed (Zach 8/11).
	if w.id == "swedbank" and locked and SwedbankPanel and SwedbankPanel.HasLoan and SwedbankPanel.HasLoan() then locked = nil end
	w.open = not locked
	if f.locked then
		SetShown(f.locked, locked)
		if locked == "unsigned" then
			f.locked.title:SetText("Anmälan saknas")
			f.locked.why:SetText("Skatteverket visar bara uppgifter för godkända medborgare. Signera din anmälan, så öppnas allt här när guildledaren har gett dig rangen " .. ns.CITIZEN_RANK .. ": din skatt, guildets ställning, yrken och receptsök.")
			f.locked.sign:Enable()
		elseif locked == "waiting" then
			f.locked.title:SetText("Väntar på godkännande")
			f.locked.why:SetText("Din anmälan är mottagen. Allt här öppnas när guildledaren har gett dig rangen " .. ns.CITIZEN_RANK .. ".")
			f.locked.sign:Disable()
		end
	end
	if w.id == "skatt" or w.id == "swedbank" then
		-- The leader's wide view (Zach 7/11).
		local width = (leaderMode and not locked) and LEADER_W or MEMBER_W
		f:SetWidth(width)
	end
	if w.id == "skatt" then
		local width = f:GetWidth()
		f.tax:SetShown(not locked)
		f.count:SetWidth(width - 48)
		for c, fs in ipairs(headers) do SetShown(fs, c <= #MEMBER_COLS or leaderMode) end
		for _, row in ipairs(rows) do
			row:SetWidth(width - 40)
			for c, fs in ipairs(row.cells) do SetShown(fs, c <= #MEMBER_COLS or leaderMode) end
		end
		SetShown(f.lead, leaderMode)
		SetShown(f.leaderInfo, leaderMode)
		-- Lämnat is the leader's only.
		local leftPage = leaderMode and not locked and page == 9
		f.tax:SetShown(not locked and not leftPage)
		SetShown(f.left, leftPage)
		for _, t in ipairs(f.sideTabs) do SetShown(t, leaderMode and not locked) end
		f.sideTabs[1]:SetChecked(not leftPage)
		f.sideTabs[2]:SetChecked(leftPage)
	elseif w.id == "yrken" then
		SetShown(f.professions, not locked and page == 2)
		SetShown(f.orders, not locked and page == 8)
		for _, t in ipairs(f.sideTabs) do SetShown(t, not locked) end
		f.sideTabs[1]:SetChecked(page == 2)
		f.sideTabs[2]:SetChecked(page == 8)
	elseif w.id == "options" then
		SetShown(f.options, page == 5)
		SetShown(f.mine, page == 3)
		f.sideTabs[1]:SetChecked(page == 5)
		f.sideTabs[2]:SetChecked(page == 3)
	elseif w.id == "swedbank" then
		SetShown(f.swed, not locked)
	elseif w.id == "nytt" then
		f.sideTabs[1]:SetChecked(page ~= 10)
		f.sideTabs[2]:SetChecked(page == 10)
	end
end

-- "Guildbanken: 1234g 5s 0c (läst av Namn 07/11 20:44)". Anyone can send
-- a balance, so it always says who read it.
local function BankText()
	local bank = ns.db.bank
	if not bank then return "Guildbanken: inte läst än. Saldot visas när någon med addonen öppnar banken." end
	local text = string.format("Guildbanken: |cffffffff%s|r  (läst av %s %s)", ns.Money(bank.amount),
		bank.by or "okänd", date("%d/%m %H:%M", bank.at))
	-- The leader: reported loan payments still waiting for the bank log (Zach 10/11).
	local count, total = 0, 0
	if SwedbankPanel and SwedbankPanel.Unchecked then count, total = SwedbankPanel.Unchecked() end
	if count > 0 then
		text = text .. string.format("  |cffffd100%d betalning%s (%s) väntar på bankloggen, öppna guildbanken|r",
			count, count > 1 and "ar" or "", ns.Money(total))
	end
	return text
end

-- Only the bank line, for Swedbank when a payment comes in or checks out.
function ns.RefreshBank()
	for _, w in pairs(wins) do
		local f = w.frame
		if f:IsShown() and f.bank then f.bank:SetText(w.open and BankText() or "") end
	end
end

-- Guild repairs from the bank (Leader.lua), red when more than paid in tax.
local function Repaired(name, m)
	local repaired = ns.db.repairs and ns.db.repairs[name]
	if not repaired or repaired < 1 then return "-" end
	return (repaired > (m.paid or 0) and "|cffff4040" or "") .. ns.Money(repaired) .. (repaired > (m.paid or 0) and "|r" or "")
end

local function RefreshTax()
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
		frame.count:SetText(string.format("Visar %d-%d av %d (scrolla med mushjulet). God: inget obetalt över 8 timmars speltid. Neutral: upp till 12 timmar. Negativ: 12 timmar eller mer. Bara speltid räknas, alla dina karaktärer tillsammans. Skatteverkets favorit: längst obruten speltid i god ställning.",
			offset + 1, math.min(offset + ROWS, #sorted), #sorted))
	end

	if leaderMode then
		-- The leader sees who shares an account (Zach 10/11); nobody else does.
		local same = {}
		local acct = selected and db.members[selected] and db.members[selected].account
		if acct then
			for name, m in pairs(db.members) do
				if name ~= selected and m.account == acct then table.insert(same, name) end
			end
			table.sort(same)
		end
		frame.lead.selected:SetText(selected and ("Vald: " .. selected .. (#same > 0 and (" (samma konto: " .. table.concat(same, ", ") .. ")") or "")) or "Klicka på en medlem")
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


-- Refresh one window, or every open one.
function ns.RefreshWindow(id)
	for wid, w in pairs(wins) do
		local f = w.frame
		if (not id or id == wid) and f:IsShown() then
			-- Promoted while the window is open: it opens up at once.
			if WINDOWS[wid].locked and ns.Locked() ~= w.lockState then Layout(w) end
			if f.bank then f.bank:SetText(w.open and BankText() or "") end
			if w.open then
				if wid == "skatt" then
					if w.page == 9 then ns.RefreshLeavers() else RefreshTax() end
				elseif wid == "yrken" then
					if w.page == 8 then ns.RefreshOrders() else ns.RefreshRegistry() end
				elseif wid == "swedbank" and SwedbankPanel then SwedbankPanel.Refresh()
				elseif wid == "nytt" then ns.RefreshNews(w.page)
				elseif wid == "options" then
					if w.page == 3 then ns.RefreshMine() else ns.RefreshOptions() end
				elseif wid == "prestationer" then ns.RefreshAchievements()
				end
			end
		end
	end
end

-- Open the window that holds page n, on that page.
function ns.ShowTab(n)
	local id = PAGE_WINDOW[n] or "skatt"
	local w = wins[id] or Build(id)
	w.page = n
	if n == 3 then ns.ResetMine() end
	if not w.frame:IsShown() then
		leaderMode = IsGuildLeader() and ns.InOurGuild()
		w.frame:Show()
		if id == "skatt" and leaderMode then frame.lead.rate:SetText(string.format("%g", ns.db.rate * 100)) end
		ns.RequestRoster()
		ns.RequestBoard()
	end
	Layout(w)
	ns.RefreshWindow(id)
end

-- /skatt, /skatt yrken and the rest: open that window on that page, or
-- close it if it is already showing it.
function ns.ToggleWindow(n)
	n = n or 1
	local w = wins[PAGE_WINDOW[n] or "skatt"]
	if w and w.frame:IsShown() and w.page == n then
		w.frame:Hide()
		return
	end
	ns.ShowTab(n)
end

-- For the Swedbank addon and Bokföring (Zach 8/11, 9/11).
local PAGES = { tax = 1, professions = 2, swedbank = 6, news = 4, options = 5, achievements = 7, orders = 8, versions = 10 }
SkatteverketAPI = {
	-- Open a window on that page, or close it if it is already showing.
	Toggle = function(page) ns.ToggleWindow(PAGES[page] or 1) end,
	-- This character's standing: "good", "neutral", "negative", or nil outside the guild.
	Standing = function()
		if not ns.char or not ns.InOurGuild() then return nil end
		return ns.Standing(ns.char)
	end,
	-- Why this character cannot use the windows yet: "unsigned", "waiting", or nil.
	Locked = function() return ns.Locked() end,
	-- The bolt's to-do badge, for Swedbank's loans (Zach 10/11).
	RefreshTodo = function() if ns.RefreshTodo then ns.RefreshTodo() end end,
	-- The bank line, for Swedbank's unchecked payments (Zach 10/11).
	RefreshBank = function() if ns.RefreshBank then ns.RefreshBank() end end,
	-- The guild tax on income, 0.05 for 5%; 0 outside the guild (Zach 11/11).
	TaxRate = function()
		if not ns.db or not ns.InOurGuild() then return 0 end
		return ns.db.rate or 0
	end,
	-- Whether a work order still waits for its materials; see Orders.lua.
	OrderMaterialsDone = function(id) return ns.OrderMaterialsDone(id) end,
	OrderOpen = function(id) return ns.OrderOpen(id) end,
	-- A member's standing as last seen, or nil if unknown.
	MemberStanding = function(name)
		local m = ns.db and ns.db.members[name]
		return m and ns.Standing(m) or nil
	end,
}
