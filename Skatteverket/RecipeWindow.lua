-- Skatteverket, a member's recipes in a window like the game's own
-- profession window (Zach 7/11, screenshot of Forever's): portrait with the
-- profession icon, the skill bar, a search box, the list with categories
-- that open and close and recipes coloured as they are for that member,
-- and below it the selected recipe with its reagents. Blizzard's window
-- cannot be opened with someone else's data on Forever (no profession
-- link API), so this one is built from what they share.

local _, ns = ...

-- The classic profession window's measures (Zach 10/11, screenshot): about
-- 350 wide, rows of 16, a 265 wide skill bar of 14, reagents of 147 x 41.
local W, H = 350, 500
local LIST_ROWS, ROW_H = 8, 16
local COLOURS = { o = { 1, 0.5, 0.25 }, y = { 1, 1, 0 }, g = { 0.25, 0.75, 0.25 }, x = { 0.5, 0.5, 0.5 } }

local frame, rows, reagents = nil, {}, {}
local who, code, recipes, shown, collapsed, selected, offset, filterText = nil, nil, {}, {}, {}, nil, 0, ""

-- BPP, billigast per poäng (Zach 11/11, the guild leader only): the
-- member's recipes ranked by what one expected skill point costs to buy
-- the materials for. Expected points by colour (orange sure, yellow
-- likely, green a long shot); prices from Bokföring (vendor or Auctionator,
-- the lower). A recipe whose own steps give points (RawPlan) counts them
-- too, and is ranked by the raw materials when that is cheaper per point.
local WEIGHT = { o = 1, y = 0.75, g = 0.25 }
local COLOUR_WORD = { o = "orange", y = "gul", g = "grön" }
local bpp, ranked, info, rankPending = false, {}, {}, false

local function CanBPP()
	return IsGuildLeader() and BokforingAPI and BokforingAPI.Price ~= nil
end

local function Cost(list, price)
	local total = 0
	for _, r in ipairs(list) do
		local p = price(r.itemID)
		if not p then return end
		total = total + p * r.count
	end
	return total
end

local function Rank()
	wipe(ranked)
	wipe(info)
	rankPending = false
	if not CanBPP() then return end
	local price = BokforingAPI.Price
	for _, r in ipairs(recipes) do
		local points = r.key and WEIGHT[r.colour]
		local d = points and ns.RecipeData(r.key)
		if points and not d then rankPending = true end
		if d and #d.reagents > 0 then
			local best = { cost = Cost(d.reagents, price), points = points }
			local raw, steps = ns.RawPlan(who, r.key, 1)
			if raw then
				local p = points
				for _, st in ipairs(steps) do p = p + st.crafts * (WEIGHT[st.colour] or 0) end
				local c = Cost(raw, price)
				if c and (not best.cost or c / p < best.cost / best.points) then best = { cost = c, points = p, steps = steps } end
			end
			if best.cost then best.per = best.cost / best.points end
			info[r] = best
			table.insert(ranked, r)
		end
	end
	-- Cheapest first; those without a price last, by name.
	table.sort(ranked, function(a, b)
		local x, y = info[a].per, info[b].per
		if x and y and x ~= y then return x < y end
		if (x == nil) ~= (y == nil) then return x ~= nil end
		return a.name < b.name
	end)
end

-- "1g 20s" or "35s 40c": short enough for a row.
local function Short(copper)
	copper = math.floor(copper + 0.5)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return string.format("%dg %ds", g, s) end
	if s > 0 then return string.format("%ds %dc", s, c) end
	return c .. "c"
end

local function Decimal(n)
	return (string.format("%.2f", n):gsub("%.?0+$", ""):gsub("%.", ","))
