-- Skatteverket, the Yrken window (Zach 9/11, redone): compact like the
-- game's profession window. A dropdown picks the profession, primary and
-- secondary apart, each with how many registered members have it; below,
-- those who have it, highest level first. Click a member to open their
-- recipes in a window like the profession window (RecipeWindow.lua, Zach
-- 7/11), where a recipe can be ordered (Orders.lua). The search bar finds
-- recipes across the guild (Recipes.lua); click a result to
-- whisper the crafter. Min anmälan, this character's registration where main
-- or alt and interests can be changed, sits under Inställningar (Zach 9/11).

local _, ns = ...

local ROWS, ROW_H = 16, 18
local COLS = { { "Nr", 60 }, { "Namn", 150 }, { "Level", 45 }, { "Typ", 45 }, { "Intressen", 100 } }
local FOUND_COLS = { { "Recept", 170 }, { "Namn", 140 }, { "Yrke", 90 } }
local SECONDARY = { COO = true, FA = true, FIS = true }
local LIST_W = 400

local page, rows, sorted, found, counts = nil, {}, {}, {}, {}
local offset, filter, search = 0, nil, ""

local function Text(parent, template, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetPoint(...)
	fs:SetJustifyH("LEFT")
	return fs
end

local function HasTemplate(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then return C_XMLUtil.GetTemplateInfo(name) ~= nil end
	return true
end

local function Cells(row, cols)
	local list, cx = {}, 4
	for c, col in ipairs(cols) do
		local fs = Text(row, "GameFontHighlightSmall", "LEFT", cx, 0)
		fs:SetWidth(col[2] - 6)
		fs:SetWordWrap(false)
		list[c] = fs
		cx = cx + col[2]
	end
	return list
end

local function Headers(cols)
	local f = CreateFrame("Frame", nil, page)
	f:SetSize(LIST_W, 16)
	f:SetPoint("TOPLEFT", 24, -88)
	local x = 0
	for _, col in ipairs(cols) do
		Text(f, "GameFontNormalSmall", "TOPLEFT", x, 0):SetText(col[1])
		x = x + col[2]
	end
	return f
end

-- Hover a recipe: the item's (or spell's) own tooltip, like the profession window.
local function RecipeTooltip(self)
	if self.link then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(self.link)
		GameTooltip:Show()
	elseif self.member then
		local m = ns.db.members[self.member]
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.member)
		if m and m.interests and m.interests ~= "" then GameTooltip:AddLine("Intressen: " .. ns.InterestText(m.interests), 1, 1, 1) end
		GameTooltip:AddLine("Klicka för att se deras recept och beställa.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end
end

local function InsertLink(link)
	if not link then return end
	if ChatEdit_InsertLink then ChatEdit_InsertLink(link)
	elseif ChatFrameUtil and ChatFrameUtil.InsertLink then ChatFrameUtil.InsertLink(link) end
end

local function Whisper(name)
	if ChatFrame_SendTell then ChatFrame_SendTell(name)
	elseif ChatFrameUtil and ChatFrameUtil.SendTell then ChatFrameUtil.SendTell(name) end
end

local function Label(p)
	local n = counts[p.code] or 0
	return string.format("%s (%d)", p.label, n)
end

local function Choose(code)
	filter, offset, search = code, 0, ""
	if page.search then page.search:SetText("") end
	ns.RefreshRegistry()
end

-- The profession dropdown: the modern menu where the client has it, the
-- old UIDropDownMenu otherwise; primary professions, a line, secondary.
local function Dropdown(parent)
	local function Groups()
		local primary, secondary = {}, {}
		for _, p in ipairs(ns.PROFESSIONS) do table.insert(SECONDARY[p.code] and secondary or primary, p) end
		return primary, secondary
	end
	if HasTemplate("WowStyle1DropdownTemplate") then
		local ok, d = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
		if ok and d and d.SetupMenu then
			d:SetWidth(200)
			if d.SetDefaultText then d:SetDefaultText("Välj yrke") end
			d:SetupMenu(function(_, root)
				local primary, secondary = Groups()
				root:CreateTitle("Primära yrken")
				for _, p in ipairs(primary) do root:CreateRadio(Label(p), function() return filter == p.code end, function() Choose(p.code) end) end
				if root.CreateDivider then root:CreateDivider() end
				root:CreateTitle("Sekundära yrken")
				for _, p in ipairs(secondary) do root:CreateRadio(Label(p), function() return filter == p.code end, function() Choose(p.code) end) end
			end)
			d.Update = function(self) if self.GenerateMenu then self:GenerateMenu() end end
			return d
		end
	end
	local d = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
	UIDropDownMenu_SetWidth(d, 170)
	UIDropDownMenu_Initialize(d, function()
		local primary, secondary = Groups()
		for _, group in ipairs({ { "Primära yrken", primary }, { "Sekundära yrken", secondary } }) do
			local title = UIDropDownMenu_CreateInfo()
			title.text, title.isTitle, title.notCheckable = group[1], true, true
			UIDropDownMenu_AddButton(title)
			for _, p in ipairs(group[2]) do
				local info = UIDropDownMenu_CreateInfo()
				info.text, info.checked = Label(p), filter == p.code
				info.func = function() Choose(p.code) end
				UIDropDownMenu_AddButton(info)
			end
		end
	end)
	d.Update = function(self)
		local p = filter and ns.PROFESSION_BY_CODE[filter]
		UIDropDownMenu_SetText(self, p and Label(p) or "Välj yrke")
	end
	return d
end

function ns.BuildRegistry(parent)
	page = parent
	-- Under the title, beside the portrait: the profession, and the recipe
	-- search across the guild (Zach 9/11: a plain search bar).
	page.pick = Dropdown(page)
	page.pick:SetPoint("TOPLEFT", 66, -30)
	page.search = CreateFrame("EditBox", nil, page, "SearchBoxTemplate")
	if not page.search.Instructions then
		page.search:Hide()
		page.search = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
	end
	page.search:SetSize(150, 20)
	page.search:SetPoint("LEFT", page.pick, "RIGHT", 12, 0)
	page.search:SetAutoFocus(false)
	if page.search.Instructions then page.search.Instructions:SetText("Sök i alla yrken") end
	page.search:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
	page.search:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
	page.search:HookScript("OnTextChanged", function(self)
		search = strtrim(self:GetText() or "")
		offset = 0
		ns.RefreshRegistry()
	end)
	page.search:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Sök i alla yrken i hela guildet")
		GameTooltip:AddLine("Recept och föremål, och recept som använder det du söker som reagens.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	page.search:HookScript("OnLeave", function() GameTooltip:Hide() end)

	page.listTitle = Text(page, "GameFontNormal", "TOPLEFT", 24, -68)
	page.listTitle:SetWidth(LIST_W)
	page.headers = Headers(COLS)
	page.foundHeaders = Headers(FOUND_COLS)
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, page)
		row:SetSize(LIST_W, ROW_H)
		row:SetPoint("TOPLEFT", 20, -104 - (i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.cells = Cells(row, COLS)
		row.found = Cells(row, FOUND_COLS)
		row:SetScript("OnClick", function(self)
			if IsShiftKeyDown() and self.key then InsertLink(ns.RecipeChatLink(self.key))
			elseif self.member then ns.ShowMember(self.member, filter)
			elseif self.whisper then Whisper(self.whisper) end
		end)
		row:SetScript("OnEnter", RecipeTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = row
	end
	page.count = Text(page, "GameFontDisableSmall", "BOTTOMLEFT", 24, 34)
	page.count:SetWidth(LIST_W)

	page:EnableMouseWheel(true)
	page:SetScript("OnMouseWheel", function(_, delta)
		local total = #search >= 2 and #found or #sorted
		offset = math.max(0, math.min(offset - delta, total - ROWS))
		ns.RefreshRegistry()
	end)
end

local function ShowCells(list, shown)
	for _, fs in ipairs(list) do if shown then fs:Show() else fs:Hide() end end
end

-- The search runs again only when the text or the recipes have changed,
-- not on every once-a-second refresh.
local foundFor, foundVersion

function ns.RefreshRegistry()
	if not page or not page:IsVisible() then return end
	local db = ns.db
	local roster = ns.RosterNames()
	local levels = {}
	wipe(counts)
	wipe(sorted)
	for name, m in pairs(db.members) do
		if m.profileAt and (not roster or roster[name]) then
			local list = ns.DecodeProfessions(m.profs)
			for code in pairs(list) do counts[code] = (counts[code] or 0) + 1 end
			if filter and list[filter] then
				table.insert(sorted, name)
				levels[name] = list[filter].rank
			end
		end
	end
	table.sort(sorted, function(a, b)
		if levels[a] ~= levels[b] then return levels[a] > levels[b] end
		local na, nb = db.members[a].number or 9999, db.members[b].number or 9999
		if na ~= nb then return na < nb end
		return a < b
	end)
	page.pick:Update()

	local searching = #search >= 2
	if not searching then
		found, foundFor = {}, nil
	elseif foundFor ~= search or foundVersion ~= ns.recipeVersion then
		found, foundFor, foundVersion = ns.SearchRecipes(search), search, ns.recipeVersion
	end
	offset = math.max(0, math.min(offset, (searching and #found or #sorted) - ROWS))

	if searching then
		page.listTitle:SetText(string.format("Recept med \"%s\"", search))
	elseif filter then
		local n = #sorted
		page.listTitle:SetText(string.format("%s: %s", ns.PROFESSION_BY_CODE[filter].label, n == 1 and "1 medlem" or n .. " medlemmar"))
	else
		page.listTitle:SetText("Välj ett yrke i listan ovan.")
	end
	if filter and not searching then page.headers:Show() else page.headers:Hide() end
	if searching then page.foundHeaders:Show() else page.foundHeaders:Hide() end

	for i, row in ipairs(rows) do
		row.whisper, row.member, row.key, row.link = nil, nil, nil, nil
		ShowCells(row.cells, not searching)
		ShowCells(row.found, searching)
		if searching then
			local hit = found[i + offset]
			if hit then
				local p = ns.PROFESSION_BY_CODE[hit.code]
				-- Offline in grey (Zach 7/11): send mail instead of a whisper.
				local who = hit.online and hit.name or ("|cff808080" .. hit.name .. " (offline)|r")
				local recipe = hit.uses and (hit.recipe .. " |cff999999(reagens)|r") or hit.recipe
				local values = { recipe, who, p and p.label or hit.code }
				for c, fs in ipairs(row.found) do fs:SetText(values[c]) end
				row.whisper = hit.online and hit.name or nil
				row.key, row.link = hit.key, ns.RecipeLink(hit.key)
				row:Show()
			else
				row:Hide()
			end
		else
			local name = filter and sorted[i + offset]
			local m = name and db.members[name]
			if m then
				local values = { ns.Number(m.number) or "-", name, levels[name], m.main and "Main" or "Alt", ns.InterestText(m.interests) }
				for c, fs in ipairs(row.cells) do fs:SetText(values[c]) end
				row.member = name
				row:Show()
			else
				row:Hide()
			end
		end
	end

	if searching then
		local sharing = 0
		for name in pairs(db.recipes) do if not roster or roster[name] then sharing = sharing + 1 end end
		local shown = #found > ROWS and string.format("Visar %d-%d av %d (scrolla). ", offset + 1, math.min(offset + ROWS, #found), #found)
			or #found == 0 and "Ingen i guildet kan det receptet, eller så har de inte delat sina recept än. " or ""
		page.count:SetText(shown .. string.format("Klicka för att viska, shift-klick länkar; grå är offline. %d medlemmar delar sina recept.", sharing))
		return
	end
	local missing = 0
	for i = 1, GetNumGuildMembers() do
		local name = ns.Short(GetGuildRosterInfo(i))
		if name and not (db.members[name] and db.members[name].profileAt) then missing = missing + 1 end
	end
	local shown = ""
	if filter and #sorted > ROWS then
		shown = string.format("Visar %d-%d av %d (scrolla). ", offset + 1, math.min(offset + ROWS, #sorted), #sorted)
	elseif filter and #sorted == 0 then
		shown = "Ingen registrerad har det yrket än. "
	end
	page.count:SetText(shown .. string.format("Inte registrerade än: %d.", missing))
end

-- Min anmälan: this character's registration in the panel (Zach 7/11),
-- instead of the scroll. Main or alt and interests can be changed here.
local mine, mainBox, altBox, interestBoxes, choice = nil, nil, nil, {}, {}

local function Check(parent, label, x, y, onClick)
	local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	box:SetSize(24, 24)
	box:SetPoint("TOPLEFT", x, y)
	local text = Text(box, "GameFontHighlight", "LEFT", box, "RIGHT", 2, 1)
	text:SetText(label)
	box:SetScript("OnClick", onClick)
	return box
end

local function Line(label, y)
	Text(mine, "GameFontNormal", "TOPLEFT", 24, y):SetText(label)
	return Text(mine, "GameFontHighlight", "TOPLEFT", 150, y)
end

function ns.BuildMine(parent)
	mine = parent
	Text(mine, "GameFontNormal", "TOPLEFT", 24, -70):SetText("Min anmälan")
	mine.number = Line("Skattenummer", -96)
	mine.name = Line("Namn", -116)
	mine.signed = Line("Anmäld", -136)
	mine.rank = Line("Rang", -156)
	mine.profs = Line("Yrken", -176)
	mine.profs:SetWidth(330)
	mine.recipes = Line("Delade recept", -216)
	mine.recipes:SetWidth(330)

	Text(mine, "GameFontNormal", "TOPLEFT", 24, -262):SetText("Karaktär")
	mainBox = Check(mine, "Huvudkaraktär", 150, -256, function() choice.main = true ns.RefreshMine() end)
	altBox = Check(mine, "Alt", 300, -256, function() choice.main = false ns.RefreshMine() end)
	Text(mine, "GameFontNormal", "TOPLEFT", 24, -296):SetText("Intressen")
	for i, interest in ipairs(ns.INTERESTS) do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		interestBoxes[i] = Check(mine, interest.label, 150 + col * 150, -290 - row * 28, function(self)
			choice.interests[interest.letter] = self:GetChecked() and true or nil
		end)
	end

	mine.note = Text(mine, "GameFontDisableSmall", "TOPLEFT", 24, -360)
	mine.note:SetWidth(390)

	mine.save = CreateFrame("Button", nil, mine, "UIPanelButtonTemplate")
	mine.save:SetSize(100, 22)
	mine.save:SetText("Spara")
	mine.save:SetPoint("BOTTOMLEFT", 8, 4)
	mine.save:SetScript("OnClick", function()
		local reg = ns.char.reg
		if not reg then ns.ShowScroll() return end
		local letters = ""
		for _, interest in ipairs(ns.INTERESTS) do
			if choice.interests[interest.letter] then letters = letters .. interest.letter end
		end
		reg.main, reg.interests = choice.main, letters
		ns.SendProfile()
		ns.Print("din anmälan är uppdaterad.")
		ns.RefreshMine()
	end)
end

-- Called when the page opens: the boxes start from what is saved.
function ns.ResetMine()
	local reg = ns.char.reg
	choice.main = not reg or reg.main ~= false
	choice.interests = {}
	for _, interest in ipairs(ns.INTERESTS) do
		if reg and (reg.interests or ""):find(interest.letter, 1, true) then choice.interests[interest.letter] = true end
	end
end

function ns.RefreshMine()
	if not mine or not mine:IsVisible() then return end
	local reg, me = ns.char.reg, ns.Me()
	mine.name:SetText(me or UnitName("player"))
	local list, parts = ns.ReadProfessions(), {}
	for _, p in ipairs(ns.PROFESSIONS) do
		if list[p.code] then table.insert(parts, p.label .. " " .. list[p.code].rank) end
	end
	mine.profs:SetText(#parts > 0 and table.concat(parts, ", ") or "inga")
	local shared = ns.OwnRecipeText()
	mine.recipes:SetText(shared ~= "" and shared or "inga än; öppna ditt yrkesfönster en gång")
	if not reg then
		mine.number:SetText("|cff808080inte anmäld|r")
		mine.signed:SetText("-")
		mine.rank:SetText("-")
		mine.note:SetText("Du har inte signerat din anmälan än. Tryck Anmäl dig för att göra det.")
		mine.save:SetText("Anmäl dig")
	else
		mine.number:SetText(ns.Number(reg.number) or "|cffff8000väntar på guildledaren|r")
		mine.signed:SetText(reg.at and date("%d/%m/%Y", reg.at) or "-")
		local status = me and ns.CitizenStatus(me, ns.RosterRanks(), ns.CitizenRankIndex())
		mine.rank:SetText(status == "ok" and ("|cff40ff40" .. ns.CITIZEN_RANK .. "|r")
			or status == "promote" and ("|cffff8000väntar på rangen " .. ns.CITIZEN_RANK .. "|r") or "-")
		mine.note:SetText("Yrken och recept uppdateras automagiskt. Byt huvudkaraktär eller alt och intressen här och tryck Spara.")
		mine.save:SetText("Spara")
	end
	mainBox:SetChecked(choice.main)
	altBox:SetChecked(not choice.main)
	for i, interest in ipairs(ns.INTERESTS) do interestBoxes[i]:SetChecked(choice.interests[interest.letter] and true or false) end
end
