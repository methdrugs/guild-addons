-- Bokföring's Today (Zach 10/11): what to do now to earn gold, at most five
-- actions, best first, within a budget, so there is as little as possible
-- to think about. Replaces the "Me dumb, me craft now" box. From what the
-- scans and his history already hold:
-- - Craft and sell: his recipes with a profit that actually sell, as many
--   as half a day's sales (the market has other sellers), less what he
--   has in bags and bank or still up on the auction house; or post what he
--   already has.
-- - Flip: buy an item that sells 3 or more a day while it is 20% or more
--   under its usual price, to sell again at the usual price; only with 7
--   days of prices behind it.
-- - When to post: the item's best hour of the day, if 10% or more above
--   its usual price, from the hour profile (Market.lua).
-- Bokföring only shows; buying stays one click per purchase in Auctionator.

local _, ns = ...

local MAX_ACTIONS = 5
local SHARE = 0.5 -- of a day's sales he can expect to sell
local MAX_CRAFTS = 20
local FLIP_SOLD, FLIP_UNDER, FLIP_DAYS = 3, 0.2, 7
local HOUR_ABOVE = 0.10
local BUDGET_SHARE = 0.25

-- The budget for today: set with /bok budget, else a quarter of the gold
-- he had when the day began (Zach 10/11: a quarter of the gold now shrank
-- with every buy, on top of the buy itself); less what Bokföring lists
-- have spent today.
function ns.Budget()
	local today, spent = date("%Y%m%d"), 0
	for _, s in ipairs(ns.db.spends or {}) do
		if date("%Y%m%d", s.at) == today then spent = spent + s.money end
	end
	-- First look today: the gold now plus what the lists already spent
	-- today (Zach 10/11: noted after a buy, the base was too low).
	local start = ns.db.dayGold
	if not start or start.day ~= today or start.v ~= 2 then
		start = { day = today, gold = GetMoney() + spent, v = 2 }
		ns.db.dayGold = start
	end
	local total = ns.db.budget or math.floor(start.gold * BUDGET_SHARE)
	-- More for today with the button (Zach 10/11).
	local extra = ns.db.budgetExtra
	if extra and extra.day == today then total = total + extra.amount end
	return math.max(0, total - spent), total, spent
end

-- "post around 20:00 (+14%)", or nil when no hour stands out.
local function When(item)
	local p = ns.HourProfile(item)
	if not p or p.high < HOUR_ABOVE then return end
	local now = tonumber(date("%H"))
	if math.abs(now - p.best) <= 1 then return string.format("now is its best hour (+%d%%)", math.floor(p.high * 100 + 0.5)) end
	return string.format("best posted around %02d:00 (+%d%%)", p.best, math.floor(p.high * 100 + 0.5))
end

-- Every action worth doing, unsorted: { kind, gain, cost, text, detail, ... }.
local function Candidates()
	local out, me = {}, ns.MeKey()
	-- Craft and sell, or post what is already made.
	for _, r in ipairs(ns.Rows(nil, false)) do
		if r.recipe.by[me] and r.profit and r.profit > 0 and r.sold and r.sold >= 0.5 and r.cost then
			local item, qty = r.recipe.item, r.recipe.qty or 1
			local want = math.min(MAX_CRAFTS * qty, math.max(1, math.floor(r.sold * SHARE + 0.5)))
			local have, up = ns.Have(item), ns.OnAH(item)
			local each = r.profit / qty
			local when = When(item)
			if have > 0 then
				local n = math.min(have, want)
				table.insert(out, { kind = "post", item = item, n = n, gain = (r.sells / qty) * n, cost = 0,
					text = string.format("Post %d %s from your bags", n, r.recipe.name or ns.ItemName(item)),
					detail = string.format("about %s, %.0f sell a day%s", ns.Money((r.sells / qty) * n), r.sold, when and (", " .. when) or "") })
			end
			local crafts = math.ceil((want - have - up) / qty)
			if crafts > 0 then
				table.insert(out, { kind = "craft", id = r.id, item = item, n = crafts, gain = each * crafts * qty, cost = r.cost * crafts,
					text = string.format("Craft %d %s", crafts, r.recipe.name or ns.ItemName(item)),
					detail = string.format("+%s (%s each), costs %s, %.0f sell a day%s%s", ns.Money(each * crafts * qty), ns.Money(each),
						ns.Money(r.cost * crafts), r.sold, up > 0 and string.format(", %d already on the AH", up) or "", when and (", " .. when) or "") })
			end
		end
	end
	-- Flips: well under the usual price, sells well, a week of prices.
	for item in pairs(ns.db.hours or {}) do
		local level, days = ns.PriceLevel(item)
		local price, age = ns.AH(item)
		local sold = ns.SoldPerDay(item) or 0
		if level and days >= FLIP_DAYS and price and age == 0 and sold >= FLIP_SOLD and price <= level * (1 - FLIP_UNDER) then
			local each = ns.Keep(level) - price
			if each > 0 then
				local n = math.max(1, math.floor(sold * SHARE))
				local when = When(item)
				table.insert(out, { kind = "flip", item = item, n = n, gain = each * n, cost = price * n, price = price,
					text = string.format("Buy %d %s to sell again", n, ns.ItemName(item)),
					detail = string.format("%s now, usually %s: +%s, %.0f sell a day%s", ns.Money(price), ns.Money(level), ns.Money(each * n),
						sold, when and (", " .. when) or "") })
			end
		end
	end
	return out
