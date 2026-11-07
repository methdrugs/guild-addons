-- Skatteverket, the Yrken tab of the /skatt window: every profession with
-- how many registered members have it (Zach 7/11). Click a profession to
-- list those who have it, highest level first; click it again to close
-- the list. The search box finds recipes across the guild (Recipes.lua);
-- click a result to whisper the crafter. Click a member in a profession's
-- list to open their recipes in a window like the profession window
-- (RecipeWindow.lua, Zach 7/11). Min anmälan shows this
-- character's registration in the same panel, where main or alt and
-- interests can be changed.

local _, ns = ...

local ROWS, ROW_H = 12, 18
local CELL_W, CELL_H = 158, 38
local COLS = { { "Nr", 70 }, { "Namn", 170 }, { "Nivå", 50 }, { "Typ", 50 }, { "Intressen", 130 } }
local FOUND_COLS = { { "Recept", 200 }, { "Namn", 160 }, { "Yrke", 110 } }

local page, rows, cells, sorted, found = nil, {}, {}, {}, {}
local offset, filter, search = 0, nil, ""
local listWidth = 470

local function Text(parent, template, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetPoint(...)
	fs:SetJustifyH("LEFT")
	return fs
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
	f:SetSize(listWidth, 16)
	local x = 0
	for _, col in ipairs(cols) do
		Text(f, "GameFontNormalSmall", "TOPLEFT", x, 0):SetText(col[1])
		x = x + col[2]
	end
	return f
end

-- Hover a recipe: the item's (or spell's) own tooltip, like the profession window.
local function RecipeTooltip(self)
	if not self.link then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(self.link)
	GameTooltip:Show()
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

