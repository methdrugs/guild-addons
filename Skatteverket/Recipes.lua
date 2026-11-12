-- Skatteverket, recipe search (Zach 7/11): every member's known recipes,
-- read when they open a profession window, so anyone can search the guild
-- for an enchant or a craft and see who makes it, or open one member's
-- recipes in the panel to buy what still levels their profession.
-- Enchanting has its own Craft window in Classic and is read from there.
--
-- Recipes travel as compact keys: "i4369" for the item a recipe makes,
-- "s7788" for a spell when nothing is made (enchants), and a letter for
-- how hard the recipe is for its owner: o orange, y yellow, g green, x
-- grey ("i4369y"). Names, icons and tooltips come from each client, in its
-- own language. 0.16 sent keys without the letter; both are read. Since
-- 0.18 the list keeps the window's own order with its categories as
-- "#Name" between the keys, so the panel can show them like the
-- profession window (Zach 7/11).
--
-- Guild channel:
--   W;code;part;parts;stamp;key,key,...         a member's recipes for one profession
--   J;stamp                                     member -> leader: lists newer than stamp
--   U;name;code;part;parts;stamp;key,key,...    leader: someone else's list, relayed
-- A list goes out when it changes, at most every ten minutes since colours
-- change with every skill point, and again at login when older than three
-- days; the leader relays to members who log in what they missed.

local _, ns = ...

local PART_BYTES = 200
ns.recipeVersion = 0
local RESEND_DAYS = 3
local RESEND_GAP = 600

local BY_NAME = {}
for _, p in ipairs(ns.PROFESSIONS) do BY_NAME[p.name] = p end

-- Classic difficulty words and the newer API's numbers, as one letter.
local COLOUR = { optimal = "o", medium = "y", easy = "g", trivial = "x", [0] = "o", [1] = "y", [2] = "g", [3] = "x" }

-- A category name as a list item: no separators, not too long.
local function Header(name)
	name = (name or ""):gsub("[,;|#]", "")
	if name == "" then return end
	return "#" .. name:sub(1, 30)
end

local function Key(link)
	if not link then return end
	local item = link:match("item:(%d+)")
	if item then return "i" .. item end
	local spell = link:match("enchant:(%d+)") or link:match("spell:(%d+)")
	if spell then return "s" .. spell end
end

-- Which profession a recipe belongs to. Forever's window does not say
-- which profession is open (GetBaseProfessionInfo gives 0, probe 7/11),
-- so ask about a learned recipe instead, every way the API offers.
local function ProfessionOf(ui, id)
	local candidates = {}
	if ui.GetTradeSkillLineForRecipe then
		local line, lineName, parent = ui.GetTradeSkillLineForRecipe(id)
		table.insert(candidates, parent)
		table.insert(candidates, line)
		table.insert(candidates, lineName)
	end
	if ui.GetProfessionInfoByRecipeID then
		local info = ui.GetProfessionInfoByRecipeID(id)
		if info then
			table.insert(candidates, info.parentProfessionID)
			table.insert(candidates, info.professionID)
			table.insert(candidates, info.parentProfessionName)
			table.insert(candidates, info.professionName)
		end
	end
	if ui.GetBaseProfessionInfo then
		local info = ui.GetBaseProfessionInfo()
		table.insert(candidates, info and info.professionID)
		table.insert(candidates, info and info.professionName)
	end
	for _, c in pairs(candidates) do
		for _, p in ipairs(ns.PROFESSIONS) do
			if c == p.id or c == p.name then return p end
		end
	end
end

