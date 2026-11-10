-- Bokföring's Making now (Zach 9/11): his own work order. Each shopping
-- list he made is shown until he has crafted it all or marks it done:
-- every reagent the crafts still need against what his bags hold, and what
-- the list had him buy, bought so far, with vendor goods (Weak Flux,
-- Wooden Stock) among them, since Auctionator's list leaves those out.

local _, ns = ...

local SHOW_DAYS = 7
local ROWS, ROW_H = 18, 18
-- Name, x, width.
local COLUMNS = { { "Item", 0, 260 }, { "Needed", 260, 80 }, { "In bags", 340, 80 }, { "Missing", 420, 80 }, { "Where", 500, 100 } }

local view, rows, offset = nil, {}, 0

local function Count(item)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(item, false) or 0 end
	return GetItemCount and GetItemCount(item, false) or 0
end

-- Crafts of the list's recipe since the list was made.
local function Crafted(p)
	local n = 0
	for _, c in ipairs(ns.db.crafts or {}) do
		if c.recipe == p.recipe and c.at >= p.at then n = n + 1 end
	end
	return n
end

-- The recipe's reagents: kept with the list since 0.3, else looked up.
local function Reagents(p)
	if p.reagents and #p.reagents > 0 then return p.reagents end
	local r = ns.db.recipes[p.recipe] or (ns.db.catalog and ns.db.catalog[p.recipe])
	return r and r.reagents or {}
end

local function Where(item)
	return ns.IsVendorGood(item) and "vendor" or "auction house"
end

-- The lines to show: per list a title, the reagents for the crafts left,
-- and what the list buys.
local function Lines()
	local lines, now = {}, time()
	for _, p in ipairs(ns.db.plans or {}) do
		local made = Crafted(p)
		-- A work order's materials (Zach 9/11): someone else crafts, so it
		-- stays until all is bought or he marks it done.
		local bought = true
		for item, n in pairs(p.need or {}) do
			if (p.bought[item] or 0) < n then bought = false end
		end
		local open = p.order and not bought or (not p.order and made < p.crafts)
		if not p.done and not p.flip and now - p.at < SHOW_DAYS * 86400 and open then
			table.insert(lines, { plan = p, made = made })
			local left = p.order and p.crafts or p.crafts - made
			table.insert(lines, { label = p.order and string.format("To send to %s", p.order) or string.format("For the %d crafts left", left) })
			for _, r in ipairs(Reagents(p)) do
				-- Rounded: an order's raw materials are kept per craft as fractions.
				local need, have = math.floor(r[2] * left + 0.5), Count(r[1])
				table.insert(lines, { item = r[1], need = need, have = have, missing = math.max(0, need - have) })
			end
			local buy = {}
			for item, n in pairs(p.need or {}) do table.insert(buy, { item = item, n = n, got = p.bought[item] or 0 }) end
			if #buy > 0 then
				table.sort(buy, function(a, b) return ns.ItemName(a.item) < ns.ItemName(b.item) end)
				table.insert(lines, { label = "On the shopping list" })
				for _, b in ipairs(buy) do
					table.insert(lines, { item = b.item, need = b.n, bought = b.got, missing = math.max(0, b.n - b.got), where = Where(b.item) })
				end
			end
		end
	end
	return lines
end

-- For the THÖNDERSTÖRM panel's Arbetsorder tab, "Till dig själv" (Zach
-- 9/11): each list still on the go as name, crafts, made, and the number of
-- reagents still missing.
function ns.WorkSummary()
	local out, current = {}, nil
	for _, line in ipairs(Lines()) do
		if line.plan then
			current = { name = string.format("%s x%d%s", line.plan.recipeName or ns.ItemName(line.plan.item), line.plan.crafts,
				line.plan.order and (" till " .. line.plan.order) or ""),
				made = line.made, crafts = line.plan.crafts, missing = 0 }
			table.insert(out, current)
		elseif current and line.item and not line.bought and line.missing > 0 then
			current.missing = current.missing + 1
		end
	end
	return out
end

