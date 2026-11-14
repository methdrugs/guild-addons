-- Recipes to go and get (Zach 10/11): which recipes this character has
-- not learned, the skill each needs and where it comes from. Forever's
-- recipe API gives neither the skill nor the source (an unlearned recipe
-- has no skill field and GetRecipeSourceText says nothing), so both are
-- read from the game itself, nothing copied from a site:
-- - recipe items ("Schematic: Deadly Blunderbuss"): a background walk of
--   every item number, once, keeps each recipe item with the skill its
--   tooltip asks for ("Requires Engineering (175)");
-- - trainers: opening one keeps each recipe it teaches and its skill;
-- - vendors: a recipe item seen at a merchant keeps the vendor and zone.
-- A recipe with no recipe item is taught by a trainer; one with an item
-- is a vendor's when seen at one, otherwise a drop, quest or vendor not
-- seen yet.

local _, ns = ...

local ITEM_MAX = 300000
local FRAME_MS = 4
-- Raise when the walk changes, so it runs again once.
local ITEM_SCAN = 1

-- The modern client has it under C_Item only (Zach 10/11: /bok scan items
-- did nothing).
local function Instant(item)
	local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if f then return f(item) end
end

local function Key(name)
	return name and name:lower():gsub("^%s+", ""):gsub("%s+$", "") or nil
end

-- "Requires %s (%d)" as a pattern for this client's language.
local function SkillPattern()
	local text = ITEM_MIN_SKILL or "Requires %s (%d)"
	text = text:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	text = text:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
	return "^" .. text .. "$"
end

-- The tooltip's lines for an item, from the modern tooltip data or a
-- hidden tooltip.
local scanTip
local function TooltipLines(item)
	local lines = {}
	if C_TooltipInfo and C_TooltipInfo.GetItemByID then
		local ok, data = pcall(C_TooltipInfo.GetItemByID, item)
		if ok and data and data.lines then
			for _, l in ipairs(data.lines) do
				if l.leftText then table.insert(lines, l.leftText) end
			end
			return lines
		end
	end
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "BokforingScanTip", nil, "GameTooltipTemplate")
	end
	scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanTip:SetItemByID(item)
	for i = 1, scanTip:NumLines() do
		local left = _G["BokforingScanTipTextLeft" .. i]
		local text = left and left:GetText()
		if text then table.insert(lines, text) end
	end
	return lines
end

local function Cached(item)
	if C_Item and C_Item.IsItemDataCachedByID then return C_Item.IsItemDataCachedByID(item) end
	return ns.ItemLink(item) ~= nil
end

-- One recipe item: what it teaches (its name after "Schematic: " and the
-- like), the profession and the skill. nil while the item is loading.
local function ReadItem(item, pattern)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)
	if not name then return end
	local entry = { teaches = Key(name:match("^[^:]+:%s*(.+)$") or name) }
	for _, line in ipairs(TooltipLines(item)) do
		local profession, skill = line:match(pattern)
		if profession and tonumber(skill) then
			entry.profession, entry.skill = profession, tonumber(skill)
			break
		end
	end
	return entry
end

