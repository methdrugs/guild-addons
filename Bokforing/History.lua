-- Bokföring's history (Zach 9/11): does the crafting pay, and was it what
-- Bokföring promised? Kept for 90 days:
--
-- Lists: each shopping list Bokföring makes is a plan, open for 3 days or
-- until all of it is bought, and never made twice. Gold spent on an item of
-- an open plan, at the auction house or a vendor, is a Bokföring expense;
-- nothing else is (Zach 9/11: not repairs, not reagents bought outside a
-- list, not reagents already in the bags).
-- Crafts: each craft of one of his recipes, with the cost and price
-- Bokföring expected at that moment.
-- Income: the sold mails Mail.lua reads, of items he crafted before the sale.
--
-- An auction house purchase is the drop in gold after he confirms a buy;
-- Bokföring never buys, it only watches the buy he clicked.

local _, ns = ...

local KEEP = 90 * 86400
local PLAN_OPEN = 3 * 86400
local WAIT = 30 -- seconds a purchase may take to show in his gold
local DAYS = 30 -- days in the graph
local ROWS, ROW_H = 9, 18
local GRAPH_H, GRAPH_X, GRAPH_W = 110, 80, 600
-- The graph's lines: running total and colour.
local LINES = { { "spentSum", 0.9, 0.2, 0.2 }, { "predicted", 0.25, 0.5, 1 }, { "incomeSum", 1, 0.82, 0 } }
-- Name, x, width.
-- Posted and On AH (Zach 10/11): what went up for sale against what sold.
-- Stock (Zach 11/11): what he holds of it, at today's price.
local COLUMNS = { { "Item", 0, 150 }, { "Crafted", 150, 45 }, { "Posted", 195, 45 }, { "Sold", 240, 40 }, { "On AH", 280, 40 },
	{ "Spent", 320, 65 }, { "Income", 385, 65 }, { "Net", 450, 60 }, { "Stock", 510, 60 }, { "Expected", 570, 60 }, { "Real each", 630, 60 } }

local function Data()
	local db = ns.db
	db.plans = db.plans or {}
	db.crafts = db.crafts or {}
	db.spends = db.spends or {}
	db.posts = db.posts or {}
	return db
end

local function Open(plan, now)
	if now - plan.at > PLAN_OPEN then return false end
	for item, n in pairs(plan.need) do
		if (plan.bought[item] or 0) < n then return true end
	end
	return false
end

-- Lists ------------------------------------------------------------------