end

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
	local b = bpp and self.row and info[self.row]
	if b then
		GameTooltip:AddLine(" ")
		if b.per then
			GameTooltip:AddLine(string.format("BPP: %s per poäng", Short(b.per)), 1, 0.82, 0)
			GameTooltip:AddLine(string.format("Ett craft kostar %s och ger ungefär %s poäng.", Short(b.cost), Decimal(b.points)), 1, 1, 1, true)
		else
			GameTooltip:AddLine("Inget pris för allt som behövs: öppna Auctionator och skanna.", 1, 0.3, 0.3, true)
		end
		if b.steps then
			local made = {}
			for _, st in ipairs(b.steps) do
				table.insert(made, string.format("%d %s (%s)", st.crafts, ns.ItemName(st.itemID) or "...", COLOUR_WORD[st.colour] or "?"))
			end
			GameTooltip:AddLine("Med råvaror, hen gör själv: " .. table.concat(made, ", "), 0.6, 0.8, 1, true)
		end
	end
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
	if bpp then
		for _, r in ipairs(ranked) do
			if text == "" or r.name:lower():find(text, 1, true) then table.insert(shown, r) end
		end
		return
	end
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

	-- The skill bar under the title, as in the classic profession window
	-- (Zach 10/11, screenshot): the character sheet's skill bar art, half
	-- blue on a faint blue ground, its own border, the name in gold and the
	-- rank in white.
	local bar = CreateFrame("StatusBar", nil, frame)
	bar:SetSize(265, 14)
	bar:SetPoint("TOPLEFT", 66, -34)
	bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
	bar:SetStatusBarColor(0, 0, 1, 0.5)
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	barBg:SetColorTexture(0, 0, 0.75, 0.25)
	local border = bar:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder")
	border:SetSize(274, 27)
	border:SetPoint("LEFT", -5, 0)
	bar.text = Text(bar, "GameFontNormalSmall", "LEFT", 6, 1)
	bar.value = Text(bar, "GameFontHighlightSmall", "LEFT", bar.text, "RIGHT", 13, 0)
	frame.bar = bar

	-- Above the list as in the classic window (Zach 10/11): All with its
	-- minus to close or open every category, the search box with its
	-- placeholder, and where Filter sits, when it was shared.
	local all = CreateFrame("Button", nil, frame)
	all:SetSize(60, 16)
	all:SetPoint("TOPLEFT", 16, -58)
	all.toggle = all:CreateTexture(nil, "ARTWORK")
	all.toggle:SetSize(16, 16)
	all.toggle:SetPoint("LEFT")
	all.text = Text(all, "GameFontNormal", "LEFT", 18, 0)
	all.text:SetText("Alla")
	all:SetScript("OnClick", function()
		local open = false
		for _, r in ipairs(recipes) do
			if r.header and not collapsed[r.header] then open = true end
		end
		for _, r in ipairs(recipes) do
			if r.header then collapsed[r.header] = open or nil end
		end
		offset = 0
		ns.RefreshRecipeWindow()
	end)
	frame.all = all

	local boxed = HasTemplate("SearchBoxTemplate")
	local search = CreateFrame("EditBox", nil, frame, boxed and "SearchBoxTemplate" or "InputBoxTemplate")
	search:SetSize(150, 20)
	search:SetPoint("TOPLEFT", 92, -56)
	search:SetAutoFocus(false)
	if search.Instructions then search.Instructions:SetText("Sök") end
	search:SetScript("OnEscapePressed", search.ClearFocus)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:HookScript("OnTextChanged", function(self)
		filterText = strtrim(self:GetText() or "")
		offset = 0
		ns.RefreshRecipeWindow()
	end)
	if not boxed then Text(frame, "GameFontNormalSmall", "RIGHT", search, "LEFT", -8, 0):SetText("Sök") end
	frame.search = search
	frame.shared = Text(frame, "GameFontDisableSmall", "TOPRIGHT", -18, -61)
	frame.shared:SetJustifyH("RIGHT")

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
		row.toggle:SetSize(16, 16)
		row.toggle:SetPoint("LEFT", 0, 0)
		row.text = Text(row, "GameFontNormal", "LEFT", 18, 0)
		row.text:SetWidth(W - 60)
		row.text:SetWordWrap(false)
		row.cost = Text(row, "GameFontHighlightSmall", "RIGHT", -4, 0)
		row.cost:SetJustifyH("RIGHT")
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
		b:SetSize(147, 41)
		b:SetPoint("TOPLEFT", 8 + col * 152, -78 - row * 43)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(39, 39)
		b.icon:SetPoint("LEFT", 0, 0)
		b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -2, 2)
		local box = b:CreateTexture(nil, "BACKGROUND")
		box:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 2, 0)
		box:SetPoint("BOTTOMRIGHT", 0, 1)
		box:SetColorTexture(0, 0, 0, 0.45)
		b.name = Text(b, "GameFontHighlightSmall", "LEFT", b.icon, "RIGHT", 8, 0)
		b.name:SetWidth(96)
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
	frame.whisper:SetSize(90, 22)
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
	frame.bpp = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.bpp:SetSize(50, 22)
	frame.bpp:SetText("BPP")
	frame.bpp:SetPoint("BOTTOMLEFT", 6, 6)
	frame.bpp:SetScript("OnClick", function(self)
		bpp = not bpp
		offset = 0
		if bpp then self:LockHighlight() else self:UnlockHighlight() end
		ns.RefreshRecipeWindow()
	end)
	frame.bpp:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Billigast per poäng")
		GameTooltip:AddLine("Recepten sorterade efter vad en färdighetspoäng kostar i material för den här medlemmen. Orange ger 1 poäng, gul ungefär 0,75, grön 0,25, grå ingenting. Priser från säljare och Auctionator, det lägre. Gör hen själv en reagens som ger poäng räknas råvarorna när det blir billigare per poäng.", 1, 1, 1, true)
		GameTooltip:AddLine("Klicka igen för vanliga listan. Bara du ser knappen.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	frame.bpp:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- Inside the details at the bottom: the buttons take the whole width.
	frame.note = Text(detail, "GameFontDisableSmall", "BOTTOMLEFT", 10, 6)
	frame.note:SetWidth(W - 40)

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
	if bpp and (not CanBPP() or who == ns.Me()) then
		bpp = false
		frame.bpp:UnlockHighlight()
	end
	if bpp and (not quiet or rankPending) then Rank() end
	if not selected then
		for _, r in ipairs(bpp and ranked or recipes) do if r.key then selected = r break end end
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
	local anyOpen = false
	for _, r in ipairs(recipes) do
		if r.header and not collapsed[r.header] then anyOpen = true end
	end
	frame.all.toggle:SetTexture(anyOpen and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")

	for i, row in ipairs(rows) do
		local r = shown[i + offset]
		row.row = r
		row.link = nil
		row.cost:SetText("")
		row.text:SetWidth(bpp and W - 120 or W - 60)
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
			local b = bpp and info[r]
			if b then row.cost:SetText(b.per and (Short(b.per) .. "/p") or "|cff808080inget pris|r") end
			-- By key: the list is read anew every second, while BPP keeps its
			-- ranking from the last full refresh (Zach 11/11: the grey bar went).
			if selected and r.key == selected.key then row.selected:Show() else row.selected:Hide() end
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
	frame.bpp:SetShown(CanBPP() and who ~= ns.Me())
	if selected and selected.key and who ~= ns.Me() and ns.IsCitizen(who) then frame.order:Enable() else frame.order:Disable() end
	if not quiet then
		local online = ns.Online(who)
		if online then frame.whisper:Enable() else frame.whisper:Disable() end
		frame.note:SetText((bpp and "BPP: billigast per poäng först. " or "") .. (online and "Shift-klicka för att länka i chatten." or "Offline just nu, skicka post."))
	end
end
