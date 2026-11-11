-- Bokföring's shopping list (Zach 9/11): right-click a recipe, say how many
-- crafts, and the reagents go into an Auctionator shopping list. Buying
-- stays one click per purchase in Auctionator, as the game demands; an
-- addon may not buy by itself.
--
-- The quickest craft by default: buy every reagent, craft only what cannot
-- be bought. "Raw materials" instead goes down to what is cheapest to make
-- yourself (ore rather than bars). Reagents already in the bags are taken
-- off, unless he unticks that in the menu (saved). Each list is kept as a
-- plan for the history, and the same list is not made twice while open.

local _, ns = ...

local CALLER = "Bokforing"

-- Everything to buy for n of an item: buy[item] = count, going down into
-- recipes where that is the way (or, raw, the cheaper way).
local function Need(item, n, raw, owned, buy, depth)
	if owned[item] > 0 then
		local take = math.min(owned[item], n)
		owned[item], n = owned[item] - take, n - take
	end
	if n <= 0 then return end
	local _, how, via = ns.CostOf(item, raw)
	local r = how == "craft" and via and ns.Recipe(via)
	if r and depth < 4 then
		local crafts = math.ceil(n / r.qty)
		for _, reagent in ipairs(r.reagents) do Need(reagent[1], reagent[2] * crafts, raw, owned, buy, depth + 1) end
		return
	end
	buy[item] = (buy[item] or 0) + n
end

local function Owned(item)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(item, false) or 0 end
	return GetItemCount and GetItemCount(item, false) or 0
end

local function SearchString(name, count)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.ConvertToSearchString then
		local ok, text = pcall(api.ConvertToSearchString, CALLER, { searchString = name, isExact = true, quantity = count })
		if ok and text then return text end
		ok, text = pcall(api.ConvertToSearchString, CALLER, { searchString = name, isExact = true })
		if ok and text then return text end
	end
	return "\"" .. name .. "\""
end

-- An item's name, or nil while the game has not loaded it yet.
local function Known(item)
	return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)) or (GetItemInfo and GetItemInfo(item))
end

function ns.Shop(id, crafts, raw, tries)
	local r = ns.Recipe(id)
	if not r then return end
	-- The same list still open (Zach 9/11): no second plan, but the
	-- Auctionator list is made again, under the same name so it replaces the
	-- old one, with what is left to buy.
	local open = ns.OpenPlan(id, crafts, raw)
	local useOwned = ns.db.useOwned ~= false
	local buy = {}
	if open and not useOwned then
		for item, n in pairs(open.need) do
			local left = n - (open.bought[item] or 0)
			if left > 0 then buy[item] = left end
		end
	else
		-- What the bags lack, looked up once per item; for an open list too
		-- (Zach 9/11: x5 Blunderbuss gave only Medium Leather, the rest
		-- counted as bought on that list but no longer in his bags).
		local owned = setmetatable({}, { __index = function(t, item)
			local n = useOwned and Owned(item) or 0
			rawset(t, item, n)
			return n
		end })
		for _, reagent in ipairs(r.reagents) do Need(reagent[1], reagent[2] * crafts, raw, owned, buy, 0) end
	end
	-- Names the game has not loaded yet (Zach 9/11: Copper Ore went into
	-- the list as "item 2770"): ask for them and try again shortly.
	local unknown = false
	for item in pairs(buy) do
		if not Known(item) then
			unknown = true
			if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(item) end
		end
	end
	if unknown and (tries or 0) < 10 then
		C_Timer.After(0.3, function() ns.Shop(id, crafts, raw, (tries or 0) + 1) end)
		return
	end
	if unknown then ns.Print("some item names did not load; the list may show item numbers.") end

	local listName = string.format("Bokföring: %s x%d%s", r.name or ns.ItemName(r.item), crafts, raw and " (raw)" or "")
	local terms, lines, vendor, total = {}, {}, {}, 0
	for item, count in pairs(buy) do
		local name = ns.ItemName(item)
		local each, how = ns.CostOf(item, false)
		total = total + (each or 0) * count
		if how == "vendor" or ns.IsVendorGood(item) then
			table.insert(vendor, string.format("%d x %s%s", count, name, each and (" (" .. ns.Money(each * count) .. ")") or ""))
		else
			table.insert(terms, SearchString(name, count))
			table.insert(lines, string.format("%d x %s%s", count, name, each and (" (" .. ns.Money(each * count) .. ")") or ""))
		end
	end
	table.sort(lines)
	table.sort(vendor)
	if #terms == 0 and #vendor == 0 then
		ns.Print(open and "everything on this list is bought." or ("you already have everything for " .. crafts .. " crafts."))
		return
	end
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if #terms > 0 then
		local ok = api and api.CreateShoppingList and pcall(api.CreateShoppingList, CALLER, listName, terms)
		if ok then
			ns.Print(string.format("Auctionator list \"%s\": open Shopping in Auctionator, pick the list and buy each with a click.", listName))
		else
			ns.Print("could not make an Auctionator list; buy these yourself:")
		end
		for _, line in ipairs(lines) do ns.Print("  auction house: " .. line) end
	end
	for _, line in ipairs(vendor) do ns.Print("  vendor: " .. line) end
	-- What this list buys counts as Bokföring's expense for 3 days (History.lua).
	if not open then ns.NewPlan(id, r.item, crafts, raw, buy, listName, r) end
	if open then
		ns.Print(string.format("this list from %s was still open: made again with what is left to buy.", date("%d/%m %H:%M", open.at)))
	else
		ns.Print(string.format("about %s in all%s.", ns.Money(total), useOwned and ", what is in your bags taken off" or ""))
	end
