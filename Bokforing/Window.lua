-- Bokföring's list (Zach 8/11): his recipes by profit per craft, in the
-- classic panel look with dropdowns for the view and the profession (Zach
-- 9/11). Opened with /bok or the button above a profession
-- window, which shows that profession only. Hover a row for what goes into
-- it and where each reagent is cheapest.
-- Three views (Zach 9/11): his own recipes (the baseline), all recipes with
-- those guild members share, and gathering prices. The history and the
-- market are side tabs (Zach 9/11); the search box filters the recipes and
-- the market's items.

local _, ns = ...

local W, H, ROWS, ROW_H = 730, 460, 18, 18
local COLOURS = { o = { 1, 0.5, 0.25 }, y = { 1, 1, 0 }, g = { 0.25, 0.75, 0.25 }, x = { 0.6, 0.6, 0.6 }, w = { 1, 1, 1 } }
-- The columns, defined below the helpers they use; he picks which show
-- (Zach 9/11: right-click a header), saved for the account.
local COLUMNS, GATHER, Shown
local MAX_COLUMNS = 16
local OLD_DAYS = 2
local SKILL_HEX = { o = "ff8040", y = "ffff00", g = "40c040", x = "808080", r = "ff4040" }
local MODES = { "mine", "all", "gather" }
local MODE_NAMES = { mine = "My recipes", all = "All recipes", gather = "Gathering" }
-- Side tabs on the right edge (Zach 9/11): the list, what he is making now
-- from his shopping lists, and the history of what crafting through
-- Bokföring really earned.
local TABS = { { "today", "Today", "Interface\\Icons\\INV_Misc_PocketWatch_01" }, { "recipes", "Recipes", "Interface\\Icons\\INV_Scroll_03" }, { "work", "Making now", "Interface\\Icons\\INV_Hammer_20" },
	{ "market", "Market", "Interface\\Icons\\INV_Misc_Spyglass_03" }, { "history", "History", "Interface\\Icons\\INV_Misc_Book_09" } }

local frame, rows, list, offset = nil, {}, {}, 0
local profession, skillUps
local sellable = true
-- Level up (Zach 10/11): the crafts that raise this character's skill
-- for the least gold, or the most, money per skill point first; with Can
-- learn also recipes to buy. Me dumb, me craft now became the Today tab.
local levelUp = false
-- Profit a day first: what actually brings money in (Zach 9/11).
local sortKey, sortUp = "perDay", false
local mode = "mine"
-- Today first (Zach 10/11): the page that tells what to do.
local page = "today"
-- Recipes to go and get (Zach 10/11): not learned on this character and
-- its skill is enough, or more skill is needed first; a left-click on one
-- folds out where it comes from.
local canLearn, needSkill = false, false
local Counts
local expanded = {}

local function Text(parent, font, x, width, justify)
	local t = parent:CreateFontString(nil, "OVERLAY", font)
	t:SetPoint("LEFT", x, 0)
	t:SetWidth(width)
	t:SetJustifyH(justify or "RIGHT")
	t:SetWordWrap(false)
	return t
end

local function ListingLine(r)
	if r.quantity then
		if r.quantity == 0 then
			GameTooltip:AddLine("None for sale at the last scan: no competition. The price is from the last time one was seen.", 0.25, 1, 0.25, true)
		end
		local few = r.quantity > 0 and r.quantity < ns.FEW
		local auctions = r.listed and r.listed > 0 and string.format(" in %d auction%s", r.listed, r.listed == 1 and "" or "s") or ""
		GameTooltip:AddLine(string.format("%d for sale%s at the last scan%s", r.quantity, auctions, few and ": a thin market" or ""),
			few and 1 or 0.6, few and 0.3 or 0.6, few and 0.3 or 0.6)
	else
		GameTooltip:AddLine("For sale unknown: scan with Auctionator at the auction house", 0.6, 0.6, 0.6)
	end
end

-- Seconds as "45s" or "2m 05s".
local function Seconds(t)
	if not t then return "|cff808080?|r" end
	t = math.floor(t + 0.5)
	if t < 60 then return t .. "s" end
	return string.format("%dm %02ds", math.floor(t / 60), t % 60)
end