-- The modern window (Forever): recipe numbers, grouped by category, with
-- the colour for this character. Reagents and the made item are looked up
-- from the number on the reader's client (GetRecipeSchematic), so they
-- cost nothing to send.
local function ReadModern()
	local ui = C_TradeSkillUI
	if not ui or not ui.GetAllRecipeIDs or not ui.GetRecipeInfo then return end
	if (ui.IsTradeSkillLinked and ui.IsTradeSkillLinked()) or (ui.IsTradeSkillGuild and ui.IsTradeSkillGuild()) then return end
	local groups, order, p = {}, {}, nil
	for _, id in ipairs(ui.GetAllRecipeIDs() or {}) do
		local r = ui.GetRecipeInfo(id)
		if r and r.learned then
			p = p or ProfessionOf(ui, id)
			local category = r.categoryID or 0
			if not groups[category] then
				groups[category] = {}
				table.insert(order, category)
			end
			table.insert(groups[category], "s" .. id .. (COLOUR[r.relativeDifficulty] or COLOUR[r.difficulty] or ""))
		end
	end
	if not p then return end
	local keys = {}
	for _, category in ipairs(order) do
		local info = ui.GetCategoryInfo and category ~= 0 and ui.GetCategoryInfo(category)
		local header = Header(info and info.name)
		if header then table.insert(keys, header) end
		for _, key in ipairs(groups[category]) do table.insert(keys, key) end
	end
	return p, keys
end

local function ReadTradeSkill()
	if not GetNumTradeSkills or not GetTradeSkillLine then return end
	if IsTradeSkillLinked and IsTradeSkillLinked() then return end
	local p = BY_NAME[GetTradeSkillLine() or ""]
	if not p then return end
	local keys = {}
	for i = 1, GetNumTradeSkills() do
		local name, kind, _, expanded = GetTradeSkillInfo(i)
		if kind == "header" or kind == "subheader" then
			-- A closed category hides its recipes; read only a fully open list.
			if not expanded then return p, nil end
			local header = Header(name)
			if header then table.insert(keys, header) end
		elseif kind then
			local key = Key(GetTradeSkillItemLink and GetTradeSkillItemLink(i)) or Key(GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i))
			if key then table.insert(keys, key .. (COLOUR[kind] or "")) end
		end
	end
	return p, keys
end

local function ReadCraft()
	if not GetNumCrafts or not GetCraftDisplaySkillLine then return end
	local p = BY_NAME[GetCraftDisplaySkillLine() or ""]
	if not p then return end
	local keys = {}
	for i = 1, GetNumCrafts() do
		local name, _, kind, _, expanded = GetCraftInfo(i)
		if kind == "header" then
			if not expanded then return p, nil end
			local header = Header(name)
			if header then table.insert(keys, header) end
		elseif kind then
			local key = Key(GetCraftItemLink and GetCraftItemLink(i)) or Key(GetCraftRecipeLink and GetCraftRecipeLink(i))
			if key then table.insert(keys, key .. (COLOUR[kind] or "")) end
		end
	end
	return p, keys
end

local function Store(name, code, at, keys)
	local db = ns.db
	db.recipes[name] = db.recipes[name] or {}
	local old = db.recipes[name][code]
	if old and old.at >= at then return end
	db.recipes[name][code] = { at = at, keys = keys }
	db.recipesSeen = math.max(db.recipesSeen or 0, at)
	ns.recipeVersion = ns.recipeVersion + 1
	if ns.RefreshRegistry then ns.RefreshRegistry() end
end

-- One list in parts under the 255 byte limit, a little apart.
local function Parts(keys)
	local parts, chunk, length = {}, {}, 0
	for _, key in ipairs(keys) do
		if length + #key + 1 > PART_BYTES and #chunk > 0 then
			table.insert(parts, table.concat(chunk, ","))
			chunk, length = {}, 0
		end
		table.insert(chunk, key)
		length = length + #key + 1
	end
	table.insert(parts, table.concat(chunk, ","))
	return parts
end

local queue, sending = {}, false
local function Pump()
	local msg = table.remove(queue, 1)
	if not msg then sending = false return end
	ns.Send(msg)
	C_Timer.After(0.5, Pump)
end
local function Queue(msg)
	table.insert(queue, msg)
	if not sending then
		sending = true
		C_Timer.After(0.5, Pump)
	end
end