-- The background walk: first every item number for recipe items (the
-- client knows their class at once), then each one's name and tooltip as
-- the game loads them.
local walker
local walkDone = {}
function ns.ScanRecipeItems(quiet, done)
	if done then table.insert(walkDone, done) end
	if walker then
		if not quiet then ns.Print("already reading recipe items.") end
		return
	end
	if not ((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant) then
		if not quiet then ns.Print("this client cannot look up items.") end
		return
	end
	local RECIPE = Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
	local id, found, waiting, read, tries = 0, {}, {}, {}, 0
	local pattern = SkillPattern()
	if not quiet then ns.Print("reading recipe items in the background; this takes a minute, play on.") end
	walker = CreateFrame("Frame")
	walker:SetScript("OnUpdate", function(self)
		local start = debugprofilestop()
		if id < ITEM_MAX then
			while id < ITEM_MAX and debugprofilestop() - start < FRAME_MS do
				id = id + 1
				local _, _, _, _, _, class, subclass = Instant(id)
				-- Subclass 0 is books, not recipes for a profession.
				if class == RECIPE and subclass ~= 0 then table.insert(found, id) end
			end
			if ns.ReadProgress then ns.ReadProgress(string.format("Items %d%%", math.floor(id * 80 / ITEM_MAX))) end
			if id >= ITEM_MAX then
				waiting = found
				if #found == 0 then
					-- This client cannot tell; keep nothing, so sources stay unknown.
					self:SetScript("OnUpdate", nil)
					walker = nil
					if not quiet then ns.Print("no recipe items found on this client.") end
					local callbacks = walkDone
					walkDone = {}
					for _, f in ipairs(callbacks) do f() end
				end
			end
			return
		end
		local still = {}
		for _, item in ipairs(waiting) do
			if debugprofilestop() - start >= FRAME_MS then
				table.insert(still, item)
			elseif Cached(item) then
				local entry = ReadItem(item, pattern)
				if entry then read[item] = entry else table.insert(still, item) end
			else
				if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(item) end
				table.insert(still, item)
			end
		end
		waiting = still
		tries = tries + 1
		-- Done, or some never load (items the server does not have).
		if #waiting == 0 or tries > 3000 then
			self:SetScript("OnUpdate", nil)
			walker = nil
			ns.db.recipeItems, ns.db.recipeItemsAt, ns.db.recipeItemsScan = read, time(), ITEM_SCAN
			local n = 0
			for _ in pairs(read) do n = n + 1 end
			ns.Print(string.format("done: %d recipe items read.", n))
			local callbacks = walkDone
			walkDone = {}
			for _, f in ipairs(callbacks) do f() end
			ns.learnIndex = nil
			if ns.RowsChanged then ns.RowsChanged() end
			if ns.Refresh then ns.Refresh() end
		end
	end)
end

-- Trainers: every recipe listed, with the skill it needs.
local function ReadTrainer()
	if not GetNumTrainerServices or not GetTrainerServiceInfo or not GetTrainerServiceSkillReq then return end
	ns.db.trainer = ns.db.trainer or {}
	for i = 1, GetNumTrainerServices() do
		local name, _, kind = GetTrainerServiceInfo(i)
		if name and kind ~= "header" then
			local ok, profession, skill = pcall(GetTrainerServiceSkillReq, i)
			if ok and profession and profession ~= "" then
				ns.db.trainer[Key(name)] = { profession = profession, skill = tonumber(skill) or 0 }
			end
		end
	end
	ns.learnIndex = nil
end

-- Vendors: called from the merchant reading for each item for gold.
function ns.NoteRecipeVendor(item, price)
	local _, _, _, _, _, class, subclass = Instant(item)
	local RECIPE = Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
	if class ~= RECIPE or subclass == 0 then return end
	ns.db.recipeVendors = ns.db.recipeVendors or {}
	local zone = GetZoneText and GetZoneText() or "?"
	ns.db.recipeVendors[item] = { npc = UnitName("npc") or "?", zone = zone, price = price, at = time() }
end

-- Recipe name -> recipe item, the lowest item number for the same name.
local function Index()
	if ns.learnIndex then return ns.learnIndex end
	local index = {}
	for item, e in pairs(ns.db.recipeItems or {}) do
		if e.teaches and (not index[e.teaches] or item < index[e.teaches]) then index[e.teaches] = item end
	end
	ns.learnIndex = index
	return index
end

-- This character's skill in each profession, by name.
function ns.MySkills()
	local out = {}
	if GetProfessions and GetProfessionInfo then
		for _, index in ipairs({ GetProfessions() }) do
			if index then
				local name, _, skill = GetProfessionInfo(index)
				if name then out[name] = skill or 0 end
			end
		end
	end
	if not next(out) and GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, header, _, skill = GetSkillLineInfo(i)
			if name and not header then out[name] = skill or 0 end
		end
	end
	return out
end

-- What is known about getting a recipe: skill (or nil), source ("trainer",
-- "vendor", "item" or nil when unknown) and the recipe item if there is one.
function ns.LearnInfo(recipe)
	local key = Key(recipe.name)
	local info = {}
	local trained = key and ns.db.trainer and ns.db.trainer[key]
	local item = key and Index()[key]
	if item then
		local e = ns.db.recipeItems[item]
		info.item, info.skill = item, e.skill
		local vendor = ns.db.recipeVendors and ns.db.recipeVendors[item]
		if vendor then info.source, info.vendor = "vendor", vendor else info.source = "item" end
	elseif trained then
		info.source = "trainer"
	elseif ns.db.recipeItemsAt then
		-- No recipe item in the game: a trainer teaches it.
		info.source = "trainer"
	end
	if trained then info.skill = info.skill or trained.skill end
	return info
end

-- The line under an unlearned recipe on a left-click.
function ns.LearnLine(recipe)
	local info = ns.LearnInfo(recipe)
	local skill = info.skill and string.format("needs %s %d", recipe.profession or "skill", info.skill) or "skill unknown"
	if info.source == "trainer" then
		return "Trainer: " .. skill .. (info.skill and "" or ", visit a trainer once to see it")
	end
	local price = info.item and ns.AH(info.item)
	local ah = price and (", on the AH for " .. ns.Money(price)) or ""
	if info.source == "vendor" then
		return string.format("Vendor: %s, %s (%s)%s, %s", info.vendor.npc, info.vendor.zone,
			info.vendor.price and ns.Money(info.vendor.price) or "?", ah, skill)
	end
	if info.source == "item" then
		return string.format("%s: drop, quest or a vendor not seen yet%s, %s", ns.ItemName(info.item), ah, skill)
	end
	return "Source unknown until the recipe items are read (/bok scan items)"
end

-- The colour a recipe has at a skill (Zach 10/11). Orange from the skill
-- it is learned at, then yellow, green and grey; where those turn is not
-- in the game's data, so a rule of thumb from Classic recipes (yellow 25
-- points on, green 40, grey 55; tighter from 250) is corrected by every
-- colour seen at a known skill: his own characters' when a profession
-- window opens, and guild members' through Skatteverket's recipe lists
-- and their registered skill.
local ORDER = { o = 1, y = 2, g = 3, x = 4 }
local LETTER = { "o", "y", "g", "x" }