local function Tooltip(row)
	local r = row.data
	if not r then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if mode == "gather" then
		GameTooltip:SetItemByID(r.item)
		ListingLine(r)
		GameTooltip:Show()
		return
	end
	if r.learn then
		local info = ns.LearnInfo(r.parent.recipe)
		if info.item then GameTooltip:SetItemByID(info.item) else GameTooltip:AddLine(r.parent.recipe.name or "?") end
		GameTooltip:AddLine(ns.LearnLine(r.parent.recipe), 0.25, 1, 0.25, true)
		GameTooltip:Show()
		return
	end
	GameTooltip:AddLine(r.recipe.name or ns.ItemName(r.recipe.item))
	if r.recipe.qty ~= 1 then GameTooltip:AddLine(string.format("Makes %g", r.recipe.qty), 0.7, 0.7, 0.7) end
	for _, b in ipairs(ns.Breakdown(r.id)) do
		GameTooltip:AddDoubleLine(string.format("%d x %s", b.count, b.name),
			b.each and string.format("%s (%s)", ns.Money(b.each * b.count), b.source) or "no price", 1, 1, 1, 0.8, 0.8, 0.8)
		if b.madeEach then
			GameTooltip:AddDoubleLine("    or make it: " .. (b.via or "?"), ns.Money(b.madeEach * b.count), 0.25, 1, 0.25, 0.25, 1, 0.25)
		end
	end
	-- Making the reagents yourself (Zach 9/11): what it changes.
	if r.costMade and r.cost and r.costMade < r.cost then
		local profit = r.sells and (r.sells - r.costMade)
		GameTooltip:AddLine(string.format("Making the reagents yourself: cost %s%s, %s more a craft",
			ns.Money(r.costMade), profit and (", profit " .. ns.Money(profit)) or "", ns.Money(r.cost - r.costMade)), 0.25, 1, 0.25, true)
	end
	-- Raw or bought reagents (Zach 9/11): the gold against the time.
	if r.time then
		GameTooltip:AddLine(string.format("Time per craft: %s with bought reagents%s", Seconds(r.time),
			r.profitMade and r.timeMade and (", " .. Seconds(r.timeMade) .. " from raw") or ""), 0.6, 0.6, 0.6)
	end
	if r.rawWorth ~= nil then
		local extra = r.timeMade and r.time and r.timeMade - r.time
		GameTooltip:AddLine(string.format("From raw: %s more profit each%s", ns.Money(r.cost - r.costMade),
			extra and extra > 0 and string.format(" for %s more each", Seconds(extra)) or ""), 1, 1, 1, true)
		if r.rawPerMin and r.buyPerMin then
			GameTooltip:AddLine(string.format("The extra time earns %s a minute; crafting with bought reagents earns %s a minute.",
				ns.Money(r.rawPerMin), ns.Money(r.buyPerMin)), 0.8, 0.8, 0.8, true)
		end
		if r.rawWorth then
			GameTooltip:AddLine("Worth crafting from raw.", 0.25, 1, 0.25)
		else
			GameTooltip:AddLine("Not worth it: buy the reagents.", 1, 0.5, 0.25)
		end
	end
	ListingLine(r)
	if r.sold then
		GameTooltip:AddLine(string.format("Sold/day %.1f, from %d hours of scans", r.sold, ns.SoldBasis(r.recipe.item)), 0.6, 0.6, 0.6)
	end
	if r.perPoint then
		GameTooltip:AddLine(string.format("Level up: %d crafts to %s, %d skill points, %s a point%s.", r.levelN, r.levelTo, r.levelPoints,
			ns.Money(r.perPoint), r.recipePrice and r.recipePrice > 0 and (", the recipe's " .. ns.Money(r.recipePrice) .. " included") or ""),
			r.perPoint >= 0 and 0.25 or 1, r.perPoint >= 0 and 1 or 0.5, 0.25, true)
		GameTooltip:AddLine("Sales count as many as two days of the market take; the rest at the vendor's price.", 0.6, 0.6, 0.6, true)
	end
	if r.myCount then
		GameTooltip:AddLine(string.format("You sold %d in the last 7 days, for %s", r.myCount, ns.Money(r.myMoney)), 0.25, 1, 0.25)
	end
	if r.age then
		local old = r.age > OLD_DAYS
		GameTooltip:AddLine(string.format("AH price %d day%s old", r.age, r.age == 1 and "" or "s"), old and 1 or 0.6, old and 0.3 or 0.6, old and 0.3 or 0.6)
	end
	local who = {}
	for name, c in pairs(r.recipe.by) do table.insert(who, name .. " (" .. c .. ")") end
	if #who > 0 then GameTooltip:AddLine("Known by " .. table.concat(who, ", "), 0.6, 0.6, 0.6, true) end
	local guild = {}
	for name in pairs(r.recipe.guild or {}) do table.insert(guild, name) end
	table.sort(guild)
	if #guild > 0 then GameTooltip:AddLine("In the guild: " .. table.concat(guild, ", "), 0.6, 0.6, 0.6, true) end
	local guide = ns.ColourGuide(r.id, r.skill)
	if guide then GameTooltip:AddLine(guide, 0.6, 0.6, 0.6, true) end
	if not r.recipe.by[ns.MeKey()] then GameTooltip:AddLine("Not learned on this character: click for where to get it", 0.6, 0.6, 0.6, true) end
	GameTooltip:Show()
end

