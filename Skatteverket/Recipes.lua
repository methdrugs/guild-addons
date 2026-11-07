-- Skatteverket, recipe search (Zach 7/11): every member's known recipes,
-- read when they open a profession window, so anyone can search the guild
-- for an enchant or a craft and see who makes it. Enchanting has its own
-- Craft window in Classic and is read from there.
--
-- Recipes travel as compact keys, "s7788" for a spell, "i4369" for an
-- item when a client gives only the made item; names are looked up on
-- each client, in its own language.
--
-- Guild channel:
--   W;code;part;parts;stamp;key,key,...         a member's recipes for one profession
--   J;stamp                                     member -> leader: lists newer than stamp
--   U;name;code;part;parts;stamp;key,key,...    leader: someone else's list, relayed
-- A list goes out when it changes, and again at login when older than
-- three days; the leader relays to members who log in what they missed.

local _, ns = ...

local PART_BYTES = 200
ns.recipeVersion = 0
local RESEND_DAYS = 3

local BY_NAME = {}
for _, p in ipairs(ns.PROFESSIONS) do BY_NAME[p.name] = p end

-- What the open window shows, as a sorted list of keys; nil when it is
-- someone else's linked profession or nothing could be read.
local function Key(link)
	if not link then return end
	local spell = link:match("enchant:(%d+)") or link:match("spell:(%d+)")
	if spell then return "s" .. spell end
	local item = link:match("item:(%d+)")
	if item then return "i" .. item end
end

local function ReadModern()
	local ui = C_TradeSkillUI
	if not ui or not ui.GetAllRecipeIDs or not ui.GetRecipeInfo then return end
	if (ui.IsTradeSkillLinked and ui.IsTradeSkillLinked()) or (ui.IsTradeSkillGuild and ui.IsTradeSkillGuild()) then return end
	local line
	if ui.GetBaseProfessionInfo then
		local info = ui.GetBaseProfessionInfo()
		line = info and (info.professionID or info.skillLineID)
	end
	if not line and ui.GetTradeSkillLine then line = ui.GetTradeSkillLine() end
	local p
	for _, prof in ipairs(ns.PROFESSIONS) do
		if prof.id == line then p = prof end
	end
	if not p then return end
	local keys = {}
	for _, id in ipairs(ui.GetAllRecipeIDs() or {}) do
		local r = ui.GetRecipeInfo(id)
		if r and r.learned then table.insert(keys, "s" .. id) end
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
		local _, kind = GetTradeSkillInfo(i)
		if kind and kind ~= "header" and kind ~= "subheader" then
			local key = Key(GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)) or Key(GetTradeSkillItemLink and GetTradeSkillItemLink(i))
			if key then table.insert(keys, key) end
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
		local _, _, kind = GetCraftInfo(i)
		if kind and kind ~= "header" then
			local key = Key(GetCraftRecipeLink and GetCraftRecipeLink(i)) or Key(GetCraftItemLink and GetCraftItemLink(i))
			if key then table.insert(keys, key) end
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

local function SendOwn(code)
	local mine = ns.char.recipes[code]
	if not mine or not ns.InOurGuild() then return end
	local parts = Parts(mine.keys)
	for i, part in ipairs(parts) do
		Queue(string.format("W;%s;%d;%d;%d;%s", code, i, #parts, mine.at, part))
	end
	mine.sentAt = ns.Now()
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
			local ok
			ok, p, keys = pcall(ReadModern)
			if not ok or not p then p, keys = ReadTradeSkill() end
		end
		if not p or not keys or #keys == 0 then return end
		table.sort(keys)
		local mine = ns.char.recipes[p.code]
		if mine and table.concat(mine.keys, ",") == table.concat(keys, ",") then return end
		local at = ns.Now()
		ns.char.recipes[p.code] = { at = at, keys = keys }
		if ns.Me() then Store(ns.Me(), p.code, at, keys) end
		ns.Print(string.format("%d recept i %s delas med guildet.", #keys, p.label))
		C_Timer.After(10, function() SendOwn(p.code) end)
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
		for key in (got[i] or ""):gmatch("[si]%d+") do table.insert(keys, key) end
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

-- The recipe's name on this client, or nil while an item is still loading.
local names = {}
local function Name(key)
	if names[key] then return names[key] end
	local kind, id = key:sub(1, 1), tonumber(key:sub(2))
	local name
	if kind == "s" then
		if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(id)
		elseif GetSpellInfo then name = GetSpellInfo(id) end
	else
		if C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(id)
		elseif GetItemInfo then name = GetItemInfo(id) end
		if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
	end
	names[key] = name
	return name
end

-- { recipe, name, code } for every recipe whose name contains text, in
-- members who are in the guild now; recipe name first, then member.
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
						table.insert(results, { recipe = recipe, name = name, code = code, online = online[name] })
					end
				end
			end
		end
	end
	table.sort(results, function(a, b)
		if a.recipe ~= b.recipe then return a.recipe < b.recipe end
		return a.name < b.name
	end)
	return results
end

-- What this character shares, for Min anmälan: "Ingenjör 45 (07/11)".
function ns.OwnRecipeText()
	local parts = {}
	for _, p in ipairs(ns.PROFESSIONS) do
		local mine = ns.char.recipes[p.code]
		if mine then table.insert(parts, string.format("%s %d (%s)", p.label, #mine.keys, ns.Day(mine.at))) end
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
			or p and string.format("%s, %d recept, första %s", p.label, #keys, tostring(keys[1] and Name(keys[1])))
			or "inget"))
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