-- Every colour seen for each recipe: { skill, colour index, who }.
local seenCache, seenAt = nil, 0
local function Seen()
	if seenCache and time() - seenAt < 60 then return seenCache end
	local out = {}
	local function Add(id, skill, letter, who)
		if not (id and skill and ORDER[letter]) then return end
		out[id] = out[id] or {}
		table.insert(out[id], { skill, ORDER[letter], who })
	end
	for id, r in pairs(ns.db.recipes) do
		for who, s in pairs(r.seen or {}) do Add(id, s[2], s[1], who) end
	end
	local skatt = SkatteverketDB
	if type(skatt) == "table" and type(skatt.recipes) == "table" and type(skatt.members) == "table" then
		for member, lists in pairs(skatt.recipes) do
			local m = skatt.members[member]
			local profs = m and m.profs or ""
			for code, list in pairs(lists) do
				local skill = tonumber(profs:match("%f[%a]" .. code .. "(%d+)"))
				if skill and ns.SKATT_PROFESSIONS[code] and type(list.keys) == "table" then
					for _, key in ipairs(list.keys) do
						local id, letter = key:match("^s(%d+)(%a)$")
						Add(tonumber(id), skill, letter, member)
					end
				end
			end
		end
	end
	seenCache, seenAt = out, time()
	return out
end

-- The skills where yellow, green and grey begin for a recipe learned at
-- learn, corrected by what has been seen; and whether anything was seen.
local function Guide(id, learn)
	local big = learn >= 250
	local t = { learn, learn + (big and 15 or 25), learn + (big and 25 or 40), learn + (big and 35 or 55) }
	local seen = Seen()[id] or {}
	for _, s in ipairs(seen) do
		local skill, c = s[1], s[2]
		-- Seen as colour c at skill: it began at or below, the next after.
		for k = 2, c do t[k] = math.min(t[k], skill) end
		if c < 4 then t[c + 1] = math.max(t[c + 1], skill + 1) end
	end
	for k = 2, 4 do t[k] = math.max(t[k], t[k - 1]) end
	return t, seen
end

-- The colour letter at a skill, "r" when too low; exact when seen at the
-- same colour on both sides of it (or at it).
function ns.SkillColour(id, learn, skill)
	if not learn or not skill then return end
	if skill < learn then return "r", true end
	local t, seen = Guide(id, learn)
	local c = 1
	for k = 2, 4 do if skill >= t[k] then c = k end end
	local below, above
	for _, s in ipairs(seen) do
		if s[2] == c and s[1] <= skill then below = true end
		if s[2] == c and s[1] >= skill then above = true end
	end
	return LETTER[c], below and above, t, seen
end