-- One profession in the grid: icon, name and the number of members, like
-- the skill lines of the Character window.
local function Cell(p)
	local b = CreateFrame("Button", nil, page)
	b:SetSize(CELL_W - 8, CELL_H - 6)
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(28, 28)
	b.icon:SetPoint("LEFT", 2, 0)
	b.icon:SetTexture("Interface\\Icons\\" .. p.icon)
	b.label = Text(b, "GameFontHighlightSmall", "TOPLEFT", b.icon, "TOPRIGHT", 6, -1)
	b.label:SetText(p.label)
	b.count = Text(b, "GameFontNormal", "BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 6, 1)
	b:SetScript("OnClick", function()
		filter = filter ~= p.code and p.code or nil
		offset = 0
		if filter then page.search:SetText("") end
		ns.RefreshRegistry()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(p.label .. " (" .. p.name .. ")")
		GameTooltip:AddLine("Klicka för att se vilka som har det.", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b.code = p.code
	return b
end

function ns.BuildRegistry(parent)
	page = parent
	Text(page, "GameFontNormal", "TOPLEFT", 24, -70):SetText("Yrken i " .. ns.GUILD)

	-- Recipe search, top right of the inset.
	page.search = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
	page.search:SetSize(160, 20)
	page.search:SetAutoFocus(false)
	page.search:SetScript("OnEscapePressed", page.search.ClearFocus)
	page.search:SetScript("OnEnterPressed", page.search.ClearFocus)
	page.search:SetScript("OnTextChanged", function(self)
		search = strtrim(self:GetText() or "")
		offset = 0
		if search ~= "" then filter = nil end
		ns.RefreshRegistry()
	end)
	page.searchLabel = Text(page, "GameFontNormalSmall", "RIGHT", page.search, "LEFT", -10, 0)
	page.searchLabel:SetText("Sök recept:")

	for i, p in ipairs(ns.PROFESSIONS) do cells[i] = Cell(p) end

	page.listTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	page.listTitle:SetJustifyH("LEFT")
	page.headers = Headers(COLS)
	page.foundHeaders = Headers(FOUND_COLS)
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, page)
		row:SetSize(listWidth, ROW_H)
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
	page.count:SetWidth(470)

	local mine = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	mine:SetSize(120, 22)
	mine:SetText("Min anmälan")
	mine:SetPoint("BOTTOMLEFT", 8, 4)
	mine:SetScript("OnClick", function() ns.ShowTab(3) end)

	ns.LayoutRegistry(520)
	page:EnableMouseWheel(true)
	page:SetScript("OnMouseWheel", function(_, delta)
		local total = search ~= "" and #found or #sorted
		offset = math.max(0, math.min(offset - delta, total - ROWS))
		ns.RefreshRegistry()
	end)
end

-- The grid fills the window's width: 3 columns in the members' window, 6
-- in the leader's wide one, with the list right under the last row.
function ns.LayoutRegistry(width)
	if not page then return end
	local cols = math.max(1, math.min(6, math.floor((width - 40) / CELL_W)))
	for i, b in ipairs(cells) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 20 + col * CELL_W, -92 - row * CELL_H)
	end
	page.search:ClearAllPoints()
	page.search:SetPoint("TOPLEFT", math.min(width, 520) - 190, -64)
	local top = -92 - math.ceil(#cells / cols) * CELL_H - 8
	page.listTitle:ClearAllPoints()
	page.listTitle:SetPoint("TOPLEFT", 24, top)
	for _, headers in ipairs({ page.headers, page.foundHeaders }) do
		headers:ClearAllPoints()
		headers:SetPoint("TOPLEFT", 24, top - 20)
	end
	for i, row in ipairs(rows) do
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 20, top - 36 - (i - 1) * ROW_H)
	end
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
	local counts, levels = {}, {}
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

	local searching = #search >= 2
	if not searching then
		found, foundFor = {}, nil
	elseif foundFor ~= search or foundVersion ~= ns.recipeVersion then
		found, foundFor, foundVersion = ns.SearchRecipes(search), search, ns.recipeVersion
	end
	offset = math.max(0, math.min(offset, (searching and #found or #sorted) - ROWS))

	for _, b in ipairs(cells) do
		local n = counts[b.code] or 0
		b.count:SetText(n == 1 and "1 medlem" or n .. " medlemmar")
		b.icon:SetDesaturated(n == 0 or (filter ~= nil and b.code ~= filter))
		if b.code == filter then b:LockHighlight() else b:UnlockHighlight() end
	end

	if searching then
		page.listTitle:SetText(string.format("Recept med \"%s\"", search))
	elseif filter then
		page.listTitle:SetText(ns.PROFESSION_BY_CODE[filter].label .. "  |cffffffff(klicka på ett namn för att se deras recept)|r")
	else
		page.listTitle:SetText("Klicka på ett yrke för att se vilka som har det.")
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
				local values = { hit.recipe, who, p and p.label or hit.code }
				for c, fs in ipairs(row.found) do fs:SetText(values[c]) end
				row.whisper = hit.online and hit.name or nil
				row.key, row.link = hit.key, ns.RecipeLink(hit.key)
				row:Show()
			else
				row:Hide()
			end
		else
			local name = sorted[i + offset]
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
		local shown = #found > ROWS and string.format("Visar %d-%d av %d (scrolla med mushjulet). ", offset + 1, math.min(offset + ROWS, #found), #found)
			or #found == 0 and "Ingen i guildet kan det receptet, eller så har de inte delat sina recept än. " or ""
		page.count:SetText(shown .. string.format("Klicka för att viska, shift-klick länkar i chatten; grå är offline, skicka post. %d medlemmar delar sina recept.", sharing))
		return
	end
	local missing = 0
	for i = 1, GetNumGuildMembers() do
		local name = ns.Short(GetGuildRosterInfo(i))
		if name and not (db.members[name] and db.members[name].profileAt) then missing = missing + 1 end
	end
	local shown = ""
	if filter and #sorted > ROWS then
		shown = string.format("Visar %d-%d av %d (scrolla med mushjulet). ", offset + 1, math.min(offset + ROWS, #sorted), #sorted)
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
	mine.note:SetWidth(470)

	local back = CreateFrame("Button", nil, mine, "UIPanelButtonTemplate")
	back:SetSize(100, 22)
	back:SetText("Tillbaka")
	back:SetPoint("BOTTOMLEFT", 8, 4)
	back:SetScript("OnClick", function() ns.ShowTab(2) end)
	mine.save = CreateFrame("Button", nil, mine, "UIPanelButtonTemplate")
	mine.save:SetSize(100, 22)
	mine.save:SetText("Spara")
	mine.save:SetPoint("LEFT", back, "RIGHT", 4, 0)
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
