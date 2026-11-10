-- Bokföring's market history (Zach 9/11): how the price of what he has
-- crafted, and of recipes he watches, moves over time. Every full scan (his
-- Scan AH or Auctionator's) adds the day's lowest price, and how many are
-- listed, of those items; kept for 90 days. The Market tab draws an item's lowest and
-- highest price a day, and per weekday how its price stands against its
-- own average. Shown from the first scan on: the lines fill in and settle
-- as the days go by.

local _, ns = ...

local KEEP_DAYS = 90
local ROWS, ROW_H = 18, 18
local LIST_W = 220
local GRAPH_X, GRAPH_W, GRAPH_H = 300, 390, 130
local WEEK_TOP, WEEK_H = -200, 90
-- The graph (Zach 10/11): one smooth line through every scan's lowest
-- price, like a stock chart, with the area under it filled; between scans
-- the curve is an estimate. Points are kept 30 days, at most one per 10
-- minutes; older days come from the daily record.
local POINT_DAYS = 30
local POINT_GAP = 600
local STEP = 3 -- pixels per drawn piece of the curve
local SAMPLES = math.floor(GRAPH_W / STEP)
local LABELS = 5
-- Monday first, as the calendar here; date("%w") gives 0 for Sunday.
local WEEKDAYS = { { 1, "Mon" }, { 2, "Tue" }, { 3, "Wed" }, { 4, "Thu" }, { 5, "Fri" }, { 6, "Sat" }, { 0, "Sun" } }

local function Day(t) return tonumber(date("%Y%m%d", t)) end

-- Noon of a day key, for its weekday and label.
local function Time(key)
	return time({ year = math.floor(key / 10000), month = math.floor(key / 100) % 100, day = key % 100, hour = 12 })
end

-- The items worth following (Zach 9/11): what he has crafted in the last
-- 90 days, and what he watches (right-click a recipe). Not reagents.
local function Tracked()
	local out = {}
	for _, c in ipairs(ns.db.crafts or {}) do
		if c.item then out[c.item] = true end
	end
	for item in pairs(ns.db.watch or {}) do out[item] = true end
	-- Crafted before a history reset.
	for item in pairs(ns.db.tracked or {}) do out[item] = true end
	return out
end

function ns.Watched(item) return ns.db.watch and ns.db.watch[item] or false end

function ns.Watch(item)
	ns.db.watch = ns.db.watch or {}
	ns.db.watch[item] = not ns.db.watch[item] or nil
	ns.Print(string.format("%s %s on the Market tab.", ns.ItemName(item), ns.db.watch[item] and "is now watched" or "is no longer watched"))
end

-- From Core.lua's Count: counts[item] = { q = quantity listed, lo = lowest
-- price for one, if the scan gave it }.
function ns.RecordMarket(counts)
	local market = ns.db.market
	if not market then return end
	local now = time()
	local today, oldest = Day(now), Day(now - KEEP_DAYS * 86400)
	for item in pairs(Tracked()) do
		local c = counts[item]
		local price = c and c.lo or (c and ns.AH(item))
		local days = market[item] or {}
		local d = days[today]
		if price then
			d = d or { lo = price, hi = price, sum = 0, n = 0 }
			d.lo, d.hi = math.min(d.lo, price), math.max(d.hi, price)
			d.sum, d.n = d.sum + price, d.n + 1
		end
		-- Each scan's point for the graph, at most one per 10 minutes.
		if price then
			ns.db.points = ns.db.points or {}
			local pts = ns.db.points[item] or {}
			local n = #pts
			if n >= 3 and now - pts[n - 2] < POINT_GAP then
				pts[n - 1], pts[n] = math.min(pts[n - 1], price), c and c.q or pts[n]
			else
				table.insert(pts, now)
				table.insert(pts, price)
				table.insert(pts, c and c.q or 0)
			end
			-- Flat triples: time, lowest price, listed.
			local cut = now - POINT_DAYS * 86400
			while #pts >= 3 and pts[1] < cut do
				table.remove(pts, 1)
				table.remove(pts, 1)
				table.remove(pts, 1)
			end
			ns.db.points[item] = pts
		end
		-- None listed is worth knowing too: no competition that day.
		if d or not c then
			d = d or {}
			d.q = c and c.q or 0
			days[today] = d
		end
		for key in pairs(days) do
			if key < oldest then days[key] = nil end
		end
		if next(days) then market[item] = days end
	end