end

-- The best actions that fit the budget; a cheaper count when one does not.
function ns.Today()
	local budget = ns.Budget()
	local list = Candidates()
	table.sort(list, function(a, b) return a.gain > b.gain end)
	local picked, used = {}, 0
	for _, a in ipairs(list) do
		if #picked >= MAX_ACTIONS then break end
		if a.cost > 0 and used + a.cost > budget then
			-- Fewer, if some fit; else shown greyed, over budget (Zach 10/11).
			local each = a.cost / a.n
			local n = each > 0 and math.floor((budget - used) / each) or 0
			if n >= 1 and a.kind ~= "post" then
				a.gain, a.cost = a.gain * n / a.n, each * n
				a.text = a.text:gsub("^(%a+) %d+", "%1 " .. n)
				a.n = n
				a.cut = true
			else
				a.over = true
			end
		end
		table.insert(picked, a)
		if not a.over then used = used + a.cost end
	end
	return picked, budget, used
end

-- How far the price history has come, for "learning".
local function Learning()
	local most = 0
	for item in pairs(ns.db.hours or {}) do
		local _, days = ns.PriceLevel(item)
		most = math.max(most, days or 0)
	end
	return most
end

-- The view ----------------------------------------------------------------

local view, lines = nil, {}

local function Build(frame)
	view = CreateFrame("Frame", nil, frame)
	view:SetPoint("TOPLEFT", 20, -60)
	view:SetPoint("BOTTOMRIGHT", -20, 32)
	view.budget = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	view.budget:SetPoint("TOPLEFT", 50, 0)
	view.budget:SetJustifyH("LEFT")
	-- Raise today's budget by a quarter of the gold carried now (Zach 10/11).
	view.raise = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
	view.raise:SetSize(130, 20)
	view.raise:SetPoint("TOPRIGHT", -10, 2)
	view.raise:SetText("+25% of my gold")
	view.raise:SetScript("OnClick", function()
		local add = math.floor(GetMoney() * BUDGET_SHARE)
		if add <= 0 then ns.Print("no gold to add.") return end
		local today = date("%Y%m%d")
		local extra = ns.db.budgetExtra
		if not extra or extra.day ~= today then extra = { day = today, amount = 0 } end
		extra.amount = extra.amount + add
		ns.db.budgetExtra = extra
		ns.Print("today's budget raised by " .. ns.Money(add) .. ".")
		if ns.Refresh then ns.Refresh() end
	end)
	view.raise:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:AddLine("Raise today's budget")
		GameTooltip:AddLine("Adds a quarter of the gold you carry now, for today only. Press again for more.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	view.raise:SetScript("OnLeave", function() GameTooltip:Hide() end)
	for i = 1, MAX_ACTIONS do
		local b = CreateFrame("Button", nil, view)
		b:SetSize(660, 50)
		b:SetPoint("TOPLEFT", 0, -26 - (i - 1) * 54)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(36, 36)
		b.icon:SetPoint("LEFT", 4, 0)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		b.text:SetPoint("TOPLEFT", 50, -6)
		b.text:SetJustifyH("LEFT")
		b.detail = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		b.detail:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -4)
		b.detail:SetWidth(600)
		b.detail:SetJustifyH("LEFT")
		b.detail:SetWordWrap(false)
		-- A click turns the action into an Auctionator list.
		b:SetScript("OnClick", function(self)
			local a = self.action
			if not a then return end
			if a.kind == "craft" then
				if not ns.Recipe(a.id) then ns.Rows(nil, true) end
				ns.AskCrafts(a.id, a.n, false)
			elseif a.kind == "flip" then
				-- A list of its own, kept as a plan so the buys count against
				-- the budget and show in History (Zach 10/11).
				local name = "Bokföring: flip " .. ns.ItemName(a.item)
				ns.BuyList(name, { { a.item, a.n } })
				local plan = ns.NewPlan(nil, a.item, a.n, false, { [a.item] = a.n }, name, { name = ns.ItemName(a.item), qty = 1, reagents = {} })
				plan.flip = true
			end
		end)
		b:SetScript("OnEnter", function(self)
			local a = self.action
			if not a then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(a.item)
			GameTooltip:AddLine(" ")
			if a.kind == "craft" then
				GameTooltip:AddLine("Click: the shopping list for these crafts, the number filled in.", 0.25, 1, 0.25, true)
			elseif a.kind == "flip" then
				GameTooltip:AddLine("Click: an Auctionator list to buy them. Sell them again at the usual price.", 0.25, 1, 0.25, true)
			else
				GameTooltip:AddLine("Post them with Auctionator at the auction house.", 0.25, 1, 0.25, true)
			end
			if a.cut then GameTooltip:AddLine("Fewer than it could be, to stay within today's budget.", 1, 0.82, 0, true) end
			if a.over then GameTooltip:AddLine("Over today's budget: /bok budget raises it.", 1, 0.5, 0.25, true) end
			local p = ns.HourProfile(a.item)
			if p then
				GameTooltip:AddLine(string.format("Over the day: dearest around %02d:00 (%+d%%), cheapest around %02d:00 (%+d%%), from %d hours seen.",
					p.best, math.floor(p.high * 100 + 0.5), p.worst, math.floor(p.low * 100 - 0.5), p.known), 0.6, 0.6, 0.6, true)
			end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		lines[i] = b
	end
	view.learning = view:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	view.learning:SetPoint("TOPLEFT", 0, -26 - MAX_ACTIONS * 54 - 6)
	view.learning:SetWidth(660)
	view.learning:SetJustifyH("LEFT")
	view.empty = view:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	view.empty:SetPoint("TOPLEFT", 0, -40)
	view.empty:SetWidth(660)
	view.empty:SetJustifyH("LEFT")
end

function ns.ShowToday(frame, show)
	if not view then
		if not show then return end
		Build(frame)
	end
	view:SetShown(show)
end

local ICONS = { craft = "Interface\\Icons\\Trade_Engineering", post = "Interface\\Icons\\INV_Misc_Coin_02", flip = "Interface\\Icons\\INV_Misc_Bag_10" }

function ns.RefreshToday(frame)
	local actions, _, used = ns.Today()
	local left, total, spent = ns.Budget()
	view.budget:SetText(string.format("Budget today: |cffffd100%s|r of %s left%s   |cff808080/bok budget 50g to change|r",
		ns.Money(left), ns.Money(total), spent > 0 and string.format(" (%s spent)", ns.Money(spent)) or ""))
	for i, b in ipairs(lines) do
		local a = actions[i]
		b.action = a
		if a then
			local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(a.item)) or ICONS[a.kind]
			b.icon:SetTexture(icon)
			b.text:SetText(a.over and ("|cff808080" .. a.text .. "  (over budget)|r") or a.text)
			b.detail:SetText(a.over and ("|cff808080" .. a.detail .. "|r") or a.detail)
			b.icon:SetDesaturated(a.over and true or false)
			b:Show()
		else
			b:Hide()
		end
	end
	local days = Learning()
	view.learning:SetText(days < FLIP_DAYS and string.format("Learning the prices: %d of %d days. Flips and the best hour to post come once a week of scans is in; scan at different times of day.", days, FLIP_DAYS) or "")
	view.empty:SetShown(#actions == 0)
	view.empty:SetText("Nothing worth doing right now: scan the auction house with Auctionator twice a few hours apart, and open your profession windows once.")
	frame.status:SetText(used > 0 and ("uses " .. ns.Money(used)) or "")
	frame.note:SetText("Best first: crafts that sell, what you already have, and items to buy cheap and sell again. Click an action for its shopping list.")
end

-- /bok budget 50g, or /bok budget off for a quarter of your gold.
function ns.SetBudget(text)
	if text == "off" or text == "" then
		ns.db.budget = nil
		ns.Print("budget: a quarter of the gold you carry, each day.")
	else
		local amount = ns.ParseMoney(text)
		if not amount then
			ns.Print("write it like /bok budget 50g, or /bok budget off.")
			return
		end
		ns.db.budget = amount
		ns.Print("budget: " .. ns.Money(amount) .. " a day for Today's suggestions.")
	end
	if ns.Refresh then ns.Refresh() end
end

-- Gold and bags change as he buys and crafts: keep the page current
-- (Zach 10/11: the budget stayed the same after a buy).
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_MONEY", "BAG_UPDATE_DELAYED" }) do pcall(events.RegisterEvent, events, event) end
local soon = false
events:SetScript("OnEvent", function()
	if not view or not view:IsShown() or soon then return end
	soon = true
	-- After History has noted the buy.
	C_Timer.After(1, function()
		soon = false
		if view:IsShown() and ns.Refresh then ns.Refresh() end
	end)
end)