local scheduled = {}
local function SendOwn(code)
	scheduled[code] = nil
	local mine = ns.char.recipes[code]
	if not mine or not ns.InOurGuild() then return end
	local parts = Parts(mine.keys)
	for i, part in ipairs(parts) do
		Queue(string.format("W;%s;%d;%d;%d;%s", code, i, #parts, mine.at, part))
	end
	-- Only the leader relays lists, and nobody relays to the leader: with the
	-- leader offline the list counts as unsent and goes again at the next
	-- login (Zach 8/11, a new member's recipes never reached him).
	local _, leaderOnline = ns.Leader()
	if leaderOnline or IsGuildLeader() then mine.sentAt = ns.Now() end
end

-- After the window has been open a moment, so the list has loaded.
local readAt = 0
local function ReadOpenWindow(craft)
	readAt = GetTime() + 1
	C_Timer.After(1.1, function()
		if GetTime() < readAt then return end
		local p, keys
		if craft then
			p, keys = ReadCraft()
		else
			-- Forever has only the modern window (probe 7/11); the classic list
			-- is kept for other clients.
			local ok
			ok, p, keys = pcall(ReadModern)
			if not ok or not p then p, keys = ReadTradeSkill() end
		end
		if not p or not keys or #keys == 0 then return end
		local mine = ns.char.recipes[p.code]
		if mine and table.concat(mine.keys, ",") == table.concat(keys, ",") then return end
		local at = ns.Now()
		ns.char.recipes[p.code] = { at = at, keys = keys }
		if ns.Me() then Store(ns.Me(), p.code, at, keys) end
		if not mine then ns.Print(string.format("%d recept i %s delas med guildet.", ns.CountRecipes(keys), p.label)) end
		if not scheduled[p.code] then
			scheduled[p.code] = true
			local wait = math.max(10, ((mine and mine.sentAt) or 0) + RESEND_GAP - ns.Now())
			C_Timer.After(wait, function() SendOwn(p.code) end)
		end
		if ns.RefreshWindow then ns.RefreshWindow() end
	end)
end

-- Parts waiting for the rest of their list.
local incoming = {}
local function OnPart(name, code, part, parts, at, text)
	part, parts, at = tonumber(part), tonumber(parts), tonumber(at)
	if not name or not ns.PROFESSION_BY_CODE[code] or not part or not parts or not at or parts > 50 then return end
	if at > ns.Now() + 300 then return end
	local id = name .. ";" .. code .. ";" .. at
	local got = incoming[id] or { n = 0 }
	incoming[id] = got
	if not got[part] then
		got[part] = text or ""
		got.n = got.n + 1
	end
	if got.n < parts then return end
	incoming[id] = nil
	local keys = {}
	for i = 1, parts do
		for item in (got[i] or ""):gmatch("[^,]+") do
			if item:match("^[si]%d+[oygx]?$") or item:match("^#.") then table.insert(keys, item) end
		end
	end
	Store(name, code, at, keys)
end

function ns.OnRecipes(sender, parts)
	if sender == ns.Me() then return end
	OnPart(sender, parts[2], parts[3], parts[4], parts[5], parts[6])
end

function ns.OnRelayedRecipes(parts)
	if parts[2] == ns.Me() then return end
	OnPart(parts[2], parts[3], parts[4], parts[5], parts[6], parts[7])
end

-- Leader: what a member who just logged in has missed, at most once every
-- five minutes per member.
local served = {}
function ns.OnRecipeRequest(sender, since)
	if not IsGuildLeader() or sender == ns.Me() then return end
	if served[sender] and GetTime() - served[sender] < 300 then return end
	served[sender] = GetTime()
	since = tonumber(since) or 0
	local roster = ns.RosterNames()
	for name, lists in pairs(ns.db.recipes) do
		if name ~= sender and (not roster or roster[name]) then
			for code, list in pairs(lists) do
				if list.at > since then
					local parts = Parts(list.keys)
					for i, part in ipairs(parts) do
						Queue(string.format("U;%s;%s;%d;%d;%d;%s", name, code, i, #parts, list.at, part))
					end
				end
			end
		end
	end
end

local function Parse(key)
	local kind, id, colour = key:match("^(%a)(%d+)(%a?)$")
	return kind, tonumber(id), colour ~= "" and colour or nil
end

local function ItemName(id)
	local name
	if C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(id)
	elseif GetItemInfo then name = GetItemInfo(id) end
	if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
	return name
end
ns.ItemName = ItemName

function ns.ItemIcon(id)
	if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
	return GetItemIcon and GetItemIcon(id)
end

-- What this client knows about a recipe: name, icon, the made item and
-- its reagents { itemID, count }; nil while something is still loading.
-- Kept once complete. A recipe number is looked up with the modern API,
-- which answers for any recipe, not only your own (probe 7/11).
local data = {}
local function Data(key)
	local kind, id = Parse(key)
	if not id then return end
	local base = kind .. id
	if data[base] then return data[base] end
	local d = { reagents = {} }
	if kind == "s" then
		local ui = C_TradeSkillUI
		local okInfo, r = pcall(function() return ui and ui.GetRecipeInfo and ui.GetRecipeInfo(id) end)
		local okSchematic, schematic = pcall(function() return ui and ui.GetRecipeSchematic and ui.GetRecipeSchematic(id, false) end)
		r = okInfo and r or nil
		schematic = okSchematic and schematic or nil
		d.item = schematic and schematic.outputItemID
		if d.item == 0 then d.item = nil end
		-- How many one craft makes, for raw materials (Zach 10/11).
		d.makes = math.max(1, schematic and schematic.quantityMin or 1)
		d.name = r and r.name
		d.icon = r and r.icon
		for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
			local reagent = slot.reagents and slot.reagents[1]
			if reagent and reagent.itemID and slot.required ~= false then
				table.insert(d.reagents, { itemID = reagent.itemID, count = slot.quantityRequired or 1 })
			end
		end
		if not d.name then
			if C_Spell and C_Spell.GetSpellName then d.name = C_Spell.GetSpellName(id)
			elseif GetSpellInfo then d.name = GetSpellInfo(id) end
		end
		if not d.icon then
			if C_Spell and C_Spell.GetSpellTexture then d.icon = C_Spell.GetSpellTexture(id)
			elseif GetSpellTexture then d.icon = GetSpellTexture(id) end
		end
	else
		d.item = id
	end
	if d.item then
		d.name = d.name or ItemName(d.item)
		d.icon = ns.ItemIcon(d.item) or d.icon
	end
	if not d.name then return end
	data[base] = d
	return d
end
ns.RecipeData = Data

local function Name(key)
	local d = Data(key)
	return d and d.name
end
-- For arbetsordrar (Orders.lua).
ns.RecipeName = function(key) return Name(key) or "..." end

-- Raw materials (Zach 10/11): a reagent the crafter makes themselves at a
-- colour that still gives skill points (orange, yellow, green, as their own
-- shared list shows it) is better sent as what it is made of, so they
-- level on it too; down every step that still gives points. Returns the
-- raw materials { itemID, count } for count crafts, and the steps they
-- make on the way { itemID, crafts, colour }; nil when nothing changes or
-- something is still loading.
local POINTS = { o = true, y = true, g = true }
-- At 300 a profession gives no more points (Zach 12/11), whatever colour.
local SKILL_MAX = 300
function ns.RawPlan(crafter, key, count)
	local makes = {}
	local member = ns.db.members[crafter]
	local levels = member and ns.DecodeProfessions(member.profs) or {}
	if crafter == ns.Me() then levels = ns.ReadProfessions() end
	for code, list in pairs(ns.db.recipes[crafter] or {}) do
		local done = levels[code] and levels[code].rank >= SKILL_MAX
		for _, k in ipairs(done and {} or list.keys or {}) do
			local _, _, colour = Parse(k)
			if k:sub(1, 1) ~= "#" and POINTS[colour] then
				local d = Data(k)
				if d and d.item and #d.reagents > 0 then makes[d.item] = { key = k, colour = colour, d = d } end
			end
		end
	end
	local top = Data(key)
	if not top or #top.reagents == 0 then return end
	local raw, steps, order = {}, {}, {}
	local function Add(item, n)
		if not raw[item] then table.insert(order, item) end
		raw[item] = (raw[item] or 0) + n
	end
	local function Expand(item, need, depth)
		local m = makes[item]
		if not m or depth > 4 then Add(item, need) return end
		local crafts = math.ceil(need / m.d.makes)
		table.insert(steps, { itemID = item, crafts = crafts, colour = m.colour })
		for _, r in ipairs(m.d.reagents) do Expand(r.itemID, r.count * crafts, depth + 1) end
	end
	for _, r in ipairs(top.reagents) do Expand(r.itemID, r.count * count, 1) end
	if #steps == 0 then return end
	local out = {}
	for _, item in ipairs(order) do table.insert(out, { itemID = item, count = raw[item] }) end
	return out, steps
end

-- { recipe, name, code } for every recipe whose name contains text, in
-- members who are in the guild now; recipe name first, then member. A
-- recipe that uses a reagent by that name is found too, with uses set to
-- the reagent (Zach 12/11).
function ns.SearchRecipes(text)
	local results, roster, online = {}, ns.RosterNames(), {}
	for i = 1, GetNumGuildMembers() do
		local full, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
		if full and isOnline then online[ns.Short(full)] = true end
	end
	text = text:lower()
	for name, lists in pairs(ns.db.recipes) do
		if not roster or roster[name] then
			for code, list in pairs(lists) do
				for _, key in ipairs(list.keys) do
					local recipe = Name(key)
					if recipe and recipe:lower():find(text, 1, true) then
						table.insert(results, { recipe = recipe, name = name, code = code, online = online[name], key = key })
					elseif recipe then
						local d = Data(key)
						for _, r in ipairs(d and d.reagents or {}) do
							local reagent = ItemName(r.itemID)
							if reagent and reagent:lower():find(text, 1, true) then
								table.insert(results, { recipe = recipe, name = name, code = code, online = online[name], key = key, uses = reagent })
								break
							end
						end
					end
				end
			end
		end
	end
	table.sort(results, function(a, b)
		-- What was searched for first, then what uses it.
		if (a.uses == nil) ~= (b.uses == nil) then return a.uses == nil end
		if a.recipe ~= b.recipe then return a.recipe < b.recipe end
		return a.name < b.name
	end)
	return results
end

-- For the panel: the hyperlink for tooltips and chat, and the icon.
function ns.RecipeLink(key)
	local kind, id = Parse(key)
	if not id then return end
	local d = Data(key)
	if d and d.item then return "item:" .. d.item end
	return (kind == "i" and "item:" or "spell:") .. id
end

function ns.RecipeChatLink(key)
	local d = Data(key)
	if d and d.item then
		if C_Item and C_Item.GetItemInfo then return select(2, C_Item.GetItemInfo(d.item)) end
		return GetItemInfo and select(2, GetItemInfo(d.item))
	end
	local _, id = Parse(key)
	if not id then return end
	if C_Spell and C_Spell.GetSpellLink then return C_Spell.GetSpellLink(id) end
	return GetSpellLink and GetSpellLink(id)
end

function ns.RecipeIcon(key)
	local d = Data(key)
	return d and d.icon
end

-- Recipes in a list, not counting category names.
function ns.CountRecipes(keys)
	local n = 0
	for _, key in ipairs(keys) do if key:sub(1, 1) ~= "#" then n = n + 1 end end
	return n
end

-- One member's recipes in one profession, as rows for the panel: { header }
-- or { key, name, colour }, in their window's order with its categories;
-- and when they were shared. A list from 0.16 or 0.17 has no categories
-- and is sorted orange, yellow, green, grey, then by name.
local RANK = { o = 1, y = 2, g = 3, x = 4 }
function ns.MemberRecipes(name, code)
	local list = ns.db.recipes[name] and ns.db.recipes[name][code]
	if not list then return {}, nil end
	local out, headers = {}, false
	for _, key in ipairs(list.keys) do
		if key:sub(1, 1) == "#" then
			headers = true
			table.insert(out, { header = key:sub(2) })
		else
			local _, _, colour = Parse(key)
			table.insert(out, { key = key, name = Name(key) or "...", colour = colour })
		end
	end
	if not headers then
		table.sort(out, function(a, b)
			local ra, rb = RANK[a.colour] or 5, RANK[b.colour] or 5
			if ra ~= rb then return ra < rb end
			return a.name < b.name
		end)
	end
	return out, list.at
end

-- What this character shares, for Min anmälan: "Ingenjör 45 (07/11)".
function ns.OwnRecipeText()
	local parts = {}
	for _, p in ipairs(ns.PROFESSIONS) do
		local mine = ns.char.recipes[p.code]
		if mine then table.insert(parts, string.format("%s %d (%s)", p.label, ns.CountRecipes(mine.keys), ns.Day(mine.at))) end
	end
	return table.concat(parts, ", ")
end

-- /skatt recepttest: what the game offers on this client, with the
-- profession window open.
function ns.RecipeTest()
	ns.Print(string.format("C_TradeSkillUI %s, GetNumTradeSkills %s, GetTradeSkillRecipeLink %s, GetNumCrafts %s, GetCraftRecipeLink %s, GetCraftItemLink %s.",
		C_TradeSkillUI and "finns" or "saknas", GetNumTradeSkills and "finns" or "saknas", GetTradeSkillRecipeLink and "finns" or "saknas",
		GetNumCrafts and "finns" or "saknas", GetCraftRecipeLink and "finns" or "saknas", GetCraftItemLink and "finns" or "saknas"))
	for _, read in ipairs({ { "nya", ReadModern }, { "klassiska", ReadTradeSkill }, { "förtrollning", ReadCraft } }) do
		local ok, p, keys = pcall(read[2])
		ns.Print(string.format("  %s: %s", read[1], not ok and ("fel: " .. tostring(p))
			or p and not keys and (p.label .. ": en kategori är stängd, öppna alla")
			or p and string.format("%s, %d recept, början: %s", p.label, ns.CountRecipes(keys), table.concat(keys, " ", 1, math.min(4, #keys)))
			or "inget"))
	end
	-- How the profession is found on this client, from the first learned recipe.
	local ui = C_TradeSkillUI
	if ui and ui.GetAllRecipeIDs then
		for _, id in ipairs(ui.GetAllRecipeIDs() or {}) do
			local r = ui.GetRecipeInfo(id)
			if r and r.learned then
				local line, lineName, parent
				if ui.GetTradeSkillLineForRecipe then line, lineName, parent = ui.GetTradeSkillLineForRecipe(id) end
				local info = ui.GetProfessionInfoByRecipeID and ui.GetProfessionInfoByRecipeID(id)
				ns.Print(string.format("  recept %d %s: rad %s %s %s, yrke %s %s", id, tostring(r.name), tostring(line), tostring(lineName), tostring(parent),
					tostring(info and info.professionID), tostring(info and (info.parentProfessionID or info.professionName))))
				local d = Data("s" .. id)
				ns.Print(string.format("  gör %s, %d reagenser", tostring(d and d.item), d and #d.reagents or 0))
				break
			end
		end
	end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE",
	"TRADE_SKILL_DATA_SOURCE_CHANGED", "CRAFT_SHOW", "CRAFT_UPDATE", "GET_ITEM_INFO_RECEIVED", "GUILD_ROSTER_UPDATE" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
	if not ns.char then return end
	if event == "PLAYER_LOGIN" then
		C_Timer.After(40, function()
			if not ns.InOurGuild() then return end
			for code, mine in pairs(ns.char.recipes) do
				if ns.Me() then Store(ns.Me(), code, mine.at, mine.keys) end
				if not mine.sentAt or mine.sentAt < mine.at or ns.Now() - mine.sentAt > RESEND_DAYS * 86400 then SendOwn(code) end
			end
			if not IsGuildLeader() then ns.Send("J;" .. (ns.db.recipesSeen or 0)) end
		end)
	elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
		ReadOpenWindow(true)
	elseif event == "GET_ITEM_INFO_RECEIVED" or event == "GUILD_ROSTER_UPDATE" then
		-- A recipe name that was still loading may now match, or someone came online.
		ns.recipeVersion = ns.recipeVersion + 1
	else
		ReadOpenWindow(false)
	end
end)
