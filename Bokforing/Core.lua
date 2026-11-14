-- Bokföring (Zach 8/11): which of his recipes earn the most on the auction
-- house. His own addon at first; in the THÖNDERSTÖRM pack since 0.3 (9/11),
-- in English, and it needs Auctionator for prices and shopping lists.
--
-- Recipes are read when a profession window opens, on every character, and
-- kept for the account, so /bok works anywhere. Prices come from Auctionator
-- (its API for other addons), so they are as fresh as his last scan.
-- Vendor prices are noted whenever a merchant is open. Only shows numbers;
-- never buys, sells or crafts.
--
-- A reagent costs the cheapest of: the vendor, the auction house, or making
-- it from a known recipe (Copper Tubes, bolts). Own mined materials count at
-- the auction house price, since selling them is what using them gives up.
-- A sale brings the auction house price less its 5% cut and the guild tax.

local _, ns = ...

local CALLER = "Bokforing"
ns.CUT = 0.05

-- Saved data's shape (0.7, Zach 14/11: saved data must survive): raised
-- with every change, and Migrate() gets a step. Nothing is ever dropped.
ns.SCHEMA = 1
local function Migrate(db)
	local from = db.schema or 0
	if from < 1 then
		-- 0.7, stock at cost (Stock.lua): new tables only; the history so far
		-- stays as it was. What he holds is valued at the next login as the
		-- opening balance.
		db.stock = db.stock or {}
		db.held = db.held or {}
		db.mailHeld = db.mailHeld or {}
		db.transit = db.transit or {}
		db.ledger = db.ledger or {}
		db.buys = db.buys or {}
		db.chars = db.chars or {}
		db.listed = db.listed or {}
	end
	db.schema = ns.SCHEMA
end

-- Skatteverket's guild tax on income, 0 without it or outside the guild.
function ns.TaxRate()
	local api = SkatteverketAPI
	return api and api.TaxRate and api.TaxRate() or 0
end

-- What a sale at that price leaves in the bag: the auction house's cut,
-- then the guild tax on the rest (Tungan Lingonsson 11/11).
function ns.Keep(price)
	return price * (1 - ns.CUT) * (1 - ns.TaxRate())
end

function ns.Print(text)
	print("|cffffd100Bokföring:|r " .. text)
end

-- "25s", "1g50s", "80c", "2" (silver); nil for anything else.
local UNIT = { g = 10000, s = 100, c = 1 }
function ns.ParseMoney(text)
	text = (text or ""):lower():gsub("%s", "")
	if text:match("^%d+$") then return tonumber(text) * 100 end
	local total = 0
	local rest = text:gsub("(%d+)([gsc])", function(n, unit)
		total = total + tonumber(n) * UNIT[unit]
		return ""
	end)
	if text == "" or rest ~= "" then return end
	return total
end

function ns.Money(copper)
	copper = math.floor((copper or 0) + 0.5)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return string.format("%s%dg %ds %dc", sign, g, s, c) end
	if s > 0 then return string.format("%s%ds %dc", sign, s, c) end
	return string.format("%s%dc", sign, c)
end

local function Me()
	local name, realm = UnitName("player"), GetRealmName and GetRealmName()
	return name and (realm and realm ~= "" and name .. "-" .. realm or name)
end
ns.MeKey = Me

-- Prices -----------------------------------------------------------------

local function API()
	return Auctionator and Auctionator.API and Auctionator.API.v1
end

local function Ask(method, item)
	local api = API()
	if not api or not api[method] then return end
	local ok, value = pcall(api[method], CALLER, item)
	if ok then return value end
end

-- Lowest auction house price in copper, and its age in days, or nil.
-- While ns.Rows works, each item is asked once (Zach 10/11: All recipes
-- took half a second, mostly asking Auctionator the same reagents).
local ahMemo
local function AskAH(item)
	local price = Ask("GetAuctionPriceByItemID", item)
	if price and price > 0 then return price, Ask("GetAuctionAgeByItemID", item) end
end
function ns.AH(item)
	if not ahMemo then return AskAH(item) end
	local m = ahMemo[item]
	if not m then
		m = { AskAH(item) }
		ahMemo[item] = m
	end
	return m[1], m[2]
end

-- What a merchant asks for one, as last seen, or nil.
function ns.Vendor(item)
	return ns.db.vendor[item]
end

-- Who sold it, for the vendor lines: " (Name, Zone)", or "" when not known.
function ns.VendorWhere(item)
	local at = ns.db.vendorAt and ns.db.vendorAt[item]
	return at and string.format(" (%s, %s)", at.npc, at.zone) or ""
end

-- Reagents every trade goods or profession vendor sells (Zach 10/11: Fine
-- Thread went on an auction house list because no vendor selling it had
-- been open yet). Classic item numbers; the names come from the game, so a
-- wrong number shows as a wrong name. Threads, dyes, bleach, salt, vials,
-- flux, rods, wood, stocks, wiring, spices, water, coal.
local VENDOR_GOODS = {}
for _, item in ipairs({ 2320, 2321, 4291, 8343, 14341, 2324, 2325, 2604, 2605, 4340, 4341, 4342, 6260, 6261, 10290,
	4289, 3371, 3372, 8925, 18256, 2880, 6217, 4470, 4399, 4400, 7191, 2678, 159, 3857 }) do
	VENDOR_GOODS[item] = true
end

-- Bought at a vendor: seen at one, or one of the goods above.
function ns.IsVendorGood(item)
	return ns.db.vendor[item] ~= nil or VENDOR_GOODS[item] == true
end

-- What one costs to buy: the vendor's price or the auction house's,
-- whichever is lower (Skatteverket's BPP, Zach 11/11); nil when neither is known.
function ns.BuyPrice(item)
	local v, a = ns.Vendor(item), ns.AH(item)
	if v and a then return math.min(v, a) end
	return v or a
end

-- A name the game has not loaded yet shows as "item 4416" and is asked
-- for; when it arrives the window is drawn again (Zach 10/11: the line
-- under a recipe said "item 4416" until opened a second time).
-- An item the game cannot load is asked for once a session only (Zach
-- 11/11: a search that found nothing asked again on every redraw, and the
-- answer redrew the window, round and round).
local waitingNames, failedNames, redraw = {}, {}, false
function ns.ItemName(item)
	local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)) or (GetItemInfo and GetItemInfo(item))
	if not name and not waitingNames[item] and not failedNames[item] and C_Item and C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(item)
		waitingNames[item] = true
	end
	return name or ("item " .. item)
end

-- The name if the game has it, never asking the server (Zach 11/11: a
-- search asked for every reagent of every recipe, and the answers redrew
-- the window for minutes).
function ns.CachedName(item)
	return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)) or (GetItemInfo and GetItemInfo(item))
