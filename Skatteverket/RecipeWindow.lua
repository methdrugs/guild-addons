-- Skatteverket, a member's recipes in a window like the game's own
-- profession window (Zach 7/11, screenshot of Forever's): portrait with the
-- profession icon, the skill bar, a search box, the list with categories
-- that open and close and recipes coloured as they are for that member,
-- and below it the selected recipe with its reagents. Blizzard's window
-- cannot be opened with someone else's data on Forever (no profession
-- link API), so this one is built from what they share.

local _, ns = ...

local W, H = 430, 560
local LIST_ROWS, ROW_H = 13, 17
local COLOURS = { o = { 1, 0.5, 0.25 }, y = { 1, 1, 0 }, g = { 0.25, 0.75, 0.25 }, x = { 0.5, 0.5, 0.5 } }

local frame, rows, reagents = nil, {}, {}
local who, code, recipes, shown, collapsed, selected, offset, filterText = nil, nil, {}, {}, {}, nil, 0, ""

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

-- A recessed box, like the window's list and details.
local function Inset(parent, ...)
	local template = HasTemplate("InsetFrameTemplate") and "InsetFrameTemplate" or (BackdropTemplateMixin and "BackdropTemplate")
	local f = CreateFrame("Frame", nil, parent, template)
	if not HasTemplate("InsetFrameTemplate") and f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		f:SetBackdropColor(0, 0, 0, 0.6)
	end
	f:SetPoint(...)
	return f
end

local function Tooltip(self)
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