-- A list still on the go: open, not marked done, and not crafted out
-- (a work order's list has no crafts of his own).
function ns.OnTheGo(p, now)
	if p.done or not Open(p, now) then return false end
	-- A work order or a flip (Zach 10/11): nothing of his to craft.
	if p.order or p.flip then return true end
	local made = 0
	for _, c in ipairs(Data().crafts) do
		if c.recipe == p.recipe and c.at >= p.at then made = made + 1 end
	end
	return made < p.crafts
end

-- The open plan for this recipe, number of crafts and kind of list, if any
-- (Zach 9/11: no duplicate list).
function ns.OpenPlan(id, crafts, raw)
	local now = time()
	for _, p in ipairs(Data().plans) do
		if p.recipe == id and p.crafts == crafts and (p.raw or false) == (raw or false) and ns.OnTheGo(p, now) then return p end
	end
end

-- Lists no longer on the go out of Auctionator (Zach 11/11: his filled up
-- with lists for crafts long done): all bought, crafted out, marked Done,
-- or older than three days. Once each; never a name a list on the go still
-- uses. Off with "keepLists", under Skatteverket's Inställningar.
function ns.CleanLists()
	if ns.db.keepLists then return end
	local now, live, gone = time(), {}, {}
	for _, p in ipairs(Data().plans) do
		if p.name and ns.OnTheGo(p, now) then live[p.name] = true end
	end
	for _, p in ipairs(Data().plans) do
		if p.name and not p.cleaned and not ns.OnTheGo(p, now) then
			p.cleaned = true
			if not live[p.name] and not gone[p.name] and ns.DeleteList(p.name) then
				gone[p.name] = true
				table.insert(gone, p.name)
			end
		end
	end
	if #gone == 1 then
		ns.Print(string.format("\"%s\" is done; the list is removed from Auctionator.", gone[1]))
	elseif #gone > 1 then
		ns.Print(string.format("%d finished lists removed from Auctionator.", #gone))
	end
end

function ns.NewPlan(id, item, crafts, raw, buy, name, recipe, order)
	local need, reagents = {}, {}
	for reagent, n in pairs(buy) do need[reagent] = n end
	-- The recipe's own reagents, for Making now (Work.lua).
	for _, r in ipairs(recipe and recipe.reagents or {}) do table.insert(reagents, { r[1], r[2] }) end
	local plan = { at = time(), recipe = id, item = item, crafts = crafts, raw = raw or nil, need = need, bought = {}, name = name,
		reagents = reagents, qty = recipe and recipe.qty or 1, recipeName = recipe and recipe.name, order = order }
	table.insert(Data().plans, plan)
	return plan
end

-- Gold spent on count of an item: the part a list on the go still needs is
-- a Bokföring expense, newest list first (Zach 9/11: an older list of the
-- same recipe took the buys meant for the one he was shopping for).
local function Spend(item, count, money)
	if not item or not money or money <= 0 or count <= 0 then return end
	local now, left, plans = time(), count, Data().plans
	for i = #plans, 1, -1 do
		local p = plans[i]
		local want = (p.need[item] or 0) - (p.bought[item] or 0)
		if left > 0 and want > 0 and ns.OnTheGo(p, now) then
			local take = math.min(want, left)
			p.bought[item] = (p.bought[item] or 0) + take
			table.insert(Data().spends, { at = now, item = item, count = take, money = money * take / count, made = p.item })
			ns.Print(string.format("counted %d x %s (%s) for %s.", take, ns.ItemName(item), ns.Money(money * take / count), p.name or "a list"))
			left = left - take
		end
	end
	ns.CleanLists()
end

-- An auction house buy he confirmed: counted once his gold drops.
local pending
local function Expect(item, count)
	if item then pending = { item = item, count = math.max(count or 1, 1), money = GetMoney(), at = GetTime() } end
end

local function MoneyChanged()
	if not pending then return end
	if GetTime() - pending.at > WAIT then
		pending = nil
		return
	end
	local spent = pending.money - GetMoney()
	if spent > 0 then
		local p = pending
		pending = nil
		Spend(p.item, p.count, spent)
	end
end

local lastSearched
-- An auction he puts up, by hand or through Auctionator (Zach 10/11): the
-- item and how many, read from the bag slot as it goes up.
local function Posted(location, quantity)
	if not (location and C_Item and C_Item.GetItemID) then return end
	local ok, item = pcall(C_Item.GetItemID, location)
	if ok and item then table.insert(Data().posts, { at = time(), item = item, qty = quantity or 1 }) end
end

local function Hooks()
	local ah = C_AuctionHouse
	if ah and ah.PostCommodity then hooksecurefunc(ah, "PostCommodity", function(location, _, quantity) Posted(location, quantity) end) end
	if ah and ah.PostItem then hooksecurefunc(ah, "PostItem", function(location, _, quantity) Posted(location, quantity) end) end
	if ah and ah.ConfirmCommoditiesPurchase then
		hooksecurefunc(ah, "ConfirmCommoditiesPurchase", function(item, quantity) Expect(item, quantity) end)
	end
	-- Single auctions: the item is the one last searched for.
	if ah and ah.SendSearchQuery then
		hooksecurefunc(ah, "SendSearchQuery", function(key) lastSearched = type(key) == "table" and key.itemID or nil end)
	end
	if ah and ah.PlaceBid then
		hooksecurefunc(ah, "PlaceBid", function() Expect(lastSearched, 1) end)
	end
	-- A vendor's price is known, so no waiting for the gold.
	if BuyMerchantItem then
		hooksecurefunc("BuyMerchantItem", function(index, quantity)
			local item = GetMerchantItemID and GetMerchantItemID(index)
			local price, stack, extended
			if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
				local info = C_MerchantFrame.GetItemInfo(index)
				if info then price, stack, extended = info.price, info.stackCount, info.hasExtendedCost end
			elseif GetMerchantItemInfo then
				local _
				_, _, price, stack, _, _, _, extended = GetMerchantItemInfo(index)
			end
			if not item or not price or price <= 0 or extended then return end
			stack = math.max(stack or 1, 1)
			local count = quantity or stack
			Spend(item, count, price * count / stack)
		end)
	end
end

-- For /bok test.
function ns.HistoryTest()
	local db, now, open = Data(), time(), 0
	for _, p in ipairs(db.plans) do
		if Open(p, now) then open = open + 1 end
	end
	local ah = C_AuctionHouse
	return string.format("%d crafts, %d purchases, %d open lists; last craft noticed: %s; buy hooks: commodities %s, bid %s, vendor %s",
		#db.crafts, #db.spends, open, ns.lastCraft or "none this session",
		ah and ah.ConfirmCommoditiesPurchase and "yes" or "no", ah and ah.PlaceBid and "yes" or "no", BuyMerchantItem and "yes" or "no")
end

-- Crafts -----------------------------------------------------------------

-- What Bokföring expected of a recipe: worked out at most once a minute,
-- since "Create all" crafts many in a row.
local expected, expectedAt = {}, 0
local function Expected(id, profession)
	if GetTime() - expectedAt > 60 then expected, expectedAt = {}, GetTime() end
	if expected[id] == nil then
		expected[id] = false
		-- All recipes, so the shopping list's recipes stay known.
		for _, row in ipairs(ns.Rows(profession, true)) do expected[row.id] = { cost = row.cost, sells = row.sells } end
	end
	return expected[id] or nil
end

-- How long his crafts take (Zach 9/11), for raw against bought reagents:
-- start to finish, or finish to finish when crafts follow each other as in
-- "Create all", so the gap between them counts. A running average.
local started, finished = {}, {}
local function Timed(id)
	local now, from = GetTime(), started[id]
	if finished[id] and from and from - finished[id] < 3 then from = finished[id] end
	finished[id], started[id] = now, nil
	if not from or now - from > 120 then return end
	local db = ns.db
	db.craftTimes = db.craftTimes or {}
	local old = db.craftTimes[id]
	db.craftTimes[id] = old and old * 0.8 + (now - from) * 0.2 or (now - from)
end

-- A recipe's number is its spell's on the modern client.
local function Crafted(id)
	local r = ns.db.recipes[id]
	if not r or not r.item then return end
	Timed(id)
	local e = Expected(id, r.profession)
	table.insert(Data().crafts, { at = time(), recipe = id, item = r.item, qty = r.qty or 1, cost = e and e.cost, sells = e and e.sells, taxed = true })
	ns.lastCraft = string.format("%s, %s", r.name or ns.ItemName(r.item), date("%H:%M"))
	ns.CleanLists()
	if ns.Refresh then ns.Refresh() end
end

local function Prune()
	local db, since = Data(), time() - KEEP
	for _, key in ipairs({ "plans", "crafts", "spends", "posts" }) do
		local list = db[key]
		for i = #list, 1, -1 do
			if list[i].at < since then table.remove(list, i) end
		end
	end
end

-- Totals -----------------------------------------------------------------

local function Day(at)
	return date("%Y-%m-%d", at)
end

-- Per day of the graph and per item (the table). Each day carries running
-- totals at its end, over all the kept history (Zach 9/11): spent on
-- reagents, the income Bokföring predicted for the crafts made (the price
-- less the cut and tax when crafted), income from sales, and the unsold
-- stock at today's auction house price less the cut and tax.
local function Totals()
	local db = Data()
	local days, byDay = {}, {}
	for k = DAYS - 1, 0, -1 do
		local at = time() - k * 86400
		local t = date("*t", at)
		t.hour, t.min, t.sec = 23, 59, 59
		local d = { key = Day(at), at = at, ends = time(t), income = 0, spent = 0, predictedDay = 0 }
		table.insert(days, d)
		byDay[d.key] = d
	end
	local items, firstCraft, sales = {}, {}, {}
	local function Item(name)
		items[name] = items[name] or { name = name, crafted = 0, posted = 0, returned = 0, sold = 0, spent = 0, income = 0, expected = 0, expectedN = 0 }
		return items[name]
	end
	for _, c in ipairs(db.crafts) do
		local name = ns.ItemName(c.item)
		local it = Item(name)
		it.item = c.item
		it.crafted = it.crafted + c.qty
		if c.sells then it.expected, it.expectedN = it.expected + c.sells, it.expectedN + c.qty end
		if not firstCraft[name] or c.at < firstCraft[name] then firstCraft[name] = c.at end
		local d = byDay[Day(c.at)]
		if d and c.sells then d.predictedDay = d.predictedDay + c.sells end
	end
	for _, s in ipairs(db.spends) do
		-- Materials for a work order make nothing of his own.
		local it = Item(s.made and ns.ItemName(s.made) or "Arbetsordrar")
		it.item = it.item or s.made
		it.spent = it.spent + s.money
		local d = byDay[Day(s.at)]
		if d then d.spent = d.spent + s.money end
	end
	-- A flip's item counts from its buy on, as a craft does (Zach 10/11).
	for _, p in ipairs(db.plans) do
		if p.flip and p.item then
			local name = ns.ItemName(p.item)
			if not firstCraft[name] or p.at < firstCraft[name] then firstCraft[name] = p.at end
		end
	end
	-- Sales count only for items crafted before them (Zach 9/11).
	local since = time() - KEEP
	for name, saleList in pairs(db.sales or {}) do
		for _, sale in ipairs(saleList) do
			if firstCraft[name] and firstCraft[name] <= sale.at and sale.at >= since then
				local it = Item(name)
				it.sold = it.sold + (sale.count or 1)
				it.income = it.income + sale.money
				table.insert(sales, { name = name, at = sale.at, count = sale.count or 1, money = sale.money })
				local d = byDay[Day(sale.at)]
				if d then d.income = d.income + sale.money end
			end
		end
	end
	-- Posted and back again, of what he crafted, after the first craft.
	for _, p in ipairs(db.posts) do
		local name = ns.ItemName(p.item)
		if firstCraft[name] and firstCraft[name] <= p.at and p.at >= since then
			local it = Item(name)
			it.posted = it.posted + p.qty
		end
	end
	for name, list in pairs(db.returns or {}) do
		for _, r in ipairs(list) do
			if firstCraft[name] and firstCraft[name] <= r.at and r.at >= since then
				local it = Item(name)
				it.returned = it.returned + (r.count or 1)
			end
		end
	end
	for _, it in pairs(items) do
		if it.expectedN > 0 then it.expectedEach = it.expected / it.expectedN end
		it.onAH = math.max(0, it.posted - it.sold - it.returned)
	end
	for _, d in ipairs(days) do
		local made, sold = {}, {}
		d.spentSum, d.incomeSum, d.predicted, d.stock, d.stockN = 0, 0, 0, 0, 0
		for _, c in ipairs(db.crafts) do
			if c.at <= d.ends then
				d.predicted = d.predicted + (c.sells or 0)
				local name = ns.ItemName(c.item)
				made[name] = (made[name] or 0) + c.qty
			end
		end
		for _, s in ipairs(db.spends) do
			if s.at <= d.ends then d.spentSum = d.spentSum + s.money end
		end
		for _, sale in ipairs(sales) do
			if sale.at <= d.ends then
				sold[sale.name] = (sold[sale.name] or 0) + sale.count
				d.incomeSum = d.incomeSum + sale.money
			end
		end
		for name, n in pairs(made) do
			local left = math.max(0, n - (sold[name] or 0))
			d.stockN = d.stockN + left
			local price = ns.AH(items[name].item)
			d.stock = d.stock + left * (price and ns.Keep(price) or items[name].expectedEach or 0)
		end
	end
	-- Net (Zach 11/11: a red Net looked like bleeding money while it was
	-- stock not sold yet): income less what the sold ones cost; without
	-- crafts (work orders) all that was spent. Stock: what he holds in bags,
	-- bank and on the auction house, at today's price after cut and tax.
	local list = {}
	for _, it in pairs(items) do
		local costEach = it.crafted > 0 and it.spent / it.crafted
		it.net = it.income - (costEach and costEach * math.min(it.sold, it.crafted) or it.spent)
		if it.sold > 0 then it.realEach = it.income / it.sold end
		if it.item then
			it.held = ns.Have(it.item) + it.onAH
			local price = ns.AH(it.item)
			it.stock = it.held * (price and ns.Keep(price) or it.expectedEach or 0)
		end
		table.insert(list, it)
	end
	table.sort(list, function(a, b)
		if a.net ~= b.net then return a.net > b.net end
		return a.name < b.name
	end)
	return days, list
end

-- The guild's days (Zach 9/11): the sum of every member's day totals,
-- never one member's own. Members' totals are to reach the leader by hidden
-- whisper and only the sum goes out; until that is built, a day without a
-- guild sum counts his own numbers. Running totals from the graph's first
-- day.
local function GuildDays(own)
	local sums = ns.db.guildDays or {}
	local out, spent, predicted, income = {}, 0, 0, 0
	for _, d in ipairs(own) do
		local g = sums[d.key] or { spent = d.spent, predicted = d.predictedDay, income = d.income }
		spent, predicted, income = spent + (g.spent or 0), predicted + (g.predicted or 0), income + (g.income or 0)
		table.insert(out, { key = d.key, at = d.at, spent = g.spent or 0, income = g.income or 0, members = g.members,
			spentSum = spent, predicted = predicted, incomeSum = income })
	end
	return out
end

-- The view ----------------------------------------------------------------

local scope = "me"

local view, bars, rows, list, offset = nil, {}, {}, {}, 0

local function Text(parent, font, x, width, justify)
	local t = parent:CreateFontString(nil, "OVERLAY", font)
	t:SetPoint("LEFT", x, 0)
	t:SetWidth(width)
	t:SetJustifyH(justify or "RIGHT")
	t:SetWordWrap(false)
	return t
end

local function Tex(parent, layer, r, g, b, a)
	local t = parent:CreateTexture(nil, layer)
	t:SetColorTexture(r, g, b, a or 1)
	return t
end

local function Build(frame)
	view = CreateFrame("Frame", nil, frame)
	view:SetPoint("TOPLEFT", 20, -88)
	view:SetPoint("BOTTOMRIGHT", -20, 32)

	-- The graph (Zach 9/11): x the days, y gold, running totals as lines:
	-- red what was spent on reagents, blue the income Bokföring predicted
	-- for what was crafted, yellow the actual income.
	local graph = CreateFrame("Frame", nil, view)
	graph:SetPoint("TOPLEFT", GRAPH_X, -6)
	graph:SetSize(GRAPH_W, GRAPH_H)
	view.graph = graph
	local yAxis = Tex(graph, "ARTWORK", 0.6, 0.6, 0.6, 0.8)
	yAxis:SetWidth(1)
	yAxis:SetPoint("TOPLEFT")
	yAxis:SetPoint("BOTTOMLEFT")
	view.zero = Tex(graph, "ARTWORK", 0.6, 0.6, 0.6, 0.8)
	view.zero:SetHeight(1)
	view.top = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	view.bottom = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	view.mid = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	view.mid:SetText("0")
	view.top:SetPoint("TOPRIGHT", graph, "TOPLEFT", -4, 0)
	view.bottom:SetPoint("BOTTOMRIGHT", graph, "BOTTOMLEFT", -4, 0)
	local legend = graph:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	legend:SetPoint("TOPLEFT", 8, -2)
	legend:SetText("|cffff4040Spent on reagents|r   |cff4080ffPredicted income|r   |cffffd100Income from sales|r")
	-- Gold at hand (Zach 11/11): income and stock against what was spent.
	view.potential = graph:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	view.potential:SetPoint("TOPRIGHT", -8, -2)
	local slot = GRAPH_W / DAYS
	for k = 1, DAYS do
		local b = CreateFrame("Frame", nil, graph)
		b:SetPoint("TOPLEFT", (k - 1) * slot, 0)
		b:SetSize(slot, GRAPH_H)
		b.lines, b.dots = {}, {}
		for n, l in ipairs(LINES) do
			if graph.CreateLine then
				b.lines[n] = graph:CreateLine(nil, "OVERLAY")
				b.lines[n]:SetThickness(2)
				b.lines[n]:SetColorTexture(l[2], l[3], l[4])
			end
			b.dots[n] = Tex(b, "OVERLAY", l[2], l[3], l[4])
			b.dots[n]:SetSize(4, 4)
		end
		if k % 7 == 2 or k == DAYS then
			b.label = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
		end
		b:EnableMouse(true)
		b:SetScript("OnEnter", function(self)
			local d = self.day
			if not d then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(date("%A %d/%m", d.at))
			GameTooltip:AddDoubleLine("This day: income", ns.Money(d.income), 1, 1, 1, 0.25, 1, 0.25)
			GameTooltip:AddDoubleLine("This day: spent", ns.Money(d.spent), 1, 1, 1, 1, 0.3, 0.3)
			GameTooltip:AddLine("So far", 1, 0.82, 0)
			GameTooltip:AddDoubleLine("Spent on reagents", ns.Money(d.spentSum), 1, 1, 1, 0.9, 0.25, 0.25)
			GameTooltip:AddDoubleLine("Predicted income", ns.Money(d.predicted), 1, 1, 1, 0.25, 0.5, 1)
			GameTooltip:AddDoubleLine("Income from sales", ns.Money(d.incomeSum), 1, 1, 1, 1, 0.82, 0)
			if d.stockN then
				GameTooltip:AddDoubleLine(string.format("Unsold stock (%d), at today's price", d.stockN), ns.Money(d.stock), 1, 1, 1, 0.8, 0.8, 0.8)
			end
			if d.members then GameTooltip:AddLine(string.format("From %d members", d.members), 0.6, 0.6, 0.6) end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		bars[k] = b
	end

	-- The table: per item crafted, sold, spent, income, net and the price
	-- expected at the craft against the price it sold for.
	local top = -GRAPH_H - 30
	local header = CreateFrame("Frame", nil, view)
	header:SetSize(690, ROW_H)
	header:SetPoint("TOPLEFT", 0, top)
	view.header = header
	for j, c in ipairs(COLUMNS) do
		Text(header, "GameFontNormalSmall", c[2], c[3], j == 1 and "LEFT" or "RIGHT"):SetText(c[1])
	end
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, view)
		row:SetSize(690, ROW_H)
		row:SetPoint("TOPLEFT", 0, top - i * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.cells = {}
		for j, c in ipairs(COLUMNS) do row.cells[j] = Text(row, "GameFontHighlightSmall", c[2], c[3], j == 1 and "LEFT" or "RIGHT") end
		row:SetScript("OnEnter", function(self)
			local it = self.data
			if not it then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(it.name)
			GameTooltip:AddLine("Spent: gold paid for reagents through Bokföring lists only. Reagents from your bags and buys outside a list are not counted.", 1, 1, 1, true)
			GameTooltip:AddLine("Income: sold mails of this item after you crafted it, without the deposit and less the guild tax.", 1, 1, 1, true)
			GameTooltip:AddLine("Expected each: the auction house price less the cut and guild tax when you crafted; real each: what it sold for after tax.", 1, 1, 1, true)
			GameTooltip:AddLine("Posted: put up on the auction house since you started crafting it, by hand or with Auctionator. On AH: posted, less sold and less what came back expired or cancelled.", 1, 1, 1, true)
			GameTooltip:AddLine("Net: income less what the sold ones cost (spent / crafted for each). Stock: what you hold in bags, bank and on the AH, at today's price after cut and tax.", 1, 1, 1, true)
			if it.held then GameTooltip:AddLine(string.format("You hold %d.", it.held), 0.6, 0.6, 0.6, true) end
			if it.crafted > it.sold then
				GameTooltip:AddLine(string.format("%d crafted not sold yet (or the sold mail not read yet).", it.crafted - it.sold), 0.6, 0.6, 0.6, true)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = row
	end
	-- Me or the guild (Zach 9/11), where the view dropdown sits on the
	-- Recipes tab.
	view.scopes = {}
	for k, sc in ipairs({ { "me", "Me" }, { "guild", "Guild" } }) do
		local b = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
		b:SetSize(70, 22)
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", 70 + (k - 1) * 74, -34)
		b:SetText(sc[2])
		b:SetScript("OnClick", function()
			scope, offset = sc[1], 0
			ns.RefreshHistory(frame)
		end)
		b.scope = sc[1]
		view.scopes[k] = b
	end
	view:EnableMouseWheel(true)
	view:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta * 3, #list - ROWS))
		ns.RefreshHistory(frame)
	end)
end

-- In the table, copper only under a gold (Zach 11/11: "25g 24s 74c" ran
-- into the next column).
local function Money(value, red)
	if not value then return "|cff808080-|r" end
	if value == 0 then return "|cff8080800|r" end
	local text = ns.Money(value)
	if math.abs(value) >= 10000 then text = text:gsub(" %d+c$", "") end
	return (red and "|cffff4040" or "") .. text .. (red and "|r" or "")
end

function ns.ShowHistory(frame, show)
	if not view then
		if not show then return end
		Build(frame)
	end
	view:SetShown(show)
end

function ns.RefreshHistory(frame)
	local days
	days, list = Totals()
	if scope == "guild" then days = GuildDays(days) end
	for _, b in ipairs(view.scopes) do
		if b.scope == scope then b:LockHighlight() else b:UnlockHighlight() end
	end
	local high, low, income, spent = 0, 0, 0, 0
	for _, d in ipairs(days) do
		high = math.max(high, d.spentSum, d.predicted, d.incomeSum)
		income, spent = income + d.income, spent + d.spent
	end
	-- Room above the highest point for the legend.
	local range = (high - low) * 1.15
	local scale = range > 0 and GRAPH_H / range or 0
	local zero = -low * scale
	local function Y(v) return zero + v * scale end
	view.mid:ClearAllPoints()
	view.mid:SetPoint("RIGHT", view.graph, "BOTTOMLEFT", -4, zero)
	view.zero:ClearAllPoints()
	view.zero:SetPoint("BOTTOMLEFT", view.graph, "BOTTOMLEFT", 0, zero)
	view.zero:SetPoint("BOTTOMRIGHT", view.graph, "BOTTOMRIGHT", 0, zero)
	view.top:ClearAllPoints()
	view.top:SetPoint("RIGHT", view.graph, "BOTTOMLEFT", -4, Y(high))
	view.top:SetText(high > 0 and ns.Money(high) or "")
	view.bottom:SetText(low < 0 and ns.Money(low) or "")
	local slot = GRAPH_W / DAYS
	for k, b in ipairs(bars) do
		local d, nextDay = days[k], days[k + 1]
		b.day = d
		for n, l in ipairs(LINES) do
			b.dots[n]:ClearAllPoints()
			b.dots[n]:SetPoint("CENTER", b, "BOTTOM", 0, Y(d[l[1]]))
			local line = b.lines[n]
			if line then
				line:SetShown(nextDay ~= nil)
				if nextDay then
					line:SetStartPoint("BOTTOMLEFT", view.graph, (k - 0.5) * slot, Y(d[l[1]]))
					line:SetEndPoint("BOTTOMLEFT", view.graph, (k + 0.5) * slot, Y(nextDay[l[1]]))
				end
			end
		end
		if b.label then b.label:SetText(date("%d/%m", d.at)) end
	end
	if scope == "guild" then
		view.potential:SetText("")
		view.header:Hide()
		for _, row in ipairs(rows) do row:Hide() end
		local members = 0
		for _, d in ipairs(days) do members = math.max(members, d.members or 0) end
		frame.status:SetText(members > 0 and string.format("%d members", members) or "only you so far")
		frame.note:SetText(string.format("Guild, last %d days: income %s, spent %s. The sum of every member's day totals; nobody's own numbers are shown.",
			DAYS, ns.Money(income), ns.Money(spent)))
		return
	end
	view.header:Show()

	offset = math.max(0, math.min(offset, #list - ROWS))
	for i, row in ipairs(rows) do
		local it = list[i + offset]
		row.data = it
		if it then
			row.cells[1]:SetText(it.name)
			row.cells[2]:SetText(it.crafted)
			row.cells[3]:SetText(it.posted)
			row.cells[4]:SetText(it.sold)
			row.cells[5]:SetText(it.onAH)
			row.cells[6]:SetText(Money(it.spent))
			row.cells[7]:SetText(Money(it.income))
			row.cells[8]:SetText(Money(it.net, it.net < 0))
			row.cells[9]:SetText(Money(it.stock))
			row.cells[10]:SetText(Money(it.expectedEach))
			-- Red when it sold for over 5% less than promised (Zach 11/11: 1% under is noise).
			row.cells[11]:SetText(Money(it.realEach, it.realEach and it.expectedEach and it.realEach < it.expectedEach * 0.95))
			row:Show()
		else
			row:Hide()
		end
	end
	local stock, held = 0, 0
	for _, it in ipairs(list) do stock, held = stock + (it.stock or 0), held + (it.held or 0) end
	local potential = income + stock - spent
	view.potential:SetText(#list > 0 and string.format("Potential: %s%s|r", potential < 0 and "|cffff4040-" or "|cff40ff40+", ns.Money(math.abs(potential))) or "")
	frame.status:SetText(string.format("%d items", #list))
	frame.note:SetText(#list == 0 and "Nothing yet: craft one of your recipes, or buy reagents through a Bokföring list (right-click a recipe)."
		or string.format("Last %d days: income %s, spent %s. In stock: %d, worth about %s at today's price. Potential: income + stock - spent. Spent: buys through Bokföring lists only.",
			DAYS, ns.Money(income), ns.Money(spent), held, ns.Money(stock)))
end

-- The item tooltip (Zach 11/11: at the auction house, what a sale makes
-- now against what it cost to craft). Cost: the newest crafts that cover
-- what he holds, so the stock in his bags; at least the latest craft.
-- Break-even: the price where the cut and the guild tax leave the cost.
local function CostEach(item)
	local crafts = Data().crafts
	local held = math.max(1, ns.Have(item))
	local n, cost = 0, 0
	for i = #crafts, 1, -1 do
		local c = crafts[i]
		if c.item == item and c.cost and n < held then
			local take = math.min(c.qty or 1, held - n)
			n, cost = n + take, cost + c.cost / (c.qty or 1) * take
		end
	end
	if n > 0 then return cost / n end
end

local function AddTooltip(tooltip, item)
	if not item or not ns.db or (ns.Allowed and not ns.Allowed()) then return end
	local cost = CostEach(item)
	if not cost then return end
	local tax = ns.TaxRate()
	local cuts = tax > 0 and string.format("5%% AH, %g%% guild tax", tax * 100) or "5% AH"
	tooltip:AddLine("Bokföring")
	tooltip:AddDoubleLine("Cost each", ns.Money(cost), 1, 1, 1, 1, 1, 1)
	local price = ns.AH(item)
	if price then
		local keep = ns.Keep(price)
		local profit = keep - cost
		tooltip:AddDoubleLine(string.format("AH now %s, you keep (%s)", ns.Money(price), cuts), ns.Money(keep), 1, 1, 1, 1, 1, 1)
		tooltip:AddDoubleLine("Profit each", (profit < 0 and "-" or "+") .. ns.Money(math.abs(profit)), 1, 1, 1,
			profit < 0 and 1 or 0.25, profit < 0 and 0.25 or 1, 0.25)
	end
	tooltip:AddDoubleLine("Break-even price", ns.Money(math.ceil(cost / ns.Keep(1))), 1, 1, 1, 1, 0.82, 0)
	tooltip:Show()
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		if tooltip == GameTooltip or tooltip == ItemRefTooltip then AddTooltip(tooltip, data and data.id) end
	end)
else
	for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
		tip:HookScript("OnTooltipSetItem", function(self)
			local _, link = self:GetItem()
			AddTooltip(self, link and tonumber(link:match("item:(%d+)")))
		end)
	end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_MONEY", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "COMMODITY_PURCHASE_FAILED" }) do
	pcall(events.RegisterEvent, events, event)
end
-- Once (0.6.4, Zach 11/11): crafts and sales saved before the guild tax
-- was counted get it taken off, so History does not mix the two. The
-- deposits in old sales cannot be told apart and stay. Waits until the
-- guild is known; outside the guild there is nothing to take off. Entries
-- from 0.6.4 on are marked taxed and never touched.
local function TaxOldHistory()
	local db = Data()
	if db.taxedHistory then return end
	local rate = ns.TaxRate()
	if rate <= 0 then return end
	for _, c in ipairs(db.crafts) do
		if c.sells and not c.taxed then c.sells, c.taxed = c.sells * (1 - rate), true end
	end
	for _, saleList in pairs(db.sales or {}) do
		for _, s in ipairs(saleList) do
			if not s.taxed then s.money, s.taxed = s.money * (1 - rate), true end
		end
	end
	db.taxedHistory = true
end

events:SetScript("OnEvent", function(_, event, unit, _, spell)
	if not ns.db then return end
	if event == "PLAYER_LOGIN" then
		Prune()
		Hooks()
		-- After Auctionator has loaded its lists.
		C_Timer.After(10, ns.CleanLists)
		C_Timer.After(10, TaxOldHistory)
	elseif event == "PLAYER_MONEY" then
		MoneyChanged()
	elseif event == "COMMODITY_PURCHASE_FAILED" then
		pending = nil
	elseif unit ~= "player" then
		return
	elseif event == "UNIT_SPELLCAST_START" then
		if ns.db.recipes[spell] then started[spell] = GetTime() end
	else
		Crafted(spell)
	end
end)

-- What Bokföring expected one of an item to bring, after the cut and tax, at its
-- latest craft; for the sale notice in chat (Zach 9/11).
function ns.ExpectedEach(name)
	local crafts = Data().crafts
	for i = #crafts, 1, -1 do
		local c = crafts[i]
		if c.sells and ns.ItemName(c.item) == name then return c.sells / c.qty end
	end
end

-- A clean start (Zach 10/11: the history from before the sold-mail fix was
-- wrong). Crafts, lists, buys, posts and sales go; the mails already seen
-- stay seen, so they are not counted again; the Market tab keeps following
-- what was crafted.
StaticPopupDialogs.BOKFORING_RESET = {
	text = "Erase Bokföring's history (crafts, lists, buys, posted auctions and sales) and start again?\n\nMarket prices and recipes stay.",
	button1 = YES,
	button2 = NO,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function()
		local db = Data()
		db.tracked = db.tracked or {}
		for _, c in ipairs(db.crafts) do
			if c.item then db.tracked[c.item] = true end
		end
		db.crafts, db.plans, db.spends, db.posts, db.sales, db.returns = {}, {}, {}, {}, {}, {}
		ns.Print("history erased; it starts again from now.")
		if ns.Refresh then ns.Refresh() end
	end,
}
function ns.ResetHistory()
	StaticPopup_Show("BOKFORING_RESET")
end

-- How many of an item are on the auction house now, from what was posted
-- less what sold or came back (Today: do not craft what still waits there).
function ns.OnAH(item)
	local db, name, n = Data(), ns.ItemName(item), 0
	for _, p in ipairs(db.posts) do
		if p.item == item then n = n + p.qty end
	end
	for _, s in ipairs(db.sales and db.sales[name] or {}) do n = n - (s.count or 1) end
	for _, r in ipairs(db.returns and db.returns[name] or {}) do n = n - (r.count or 1) end
	return math.max(0, n)
end