end

local names = CreateFrame("Frame")
for _, event in ipairs({ "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }) do pcall(names.RegisterEvent, names, event) end
names:SetScript("OnEvent", function(_, _, item, success)
	if not waitingNames[item] then return end
	waitingNames[item] = nil
	if success == false then
		failedNames[item] = true
		return
	end
	if redraw then return end
	redraw = true
	C_Timer.After(0.2, function()
		redraw = false
		if ns.Refresh then ns.Refresh() end
	end)
end)

-- An item's chat link; this client has GetItemInfo under C_Item only
-- (Zach 10/11: clicking a fold-out was an error).
function ns.ItemLink(item)
	local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not f or not item then return end
	local _, link = f(item)
	if not link and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(item) end
	return link
end

-- What a vendor pays for one (Level up: what extra crafts are worth when
-- the auction house will not take them).
function ns.VendorSell(item)
	local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not f then return 0 end
	local sell = select(11, f(item))
	return sell or 0
end

-- In the bags and the bank (the bank as of the last visit).
function ns.Have(item)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(item, true) or 0 end
	return GetItemCount and GetItemCount(item, true) or 0
end

local function ReadMerchant()
	if not GetMerchantNumItems then return end
	for i = 1, GetMerchantNumItems() do
		local item = GetMerchantItemID and GetMerchantItemID(i)
		local price, quantity, available, extended
		if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
			local info = C_MerchantFrame.GetItemInfo(i)
			if info then price, quantity, available, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
		elseif GetMerchantItemInfo then
			local _
			_, _, price, quantity, available, _, _, extended = GetMerchantItemInfo(i)
		end
		-- Token-priced goods are not for gold. Limited stock (Zach 11/11:
		-- Bronze Framework was on a list as vendor, and the vendor had none)
		-- sells out, so it is no vendor good; -1 is unlimited. A recipe is
		-- still noted where it is sold, limited or not (review 11/11).
		if item and price and price > 0 and not extended then
			local each = price / math.max(quantity or 1, 1)
			if (available or -1) < 0 then
				ns.db.vendor[item] = each
				local npc, zone = UnitName("npc") or "?", GetZoneText and GetZoneText() or "?"
				local at = ns.db.vendorAt[item]
				if not at or at.npc ~= npc or at.zone ~= zone then ns.db.vendorAt[item] = { npc = npc, zone = zone } end
			end
			if ns.NoteRecipeVendor then ns.NoteRecipeVendor(item, each) end
		end
	end
end

-- Recipes ----------------------------------------------------------------

-- The modern API's difficulty numbers as a letter: o orange, y yellow,
-- g green, x grey.
local COLOUR = { [0] = "o", [1] = "y", [2] = "g", [3] = "x" }

local function ProfessionName(ui, id)
	if ui.GetProfessionInfoByRecipeID then
		local ok, info = pcall(ui.GetProfessionInfoByRecipeID, id)
		if ok and info then
			local name = info.parentProfessionName or info.professionName
			if name and name ~= "" then return name end
		end
	end
	if ui.GetTradeSkillLineForRecipe then
		local ok, _, lineName = pcall(ui.GetTradeSkillLineForRecipe, id)
		if ok and lineName and lineName ~= "" then return lineName end
	end
	return "?"
end

-- Everything learned in the open window; skipped for someone else's linked
-- window or the guild's.
local function ReadRecipes()
	local ui = C_TradeSkillUI
	if not ui or not ui.GetAllRecipeIDs or not ui.GetRecipeInfo or not ui.GetRecipeSchematic then return 0 end
	if (ui.IsTradeSkillLinked and ui.IsTradeSkillLinked()) or (ui.IsTradeSkillGuild and ui.IsTradeSkillGuild()) then return 0 end
	local me, count, profession = Me(), 0, nil
	for _, id in ipairs(ui.GetAllRecipeIDs() or {}) do
		local r = ui.GetRecipeInfo(id)
		local ok, s = pcall(ui.GetRecipeSchematic, id, false)
		if r and r.learned and ok and s then
			profession = profession or ProfessionName(ui, id)
			local reagents = {}
			for _, slot in ipairs(s.reagentSlotSchematics or {}) do
				local reagent = slot.reagents and slot.reagents[1]
				-- Basic reagents only; optional and finishing ones are left out.
				local basic = slot.required ~= false and slot.reagentType ~= 0 and slot.reagentType ~= 2
				if reagent and reagent.itemID and basic then
					table.insert(reagents, { reagent.itemID, slot.quantityRequired or 1 })
				end
			end
			local old = ns.db.recipes[id] or { by = {} }
			-- The skill each colour was read at, for the colour guide.
			local mySkill = ns.MySkills and ns.MySkills()[profession]
			local item = s.outputItemID
			ns.db.recipes[id] = {
				name = r.name,
				profession = profession,
				item = item and item > 0 and item or nil,
				qty = ((s.quantityMin or 1) + (s.quantityMax or s.quantityMin or 1)) / 2,
				reagents = reagents,
				by = old.by,
				seen = old.seen or {},
			}
			old.by[me] = COLOUR[r.relativeDifficulty] or COLOUR[r.difficulty] or "x"
			if mySkill then ns.db.recipes[id].seen[me] = { old.by[me], mySkill } end
			count = count + 1
		end
	end
	return count, profession
end

-- Guild recipes (Zach 9/11): what members share through Skatteverket, so
-- "All recipes" can rank professions he does not have. Skatteverket keeps
-- them as keys "s<recipe>" per member and profession; the reagents and the
-- made item are looked up here, since Forever answers for any recipe.
local SKATT_PROFESSIONS
SKATT_PROFESSIONS = { ALC = "Alchemy", BS = "Blacksmithing", ENC = "Enchanting", ENG = "Engineering",
	LW = "Leatherworking", TAI = "Tailoring", COO = "Cooking", FA = "First Aid" }
ns.SKATT_PROFESSIONS = SKATT_PROFESSIONS
local looked = {}
local function LookUp(id, profession)
	if looked[id] ~= nil then return looked[id] or nil end
	local ui = C_TradeSkillUI
	if not ui or not ui.GetRecipeSchematic then return end
	local ok, s = pcall(ui.GetRecipeSchematic, id, false)
	local okInfo, r = pcall(function() return ui.GetRecipeInfo and ui.GetRecipeInfo(id) end)
	if not ok or not s or not s.outputItemID or s.outputItemID == 0 then
		looked[id] = false
		return
	end
	local reagents = {}
	for _, slot in ipairs(s.reagentSlotSchematics or {}) do
		local reagent = slot.reagents and slot.reagents[1]
		if reagent and reagent.itemID and slot.required ~= false and slot.reagentType ~= 0 and slot.reagentType ~= 2 then
			table.insert(reagents, { reagent.itemID, slot.quantityRequired or 1 })
		end
	end
	looked[id] = {
		name = okInfo and r and r.name or ns.ItemName(s.outputItemID),
		profession = profession,
		item = s.outputItemID,
		qty = ((s.quantityMin or 1) + (s.quantityMax or s.quantityMin or 1)) / 2,
		reagents = reagents,
		by = {},
		guild = {},
	}
	return looked[id]
end

local function GuildRecipes()
	local out = {}
	local shared = SkatteverketDB and SkatteverketDB.recipes
	if type(shared) ~= "table" then return out end
	for member, lists in pairs(shared) do
		for code, list in pairs(lists) do
			local profession = SKATT_PROFESSIONS[code]
			if profession and type(list.keys) == "table" then
				for _, key in ipairs(list.keys) do
					local id = tonumber(key:match("^s(%d+)"))
					local r = id and LookUp(id, profession)
					if r then
						r.guild[member] = true
						out[id] = r
					end
				end
			end
		end
	end
	return out
end

-- The catalog (Zach 9/11): every recipe in the game, so "All recipes" can
-- rank professions nobody he knows has. Forever answers GetRecipeSchematic
-- for any recipe number, learned or not, so /bok scan asks every number
-- once, a few milliseconds per frame, and keeps what makes an item from
-- reagents. Straight from the game, so Forever's own yields and reagents
-- (Gold Power Core makes 3), and nothing copied from another addon or site.
local SCAN_MAX = 1500000
local FRAME_MS = 8
local scanner

local function Schematic(ui, id)
	local ok, s = pcall(ui.GetRecipeSchematic, id, false)
	if not ok or type(s) ~= "table" or not s.outputItemID or s.outputItemID == 0 then return end
	local reagents = {}
	for _, slot in ipairs(s.reagentSlotSchematics or {}) do
		local reagent = slot.reagents and slot.reagents[1]
		if reagent and reagent.itemID and slot.required ~= false and slot.reagentType ~= 0 and slot.reagentType ~= 2 then
			table.insert(reagents, { reagent.itemID, slot.quantityRequired or 1 })
		end
	end
	if #reagents == 0 then return end
	local profession = ProfessionName(ui, id)
	if profession == "?" then profession = "Other" end
	return {
		name = s.name,
		profession = profession,
		item = s.outputItemID,
		qty = ((s.quantityMin or 1) + (s.quantityMax or s.quantityMin or 1)) / 2,
		reagents = reagents,
	}
end

-- quiet: the background run after login, without the tenths in chat.
-- done: called when it has finished, also if it was already running.
local scanDone = {}
function ns.Scan(upTo, quiet, done)
	local ui = C_TradeSkillUI
	if not ui or not ui.GetRecipeSchematic then ns.Print("this client cannot look up recipes.") return end
	if done then table.insert(scanDone, done) end
	if scanner then
		if not quiet then ns.Print("already scanning.") end
		return
	end
	local last, id, found, step = upTo or SCAN_MAX, 0, {}, 0
	local highest, count = 0, 0
	ns.Print(quiet and "reading every recipe in the game once, in the background (a minute or two); All recipes fills in after."
		or string.format("scanning recipe numbers 1 to %d; this takes a minute or two, play on.", last))
	scanner = CreateFrame("Frame")
	scanner:SetScript("OnUpdate", function(self)
		local start = debugprofilestop()
		while id < last and debugprofilestop() - start < FRAME_MS do
			id = id + 1
			local r = Schematic(ui, id)
			if r then
				found[id] = r
				count, highest = count + 1, id
			end
		end
		if ns.ReadProgress then ns.ReadProgress(string.format("Recipes %d%%", math.floor(id * 100 / last))) end
		local tenth = math.floor(id * 10 / last)
		if tenth > step and id < last and not quiet then
			step = tenth
			ns.Print(string.format("%d%%, %d recipes so far.", tenth * 10, count))
		end
		if id >= last then
			self:SetScript("OnUpdate", nil)
			scanner = nil
			ns.db.catalog = found
			ns.db.catalogAt = time()
			ns.RowsChanged()
			ns.Print(string.format("done: %d recipes, the highest number %d. All recipes now covers them.", count, highest))
			local callbacks = scanDone
			scanDone = {}
			for _, f in ipairs(callbacks) do f() end
			if ns.Refresh then ns.Refresh() end
		end
	end)
end

-- Item names in the catalog may still be loading; the made item's name is
-- the fallback.
local function Catalog()
	for _, r in pairs(ns.db.catalog) do
		r.by = r.by or {}
		-- Earlier versions kept the placeholder; drop it.
		if r.name and r.name:match("^item %d+$") then r.name = nil end
		if not r.name then
			local name = ns.ItemName(r.item)
			if not name:match("^item %d+$") then r.name = name end
		end
	end
	return ns.db.catalog
end

-- The recipes in play: his own, or everything: the catalog, the guild's,
-- his own; the more personal entry wins for the same recipe.
local pool = {}
local function Pool(all)
	pool = {}
	if all then
		for id, r in pairs(Catalog()) do pool[id] = r end
		for id, r in pairs(GuildRecipes()) do pool[id] = r end
	end
	for id, r in pairs(ns.db.recipes) do pool[id] = r end
	return pool
end

-- The cheapest way to have one: vendor, auction house or crafting.
-- Returns cost, how ("vendor", "ah", "craft") and, for crafting, the recipe.
local makers
local function Makers()
	if makers then return makers end
	makers = {}
	for id, r in pairs(pool) do
		if r.item then
			makers[r.item] = makers[r.item] or {}
			table.insert(makers[r.item], id)
		end
	end
	return makers
end

-- make: also consider crafting the reagent (Iron Ore into Iron Bar) when
-- that is cheaper. The panel buys (the quickest craft, Zach 9/11) and only
-- makes what cannot be bought; the tooltip shows what making saves.
local CraftCost
local function Cost(item, depth, seen, make)
	local best, how, via
	local v = ns.Vendor(item)
	if v then best, how = v, "vendor" end
	-- A vendor good not priced yet: the auction house price as a ceiling,
	-- but bought at the vendor.
	if not v and ns.IsVendorGood(item) then
		local a = ns.AH(item)
		if a then return a, "vendor" end
	end
	local a = ns.AH(item)
	if a and (not best or a < best) then best, how = a, "ah" end
	if depth < 4 and (make or not best) then
		for _, id in ipairs(Makers()[item] or {}) do
			if not seen[id] then
				seen[id] = true
				local c = CraftCost(id, depth + 1, seen, make)
				seen[id] = nil
				local r = pool[id]
				if c and (not best or c / r.qty < best) then best, how, via = c / r.qty, "craft", id end
			end
		end
	end
	return best, how, via
end

-- One craft's cost, or nil and the first reagent without a price.
CraftCost = function(id, depth, seen, make)
	local r = pool[id]
	local total = 0
	for _, reagent in ipairs(r.reagents) do
		local c = Cost(reagent[1], depth, seen, make)
		if not c then return nil, reagent[1] end
		total = total + c * reagent[2]
	end
	return total
end

-- Seconds one craft takes (Zach 9/11): his own crafts as timed by
-- History.lua, with the gaps of "Create all", else the spell's cast time;
-- a recipe's number is its spell's on Forever. nil when unknown.
function ns.CraftSeconds(id)
	local measured = ns.db.craftTimes and ns.db.craftTimes[id]
	if measured then return measured end
	local ms
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(id)
		ms = info and info.castTime
	elseif GetSpellInfo then
		ms = select(4, GetSpellInfo(id))
	end
	if ms and ms > 0 then return ms / 1000 end
end

-- One craft's time with every reagent the cost has crafted (make: also
-- those made because cheaper, the way from raw); nil if a step is unknown.
local function CraftTime(id, depth, seen, make)
	local t = ns.CraftSeconds(id)
	if not t or depth >= 4 then return t end
	for _, reagent in ipairs(pool[id].reagents) do
		local _, how, via = Cost(reagent[1], depth, seen, make)
		if how == "craft" and via and not seen[via] then
			seen[via] = true
			local sub = CraftTime(via, depth + 1, seen, make)
			seen[via] = nil
			if not sub then return end
			t = t + sub * reagent[2] / pool[via].qty
		end
	end
	return t
end

-- One row per recipe that makes an item: cost, what it brings after the cut,
-- profit per craft and the reagents' sources for the tooltip. Sorted by
-- profit; rows without a price last. all adds the guild's recipes.
-- Kept a minute, or until new data comes in (ns.RowsChanged), so ticking
-- a box or typing a search does not work it all out again (Zach 10/11).
local rowsCache = {}
function ns.RowsChanged()
	rowsCache = {}
end

local BuildRows
function ns.Rows(profession, all)
	local key = (profession or "") .. (all and "/all" or "/mine")
	local c = rowsCache[key]
	if c and time() - c.at < 60 then
		pool, makers = c.pool, nil
		return c.rows
	end
	ahMemo = {}
	local ok, rows = pcall(BuildRows, profession, all)
	ahMemo = nil
	if not ok then error(rows) end
	rowsCache[key] = { at = time(), rows = rows, pool = pool }
	return rows
end

BuildRows = function(profession, all)
	Pool(all)
	makers = nil
	local rows = {}
	for id, r in pairs(pool) do
		if r.item and (not profession or r.profession == profession) then
			local row = { id = id, recipe = r, mine = ns.db.recipes[id] ~= nil }
			row.cost, row.missing = CraftCost(id, 0, { [id] = true }, false)
			-- Making the reagents yourself, where cheaper: for the tooltip.
			row.costMade = CraftCost(id, 0, { [id] = true }, true)
			local price, age = ns.AH(r.item)
			row.age = age
			row.listed, row.quantity = ns.Listings(r.item)
			row.sold = ns.SoldPerDay(r.item)
			-- His own sales are proof (Zach 9/11): never less than a seventh
			-- of what he sold in the last week.
			row.myCount, row.myMoney = ns.MySales(r.item, 7)
			if row.myCount then row.sold = math.max(row.sold or 0, row.myCount / 7) end
			if price then row.sells = ns.Keep(price * r.qty) end
			row.time = CraftTime(id, 0, { [id] = true }, false)
			row.timeMade = CraftTime(id, 0, { [id] = true }, true)
			if row.cost and row.sells then
				row.profit = row.sells - row.cost
				row.margin = row.cost > 0 and row.profit / row.cost or nil
				-- What the market pays out a day (Zach 9/11): a big profit on
				-- something nobody buys is no money in. Crafts a day sold at
				-- this profit; his own share is smaller when others sell too.
				if row.sold then row.perDay = row.profit * row.sold / r.qty end
			end
			-- From raw or bought reagents (Zach 9/11: is crafting up from raw
			-- worth the time?). Raw is worth it when the gold it adds for the
			-- extra time beats what a minute of crafting with bought reagents
			-- earns.
			if row.sells and row.cost and row.costMade and row.costMade < row.cost then
				row.profitMade = row.sells - row.costMade
				local extra = (row.time and row.timeMade) and row.timeMade - row.time
				if extra and extra > 0 and row.time > 0 then
					row.rawPerMin = (row.cost - row.costMade) / extra * 60
					row.buyPerMin = row.profit / row.time * 60
					row.rawWorth = row.rawPerMin >= row.buyPerMin
				elseif extra then
					row.rawWorth = true
				end
			end
			-- Best colour among his characters, for skill-ups; white for
			-- recipes only the guild knows.
			local colour = "x"
			for _, c in pairs(r.by) do
				if ("oygx"):find(c) < ("oygx"):find(colour) then colour = c end
			end
			if not row.mine then colour = "w" end
			row.colour = colour
			table.insert(rows, row)
		end
	end
	table.sort(rows, function(a, b)
		if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
		if a.profit and a.profit ~= b.profit then return a.profit > b.profit end
		return (a.recipe.name or "") < (b.recipe.name or "")
	end)
	return rows
end

-- Why a row is in or out of Me dumb, me craft now (Zach 9/11: the
-- Blunderbuss was missing and he wanted to see why). nil when it passes.
function ns.WhyNot(r)
	local bar = ns.db.focusMin or 1000
	if not r.cost then return "no price for " .. (r.missing and ns.ItemName(r.missing) or "a reagent") end
	if not r.sells then return "no auction house price for it" end
	if not r.sold then
		local last = ns.db.snapshot and ns.db.snapshot.at
		if not last then return "Sold/day unknown: no scan yet" end
		local wait = 600 - (time() - last)
		return "Sold/day unknown: needs a second scan" .. (wait > 0 and string.format(" (in %d min at the earliest)", math.ceil(wait / 60)) or ", scan again now")
	end
	if r.sold <= 0 then return "nothing sold between your scans" end
	if r.perDay < bar then return string.format("earns %s a day, under the bar of %s (/bok min)", ns.Money(r.perDay), ns.Money(bar)) end
end

-- What Sold/day rests on: hours of scans compared.
function ns.SoldBasis(item)
	local t = ns.db.turnover[item]
	return t and t.h or 0
end

-- Each reagent's line for the tooltip: count, name, unit cost and source.
-- Uses the pool of the last ns.Rows.
-- For the shopping list: an item's cheapest source (make: also crafting,
-- for raw materials) and a recipe of the last ns.Rows' pool.
function ns.CostOf(item, make)
	makers = nil
	return Cost(item, 0, {}, make)