-- The rows to show: categories, and their recipes unless closed or
-- filtered away by the search box.
local function Visible()
	wipe(shown)
	local header, pending = nil, {}
	local text = filterText:lower()
	local function Flush()
		if header and (#pending > 0 or text == "") then
			table.insert(shown, header)
			if not collapsed[header.header] then
				for _, r in ipairs(pending) do table.insert(shown, r) end
			end
		elseif not header then
			for _, r in ipairs(pending) do table.insert(shown, r) end
		end
		pending = {}
	end
	for _, r in ipairs(recipes) do
		if r.header then
			Flush()
			header = r
		elseif text == "" or r.name:lower():find(text, 1, true) then
			table.insert(pending, r)
		end
	end
	Flush()
end

local function Build()
	local classic = HasTemplate("ButtonFrameTemplate")
	if classic then
		frame = CreateFrame("Frame", "SkatteverketRecipeFrame", UIParent, "ButtonFrameTemplate")
	else
		frame = CreateFrame("Frame", "SkatteverketRecipeFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
		frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -6, -6)
	end
	if frame.Inset then frame.Inset:Hide() end
	frame:SetSize(W, H)
	frame:SetPoint("CENTER", 200, 0)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "SkatteverketRecipeFrame")
	frame.title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
	if not frame.title then
		frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.title:SetPoint("TOP", 0, -16)
	end
	frame.portrait = frame.portrait or frame.Portrait or (frame.PortraitContainer and frame.PortraitContainer.portrait)

	-- The skill bar under the title, as in the profession window
	-- (screenshot 7/11): framed, blue, the name on the left and rank/cap.
	local bar = CreateFrame("StatusBar", nil, frame, BackdropTemplateMixin and "BackdropTemplate")
	bar:SetSize(W - 84, 16)
	bar:SetPoint("TOPLEFT", 64, -30)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(0, 0.3, 0.85)
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	barBg:SetColorTexture(0.12, 0.12, 0.2, 0.9)
	if bar.SetBackdrop then
		-- A thin grey edge, a little outside the bar.
		local edge = CreateFrame("Frame", nil, bar, "BackdropTemplate")
		edge:SetPoint("TOPLEFT", -3, 3)
		edge:SetPoint("BOTTOMRIGHT", 3, -3)
		edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
		edge:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	end
	bar.text = Text(bar, "GameFontHighlightSmall", "LEFT", 8, 0)
	bar.value = Text(bar, "GameFontHighlightSmall", "LEFT", bar.text, "RIGHT", 24, 0)
	frame.bar = bar

	-- Search, top left of the list.
	local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	search:SetSize(160, 20)
	search:SetPoint("TOPLEFT", 78, -54)
	search:SetAutoFocus(false)
	search:SetScript("OnEscapePressed", search.ClearFocus)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnTextChanged", function(self)
		filterText = strtrim(self:GetText() or "")
		offset = 0
		ns.RefreshRecipeWindow()
	end)
	Text(frame, "GameFontNormalSmall", "RIGHT", search, "LEFT", -8, 0):SetText("Sök")
	frame.search = search
	frame.shared = Text(frame, "GameFontDisableSmall", "LEFT", search, "RIGHT", 12, 0)

	-- The list.
	local list = Inset(frame, "TOPLEFT", 10, -80)
	list:SetSize(W - 20, LIST_ROWS * ROW_H + 12)
	for i = 1, LIST_ROWS do
		local row = CreateFrame("Button", nil, list)
		row:SetSize(W - 36, ROW_H)
		row:SetPoint("TOPLEFT", 8, -6 - (i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.selected = row:CreateTexture(nil, "BACKGROUND")
		row.selected:SetAllPoints()
		row.selected:SetColorTexture(0.5, 0.5, 0.5, 0.35)
		row.toggle = row:CreateTexture(nil, "ARTWORK")
		row.toggle:SetSize(14, 14)
		row.toggle:SetPoint("LEFT", 0, 0)
		row.text = Text(row, "GameFontNormal", "LEFT", 18, 0)
		row.text:SetWidth(W - 60)
		row.text:SetWordWrap(false)
		row:SetScript("OnClick", function(self)
			local r = self.row
			if not r then return end
			if r.header then
				collapsed[r.header] = not collapsed[r.header]
			elseif IsShiftKeyDown() then
				InsertLink(ns.RecipeChatLink(r.key))
				return
			else
				selected = r
			end
			ns.RefreshRecipeWindow()
		end)
		row:SetScript("OnEnter", Tooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = row
	end
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta * 2, #shown - LIST_ROWS))
		ns.RefreshRecipeWindow()
	end)
	frame.scrollNote = Text(frame, "GameFontDisableSmall", "TOPRIGHT", list, "BOTTOMRIGHT", -4, -2)
	frame.scrollNote:SetJustifyH("RIGHT")

	-- The selected recipe: icon, name and reagents.
	local detail = Inset(frame, "TOPLEFT", list, "BOTTOMLEFT", 0, -16)
	detail:SetPoint("BOTTOMRIGHT", -10, 32)
	local icon = CreateFrame("Button", nil, detail)
	icon:SetSize(40, 40)
	icon:SetPoint("TOPLEFT", 10, -10)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints()
	icon:SetScript("OnEnter", Tooltip)
	icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	icon:SetScript("OnClick", function(self) if IsShiftKeyDown() and selected then InsertLink(ns.RecipeChatLink(selected.key)) end end)
	frame.icon = icon
	frame.name = Text(detail, "GameFontNormalLarge", "TOPLEFT", icon, "TOPRIGHT", 10, -2)
	frame.name:SetWidth(W - 100)
	frame.reagentTitle = Text(detail, "GameFontNormal", "TOPLEFT", 10, -60)
	frame.reagentTitle:SetText("Reagenser:")
	for i = 1, 8 do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local b = CreateFrame("Button", nil, detail)
		b:SetSize(186, 38)
		b:SetPoint("TOPLEFT", 10 + col * 196, -78 - row * 42)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(36, 36)
		b.icon:SetPoint("LEFT", 0, 0)
		b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -2, 2)
		local box = b:CreateTexture(nil, "BACKGROUND")
		box:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 2, 0)
		box:SetPoint("BOTTOMRIGHT", 0, 1)
		box:SetColorTexture(0, 0, 0, 0.45)
		b.name = Text(b, "GameFontHighlightSmall", "LEFT", b.icon, "RIGHT", 8, 0)
		b.name:SetWidth(136)
		b:SetScript("OnEnter", Tooltip)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		reagents[i] = b
	end
	frame.empty = Text(detail, "GameFontDisable", "CENTER", detail, "CENTER", 0, 0)
	frame.empty:SetJustifyH("CENTER")
	frame.empty:SetWidth(W - 60)

	-- Buttons along the bottom, as Create All, Create and Exit.
	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(90, 22)
	close:SetText("Stäng")
	close:SetPoint("BOTTOMRIGHT", -8, 6)
	close:SetScript("OnClick", function() frame:Hide() end)
	frame.whisper = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.whisper:SetSize(110, 22)
	frame.whisper:SetText("Viska")
	frame.whisper:SetPoint("RIGHT", close, "LEFT", -4, 0)
	frame.whisper:SetScript("OnClick", function()
		if not who then return end
		if ChatFrame_SendTell then ChatFrame_SendTell(who)
		elseif ChatFrameUtil and ChatFrameUtil.SendTell then ChatFrameUtil.SendTell(who) end
	end)
	-- Arbetsorder (Zach 9/11): order the selected recipe from this member.
	frame.order = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.order:SetSize(90, 22)
	frame.order:SetText("Beställ")
	frame.order:SetPoint("RIGHT", frame.whisper, "LEFT", -4, 0)
	frame.order:SetScript("OnClick", function()
		if who and selected and selected.key then ns.OrderDialog(who, selected.key) end
	end)
	frame.note = Text(frame, "GameFontDisableSmall", "BOTTOMLEFT", 14, 12)
	frame.note:SetWidth(W - 320)

	frame:SetScript("OnUpdate", function(self, elapsed)
		-- Item names and icons load in the background; show them as they come.
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed > 1 then
			self.elapsed = 0
			ns.RefreshRecipeWindow(true)
		end
	end)
	frame:Hide()
end