local function Text(parent, font, x, width, justify)
	local t = parent:CreateFontString(nil, "OVERLAY", font)
	t:SetPoint("LEFT", x, 0)
	t:SetWidth(width)
	t:SetJustifyH(justify or "RIGHT")
	t:SetWordWrap(false)
	return t
end

local function Build(frame)
	view = CreateFrame("Frame", nil, frame)
	view:SetPoint("TOPLEFT", 20, -88)
	view:SetPoint("BOTTOMRIGHT", -20, 32)
	local header = CreateFrame("Frame", nil, view)
	header:SetSize(690, ROW_H)
	header:SetPoint("TOPLEFT")
	for j, c in ipairs(COLUMNS) do
		Text(header, "GameFontNormalSmall", c[2], c[3], j == 1 and "LEFT" or "RIGHT"):SetText(c[1])
	end
	view.empty = view:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	view.empty:SetPoint("TOPLEFT", 0, -30)
	view.empty:SetText("Nothing on the go. Right-click a recipe on the Recipes tab and choose Buy for N crafts.")
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, view)
		row:SetSize(690, ROW_H)
		row:SetPoint("TOPLEFT", 0, -i * ROW_H)
		row.cells = {}
		for j, c in ipairs(COLUMNS) do row.cells[j] = Text(row, "GameFontHighlightSmall", c[2], c[3], j == 1 and "LEFT" or "RIGHT") end
		row.list = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.list:SetSize(110, 18)
		row.list:SetPoint("RIGHT", -84, 0)
		row.list:SetText("Shopping list")
		row.done = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.done:SetSize(76, 18)
		row.done:SetPoint("RIGHT", -4, 0)
		row.done:SetText("Done")
		rows[i] = row
	end
	view:EnableMouseWheel(true)
	view:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, offset - delta * 3)
		ns.RefreshWork(frame)
	end)
end

function ns.ShowWork(frame, show)
	if not view then
		if not show then return end
		Build(frame)
	end
	view:SetShown(show)
end

function ns.RefreshWork(frame)
	local lines = Lines()
	offset = math.max(0, math.min(offset, #lines - ROWS))
	view.empty:SetShown(#lines == 0)
	for i, row in ipairs(rows) do
		local line = lines[i + offset]
		for _, cell in ipairs(row.cells) do cell:SetText("") end
		row.list:Hide()
		row.done:Hide()
		if not line then
			row:Hide()
		else
			if line.plan then
				local p = line.plan
				row.cells[1]:SetText(p.order and string.format("|cffffd100Arbetsorder: %s x%d|r  to %s, %s", p.recipeName or "?", p.crafts, p.order, date("%d/%m %H:%M", p.at))
					or string.format("|cffffd100%s x%d%s|r  made %d, %s", p.recipeName or ns.ItemName(p.item), p.crafts,
					p.raw and " (raw)" or "", line.made, date("%d/%m %H:%M", p.at)))
				row.list:SetShown(not p.order)
				-- The Auctionator list again, with what is left to buy.
				row.list:SetScript("OnClick", function()
					if not ns.Recipe(p.recipe) then ns.Rows(nil, true) end
					ns.Shop(p.recipe, p.crafts, p.raw)
				end)
				row.done:SetScript("OnClick", function()
					p.done = true
					ns.RefreshWork(frame)
				end)
				row.done:Show()
			elseif line.label then
				row.cells[1]:SetText("  |cffa0a0a0" .. line.label .. "|r")
			else
				row.cells[1]:SetText("    " .. ns.ItemName(line.item))
				row.cells[2]:SetText(line.bought and string.format("%d/%d bought", line.bought, line.need) or line.need)
				if not line.bought then row.cells[3]:SetText(line.have) end
				row.cells[4]:SetText(line.missing > 0 and ("|cffff4040" .. line.missing .. "|r") or "|cff40ff40-|r")
				row.cells[5]:SetText(line.where or "")
			end
			row:Show()
		end
	end
	frame.status:SetText("")
	frame.note:SetText("Missing: what the crafts still need beyond your bags, or what the list still has to buy. Vendor goods are not in Auctionator's list; buy them at a vendor.")
end

-- Bags change as he buys and crafts; keep the page current.
local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function()
	if view and view:IsShown() and ns.Refresh then ns.Refresh() end
end)