end

function ns.Recipe(id)
	return pool[id]
end

-- Each reagent bought (each, source) and, when making it is cheaper, made
-- (madeEach, via: the recipe).
function ns.Breakdown(id)
	makers = nil
	local out = {}
	for _, reagent in ipairs(pool[id].reagents) do
		local c, how, via = Cost(reagent[1], 0, { [id] = true }, false)
		local source = how == "craft" and ("made: " .. (pool[via].name or "?")) or how or "no price"
		local b = { name = ns.ItemName(reagent[1]), count = reagent[2], each = c, source = source }
		local m, mhow, mvia = Cost(reagent[1], 0, { [id] = true }, true)
		if mhow == "craft" and m and (not c or m < c) then b.madeEach, b.via = m, pool[mvia].name end
		table.insert(out, b)
	end
	return out
end

function ns.Professions(all)
	local seen, list = {}, {}
	for _, r in pairs(Pool(all)) do
		if r.profession and not seen[r.profession] then
			seen[r.profession] = true
			table.insert(list, r.profession)
		end
	end
	table.sort(list)
	return list
end

-- Gathering (Zach 9/11): what raw materials and bars fetch, as a guide to
-- whether a gathering profession pays. No profit: that depends on how fast
-- he gathers. Classic item numbers; names come from the game, so a wrong
-- number shows as a wrong name.
local GATHER = {
	Mining = { 2770, 2771, 2775, 2772, 2776, 3858, 7911, 10620, 2835, 2836, 2838, 7912, 12365,
		2840, 3576, 2841, 2842, 3575, 3577, 3859, 3860, 6037, 12359 },
	Herbalism = { 2447, 765, 2449, 785, 2450, 3820, 2453, 3355, 3369, 3356, 3357, 3818, 3821, 3358, 3819,
		4625, 8831, 8836, 8838, 8839, 8845, 8846, 13464, 13463, 13465, 13466, 13467, 13468 },
	Skinning = { 2934, 2318, 783, 2319, 4232, 4234, 4235, 4304, 8169, 8170, 8171 },
}
ns.GATHER_PROFESSIONS = { "Herbalism", "Mining", "Skinning" }