function ns.ShowMember(name, profession)
	if not name or not profession then return end
	if not frame then Build() end
	who, code, offset, selected, filterText = name, profession, 0, nil, ""
	wipe(collapsed)
	frame.search:SetText("")
	local p = ns.PROFESSION_BY_CODE[code]
	frame.title:SetText(name .. " - " .. p.label)
	if frame.portrait then
		if frame.SetPortraitToAsset then frame:SetPortraitToAsset("Interface\\Icons\\" .. p.icon)
		else frame.portrait:SetTexture("Interface\\Icons\\" .. p.icon) end
	end
	frame:Show()
	ns.RefreshRecipeWindow()
end

function ns.RefreshRecipeWindow(quiet)
	if not frame or not frame:IsShown() or not who then return end
	local p = ns.PROFESSION_BY_CODE[code]
	local at
	recipes, at = ns.MemberRecipes(who, code)
	-- Keep the selection across refreshes, by key.
	if selected and selected.key then
		for _, r in ipairs(recipes) do if r.key == selected.key then selected = r end end
	end
	if not selected then
		for _, r in ipairs(recipes) do if r.key then selected = r break end end
	end
	Visible()
	offset = math.max(0, math.min(offset, #shown - LIST_ROWS))

	-- Your own level live from the game; others' as last shared.
	local m = ns.db.members[who]
	local level = m and ns.DecodeProfessions(m.profs)[code]
	if who == ns.Me() then level = ns.ReadProfessions()[code] or level end
	-- The cap comes with 0.20 and later; before that, the next step up from the rank.
	local cap = level and level.max
	if level and not cap then
		cap = 75
		while cap < level.rank do cap = cap + 75 end
	end
	frame.bar:SetMinMaxValues(0, cap or 1)
	frame.bar:SetValue(level and level.rank or 0)
	frame.bar.text:SetText(p.label)
	frame.bar.value:SetText(level and string.format("%d/%d", level.rank, cap) or "")
	frame.shared:SetText(at and ("Delat " .. ns.Day(at)) or "")

	for i, row in ipairs(rows) do
		local r = shown[i + offset]
		row.row = r
		row.link = nil
		if r and r.header then
			row.toggle:SetTexture(collapsed[r.header] and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
			row.toggle:Show()
			row.text:SetPoint("LEFT", 18, 0)
			row.text:SetText(r.header)
			row.text:SetTextColor(1, 0.82, 0)
			row.selected:Hide()
			row:Show()
		elseif r then
			row.toggle:Hide()
			row.text:SetPoint("LEFT", 26, 0)
			row.text:SetText(r.name)
			local c = COLOURS[r.colour] or { 1, 1, 1 }
			row.text:SetTextColor(c[1], c[2], c[3])
			row.link = ns.RecipeLink(r.key)
			if r == selected then row.selected:Show() else row.selected:Hide() end
			row:Show()
		else
			row:Hide()
		end
	end
	frame.scrollNote:SetText(#shown > LIST_ROWS and string.format("%d-%d av %d, scrolla med mushjulet", offset + 1, math.min(offset + LIST_ROWS, #shown), #shown) or "")

	local d = selected and ns.RecipeData(selected.key)
	local hasRecipe = selected ~= nil
	frame.icon:SetShown(hasRecipe)
	frame.name:SetShown(hasRecipe)
	frame.reagentTitle:SetShown(hasRecipe and d ~= nil and #d.reagents > 0)
	if hasRecipe then
		frame.empty:SetText("")
		frame.icon.texture:SetTexture((d and d.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
		frame.icon.link = ns.RecipeLink(selected.key)
		-- Only the name in its colour, as in the profession window (Zach 7/11).
		frame.name:SetText(selected.name)
		local c = COLOURS[selected.colour] or { 1, 0.82, 0 }
		frame.name:SetTextColor(c[1], c[2], c[3])
	else
		frame.empty:SetText(at and "Inga recept att visa." or (who .. " har inte delat sina recept än. De delas när de öppnar sitt yrkesfönster med Skatteverket."))
	end
	for i, b in ipairs(reagents) do
		local reagent = hasRecipe and d and d.reagents[i]
		if reagent then
			b.icon:SetTexture(ns.ItemIcon(reagent.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
			-- What you have / what is needed, as in the profession window.
			local have = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(reagent.itemID)) or (GetItemCount and GetItemCount(reagent.itemID)) or 0
			b.count:SetText(have .. "/" .. reagent.count)
			b.name:SetText(ns.ItemName(reagent.itemID) or "...")
			b.link = "item:" .. reagent.itemID
			b:Show()
		else
			b:Hide()
		end
	end
	-- Citizens only, both ends (Zach 9/11).
	frame.order:SetShown(not ns.Locked())
	if selected and selected.key and who ~= ns.Me() and ns.IsCitizen(who) then frame.order:Enable() else frame.order:Disable() end
	if not quiet then
		local online = ns.Online(who)
		if online then frame.whisper:Enable() else frame.whisper:Disable() end
		frame.note:SetText(online and "Shift-klicka för att länka i chatten." or "Offline just nu, skicka post.")
	end
end