end

-- Hours of the day (Zach 10/11, for Today: "sell later around 20:00").
-- Every item that sells at least once a day, or that he follows, keeps
-- its price at each hour as a share of its own running level, so days
-- with a higher or lower price overall do not blur the pattern. Running
-- averages, so the size stays fixed: about 30 numbers an item, and items
-- not seen for 30 days drop off (about 0.2 MB for a thousand items).
local HOUR_WEIGHT, LEVEL_WEIGHT = 0.3, 0.1
local HOUR_DAYS = 30

function ns.RecordHours(counts)
	ns.db.hours = ns.db.hours or {}
	local hours, tracked = ns.db.hours, Tracked()
	local now = time()
	local hour, today = tonumber(date("%H", now)) + 1, Day(now)
	for item, c in pairs(counts) do
		local h = hours[item]
		if c.lo and (h or tracked[item] or (ns.SoldPerDay(item) or 0) >= 1) then
			h = h or { level = c.lo, n = 0, h = {} }
			-- A scan more than three times off the level is an odd listing.
			if c.lo < h.level * 3 and c.lo > h.level / 3 then
				local share = c.lo / h.level
				local old = h.h[hour]
				h.h[hour] = math.floor(((old and old + HOUR_WEIGHT * (share - old)) or share) * 1000 + 0.5) / 1000
				h.level = math.floor(h.level + LEVEL_WEIGHT * (c.lo - h.level) + 0.5)
				h.n = h.n + 1
			end
			h.d = today
			h.f = h.f or today
			hours[item] = h
		end
	end
	local oldest = Day(now - HOUR_DAYS * 86400)
	for item, h in pairs(hours) do
		if h.d < oldest then hours[item] = nil end
	end
end

-- An item's best and cheapest hour (1-24 as 0-23 o'clock) and how much
-- above and below its level, once at least 8 hours are known; nil before.
function ns.HourProfile(item)
	local h = ns.db.hours and ns.db.hours[item]
	if not h then return end
	local known, best, worst = 0, nil, nil
	for k = 1, 24 do
		local v = h.h[k]
		if v then
			known = known + 1
			if not best or v > h.h[best] then best = k end
			if not worst or v < h.h[worst] then worst = k end
		end
	end
	if known < 8 then return nil, known end
	return { best = best - 1, worst = worst - 1, high = h.h[best] - 1, low = h.h[worst] - 1, known = known, level = h.level }
end

-- An item's running price level and how many days it has been followed.
function ns.PriceLevel(item)
	local h = ns.db.hours and ns.db.hours[item]
	if not h then return end
	local first = h.f and time({ year = math.floor(h.f / 10000), month = math.floor(h.f / 100) % 100, day = h.f % 100, hour = 12 })
	return h.level, first and math.floor((time() - first) / 86400) + 1 or 1, h.n
end

-- Each hour's share of the level (1-24), for the Today tooltip.
function ns.HourShares(item)
	local h = ns.db.hours and ns.db.hours[item]
	return h and h.h
end

-- An item's days, oldest first: { key, lo, hi, avg, q }.
local function Days(item)
	local out = {}
	for key, d in pairs(ns.db.market and ns.db.market[item] or {}) do
		table.insert(out, { key = key, lo = d.lo, hi = d.hi, avg = d.n and d.n > 0 and d.sum / d.n or nil, q = d.q })
	end
	table.sort(out, function(a, b) return a.key < b.key end)
	return out
end