function ns.GatherRows(profession)
	local rows = {}
	for _, p in ipairs(ns.GATHER_PROFESSIONS) do
		if not profession or profession == p then
			for _, item in ipairs(GATHER[p]) do
				local price, age = ns.AH(item)
				local listed, quantity = ns.Listings(item)
				table.insert(rows, { item = item, profession = p, price = price, age = age, listed = listed, quantity = quantity,
					sold = ns.SoldPerDay(item) })
			end
		end
	end
	table.sort(rows, function(a, b)
		if (a.price ~= nil) ~= (b.price ~= nil) then return a.price ~= nil end
		if a.price and a.price ~= b.price then return a.price > b.price end
		return a.item < b.item
	end)
	return rows
end

-- Listings ----------------------------------------------------------------

-- How many auctions there are of each item, counted from a full auction
-- house scan, Auctionator's or Bokföring's own (the Scan AH button): few
-- listings is a red flag (Zach 8/11), a thin market one seller can swing.
-- Ordinary searches are not counted; they show only part of the house.
ns.FEW = 5

-- Turnover (Zach 9/11): what sells. Each full scan is compared with the one
-- before; an auction that is gone was bought, unless its seller has the
-- same item up again (a repost or an undercut). Auctions that expire count
-- as sold too, so scan at least twice a day for honest numbers. Kept per
-- item as sold quantity over hours watched, the old weighing half as much
-- every three days.
local MIN_GAP, MAX_GAP, HALF_LIFE = 600, 48 * 3600, 72 * 3600