end

-- A finished list out of Auctionator (Zach 9/11). Only through its API;
-- /bok test says whether this Auctionator has the function. True when gone.
function ns.DeleteList(name)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	return api and api.DeleteShoppingList and pcall(api.DeleteShoppingList, CALLER, name) or false
end

-- A work order where he sends the materials (Zach 9/11): what the crafter
-- needs that his bags do not hold goes on an Auctionator list, and the order
-- shows under Making now until bought or marked done. reagents are
-- { itemID, count } per craft, from Skatteverket's recipe data; with
-- total, the counts are for the whole order (raw materials, Zach 10/11).
function ns.ShopForOrder(name, reagents, crafts, to, total)
	local buy, terms, vendor = {}, {}, {}
	for _, r in ipairs(reagents) do
		local missing = (total and r[2] or r[2] * crafts) - Owned(r[1])
		if missing > 0 then buy[r[1]] = (buy[r[1]] or 0) + missing end
	end
	local listName = string.format("Bokföring: %s x%d till %s", name, crafts, to)
	local perCraft = reagents
	if total then
		perCraft = {}
		for _, r in ipairs(reagents) do table.insert(perCraft, { r[1], r[2] / crafts }) end
	end
	local recipe = { name = name, qty = 1, reagents = perCraft }
	ns.NewPlan(nil, nil, crafts, false, buy, listName, recipe, to)
	for item, count in pairs(buy) do
		if ns.IsVendorGood(item) then
			table.insert(vendor, string.format("%d x %s", count, ns.ItemName(item)))
		else
			table.insert(terms, SearchString(ns.ItemName(item), count))
		end
	end
	if #terms == 0 and #vendor == 0 then
		ns.Print(string.format("du har allt material till arbetsordern (%s x%d till %s) i väskorna; skicka det till %s.", name, crafts, to, to))
		return
	end
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if #terms > 0 and api and api.CreateShoppingList and pcall(api.CreateShoppingList, CALLER, listName, terms) then
		ns.Print(string.format("material att köpa till arbetsordern ligger i Auctionator-listan \"%s\"; se Making now i /bok.", listName))
	end
	for _, line in ipairs(vendor) do ns.Print("  vendor: " .. line) end
end

-- A list of items and counts, for Today's buys (Zach 10/11).
function ns.BuyList(listName, wanted)
	local terms, names = {}, {}
	for _, w in ipairs(wanted) do
		local name = Known(w[1]) or ns.ItemName(w[1])
		table.insert(terms, SearchString(name, w[2]))
		table.insert(names, string.format("%d x %s", w[2], name))
	end
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if #terms > 0 and api and api.CreateShoppingList and pcall(api.CreateShoppingList, CALLER, listName, terms) then
		ns.Print(string.format("Auctionator list \"%s\": %s. Open Shopping in Auctionator and buy each with a click.", listName, table.concat(names, ", ")))
	else
		ns.Print("could not make an Auctionator list; buy these yourself: " .. table.concat(names, ", "))
	end
end

-- Buy for N crafts with N filled in (Today, Level up).
function ns.AskCrafts(id, n, raw)
	local r = ns.Recipe(id)
	if not r then return end
	local dialog = StaticPopup_Show("BOKFORING_CRAFTS", r.name or ns.ItemName(r.item), nil, { id = id, raw = raw })
	local box = dialog and (dialog.editBox or dialog.EditBox)
	if box and n then
		box:SetText(tostring(n))
		box:HighlightText()
	end
end

-- Recipes to buy (Zach 10/11): one Auctionator list, "Bokföring: recipes",
-- made again with every recipe item added and not yet in the bags.
local RECIPE_LIST = "Bokföring: recipes"
function ns.BuyRecipe(item, remove)
	ns.db.recipeBuy = ns.db.recipeBuy or {}
	ns.db.recipeBuy[item] = not remove or nil
	local terms, names = {}, {}
	for wanted in pairs(ns.db.recipeBuy) do
		if Owned(wanted) > 0 then
			ns.db.recipeBuy[wanted] = nil
		else
			local name = Known(wanted)
			if name then
				table.insert(terms, SearchString(name, 1))
				table.insert(names, name)
			end
		end
	end
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if #terms == 0 then
		if api and api.DeleteShoppingList then pcall(api.DeleteShoppingList, CALLER, RECIPE_LIST) end
		ns.Print("no recipes left to buy.")
		return
	end
	if api and api.CreateShoppingList and pcall(api.CreateShoppingList, CALLER, RECIPE_LIST, terms) then
		table.sort(names)
		ns.Print(string.format("Auctionator list \"%s\": %s.", RECIPE_LIST, table.concat(names, ", ")))
	else
		ns.Print("could not make an Auctionator list; buy it yourself: " .. ns.ItemName(item))
	end