-- An unknown template does not always raise an error; ask the client first.
local function HasTemplate(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then return C_XMLUtil.GetTemplateInfo(name) ~= nil end
	return true
end

-- The classic panel (Zach 9/11), as Skatteverket's: portrait, title bar
-- and a recessed inset. Falls back to the old dialog look.
local function Panel()
	local ok, f = false, nil
	if HasTemplate("ButtonFrameTemplate") then ok, f = pcall(CreateFrame, "Frame", "BokforingFrame", UIParent, "ButtonFrameTemplate") end
	if ok and f then
		local art = "Interface\\Icons\\INV_Misc_Coin_02"
		local portrait = f.portrait or f.Portrait or (f.PortraitContainer and f.PortraitContainer.portrait) or _G["BokforingFramePortrait"]
		if f.SetPortraitToAsset then f:SetPortraitToAsset(art) elseif portrait then portrait:SetTexture(art) end
		if portrait then portrait:Show() end
		local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
		if title then title:SetText("Bokföring") end
		if f.Inset then
			f.Inset:ClearAllPoints()
			f.Inset:SetPoint("TOPLEFT", 4, -84)
			f.Inset:SetPoint("BOTTOMRIGHT", -6, 30)
		end
		return f
	end
	f = CreateFrame("Frame", "BokforingFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -16)
	title:SetText("Bokföring")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	return f
end

-- A dropdown (Zach 9/11): the modern menu where the client has it, the old
-- UIDropDownMenu otherwise. options() gives { value, text } pairs, current()
-- the chosen value, choose(value) is called on a pick.
local function Dropdown(parent, width, options, current, choose)
	if HasTemplate("WowStyle1DropdownTemplate") then
		local ok, d = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
		if ok and d and d.SetupMenu then
			d:SetWidth(width)
			d:SetupMenu(function(_, root)
				for _, o in ipairs(options()) do
					root:CreateRadio(o[2], function() return current() == o[1] end, function() choose(o[1]) end)
				end
			end)
			d.Update = function(self) if self.GenerateMenu then self:GenerateMenu() end end
			return d
		end
	end
	local d = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
	UIDropDownMenu_SetWidth(d, width - 30)
	UIDropDownMenu_Initialize(d, function()
		for _, o in ipairs(options()) do
			local info = UIDropDownMenu_CreateInfo()
			info.text, info.checked = o[2], current() == o[1]
			info.func = function() choose(o[1]) end
			UIDropDownMenu_AddButton(info)
		end
	end)
	d.Update = function(self)
		for _, o in ipairs(options()) do
			if o[1] == current() then UIDropDownMenu_SetText(self, o[2]) end
		end
	end
	return d
end

-- A checkbox with its label on the right.
local function Checkbox(label, onClick)
	local c = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	c:SetSize(24, 24)
	local text = c.text or c.Text or c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:ClearAllPoints()
	text:SetPoint("LEFT", c, "RIGHT", 2, 0)
	text:SetFontObject("GameFontHighlight")
	text:SetText(label)
	c.label = text
	c:SetScript("OnClick", onClick)
	return c
end

local function Build()
	frame = Panel()
	frame:SetSize(W, H)
	frame:SetPoint("CENTER", 0, 40)
	-- The same layer as the THÖNDERSTÖRM panel, and to the front when
	-- clicked (Zach 9/11: one stuck behind the other).
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "BokforingFrame")

	-- Which view: his recipes (the baseline), all recipes, gathering.
	frame.view = Dropdown(frame, 150,
		function()
			local out = {}
			for _, m in ipairs(MODES) do table.insert(out, { m, MODE_NAMES[m] }) end
			return out
		end,
		function() return mode end,
		function(m)
			mode, profession, offset = m, nil, 0
			sortKey, sortUp = m == "gather" and "price" or "perDay", false
			ns.Refresh()
		end)
	frame.view:SetPoint("TOPLEFT", 70, -32)

	-- Which profession, from those in the chosen view.
	frame.pick = Dropdown(frame, 170,
		function()
			local out = { { "", "All professions" } }
			local all = mode == "gather" and ns.GATHER_PROFESSIONS or ns.Professions(mode == "all")
			for _, p in ipairs(all) do table.insert(out, { p, p }) end
			return out
		end,
		function() return profession or "" end,
		function(p)
			profession, offset = p ~= "" and p or nil, 0
			ns.Refresh()
		end)
	frame.pick:SetPoint("LEFT", frame.view, "RIGHT", 8, 0)

	local ups = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	ups:SetSize(24, 24)
	ups:SetPoint("LEFT", frame.pick, "RIGHT", 8, 0)
	local upsText = ups.text or ups.Text or ups:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	upsText:ClearAllPoints()
	upsText:SetPoint("LEFT", ups, "RIGHT", 2, 0)
	upsText:SetFontObject("GameFontHighlight")
	upsText:SetText("Skill-ups")
	ups:SetScript("OnClick", function(self)
		skillUps = self:GetChecked() and true or false
		offset = 0
		ns.Refresh()
	end)
	frame.ups = ups

	-- Sellable only (Zach 9/11, on by default): hide what has no auction price.
	local sell = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	sell:SetSize(24, 24)
	sell:SetPoint("LEFT", upsText, "RIGHT", 10, 0)
	local sellText = sell.text or sell.Text or sell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sellText:ClearAllPoints()
	sellText:SetPoint("LEFT", sell, "RIGHT", 2, 0)
	sellText:SetFontObject("GameFontHighlight")
	sellText:SetText("Sellable only")
	sell:SetChecked(sellable)
	frame.sell = sell
	sell:SetScript("OnClick", function(self)
		sellable = self:GetChecked() and true or false
		offset = 0
		ns.Refresh()
	end)

	-- A ? by the close button: every command on hover, in chat on a click
	-- (Zach 10/11: /bok help should show on Bokföring itself).
	local help = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	help:SetSize(22, 20)
	help:SetPoint("TOPRIGHT", -28, -1)
	help:SetText("?")
	help:SetFrameLevel(frame:GetFrameLevel() + 10)
	help:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:AddLine("Bokföring: commands")
		for _, line in ipairs(ns.HELP) do GameTooltip:AddDoubleLine(line[1], line[2], 1, 0.82, 0, 1, 1, 1) end
		GameTooltip:AddLine("Click to write them in chat.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	help:SetScript("OnLeave", function() GameTooltip:Hide() end)
	help:SetScript("OnClick", function() SlashCmdList.BOKFORING("help") end)

	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.status:SetPoint("TOPRIGHT", -16, -40)
	frame.status:SetJustifyH("RIGHT")

	local header = CreateFrame("Frame", nil, frame)
	header:SetSize(W - 40, ROW_H)
	header:SetPoint("TOPLEFT", 20, -88)
	frame.header = header
	frame.heads = {}
	for j = 1, MAX_COLUMNS do
		local b = CreateFrame("Button", nil, header)
		b:SetSize(10, ROW_H)
		b.text = Text(b, "GameFontNormalSmall", 0, 10)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		-- Click to sort by it, again to turn the order round; names A-Z first,
		-- numbers largest first. Right-click: which columns show.
		b:SetScript("OnClick", function(self, mouse)
			if mouse == "RightButton" then
				if mode ~= "gather" then ns.ColumnMenu(self) end
				return
			end
			if not self.key then return end
			if sortKey == self.key then sortUp = not sortUp else sortKey, sortUp = self.key, self.key == "name" or self.key == "profession" end
			offset = 0
			ns.Refresh()
		end)
		frame.heads[j] = b
	end

	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(W - 40, ROW_H)
		row:SetPoint("TOPLEFT", 20, -88 - i * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.cells = {}
		for j = 1, MAX_COLUMNS do row.cells[j] = Text(row, "GameFontHighlightSmall", 0, 10) end
		row.wide = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.wide:SetPoint("LEFT", 24, 0)
		row.wide:SetPoint("RIGHT", -4, 0)
		row.wide:SetJustifyH("LEFT")
		row.wide:SetWordWrap(false)
		row:SetScript("OnEnter", Tooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		-- Shift-click links the item in chat; right-click a recipe for the
		-- shopping list (Zach 9/11).
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, mouse)
			if mouse == "RightButton" then
				local d = self.data
				if d and d.learn then
					local item = ns.LearnInfo(d.parent.recipe).item
					if item then ns.RecipeMenu(self, item) end
				elseif d and d.recipe and d.cost ~= nil then
					ns.ShopMenu(self, d)
				end
				return
			end
			local data = self.data
			-- The fold-out: shift-click links the recipe item.
			if data and data.learn then
				local info = ns.LearnInfo(data.parent.recipe)
				if IsModifiedClick("CHATLINK") then
					local link = ns.ItemLink(info.item)
					if link then ChatEdit_InsertLink(link) end
				else
					ns.ShowItemRef(info.item)
				end
				return
			end
			local item = data and (data.item or data.recipe.item)
			if item and IsModifiedClick("CHATLINK") then
				local link = ns.ItemLink(item)
				if link then ChatEdit_InsertLink(link) end
				return
			end
			-- Not learned here: open or close where to get it.
			if data and data.recipe and not data.recipe.by[ns.MeKey()] then
				expanded[data.id] = not expanded[data.id] or nil
				ns.Refresh()
			end
		end)
		rows[i] = row
	end
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta * 3, #list - ROWS))
		ns.Refresh()
	end)

	local d = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	d:SetSize(24, 24)
	d:SetPoint("TOPLEFT", 68, -58)
	local dText = d.text or d.Text or d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	dText:ClearAllPoints()
	dText:SetPoint("LEFT", d, "RIGHT", 2, 0)
	dText:SetFontObject("GameFontNormal")
	dText:SetText("Level up")
	d:SetScript("OnClick", function(self)
		levelUp = self:GetChecked() and true or false
		if levelUp then sortKey, sortUp = "perPoint", false end
		offset = 0
		ns.Refresh()
	end)
	d:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:AddLine("Level up")
		GameTooltip:AddLine("The crafts that raise this character's skill, the most gold per skill point first: those that pay for themselves on top, then the cheapest. Crafts: how many until the recipe turns green (or grey). With Can learn: recipes to buy too, their price included.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	d:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.levelBox = d

	-- Search (Zach 9/11): a recipe by its name or a reagent's, and on the
	-- Market tab an item by its name.
	local search = CreateFrame("EditBox", nil, frame, HasTemplate("SearchBoxTemplate") and "SearchBoxTemplate" or "InputBoxTemplate")
	search:SetSize(170, 20)
	search:SetPoint("TOPLEFT", 300, -60)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function(self)
		local text = strtrim(self:GetText() or ""):lower()
		if text == ns.search then return end
		ns.search, offset = text, 0
		ns.Refresh()
	end)
	frame.search = search

	local function Learn(self)
		if self == frame.canLearn then canLearn = self:GetChecked() and true or false else needSkill = self:GetChecked() and true or false end
		-- Unlearned recipes are in All recipes; lowest skill first; and a
		-- missing auction price must not hide a recipe to learn (Zach 10/11).
		if (canLearn or needSkill) and mode == "mine" then mode = "all" end
		if canLearn or needSkill then
			sellable = false
			frame.sell:SetChecked(false)
		end
		if canLearn or needSkill then sortKey, sortUp = "skill", true end
		offset = 0
		ns.Refresh()
	end
	frame.canLearn = Checkbox("Can learn", Learn)
	frame.canLearn:SetPoint("TOPLEFT", 478, -58)
	frame.canLearn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:AddLine("Can learn")
		GameTooltip:AddLine("Recipes this character has not learned and has the skill for now, lowest skill first. Click one for where to get it.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame.canLearn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.needSkill = Checkbox("Need skill", Learn)
	frame.needSkill:SetPoint("LEFT", frame.canLearn.label, "RIGHT", 10, 0)
	frame.needSkill:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:AddLine("Need skill")
		GameTooltip:AddLine("Recipes that need more skill than this character has, lowest first: what to aim for. ? means the skill is not known yet; visiting the trainer fills it in.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame.needSkill:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- The side tabs, as the spellbook's on the right edge.
	frame.tabs = {}
	for k, t in ipairs(TABS) do
		local tab = CreateFrame("CheckButton", nil, frame)
		tab:SetSize(32, 32)
		tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -48 - (k - 1) * 48)
		local bg = tab:CreateTexture(nil, "BACKGROUND")
		bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
		bg:SetSize(64, 64)
		bg:SetPoint("TOPLEFT", -3, 11)
		tab:SetNormalTexture(t[3])
		-- Glows made by hand with additive blending: given by path the
		-- checked one is drawn plain and the icon goes black (Skatteverket 7/11).
		local glow = tab:CreateTexture(nil, "HIGHLIGHT")
		glow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
		glow:SetBlendMode("ADD")
		glow:SetAllPoints()
		local checked = tab:CreateTexture(nil, "OVERLAY")
		checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		checked:SetBlendMode("ADD")
		checked:SetAllPoints()
		tab:SetCheckedTexture(checked)
		tab.page = t[1]
		tab:SetScript("OnClick", function(self)
			page, offset = self.page, 0
			ns.Refresh()
		end)
		tab:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(t[2])
			GameTooltip:Show()
		end)
		tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
		frame.tabs[k] = tab
	end

	-- Read recipes (Zach 10/11), in place of Scan AH: every recipe and
	-- recipe item in the game, once, then greyed out. Market data comes
	-- from Auctionator's own scans (/bok ah still scans with Bokföring).
	local scan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	scan:SetSize(120, 22)
	scan:SetPoint("BOTTOMRIGHT", -10, 5)
	scan:SetScript("OnClick", ns.ReadRecipes)
	scan:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Read recipes")
		GameTooltip:AddLine("Reads every recipe and recipe item in the game once, so All recipes, Can learn, Need skill and the Skill column work. A few minutes in the background; play on. Prices and what sells come from Auctionator's scans at the auction house.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	scan:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.scan = scan
	-- How far the reading is, on the button itself.
	function ns.ReadProgress(text)
		if ns.RecipesState() ~= "done" then scan:SetText(text) end
	end
	function ns.ReadButton()
		local state = ns.RecipesState()
		if state == "done" then
			scan:SetText("Recipes read")
			scan:Disable()
		elseif state == "todo" then
			scan:SetText("Read recipes")
			scan:Enable()
		else
			scan:Disable()
		end
	end

	frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.note:SetPoint("BOTTOMLEFT", 16, 10)
	frame.note:SetPoint("BOTTOMRIGHT", scan, "BOTTOMLEFT", -8, 5)
	frame.note:SetJustifyH("LEFT")
	frame:Hide()
end

local function Cell(value, red)
	if not value then return "|cff808080-|r" end
	return (red and "|cffff4040" or "") .. ns.Money(value) .. (red and "|r" or "")
end

local function Sold(r)
	if not r.sold then return "|cff808080?|r" end
	return r.sold < 1 and string.format("%.1f", r.sold) or tostring(math.floor(r.sold + 0.5))
end

-- By the clicked column; rows without a value last whichever way.
local function Sort(t)
	table.sort(t, function(a, b)
		local va, vb = a[sortKey], b[sortKey]
		if sortKey == "name" then va, vb = a.recipe and a.recipe.name or ns.ItemName(a.item), b.recipe and b.recipe.name or ns.ItemName(b.item) end
		if (va ~= nil) ~= (vb ~= nil) then return va ~= nil end
		-- Ties and rows without the value: the larger profit first.
		if va == nil or va == vb then
			if (a.profit or -1e12) ~= (b.profit or -1e12) then return (a.profit or -1e12) > (b.profit or -1e12) end
			return (a.id or a.item) < (b.id or b.item)
		end
		if sortUp then return va < vb end
		return va > vb
	end)
end

-- Places the given columns from the left, hides the rest and fits the
-- panel's width to them (never narrower than the controls on top).
local function Layout(cols)
	local x = 10
	for j = 1, MAX_COLUMNS do
		local c, b = cols[j], frame.heads[j]
		local cells = {}
		for i, row in ipairs(rows) do cells[i] = row.cells[j] end
		if c then
			local justify = j == 1 and "LEFT" or "RIGHT"
			b:ClearAllPoints()
			b:SetPoint("LEFT", x, 0)
			b:SetWidth(c.width)
			b.text:SetWidth(c.width)
			b.text:SetJustifyH(justify)
			b.key = c.sort
			b.text:SetText(c.head .. (c.sort and c.sort == sortKey and (sortUp and " ^" or " v") or ""))
			b:Show()
			for _, cell in ipairs(cells) do
				cell:ClearAllPoints()
				cell:SetPoint("LEFT", x, 0)
				cell:SetWidth(c.width)
				cell:SetJustifyH(justify)
				cell:Show()
			end
			x = x + c.width
		else
			b:Hide()
			for _, cell in ipairs(cells) do cell:Hide() end
		end
	end
	local width = math.max(W, x + 65)
	frame:SetWidth(width)
	frame.header:SetWidth(width - 40)
	for _, row in ipairs(rows) do row:SetWidth(width - 40) end
end

-- How many are for sale: few is a thin market, in red (Zach 8/11); none
-- is a gap to fill, in green (Zach 9/11), if it sells at all.
local function Listed(r)
	if not r.quantity then return "|cff808080?|r" end
	if r.quantity == 0 then return "|cff40ff40none|r" end
	return (r.quantity < ns.FEW and "|cffff4040" or "") .. r.quantity .. (r.quantity < ns.FEW and "|r" or "")
end

local function Aged(value, age)
	if not value then return "|cff808080-|r" end
	local old = age and age > OLD_DAYS
	return (old and "|cffff8040" or "") .. ns.Money(value) .. (old and "|r" or "")
end

-- key, header, width, sort field, what a row shows; default: shown at first.
COLUMNS = {
	{ key = "name", head = "Recipe", width = 190, sort = "name", fixed = true, show = function(r) return r.recipe.name or ns.ItemName(r.recipe.item) end },
	-- The skill it needs (Zach 10/11), ? when not known yet.
	-- Coloured as the recipe is for this character (Zach 10/11): orange,
	-- yellow, green or grey once learned; red while the skill is too low;
	-- white when learnable, as its colour shows only once learned.
	-- Estimated colours (not seen at this skill) get a ~ (Zach 10/11).
	{ key = "skill", head = "Skill", width = 40, sort = "skill", default = true, show = function(r)
		local hex = SKILL_HEX[r.skillColour] or "ffffff"
		return "|cff" .. hex .. (r.skillExact == false and "~" or "") .. (r.skill and tostring(r.skill) or "?") .. "|r"
	end },
	{ key = "cost", head = "Cost", width = 75, sort = "cost", default = true,
		show = function(r) return r.cost and ns.Money(r.cost) or ("|cff808080no price: " .. ns.ItemName(r.missing) .. "|r") end },
	{ key = "sells", head = "Sells", width = 75, sort = "sells", default = true, show = function(r) return Aged(r.sells, r.age) end },
	{ key = "profit", head = "Profit", width = 75, sort = "profit", default = true, show = function(r) return Cell(r.profit, r.profit and r.profit < 0) end },
	{ key = "margin", head = "%", width = 45, sort = "margin", default = true,
		show = function(r) return r.margin and string.format("%d%%", math.floor(r.margin * 100 + 0.5)) or "" end },
	-- Few listings: a thin market, in red (Zach 8/11).
	{ key = "quantity", head = "For sale", width = 55, sort = "quantity", default = true, show = Listed },
	{ key = "sold", head = "Sold/day", width = 60, sort = "sold", default = true, show = Sold },
	{ key = "perDay", head = "Profit/day", width = 80, sort = "perDay", default = true,
		show = function(r) return r.perDay and Cell(r.perDay, r.perDay < 0) or "|cff808080?|r" end },
	-- Craft time and from raw (Zach 9/11).
	{ key = "time", head = "Time", width = 55, sort = "time", show = function(r) return Seconds(r.time) end },
	{ key = "timeMade", head = "Time raw", width = 60, sort = "timeMade", show = function(r) return r.profitMade and Seconds(r.timeMade) or "|cff808080-|r" end },
	{ key = "profitMade", head = "Profit raw", width = 75, sort = "profitMade", show = function(r) return Cell(r.profitMade, r.profitMade and r.profitMade < 0) end },
	{ key = "raw", head = "Raw?", width = 45, sort = "rawPerMin", show = function(r)
		if r.rawWorth == nil then return "|cff808080-|r" end
		return r.rawWorth and "|cff40ff40yes|r" or "|cffff8040no|r"
	end },
	-- Level up (Zach 10/11): gold per skill point, and crafts until the
	-- colour changes.
	{ key = "perPoint", head = "Per point", width = 70, sort = "perPoint", level = true,
		show = function(r) return r.perPoint and Cell(r.perPoint, r.perPoint < 0) or "|cff808080-|r" end },
	{ key = "levelN", head = "Crafts", width = 75, sort = "levelN", level = true,
		show = function(r) return r.levelN and string.format("%d to %s", r.levelN, r.levelTo) or "|cff808080-|r" end },
	-- The price's move (Zach 9/11): the last day against the two weeks before.
	{ key = "trend", head = "Trend", width = 55, sort = "trend", show = function(r) return ns.TrendText(r.trend) end },
}

GATHER = {
	{ head = "Item", width = 190, sort = "name", show = function(r) return ns.ItemName(r.item) end },
	{ head = "Profession", width = 75, sort = "profession", show = function(r) return r.profession end },
	{ head = "AH price", width = 75, sort = "price", show = function(r) return Aged(r.price, r.age) end },
	{ head = "Age", width = 75, sort = "age", show = function(r) return r.age and (r.age .. " d") or "" end },
	{ head = "For sale", width = 55, sort = "quantity", show = Listed },
	{ head = "Sold/day", width = 60, sort = "sold", show = Sold },
}

-- The recipe columns he has ticked, in their fixed order.
local function Picked(c)
	local chosen = ns.db.columns
	if c.level then return levelUp end
	if c.fixed then return true end
	-- A column added since he picked (Skill, 10/11) shows by its default.
	if chosen and chosen[c.key] ~= nil then return chosen[c.key] == true end
	return c.default == true
end

Shown = function()
	local out = {}
	for _, c in ipairs(COLUMNS) do
		if Picked(c) then table.insert(out, c) end
	end
	return out
end

-- Right-click a header: tick the columns to show, or go back to the default.
function ns.ColumnMenu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Columns")
		for _, c in ipairs(COLUMNS) do
			if not c.fixed and not c.level then
				root:CreateCheckbox(c.head, function() return Picked(c) end, function()
					local chosen = ns.db.columns
					if not chosen then
						chosen = {}
						for _, d in ipairs(COLUMNS) do chosen[d.key] = d.default == true end
						ns.db.columns = chosen
					end
					chosen[c.key] = not chosen[c.key]
					ns.Refresh()
				end)
			end
		end
		root:CreateButton("Reset to default", function()
			ns.db.columns = nil
			ns.Refresh()
		end)
	end)
end

-- The search box: the recipe's name, the made item's or a reagent's.
local function Found(r)
	local query = ns.search
	if not query or query == "" then return true end
	local function Has(name) return name and name:lower():find(query, 1, true) ~= nil end
	if Has(r.recipe.name) or Has(ns.ItemName(r.recipe.item)) then return true end
	for _, reagent in ipairs(r.recipe.reagents or {}) do
		if Has(ns.ItemName(reagent[1])) then return true end
	end
	return false
end

-- Gathering: what each raw material or bar fetches, dearest first.
local function RefreshGather()
	Layout(GATHER)
	list = {}
	local query = ns.search
	for _, r in ipairs(ns.GatherRows(profession)) do
		if (not sellable or r.price) and (not query or query == "" or ns.ItemName(r.item):lower():find(query, 1, true)) then table.insert(list, r) end
	end
	Sort(list)
	offset = math.max(0, math.min(offset, #list - ROWS))
	for i, row in ipairs(rows) do
		local r = list[i + offset]
		row.data = r
		if r then
			row.cells[1]:SetTextColor(1, 1, 1)
			for j, c in ipairs(GATHER) do row.cells[j]:SetText(c.show(r)) end
			row:Show()
		else
			row:Hide()
		end
	end
	frame.status:SetText(string.format("%d items", #list))
	frame.note:SetText("Price per item on the auction house, before the 5% cut. A guide only: what gathering earns depends on how fast you gather.")
end

local Draw
-- How long the last refresh took (Zach 10/11: a freeze on opening), for
-- /bok test.
-- Not learned on this character: learnable now, or more skill needed;
-- and the colour of the skill for this character.
local function Classify(r, me, skills)
	-- Rows are kept between refreshes; work these out afresh.
	r.skill, r.learnable, r.needs = ns.LearnInfo(r.recipe).skill, nil, nil
	r.have = skills[r.recipe.profession]
	local mine = r.recipe.by[me]
	if mine then
		r.skillColour, r.skillExact = mine, true
	elseif r.skill and not r.have then
		r.skillColour, r.skillExact = "r", true
	else
		r.skillColour, r.skillExact = ns.SkillColour(r.id, r.skill, r.have)
	end
	if not mine then
		if r.have and r.skill and r.skill <= r.have then r.learnable = true else r.needs = true end
	end
	r.perPoint, r.levelN, r.levelTo, r.levelPoints, r.recipePrice = nil, nil, nil, nil, nil
	if levelUp then ns.LevelPlan(r, mine) end
end

-- The boxes and filters above the list, the learn boxes aside.
local function Passes(r)
	-- Skill-ups: his own recipes that are not grey.
	-- Level up: what this character can craft for skill, or learn now
	-- with Can learn.
	local level = not levelUp or (r.perPoint ~= nil and (r.recipe.by[ns.MeKey()] or (canLearn and r.learnable)))
	-- Skill-ups by this character's colour, estimated for recipes not
	-- learned (Zach 10/11: with Can learn it showed nothing).
	local up = r.skillColour == "o" or r.skillColour == "y" or r.skillColour == "g"
	return (not skillUps or up) and (not sellable or r.sells) and level and Found(r)
end

Counts = function(recipeRows, me, skills)
	local can, need = 0, 0
	for _, r in ipairs(recipeRows) do
		Classify(r, me, skills)
		if Passes(r) then
			if r.learnable then can = can + 1 end
			if r.needs then need = need + 1 end
		end
	end
	frame.canLearn.label:SetText(string.format("Can learn (%d)", can))
	frame.needSkill.label:SetText(string.format("Need skill (%d)", need))
end

function ns.Refresh()
	if not frame or not frame:IsShown() then return end
	if ns.ReadButton then ns.ReadButton() end
	local start = debugprofilestop()
	Draw()
	ns.refreshMs = debugprofilestop() - start
	ns.refreshWhat = page .. "/" .. mode
end

Draw = function()
	frame.view:Update()
	frame.pick:Update()
	for _, tab in ipairs(frame.tabs) do tab:SetChecked(tab.page == page) end
	local other = page ~= "recipes"
	ns.ShowHistory(frame, page == "history")
	ns.ShowWork(frame, page == "work")
	ns.ShowMarket(frame, page == "market")
	ns.ShowToday(frame, page == "today")
	frame.search:SetShown(page == "recipes" or page == "market")
	frame.header:SetShown(not other)
	frame.view:SetShown(not other)
	frame.pick:SetShown(not other)
	frame.sell:SetShown(not other)
	frame.canLearn:SetShown(not other and mode ~= "gather")
	frame.needSkill:SetShown(not other and mode ~= "gather")
	for _, row in ipairs(rows) do row.wide:Hide() end
	if other then
		frame.ups:Hide()
		frame.levelBox:Hide()
		for _, row in ipairs(rows) do row:Hide() end
		if page == "history" then ns.RefreshHistory(frame)
		elseif page == "market" then ns.RefreshMarket(frame)
		elseif page == "today" then ns.RefreshToday(frame)
		else ns.RefreshWork(frame) end
		return
	end
	if mode == "gather" then
		frame.ups:Hide()
		frame.levelBox:Hide()
		RefreshGather()
		return
	end
	frame.ups:Show()
	frame.levelBox:Show()
	local cols = Shown()
	Layout(cols)
	list = {}
	local me, skills = ns.MeKey(), ns.MySkills()
	local recipeRows = ns.Rows(profession, mode == "all")
	for _, r in ipairs(recipeRows) do
		Classify(r, me, skills)
		if Passes(r) and (not (canLearn or needSkill) or (canLearn and r.learnable) or (needSkill and r.needs)) then
			r.trend = ns.Trend(r.recipe.item)
			table.insert(list, r)
		end
	end
	frame.canLearn:SetChecked(canLearn)
	frame.needSkill:SetChecked(needSkill)
	-- The counts are of all recipes, whichever view is shown (Zach 10/11:
	-- My recipes showed 0 until a box was ticked); worked out a moment
	-- later there, so the window opens first.
	if mode == "all" then
		Counts(recipeRows, me, skills)
	else
		local wanted = profession
		C_Timer.After(0.05, function()
			if not frame:IsShown() or mode ~= "mine" or profession ~= wanted then return end
			Counts(ns.Rows(wanted, true), me, skills)
		end)
	end
	Sort(list)
	-- The fold-outs under the recipes clicked open.
	local shown = {}
	for _, r in ipairs(list) do
		table.insert(shown, r)
		if expanded[r.id] and not r.recipe.by[me] then table.insert(shown, { learn = true, parent = r }) end
	end
	list = shown
	offset = math.max(0, math.min(offset, #list - ROWS))
	for i, row in ipairs(rows) do
		local r = list[i + offset]
		row.data = r
		if r and r.learn then
			for _, cell in ipairs(row.cells) do cell:Hide() end
			row.wide:SetText("|cff40ff40" .. ns.LearnLine(r.parent.recipe) .. "|r")
			row.wide:Show()
			row:Show()
		elseif r then
			local c = COLOURS[r.colour] or COLOURS.x
			row.cells[1]:SetTextColor(c[1], c[2], c[3])
			for j, col in ipairs(cols) do row.cells[j]:SetText(col.show(r)) end
			row:Show()
		else
			row:Hide()
		end
	end
	local auctionator = Auctionator and Auctionator.API and Auctionator.API.v1
	frame.status:SetText(auctionator and string.format("%d recipes", #list) or "|cffff4040Auctionator not found|r")
	if canLearn or needSkill then
		-- Why the list may be short (Zach 10/11).
		local why = not ns.db.catalogAt and "No recipe catalog yet: it is read once by itself a minute after login, or now with /bok scan. "
			or (#list == 0 and sellable) and "Untick Sellable only to see recipes whose item has no auction house price. " or ""
		frame.note:SetText(why .. "Not learned on this character. Skill: what the recipe needs, ? until known (a trainer visit fills it in). Click a recipe for where to get it.")
		return
	end
	frame.note:SetText(#list == 0 and (mode == "all" and "No recipes: none of yours, and none shared by the guild through Skatteverket."
		or "No recipes yet: open each profession window once on each character.")
		or "Sells: after the 5% cut, orange if the price is over 2 days old. For sale: red under 5, green none. Profit/day: profit x sold a day, from two scans hours apart. White: you don't know it. Right-click to buy.")
end

function ns.Toggle(only)
	if ns.Allowed and not ns.Allowed() then return end
	if not frame then Build() end
	if frame:IsShown() and not only then
		frame:Hide()
		return
	end
	if only then profession, mode, page = only, "mine", "recipes" end
	frame:Show()
	ns.Refresh()
end

-- For the THÖNDERSTÖRM minimap button's right-click list (Zach 9/11).
BokforingAPI = {
	Toggle = function() ns.Toggle() end,
	-- Open on Making now, for Arbetsorder's "Till dig själv".
	ShowWork = function()
		if not frame or not frame:IsShown() then ns.Toggle() end
		page = "work"
		ns.Refresh()
	end,
	Work = function() return ns.WorkSummary() end,
	-- For Skatteverket's work orders where he sends the materials.
	ShopForOrder = function(name, reagents, crafts, to) ns.ShopForOrder(name, reagents, crafts, to) end,
	Refresh = function() if ns.Refresh then ns.Refresh() end end,
}

-- The button above whichever profession window this client has.
local button
function ns.ShowButton()
	local parent = ProfessionsFrame or TradeSkillFrame
	if button or not parent or (ns.Allowed and not ns.Allowed()) then return end
	button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(90, 22)
	button:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, 2)
	button:SetText("Bokföring")
	button:SetScript("OnClick", function()
		if frame and frame:IsShown() then frame:Hide() else ns.Toggle(ns.openProfession) end
	end)
end

-- Off outside THÖNDERSTÖRM (Guild.lua).
function ns.Hide()
	if frame then frame:Hide() end
	if button then button:Hide() end
end