-- A tooltip line: where the colours turn, and who it was seen with.
function ns.ColourGuide(id, learn)
	if not learn then return end
	local t, seen = Guide(id, learn)
	local names = { "orange", "yellow", "green", "grey" }
	local who = {}
	for _, s in ipairs(seen) do table.insert(who, string.format("%s %s at %d", s[3], names[s[2]], s[1])) end
	return string.format("Colours: orange %d, yellow %d, green %d, grey %d%s", t[1], t[2], t[3], t[4],
		#who > 0 and (" (seen: " .. table.concat(who, ", ") .. ")") or " (rule of thumb, nobody seen with it yet)")
end

-- Level up (Zach 10/11): for a recipe this character can craft or learn
-- now, how many crafts until it turns green (grey once green), the skill
-- points that gives, and the gold per point: what the crafts sell for
-- (as many as two days of the market take, the rest at the vendor's
-- price), less what they cost and, for one not learned, the recipe's
-- price. Skill-up chance as in Classic: orange always, then falling from
-- yellow to nothing at grey.
-- nextColour (Today, 0.6.6): only as far as the next colour, the cheapest
-- route there.
local GUESS = { o = 1, y = 0.6, g = 0.25 }
local TURNS = { [2] = "yellow", [3] = "green", [4] = "grey" }
function ns.LevelPlan(r, learned, nextColour)
	local skill, colour = r.have, r.skillColour
	if not skill or not r.cost or not (colour == "o" or colour == "y" or colour == "g") then return end
	local crafts, points, to
	if r.skill then
		local t = Guide(r.id, r.skill)
		if skill >= t[4] then return end
		local function Chance(x) return x < t[2] and 1 or math.max(0.05, (t[4] - x) / math.max(t[4] - t[2], 1)) end
		local target = skill < t[3] and t[3] or t[4]
		to = skill < t[3] and "green" or "grey"
		if nextColour then
			for k = 4, 2, -1 do
				if skill < t[k] then target, to = t[k], TURNS[k] end
			end
		end
		crafts, points = 0, target - skill
		for x = skill, target - 1 do crafts = crafts + 1 / Chance(x) end
	else
		-- Where the colours turn is not known: ten crafts at the colour's
		-- usual chance.
		crafts, points, to = 10, 10 * GUESS[colour], "?"
	end
	crafts = math.ceil(crafts)
	if points <= 0 then return end
	local qty = r.recipe.qty or 1
	local made = crafts * qty
	local market = math.floor((r.sold or 0) * 2)
	local each = r.sells and r.sells / qty or 0
	local value = math.min(made, market) * each + math.max(0, made - market) * ns.VendorSell(r.recipe.item) * (1 - ns.TaxRate())
	local recipePrice = 0
	if not learned then
		local item = ns.LearnInfo(r.recipe).item
		recipePrice = item and (ns.AH(item) or (ns.db.recipeVendors and ns.db.recipeVendors[item] and ns.db.recipeVendors[item].price)) or 0
	end
	r.levelN, r.levelTo, r.levelPoints, r.recipePrice = crafts, to, math.floor(points + 0.5), recipePrice
	r.perPoint = (value - crafts * r.cost - recipePrice) / points
end

-- Opens the recipe item as a clicked chat link does (Zach 10/11).
function ns.ShowItemRef(item)
	if not ItemRefTooltip or not item then return end
	if not ItemRefTooltip:IsShown() then ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
	if ItemRefTooltip.ItemRefSetHyperlink then
		ItemRefTooltip:ItemRefSetHyperlink("item:" .. item)
	else
		ItemRefTooltip:SetHyperlink("item:" .. item)
	end
	ItemRefTooltip:Show()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "TRAINER_SHOW", "TRAINER_UPDATE" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
	if not ns.db or (ns.Allowed and not ns.Allowed()) then return end
	if event == "PLAYER_LOGIN" then
		-- The recipe catalog, once, for members who never ran /bok scan
		-- (Zach 10/11: a blacksmith saw nothing under All recipes, Need skill).
		if not ns.db.catalogAt then
			C_Timer.After(90, function()
				if (ns.Allowed and not ns.Allowed()) or ns.db.catalogAt then return end
				ns.Scan(nil, true)
			end)
		end
		-- Once, a little after login, in the background.
		if ns.db.recipeItemsScan ~= ITEM_SCAN then
			C_Timer.After(30, function()
				if ns.Allowed and not ns.Allowed() then return end
				ns.ScanRecipeItems(true)
			end)
		end
	else
		ReadTrainer()
	end
end)

-- For /bok test.
function ns.LearnTest()
	local items, trainer, vendors = 0, 0, 0
	for _ in pairs(ns.db.recipeItems or {}) do items = items + 1 end
	for _ in pairs(ns.db.trainer or {}) do trainer = trainer + 1 end
	for _ in pairs(ns.db.recipeVendors or {}) do vendors = vendors + 1 end
	local skills = {}
	for name, skill in pairs(ns.MySkills()) do table.insert(skills, name .. " " .. skill) end
	return string.format("%d recipe items%s, %d trainer recipes, %d recipe items seen at vendors; this character: %s",
		items, ns.db.recipeItemsAt and (" read " .. date("%d/%m %H:%M", ns.db.recipeItemsAt)) or " (not read yet)",
		trainer, vendors, #skills > 0 and table.concat(skills, ", ") or "no professions found")
end

-- Read recipes (Zach 10/11): the button at the bottom of Bokföring does
-- both reads once, the catalog and then the recipe items, and is greyed out
-- when both are done. Prices come from Auctionator's scans.
local reading = false
function ns.ReadRecipes()
	if reading then return end
	reading = true
	local function Finish()
		reading = false
		ns.RowsChanged()
		if ns.Refresh then ns.Refresh() end
	end
	local function Items()
		if ns.db.recipeItemsAt then Finish() else ns.ScanRecipeItems(true, Finish) end
	end
	if ns.db.catalogAt then Items() else ns.Scan(nil, true, Items) end
	if ns.Refresh then ns.Refresh() end
end

-- "done", "reading" or "todo", for the button.
function ns.RecipesState()
	if ns.db.catalogAt and ns.db.recipeItemsAt then return "done" end
	if reading then return "reading" end
	return "todo"
end