end

function ns.WantsRecipe(item)
	return ns.db.recipeBuy and ns.db.recipeBuy[item] or false
end

-- Right-click on the line under an unlearned recipe.
function ns.RecipeMenu(owner, item)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		ns.BuyRecipe(item, ns.WantsRecipe(item))
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		local price = ns.AH(item)
		root:CreateTitle(ns.ItemName(item))
		if ns.WantsRecipe(item) then
			root:CreateButton("Take off the recipe list", function() ns.BuyRecipe(item, true) end)
		else
			root:CreateButton("Buy" .. (price and (" (AH " .. ns.Money(price) .. ")") or " (not seen on the AH)"), function() ns.BuyRecipe(item) end)
		end
	end)
end

-- How many crafts: a small box, then the list.
StaticPopupDialogs.BOKFORING_CRAFTS = {
	text = "How many crafts of %s?",
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = true,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnShow = function(self)
		local box = self.editBox or self.EditBox
		box:SetText("1")
		box:HighlightText()
	end,
	OnAccept = function(self, data)
		local box = self.editBox or self.EditBox
		local n = tonumber(box:GetText())
		if n and n >= 1 and n <= 1000 then ns.Shop(data.id, math.floor(n), data.raw) else ns.Print("give a number of crafts, 1 to 1000.") end
	end,
	EditBoxOnEnterPressed = function(box)
		local popup = box:GetParent()
		StaticPopupDialogs.BOKFORING_CRAFTS.OnAccept(popup, popup.data)
		popup:Hide()
	end,
	EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
}

local function Ask(row, raw)
	-- Level up fills in the crafts until green (Zach 10/11).
	ns.AskCrafts(row.id, row.levelN, raw)
end

-- The right-click menu on a recipe row.
function ns.ShopMenu(owner, row)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			root:CreateTitle(row.recipe.name or ns.ItemName(row.recipe.item))
			root:CreateButton("Buy for N crafts...", function() Ask(row, false) end)
			root:CreateButton("Buy raw materials for N crafts...", function() Ask(row, true) end)
			root:CreateCheckbox("Use reagents in my bags", function() return ns.db.useOwned ~= false end,
				function() ns.db.useOwned = ns.db.useOwned == false end)
			-- Its price on the Market tab, without crafting it (Zach 9/11).
			root:CreateCheckbox("Watch the price (Market tab)", function() return ns.Watched(row.recipe.item) end,
				function() ns.Watch(row.recipe.item) end)
			-- Not learned here and there is a recipe item: buy it (Zach 10/11).
			local recipeItem = not row.recipe.by[ns.MeKey()] and ns.LearnInfo(row.recipe).item
			if recipeItem then
				if root.CreateDivider then root:CreateDivider() end
				if ns.WantsRecipe(recipeItem) then
					root:CreateButton("Take the recipe off the recipe list", function() ns.BuyRecipe(recipeItem, true) end)
				else
					local price = ns.AH(recipeItem)
					root:CreateButton("Buy the recipe" .. (price and (" (AH " .. ns.Money(price) .. ")") or " (not seen on the AH)"),
						function() ns.BuyRecipe(recipeItem) end)
				end
			end
		end)
	else
		-- No menu on this client: the quickest craft; raw with Shift.
		Ask(row, IsShiftKeyDown())
	end
end

-- The auction house window, dragged anywhere and put back there each time
-- (Zach 9/11: Auctionator's window could not be moved). Only moves the
-- window; nothing about buying.
local moved
local function AuctionWindow()
	return AuctionHouseFrame or AuctionFrame
end

local function PutBack()
	local f, at = AuctionWindow(), ns.db and ns.db.ahAt
	if not f or not at then return end
	f:ClearAllPoints()
	f:SetPoint(at[1], UIParent, at[2], at[3], at[4])
end

local function Movable()
	local f = AuctionWindow()
	if not f or moved == f then return end
	moved = f
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:HookScript("OnDragStart", function(self) self:StartMoving() end)
	f:HookScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relative, x, y = self:GetPoint(1)
		ns.db.ahAt = { point, relative, x, y }
	end)
end

local ahEvents = CreateFrame("Frame")
pcall(ahEvents.RegisterEvent, ahEvents, "AUCTION_HOUSE_SHOW")
ahEvents:SetScript("OnEvent", function()
	if not ns.db then return end
	-- After the game has placed it, as it does each time it opens.
	C_Timer.After(0, function()
		Movable()
		PutBack()
	end)
end)