local function Turnover(old, new, gap)
	local decay = 0.5 ^ (gap / HALF_LIFE)
	for item, auctions in pairs(old) do
		local now = new[item] or {}
		local sellers = {}
		for key in pairs(now) do sellers[key:match(":([^:]*)$")] = true end
		local sold = 0
		for key, n in pairs(auctions) do
			local gone = n - (now[key] or 0)
			local count, seller = key:match("^(%d+):%d+:(.*)$")
			if gone > 0 and not (seller ~= "?" and sellers[seller]) then
				sold = sold + gone * (tonumber(count) or 1)
			end
		end
		local t = ns.db.turnover[item] or { q = 0, h = 0 }
		t.q = t.q * decay + sold
		t.h = t.h * decay + gap / 3600
		ns.db.turnover[item] = t
	end
end

-- A summary scan (Auctionator's on Forever, and Scan AH; 09/11) gives only
-- the quantity for sale per item, not single auctions: what sold is then
-- how much the quantity fell, which misses sales covered by new listings.
local function SummaryTurnover(old, new, gap)
	local decay = 0.5 ^ (gap / HALF_LIFE)
	for item, quantity in pairs(old) do
		local t = ns.db.turnover[item] or { q = 0, h = 0 }
		t.q = t.q * decay + math.max(0, quantity - (new[item] or 0))
		t.h = t.h * decay + gap / 3600
		ns.db.turnover[item] = t
	end
end

-- summary: rows are items with their total quantity, not single auctions.
local function Count(total, info, summary)
	local counts, auctions = {}, {}
	for i = 1, total do
		local item, quantity, buyout, seller, unit = info(i)
		if item then
			local c = counts[item] or { n = 0, q = 0 }
			c.n, c.q = c.n + 1, c.q + (quantity or 1)
			-- The lowest price for one, for the market history (Market.lua).
			if unit and unit > 0 and (not c.lo or unit < c.lo) then c.lo = unit end
			counts[item] = c
			if summary then
				auctions[item] = (auctions[item] or 0) + (quantity or 0)
			else
				-- One auction as count:buyout:seller, to see it again next scan.
				local key = string.format("%d:%d:%s", quantity or 1, buyout or 0, seller or "?")
				auctions[item] = auctions[item] or {}
				auctions[item][key] = (auctions[item][key] or 0) + 1
			end
		end
	end
	if not next(counts) then return end
	if ns.RecordMarket then ns.RecordMarket(counts) end
	if ns.RecordHours then ns.RecordHours(counts) end
	-- Today's vendor flips (0.6.6): one scan is enough.
	if ns.RecordVendorFlips then ns.RecordVendorFlips(counts) end
	local now = time()
	local kind = summary and "summary" or "auctions"
	local last = ns.db.snapshot
	if last and last.at then
		local gap = now - last.at
		-- The same scan reported twice is not a new look; said aloud when
		-- he asked for it (Zach 9/11: Scan AH seemed to do nothing).
		if gap < MIN_GAP then
			if ns.scanAsked then
				ns.Print(string.format("the last scan was %d min ago; scan again in %d min for new counts.", math.floor(gap / 60), math.ceil((MIN_GAP - gap) / 60)))
			end
			ns.scanAsked = nil
			return
		end
		if gap <= MAX_GAP and (last.kind or "auctions") == kind then
			if summary then SummaryTurnover(last.auctions, auctions, gap) else Turnover(last.auctions, auctions, gap) end
		end
	end
	ns.scanAsked = nil
	ns.db.snapshot = { at = now, kind = kind, auctions = auctions }
	ns.db.listings = {}
	ns.db.scanned = { at = now, items = 0 }
	for item, c in pairs(counts) do
		ns.db.listings[item] = { n = not summary and c.n or nil, q = c.q, at = now }
		ns.db.scanned.items = ns.db.scanned.items + 1
	end
	ns.Print(string.format("full scan counted: %d items on the auction house.", ns.db.scanned.items))
	if ns.Refresh then ns.Refresh() end
end

-- Modern full scan (C_AuctionHouse.ReplicateItems). Both APIs give buyout
-- 10th, seller 14th, item 17th.
local function ReadReplicate()
	local ah = C_AuctionHouse
	if not ah or not ah.GetNumReplicateItems then return end
	ns.seen = "REPLICATE_ITEM_LIST_UPDATE, " .. tostring(ah.GetNumReplicateItems()) .. " auctions"
	Count(ah.GetNumReplicateItems(), function(i)
		local _, _, quantity, _, _, _, _, _, _, buyout, _, _, _, seller, _, _, item = ah.GetReplicateItemInfo(i)
		return item, quantity, buyout, seller, buyout and buyout > 0 and buyout / math.max(quantity or 1, 1) or nil
	end)
end

-- Classic "get all" scan: one batch holding the whole house. A normal
-- search page is at most 50, so a bigger batch is a full scan; 1000 was
-- too high a bar, a small server can have fewer (09/11).
local function ReadGetAll()
	if not GetNumAuctionItems then return end
	local batch, total = GetNumAuctionItems("list")
	ns.seen = string.format("AUCTION_ITEM_LIST_UPDATE, batch %s of %s", tostring(batch), tostring(total))
	if not batch or batch <= 50 or batch ~= total then return end
	Count(batch, function(i)
		local _, _, quantity, _, _, _, _, _, _, buyout, _, _, _, seller, _, _, item = GetAuctionItemInfo("list", i)
		return item, quantity, buyout, seller, buyout and buyout > 0 and buyout / math.max(quantity or 1, 1) or nil
	end)
end

-- The summary scan: an empty browse, paged until the server says it is
-- all there. A browse of a few hundred items or less is an ordinary search
-- and is not counted.
local FULL_BROWSE = 300
local browsing = false
-- Progress of his own scan (Zach 9/11: Scan AH showed nothing while it
-- ran): items so far against the last full scan's count, on the button.
-- nil when done. No answer for 30 seconds ends it.
local progressAt = 0
local function Progress(n)
	progressAt = GetTime()
	local expected = ns.db.scanned and ns.db.scanned.items
	if ns.ScanProgress then
		ns.ScanProgress(n and (expected and expected > 0 and math.min(99, math.floor(n / expected * 100)) or 0))
	end
	if n then
		C_Timer.After(31, function()
			if browsing and GetTime() - progressAt >= 30 then
				browsing = false
				Progress(nil)
				ns.Print("no answer from the auction house for 30 seconds; scan stopped. Try again.")
			end
		end)
	end
end
local function ReadBrowse()
	local ah = C_AuctionHouse
	if not ah or not ah.GetBrowseResults then return end
	local results = ah.GetBrowseResults() or {}
	local full = not ah.HasFullBrowseResults or ah.HasFullBrowseResults()
	ns.seen = string.format("browse results, %d items%s", #results, full and "" or ", more coming")
	if not full then
		if browsing then
			Progress(#results)
			if ah.RequestMoreBrowseResults then ah.RequestMoreBrowseResults() end
		end
		return
	end
	local asked = browsing
	browsing = false
	if asked then Progress(nil) end
	if #results < FULL_BROWSE then
		if asked then ns.Print(string.format("the auction house answered with only %d items; not counted as a full scan.", #results)) end
		return
	end
	if asked then ns.scanAsked = true end
	Count(#results, function(i)
		local r = results[i]
		return r.itemKey and r.itemKey.itemID, r.totalQuantity, nil, nil, r.minPrice
	end, true)
end
ns.ReadBrowse = ReadBrowse

-- Bokföring's own scan, from the Scan AH button with the auction house
-- open: the same summary scan Auctionator makes on Forever (09/11).
function ns.ScanAH()
	local ah = C_AuctionHouse
	local open = (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown())
	if not open then
		ns.Print("open the auction house first, then press Scan AH.")
		return
	end
	if ah and ah.SendBrowseQuery then
		browsing = true
		local price = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
		local ok, err = pcall(ah.SendBrowseQuery, { searchString = "", sorts = { { sortOrder = price, reverseSort = false } }, filters = {}, itemClassFilters = {} })
		if not ok then
			browsing = false
			ns.Print("the scan was refused: " .. tostring(err))
			return
		end
		Progress(0)
		ns.Print("scan started; it takes a little while, the result comes in chat.")
	elseif ah and ah.ReplicateItems then
		ah.ReplicateItems()
		ns.Print("full scan asked for; the counts come when the server answers.")
	elseif QueryAuctionItems and CanSendAuctionQuery then
		local _, all = CanSendAuctionQuery()
		if not all then ns.Print("the server allows one full scan every 15 minutes; try again later.") return end
		QueryAuctionItems("", nil, nil, 0, false, 0, true)
		ns.Print("full scan asked for; the counts come when the server answers.")
	else
		ns.Print("this client has no full scan.")
	end
end

-- Listings of an item as of the last full scan: count, quantity, age in
-- days; nil if it has not been scanned.
function ns.Listings(item)
	local l = ns.db.listings[item]
	if l then return l.n, l.q, math.floor((time() - l.at) / 86400) end
	if next(ns.db.listings) then return 0, 0 end
end

-- Sold per day, or nil until two full scans have been compared.
function ns.SoldPerDay(item)
	local t = ns.db.turnover[item]
	if t and t.h > 0 then return t.q / t.h * 24 end
	if next(ns.db.turnover) then return 0 end
end

-- Events ------------------------------------------------------------------

local readAt = 0
local function ReadSoon()
	readAt = GetTime() + 1
	C_Timer.After(1.1, function()
		if GetTime() < readAt then return end
		local count, profession = ReadRecipes()
		if count > 0 then
			ns.openProfession = profession
			if ns.ShowButton then ns.ShowButton() end
			if ns.Refresh then ns.Refresh() end
		end
	end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
	"MERCHANT_SHOW", "MERCHANT_UPDATE", "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_ITEM_LIST_UPDATE", "AUCTION_HOUSE_SHOW",
	"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, name)
	ns.RowsChanged()
	if event == "ADDON_LOADED" then
		if name ~= "Bokforing" then return end
		BokforingDB = BokforingDB or {}
		ns.db = BokforingDB
		ns.db.recipes = ns.db.recipes or {}
		ns.db.vendor = ns.db.vendor or {}
		-- Once (0.6.4): prices from before limited stock was left out, and
		-- with no vendor name, are forgotten and learnt again (Zach 11/11).
		if not ns.db.vendorAt then ns.db.vendor = {} end
		ns.db.vendorAt = ns.db.vendorAt or {}
		ns.db.listings = ns.db.listings or {}
		ns.db.catalog = ns.db.catalog or {}
		ns.db.turnover = ns.db.turnover or {}
		ns.db.market = ns.db.market or {}
		Migrate(ns.db)
	elseif not ns.db or (ns.Allowed and not ns.Allowed()) then
		return
	elseif event:match("^AUCTION") or event == "REPLICATE_ITEM_LIST_UPDATE" then
		-- Every auction event this session, for /bok test (09/11: an
		-- Auctionator scan left no trace).
		ns.events = ns.events or {}
		ns.events[event] = (ns.events[event] or 0) + 1
		if event == "REPLICATE_ITEM_LIST_UPDATE" then ReadReplicate() end
		if event == "AUCTION_ITEM_LIST_UPDATE" then ReadGetAll() end
		if event:match("^AUCTION_HOUSE_BROWSE_RESULTS") then ReadBrowse() end
	elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
		ReadMerchant()
	else
		ReadSoon()
	end
end)

-- Every command, for /bok help and the ? on the window (Zach 10/11).
ns.HELP = {
	{ "/bok", "opens and closes Bokföring" },
	{ "Read recipes", "the button at the bottom: reads every recipe and recipe item in the game once" },
	{ "Prices", "scan the auction house with Auctionator; Bokföring reads its scans" },
	{ "Your recipes", "open each profession window once on each character" },
	{ "/bok budget 50g", "how much Today may suggest spending a day; /bok budget off: a quarter of your gold" },
	{ "/bok reset history", "erases the history and starts again" },
	{ "/bok size", "how big the saved data is, and cleaning it" },
	{ "/bok scan", "reads every recipe again" },
	{ "/bok scan items", "reads the recipe items again (skill and where to get them)" },
	{ "/bok ah", "scans the auction house with Bokföring itself" },
	{ "/bok why name", "what a recipe lacks: a price, sales or profit a day" },
	{ "/bok test", "checks Auctionator, the data and the timing, for bug reports" },
}

SLASH_BOKFORING1 = "/bok"
SLASH_BOKFORING2 = "/bokforing"
SlashCmdList.BOKFORING = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if ns.Allowed and not ns.Allowed() then return end
	if msg == "test" then
		-- Whether Auctionator's API is there, and a price it knows.
		local api = API()
		ns.Print("Auctionator API: " .. (api and "found" or "missing") .. ".")
		if api then
			ns.Print(string.format("Auctionator shopping lists: CreateShoppingList %s, ConvertToSearchString %s, DeleteShoppingList %s.",
				api.CreateShoppingList and "yes" or "no", api.ConvertToSearchString and "yes" or "no", api.DeleteShoppingList and "yes" or "no"))
		end
		local recipes, vendor = 0, 0
		for _ in pairs(ns.db.recipes) do recipes = recipes + 1 end
		for _ in pairs(ns.db.vendor) do vendor = vendor + 1 end
		local listed = 0
		for _ in pairs(ns.db.listings) do listed = listed + 1 end
		ns.Print(string.format("%d recipes, %d vendor prices, listings of %d items saved.", recipes, vendor, listed))
		local catalog = 0
		for _ in pairs(ns.db.catalog) do catalog = catalog + 1 end
		-- What the game tells about a recipe not learned, to see whether the
		-- skill it needs is there (Zach 9/11).
		local ui = C_TradeSkillUI
		for id in pairs(ns.db.catalog) do
			if not ns.db.recipes[id] and ui and ui.GetRecipeInfo then
				local ok, info = pcall(ui.GetRecipeInfo, id)
				local fields = {}
				if ok and type(info) == "table" then
					for k, v in pairs(info) do
						if type(v) ~= "table" then table.insert(fields, k .. "=" .. tostring(v)) end
					end
					table.sort(fields)
				end
				ns.Print(string.format("Recipe %d not learned: %s", id, #fields > 0 and table.concat(fields, ", ") or "no info"))
				-- Where to get it and the skill it needs, if this client says (Zach 10/11).
				local okSource, source = pcall(ui.GetRecipeSourceText or error, id)
				ns.Print(string.format("Recipe %d source: %s", id, okSource and source and tostring(source):gsub("|", "||") or "none"))
				break
			end
		end
		ns.Print(catalog > 0 and string.format("Catalog: %d recipes, scanned %s.", catalog, date("%d/%m %H:%M", ns.db.catalogAt)) or "Catalog: empty, run /bok scan.")
		-- Per profession, as the catalog names them (Zach 10/11: a
		-- blacksmith's All recipes stayed empty after /bok scan).
		local per = {}
		for _, r in pairs(ns.db.catalog) do per[r.profession or "?"] = (per[r.profession or "?"] or 0) + 1 end
		local parts = {}
		for p, n in pairs(per) do table.insert(parts, p .. " " .. n) end
		table.sort(parts)
		if #parts > 0 then ns.Print("Catalog by profession: " .. table.concat(parts, ", ") .. ".") end
		local me, learned = ns.MeKey(), {}
		for _, r in pairs(ns.db.recipes) do
			if r.by and r.by[me] then learned[r.profession or "?"] = (learned[r.profession or "?"] or 0) + 1 end
		end
		parts = {}
		for p, n in pairs(learned) do table.insert(parts, p .. " " .. n) end
		table.sort(parts)
		ns.Print("Learned on this character: " .. (#parts > 0 and table.concat(parts, ", ") or "none read yet; open your profession windows") .. ".")
		-- What the scan code has seen this session, to find why counts stay empty.
		ns.Print("Mailbox: " .. (ns.MailTest and ns.MailTest() or "?") .. ".")
		-- Sales noted from sold mails so far, newest first (Zach 9/11: did
		-- any sold mail ever reach Bokföring?).
		local noted = {}
		for item, list in pairs(ns.db.sales or {}) do
			for _, sale in ipairs(list) do table.insert(noted, { item = item, at = sale.at, money = sale.money }) end
		end
		table.sort(noted, function(a, b) return a.at > b.at end)
		ns.Print(string.format("Sales noted from mail: %d%s", #noted, noted[1] and string.format(", newest %s for %s on %s",
			noted[1].item, ns.Money(noted[1].money), date("%d/%m %H:%M", noted[1].at)) or ""))
		ns.Print("History: " .. ns.HistoryTest() .. ".")
		ns.Print("Sold notice copy: " .. ns.NoticeTest() .. ".")
		ns.Print("Saved data: " .. ns.SizeTest() .. ".")
		ns.Print("Recipes to learn: " .. ns.LearnTest() .. ".")
		ns.Print("Stock at cost: " .. ns.StockTest() .. ".")
		local profiles, ready = 0, 0
		for item in pairs(ns.db.hours or {}) do
			profiles = profiles + 1
			if ns.HourProfile(item) then ready = ready + 1 end
		end
		ns.Print(string.format("Hours of the day: %d items followed, %d with 8 or more hours known.", profiles, ready))
		-- What opening the window costs (Zach 10/11: a freeze).
		ns.RowsChanged()
		local t0 = debugprofilestop()
		local mine = #ns.Rows(nil, false)
		local t1 = debugprofilestop()
		local all = #ns.Rows(nil, true)
		local t2 = debugprofilestop()
		ns.Print(string.format("Timing, worked out afresh: My recipes %d rows %.0f ms, All recipes %d rows %.0f ms; last window refresh %s ms (%s).",
			mine, t1 - t0, all, t2 - t1, ns.refreshMs and string.format("%.0f", ns.refreshMs) or "?", ns.refreshWhat or "not opened"))
		ns.Print("Last auction event: " .. (ns.seen or "none this session") .. ".")
		local seenEvents = {}
		for event, n in pairs(ns.events or {}) do table.insert(seenEvents, event .. " " .. n) end
		ns.Print("Auction events this session: " .. (#seenEvents > 0 and table.concat(seenEvents, ", ") or "none") .. ".")
		local ah = C_AuctionHouse
		ns.Print(string.format("Full scan API: ReplicateItems %s, GetNumReplicateItems %s, QueryAuctionItems %s, GetNumAuctionItems %s.",
			ah and ah.ReplicateItems and "yes" or "no", ah and ah.GetNumReplicateItems and "yes" or "no",
			QueryAuctionItems and "yes" or "no", GetNumAuctionItems and "yes" or "no"))
		if ns.db.scanned then ns.Print(string.format("Last full scan counted: %d items, %s.", ns.db.scanned.items, date("%d/%m %H:%M", ns.db.scanned.at))) end
		for _, r in pairs(ns.db.recipes) do
			if r.item then
				local price, age = ns.AH(r.item)
				ns.Print(string.format("%s: %s%s", ns.ItemName(r.item), price and ns.Money(price) or "no AH price",
					age and string.format(" (%d days old)", age) or ""))
				break
			end
		end
	elseif msg == "scan items" then
		-- Read the recipe items again (Learn.lua), for skills and sources.
		ns.ScanRecipeItems()
	elseif msg:match("^scan") then
		ns.Scan(tonumber(msg:match("^scan%s+(%d+)")))
	elseif msg:match("^why") then
		-- /bok why blunder: each matching recipe and why it is in or out of
		-- Me dumb, me craft now.
		local text = msg:match("^why%s+(.+)$")
		if not text then ns.Print("write it like /bok why blunderbuss.") return end
		local found = 0
		for _, r in ipairs(ns.Rows(nil, true)) do
			local name = (r.recipe.name or ""):lower()
			if name:find(text, 1, true) and found < 5 then
				found = found + 1
				local why = ns.WhyNot(r)
				ns.Print(string.format("%s: profit %s, sold/day %s, profit/day %s: %s", r.recipe.name,
					r.profit and ns.Money(r.profit) or "?", r.sold and string.format("%.1f", r.sold) or "?",
					r.perDay and ns.Money(r.perDay) or "?", why and ("out, " .. why) or "in"))
			end
		end
		if found == 0 then ns.Print("no recipe matches \"" .. text .. "\".") end
	elseif msg:match("^min") then
		-- The bar for Me dumb, me craft now: profit a day, in money.
		local amount = ns.ParseMoney(msg:match("^min%s+(.+)$"))
		if amount then
			ns.db.focusMin = amount
			ns.Print("Me dumb, me craft now shows crafts earning at least " .. ns.Money(amount) .. " a day.")
			if ns.Refresh then ns.Refresh() end
		else
			ns.Print("write it like /bok min 25s or /bok min 1g.")
		end
	elseif msg == "outside" then
		-- Characters outside the guild running Bokföring (Zach 9/11).
		ns.ListOutside()
	elseif msg:match("^budget") then
		-- Today's budget (Zach 10/11).
		ns.SetBudget(msg:match("^budget%s*(.-)$") or "")
	elseif msg == "reset history" then
		-- A clean history (Zach 10/11), after a yes.
		ns.ResetHistory()
	elseif msg == "ah" then
		-- Bokföring's own auction house scan; Auctionator's full scan feeds
		-- Bokföring the same (Zach 10/11: the button now reads recipes).
		ns.ScanAH()
	elseif msg == "size" then
		-- The size warning on demand (Zach 9/11), whatever the size.
		ns.ShowSize()
	elseif msg == "fullscan" then
		-- The detailed scan, every single auction (Zach 9/11: try whether
		-- Forever's server answers it); the result shows in chat.
		if C_AuctionHouse and C_AuctionHouse.ReplicateItems then
			C_AuctionHouse.ReplicateItems()
			ns.Print("detailed scan asked for; with the auction house open, an answer comes as \"full scan counted\" within a minute, or nothing.")
		else
			ns.Print("this client has no detailed scan.")
		end
	elseif msg == "help" then
		ns.Print("commands:")
		for _, line in ipairs(ns.HELP) do ns.Print("  " .. line[1] .. ": " .. line[2]) end
	else
		ns.Toggle()
	end
end