-- How the price moves: the latest day's average against the days before it
-- (up to two weeks), as a fraction; nil until two days are known.
function ns.Trend(item)
	local days = Days(item)
	local last = days[#days]
	if not last or not last.avg then return end
	local sum, n = 0, 0
	for k = #days - 1, math.max(1, #days - 14), -1 do
		if days[k].avg then sum, n = sum + days[k].avg, n + 1 end
	end
	if n == 0 or sum == 0 then return end
	return last.avg / (sum / n) - 1
end

-- Per weekday, the average price against the item's own average, as a
-- fraction, and how many days that rests on.
local function Weekdays(days)
	local all, n, by = 0, 0, {}
	for _, d in ipairs(days) do
		if d.avg then
			local w = tonumber(date("%w", Time(d.key)))
			by[w] = by[w] or { sum = 0, n = 0 }
			by[w].sum, by[w].n = by[w].sum + d.avg, by[w].n + 1
			all, n = all + d.avg, n + 1
		end
	end
	local mean = n > 0 and all / n or nil
	local out = {}
	for w, b in pairs(by) do out[w] = { diff = mean and mean > 0 and (b.sum / b.n) / mean - 1, n = b.n } end
	return out
end

-- The points to draw, oldest first: { t, price, q, day }. Scans where
-- kept; a day before the first scan point, from the daily record at noon.
local function Points(item)
	local out = {}
	local pts = ns.db.points and ns.db.points[item] or {}
	for k = 1, #pts - 2, 3 do table.insert(out, { t = pts[k], price = pts[k + 1], q = pts[k + 2] }) end
	local first = out[1] and out[1].t or math.huge
	local cut = time() - POINT_DAYS * 86400
	for _, d in ipairs(Days(item)) do
		-- Noon, or now for today before noon (Zach 10/11: the graph was empty).
		local t = math.min(Time(d.key), time())
		if t < first - 43200 and t >= cut and d.lo then table.insert(out, { t = t, price = d.avg or d.lo, q = d.q, day = true }) end
	end
	table.sort(out, function(a, b) return a.t < b.t end)
	return out
end

-- Tangents for a curve through the points that never overshoots them
-- (Fritsch-Carlson): peaks stay peaks, no made-up dips.
local function Tangents(p)
	local n, d, m = #p, {}, {}
	for k = 1, n - 1 do d[k] = (p[k + 1].price - p[k].price) / math.max(p[k + 1].t - p[k].t, 1) end
	m[1], m[n] = d[1], d[n - 1]
	for k = 2, n - 1 do m[k] = (d[k - 1] * d[k] <= 0) and 0 or (d[k - 1] + d[k]) / 2 end
	for k = 1, n - 1 do
		if d[k] == 0 then
			m[k], m[k + 1] = 0, 0
		else
			local a, b = m[k] / d[k], m[k + 1] / d[k]
			local q = a * a + b * b
			if q > 9 then
				local t = 3 / math.sqrt(q)
				m[k], m[k + 1] = t * a * d[k], t * b * d[k]
			end
		end
	end
	return m
end

-- The price at time t on the curve.
local function At(p, m, t)
	if t <= p[1].t then return p[1].price end
	if t >= p[#p].t then return p[#p].price end
	local k = 1
	while p[k + 1].t < t do k = k + 1 end
	local h = p[k + 1].t - p[k].t
	local u = (t - p[k].t) / h
	local u2, u3 = u * u, u * u * u
	return (2 * u3 - 3 * u2 + 1) * p[k].price + (u3 - 2 * u2 + u) * h * m[k]
		+ (-2 * u3 + 3 * u2) * p[k + 1].price + (u3 - u2) * h * m[k + 1]
end

-- The view ----------------------------------------------------------------

local view, rows, week, list, offset, pick = nil, {}, {}, {}, 0, nil

local function Tex(parent, layer, r, g, b, a)
	local t = parent:CreateTexture(nil, layer)
	t:SetColorTexture(r, g, b, a or 1)
	return t
end

local function Percent(diff)
	if not diff then return "|cff808080-|r" end
	local p = math.floor(diff * 100 + (diff < 0 and -0.5 or 0.5))
	if p == 0 then return "0%" end
	return string.format(p > 0 and "|cff40ff40+%d%%|r" or "|cffff4040%d%%|r", p)
end
ns.TrendText = function(diff)
	if not diff then return "|cff808080-|r" end
	local p = math.floor(diff * 100 + (diff < 0 and -0.5 or 0.5))
	if p == 0 then return "0%" end
	return string.format(p > 0 and "|cff40ff40^ %d%%|r" or "|cffff4040v %d%%|r", math.abs(p))
end

local function Build(frame)
	view = CreateFrame("Frame", nil, frame)
	view:SetPoint("TOPLEFT", 20, -88)
	view:SetPoint("BOTTOMRIGHT", -20, 32)

	-- The items, filtered by the search box; click one for its graph.
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, view)
		row:SetSize(LIST_W, ROW_H)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", 2, 0)
		row.name:SetWidth(LIST_W - 50)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.trend = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.trend:SetPoint("RIGHT", -2, 0)
		row.trend:SetWidth(48)
		row.trend:SetJustifyH("RIGHT")
		row.mark = Tex(row, "BACKGROUND", 1, 0.82, 0, 0.15)
		row.mark:SetAllPoints()
		-- Right-click a watched item: stop watching it (Zach 9/11).
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, mouse)
			if mouse == "RightButton" then
				if not ns.Watched(self.item) or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
				local item = self.item
				MenuUtil.CreateContextMenu(self, function(_, root)
					root:CreateTitle(ns.ItemName(item))
					root:CreateButton("Stop watching", function()
						ns.Watch(item)
						ns.RefreshMarket(frame)
					end)
				end)
				return
			end
			pick = self.item
			ns.RefreshMarket(frame)
		end)
		rows[i] = row
	end
	view:EnableMouseWheel(true)
	view:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta * 3, #list - ROWS))
		ns.RefreshMarket(frame)
	end)

	-- The price graph: x the last 30 days, y the price.
	local graph = CreateFrame("Frame", nil, view)
	graph:SetPoint("TOPLEFT", GRAPH_X, -20)
	graph:SetSize(GRAPH_W, GRAPH_H)
	view.graph = graph
	local yAxis = Tex(graph, "ARTWORK", 0.6, 0.6, 0.6, 0.8)
	yAxis:SetWidth(1)
	yAxis:SetPoint("TOPLEFT")
	yAxis:SetPoint("BOTTOMLEFT")
	local xAxis = Tex(graph, "ARTWORK", 0.6, 0.6, 0.6, 0.8)
	xAxis:SetHeight(1)
	xAxis:SetPoint("BOTTOMLEFT")
	xAxis:SetPoint("BOTTOMRIGHT")
	view.title = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	view.title:SetPoint("BOTTOMLEFT", graph, "TOPLEFT", 0, 4)
	view.legend = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	view.legend:SetPoint("BOTTOMRIGHT", graph, "TOPRIGHT", 0, 4)
	view.legend:SetText("|cffffd100Lowest price at each scan|r")
	view.top = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	view.top:SetPoint("TOPRIGHT", graph, "TOPLEFT", -4, 0)
	view.bottom = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	view.bottom:SetPoint("BOTTOMRIGHT", graph, "BOTTOMLEFT", -4, 0)
	view.empty = graph:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	view.empty:SetPoint("CENTER")
	-- The curve in short pieces, a column of fill under each.
	view.pieces, view.fills = {}, {}
	for k = 1, SAMPLES do
		if graph.CreateLine then
			local line = graph:CreateLine(nil, "OVERLAY")
			line:SetThickness(2)
			line:SetColorTexture(1, 0.82, 0)
			view.pieces[k] = line
		end
		local fill = Tex(graph, "BORDER", 1, 0.82, 0, 0.12)
		fill:SetWidth(STEP)
		view.fills[k] = fill
	end
	view.labels = {}
	for k = 1, LABELS do
		local label = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		view.labels[k] = label
	end
	-- Hover: a line down to the axis and the nearest scan.
	local marker = Tex(graph, "OVERLAY", 1, 1, 1, 0.35)
	marker:SetWidth(1)
	marker:Hide()
	local dot = Tex(graph, "OVERLAY", 1, 1, 1)
	dot:SetSize(5, 5)
	dot:Hide()
	graph:EnableMouse(true)
	graph:SetScript("OnUpdate", function(self)
		if not self:IsMouseOver() or not view.points or #view.points == 0 then
			if marker:IsShown() then
				marker:Hide()
				dot:Hide()
				GameTooltip:Hide()
			end
			return
		end
		local x = GetCursorPosition() / self:GetEffectiveScale() - self:GetLeft()
		local t = view.from + (x / GRAPH_W) * (view.to - view.from)
		local best
		for _, pt in ipairs(view.points) do
			if not best or math.abs(pt.t - t) < math.abs(best.t - t) then best = pt end
		end
		local bx = (best.t - view.from) / (view.to - view.from) * GRAPH_W
		marker:ClearAllPoints()
		marker:SetPoint("TOPLEFT", self, "TOPLEFT", bx, 0)
		marker:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", bx, 0)
		marker:Show()
		dot:ClearAllPoints()
		dot:SetPoint("CENTER", self, "BOTTOMLEFT", bx, view.Y(best.price))
		dot:Show()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(date(best.day and "%A %d/%m" or "%A %d/%m %H:%M", best.t))
		GameTooltip:AddDoubleLine(best.day and "Average that day" or "Lowest price", ns.Money(best.price), 1, 1, 1, 1, 0.82, 0)
		if best.q then GameTooltip:AddDoubleLine("Listed", best.q, 1, 1, 1, 1, 1, 1) end
		GameTooltip:AddLine("Between scans the line is an estimate.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)

	-- Weekdays: each day's price against the item's own average, a bar up
	-- when dearer, down when cheaper.
	view.weekTitle = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	view.weekTitle:SetPoint("TOPLEFT", GRAPH_X, WEEK_TOP)
	local zero = Tex(view, "ARTWORK", 0.6, 0.6, 0.6, 0.8)
	zero:SetHeight(1)
	zero:SetPoint("TOPLEFT", GRAPH_X, WEEK_TOP - 20 - WEEK_H / 2)
	zero:SetWidth(GRAPH_W)
	local w = GRAPH_W / 7
	for k, wd in ipairs(WEEKDAYS) do
		local b = CreateFrame("Frame", nil, view)
		b:SetPoint("TOPLEFT", GRAPH_X + (k - 1) * w, WEEK_TOP - 20)
		b:SetSize(w, WEEK_H)
		b.bar = Tex(b, "ARTWORK", 0.25, 0.75, 0.25)
		b.bar:SetWidth(w - 16)
		b.value = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.name = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		b.name:SetPoint("TOP", b, "BOTTOM", 0, -2)
		b.name:SetText(wd[2])
		b.wd = wd[1]
		b:EnableMouse(true)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(date("%A", Time(20261109 + (self.wd + 6) % 7)))
			GameTooltip:AddLine(self.n and string.format("From %d day%s of scans: the average price that day against the item's own average.",
				self.n, self.n == 1 and "" or "s") or "No scan on this weekday yet.", 1, 1, 1, true)
			GameTooltip:AddLine("Settles as the weeks go by; trust it after three or four.", 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		week[k] = b
	end
end

function ns.ShowMarket(frame, show)
	if not view then
		if not show then return end
		Build(frame)
	end
	view:SetShown(show)
end

-- Whether an item's name matches the search box.
local function Matches(item, query)
	if not query or query == "" then return true end
	return ns.ItemName(item):lower():find(query, 1, true) ~= nil
end

function ns.RefreshMarket(frame)
	local query = ns.search
	list = {}
	for item in pairs(Tracked()) do
		if Matches(item, query) then table.insert(list, item) end
	end
	table.sort(list, function(a, b) return ns.ItemName(a) < ns.ItemName(b) end)
	if not pick or not Matches(pick, query) then pick = list[1] end
	offset = math.max(0, math.min(offset, #list - ROWS))
	for i, row in ipairs(rows) do
		local item = list[i + offset]
		row.item = item
		if item then
			row.name:SetText(ns.ItemName(item))
			row.trend:SetText(ns.TrendText(ns.Trend(item)))
			row.mark:SetShown(item == pick)
			row:Show()
		else
			row:Hide()
		end
	end

	local days = pick and Days(pick) or {}
	local points = pick and Points(pick) or {}
	view.points = points
	local now = time()
	local high, low = 0, nil
	for _, pt in ipairs(points) do high, low = math.max(high, pt.price), math.min(low or pt.price, pt.price) end
	-- From the first point (a day at least) to now: the line shows at once
	-- and the time axis grows to 30 days.
	view.to = now
	view.from = points[1] and math.min(points[1].t, now - 86400) or now - 86400
	local pad = math.max((high - (low or 0)) * 0.15, high * 0.05)
	low = math.max(0, (low or 0) - pad)
	local top = high + pad
	local scale = top > low and GRAPH_H / (top - low) or 0
	view.Y = function(v) return (v - low) * scale end
	local m = #points >= 2 and Tangents(points)
	local px, py
	for k = 1, SAMPLES do
		local x = (k - 0.5) * STEP
		local t = view.from + x / GRAPH_W * (view.to - view.from)
		local shown = #points > 0 and t >= points[1].t and scale > 0
		local y = shown and view.Y(m and At(points, m, t) or points[1].price)
		local fill = view.fills[k]
		fill:ClearAllPoints()
		fill:SetShown(shown and y > 0)
		if shown and y > 0 then
			fill:SetPoint("BOTTOMLEFT", view.graph, "BOTTOMLEFT", x - STEP / 2, 0)
			fill:SetHeight(y)
		end
		local piece = view.pieces[k]
		if piece then
			piece:SetShown(shown and px ~= nil)
			if shown and px then
				piece:SetStartPoint("BOTTOMLEFT", view.graph, px, py)
				piece:SetEndPoint("BOTTOMLEFT", view.graph, x, y)
			end
		end
		if shown then px, py = x, y else px, py = nil, nil end
	end
	for k, label in ipairs(view.labels) do
		local x = (k - 1) / (LABELS - 1) * GRAPH_W
		local t = view.from + (k - 1) / (LABELS - 1) * (view.to - view.from)
		label:ClearAllPoints()
		label:SetPoint("TOP", view.graph, "BOTTOMLEFT", x, -2)
		label:SetText(date(view.to - view.from > 3 * 86400 and "%d/%m" or "%d/%m %H:%M", t))
	end
	view.title:SetText(pick and ns.ItemName(pick) or "")
	view.top:SetText(high > 0 and ns.Money(top) or "")
	view.bottom:SetText(high > 0 and ns.Money(low) or "")
	view.empty:SetShown(high == 0)
	view.empty:SetText(pick and "No prices yet: press Scan AH at the auction house." or "No items yet: craft something, or right-click a recipe and Watch its price.")

	local weekdays = Weekdays(days)
	local most = 0.05
	for _, v in pairs(weekdays) do most = math.max(most, math.abs(v.diff or 0)) end
	view.weekTitle:SetText(string.format("By weekday, from %d day%s of scans", #days, #days == 1 and "" or "s"))
	for _, b in ipairs(week) do
		local v = weekdays[b.wd]
		b.n = v and v.n
		local diff = v and v.diff
		local h = diff and math.max(1, math.abs(diff) / most * (WEEK_H / 2 - 12)) or 0
		b.bar:ClearAllPoints()
		b.value:ClearAllPoints()
		b.bar:SetShown(diff ~= nil)
		if diff then
			b.bar:SetHeight(h)
			if diff >= 0 then
				b.bar:SetPoint("BOTTOM", b, "CENTER", 0, 0)
				b.bar:SetColorTexture(0.25, 0.75, 0.25)
				b.value:SetPoint("BOTTOM", b.bar, "TOP", 0, 1)
			else
				b.bar:SetPoint("TOP", b, "CENTER", 0, 0)
				b.bar:SetColorTexture(0.85, 0.25, 0.25)
				b.value:SetPoint("TOP", b.bar, "BOTTOM", 0, -1)
			end
		else
			b.value:SetPoint("CENTER")
		end
		b.value:SetText(Percent(diff))
	end

	frame.status:SetText(string.format("%d items", #list))
	frame.note:SetText("What you have crafted, and recipes you watch (right-click a recipe). Each full scan (yours or Auctionator's) adds a point; between scans the line is an estimate. Kept 90 days. Trend: the last day against the two weeks before.")
end

-- Size --------------------------------------------------------------------

-- How big the saved data is (Zach 9/11: warn before it gets dangerous). The
-- game cannot read the file's size, so it is estimated from what is in it,
-- about as many bytes as the saved file takes. Everything already drops off
-- after 90 days; this is the guard if that ever is not enough.
local WARN_MB = 10
local CLEAN_DAYS = 60

local function Bytes(value, seen)
	if type(value) ~= "table" then return #tostring(value) + 2 end
	if seen[value] then return 0 end
	seen[value] = true
	local n = 4
	for k, v in pairs(value) do n = n + Bytes(k, seen) + Bytes(v, seen) + 6 end
	return n
end

-- Megabytes in all, and the biggest part by name.
function ns.DataSize()
	local total, biggest, most = 0, nil, 0
	for k, v in pairs(ns.db or {}) do
		local n = Bytes(v, {}) + #tostring(k) + 6
		total = total + n
		if n > most then biggest, most = k, n end
	end
	return total / 1048576, biggest, most / 1048576
end

-- Market days and crafts older than 60 days out; income and purchases
-- (History) stay, they are the valuable part.
local function Clean()
	local before = ns.DataSize()
	local oldest = Day(time() - CLEAN_DAYS * 86400)
	for item, days in pairs(ns.db.market or {}) do
		for key in pairs(days) do
			if key < oldest then days[key] = nil end
		end
		if not next(days) then ns.db.market[item] = nil end
	end
	local cut, kept = time() - CLEAN_DAYS * 86400, {}
	for _, c in ipairs(ns.db.crafts or {}) do
		if c.at >= cut then table.insert(kept, c) end
	end
	ns.db.crafts = kept
	-- Hour profiles of items not seen for the clean's days.
	for item, h in pairs(ns.db.hours or {}) do
		if h.d < oldest then ns.db.hours[item] = nil end
	end
	ns.Print(string.format("cleaned: saved data %.1f MB, was %.1f MB. Saved to disk at logout or /reload.", ns.DataSize(), before))
end

StaticPopupDialogs.BOKFORING_SIZE = {
	text = "Bokföring's saved data is about %s MB (most of it: %s). Over 10 MB, loading gets slower.\n\nClean out market prices and crafts older than 60 days? Your income and purchases are kept.",
	button1 = "Clean",
	button2 = "Not now",
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = Clean,
}

function ns.ShowSize()
	local mb, biggest = ns.DataSize()
	StaticPopup_Show("BOKFORING_SIZE", string.format("%.1f", mb), tostring(biggest))
end

-- Once a session, a little after login.
local check = CreateFrame("Frame")
check:RegisterEvent("PLAYER_LOGIN")
check:SetScript("OnEvent", function()
	C_Timer.After(15, function()
		if not ns.db then return end
		if ns.DataSize() >= WARN_MB then ns.ShowSize() end
	end)
end)

-- For /bok test.
function ns.SizeTest()
	local mb, biggest, most = ns.DataSize()
	return string.format("about %.2f MB, the most in %s (%.2f MB); a warning comes at %d MB", mb, tostring(biggest), most, WARN_MB)
end
