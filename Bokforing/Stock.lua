-- Bokföring's stock at cost (0.7, Zach 14/11, every point agreed): every
-- material and crafted item he owns carries what it cost, so a craft and
-- its sale show the real profit even with materials bought days before.
--
-- One pool for the account (BokforingDB is account-wide): per item how
-- many and their summed cost; the cost of one is the average. Mail between
-- his own characters moves nothing, the units stay his.
--
-- In: auction house buys (the gold paid, or the won-auction mail),
-- vendor buys, his own loot and gathering at the AH price that day, what
-- others give him (trade, guild bank, mail) at the AH price marked
-- received, crafts at the summed cost of their reagents (so bars carry
-- into Mithril Casing and on into Salt Shaker), and what he holds when it
-- starts at the AH price marked opening balance.
-- Out: an AH sale (the sold mail, after cut, deposit and guild tax, less
-- the cost), a vendor sale, and anything used, given away or destroyed at
-- cost with no income. A posted auction stays in stock until its mail
-- says sold; an expired or cancelled one adds the lost deposit to the cost.
--
-- Bags are compared after each change (BAG_UPDATE_DELAYED, a moment
-- later): what he did just before (a buy, a craft, a mail taken, a post, a
-- merchant or trade open) says where a change came from; nothing runs per
-- frame. Reconciled with what his characters hold at login and after the
-- mailbox closes: more in stock than held is trimmed, less is added at the
-- AH price marked unknown.
--
-- Kept small: one entry per item (dropped 30 days after it runs out),
-- the realised records (sales, vendor sales, used, levelling) 90 days as
-- History, buys waiting for their mail and mail between his characters 31
-- days (the mail's own life).

local _, ns = ...

local KEEP = 90 * 86400
local EMPTY_KEEP = 30 * 86400
local MAIL_KEEP = 31 * 86400
local ON_AH = 3 * 86400 -- an auction lasts 48 hours at most
local LISTED_FRESH = 2 * 86400
local WINDOW = 10 -- seconds an expected bag change may take
local DIRECT = 60 -- seconds an AH buy may take to reach the bags
local AFTER = 2 -- seconds a closed merchant, trade or bank still counts

local function DB()
	local db = ns.db
	db.stock = db.stock or {}
	db.held = db.held or {}
	db.mailHeld = db.mailHeld or {}
	db.transit = db.transit or {}
	db.ledger = db.ledger or {}
	db.buys = db.buys or {}
	db.chars = db.chars or {}
	db.listed = db.listed or {}
	return db
end

-- What one is worth today: the AH price, else what a vendor pays, else 0.
local function Worth(item)
	local price = ns.AH(item)
	if price then return price end
	local sell = ns.VendorSell(item)
	return sell > 0 and sell or 0
end

-- The stock ----------------------------------------------------------------

-- An entry: n how many, v their summed cost, o / r / u how many of them
-- were priced at the AH price as opening balance, received or unknown.
local function Entry(item)
	local stock = DB().stock
	local s = stock[item]
	if not s then
		s = { n = 0, v = 0 }
		stock[item] = s
	end
	return s
end

local function Add(item, n, each, mark)
	if not item or not n or n <= 0 then return end
	local s = Entry(item)
	s.n, s.v, s.at = s.n + n, s.v + n * math.max(0, each or 0), time()
	if mark then s[mark] = (s[mark] or 0) + n end
end
ns.StockAdd = Add

-- Takes n out at the average cost; what stock lacks is first added at the
-- AH price marked unknown. Returns the cost and how many were unknown.
local function Take(item, n)
	if not item or not n or n <= 0 then return 0, 0 end
	local s = Entry(item)
	local unknown = 0
	if s.n < n then
		unknown = n - s.n
		Add(item, unknown, Worth(item), "u")
	end
	local share = n / s.n
	local cost = s.v * share
	for _, mark in ipairs({ "o", "r", "u" }) do
		if s[mark] then
			s[mark] = s[mark] * (1 - share)
			if s[mark] < 0.5 then s[mark] = nil end
		end
	end
	s.n, s.v, s.at = s.n - n, s.v - cost, time()
	if s.n < 0.5 then s.n, s.v = 0, 0 end
	return cost, unknown
end

-- A realised record: sale, vendor, used, given, trim, or level (n is then
-- the skill points, cost the reagents).
local function Record(kind, item, n, cost, income, unknown)
	table.insert(DB().ledger, { at = time(), kind = kind, item = item, n = n, cost = math.floor(cost + 0.5),
		income = income and math.floor(income + 0.5) or nil, unk = unknown and unknown > 0 and unknown or nil })
end

-- Out of stock at cost with no income: used, given away, trimmed.
local function Out(kind, item, n)
	local cost, unknown = Take(item, n)
	Record(kind, item, n, cost, nil, unknown)
end

-- The cost of one and how many, or nil when none is in stock.
function ns.StockCost(item)
	local s = ns.db and ns.db.stock and ns.db.stock[item]
	if s and s.n >= 0.5 then return s.v / s.n, s.n, s end
end

-- An item number from its name, for the sold and returned mails (they
-- give the name only): what is in stock, posted or one of his recipes.
local function ItemByName(name)
	if not name then return end
	for item in pairs(DB().stock) do
		if ns.CachedName(item) == name then return item end
	end
	for _, p in ipairs(ns.db.posts or {}) do
		if ns.CachedName(p.item) == name then return p.item end
	end
	for _, r in pairs(ns.db.recipes) do
		if r.item and ns.CachedName(r.item) == name then return r.item end
	end
end

-- Which items count: reagents and products of every recipe known (his and
-- the catalog), and anything already in stock. Worked out once a session,
-- and again when the catalog is read anew.
local tracked, trackedAt
local function Tracked()
	if tracked and trackedAt == ns.db.catalogAt then return tracked end
	tracked, trackedAt = {}, ns.db.catalogAt
	for _, list in ipairs({ ns.db.recipes, ns.db.catalog or {} }) do
		for _, r in pairs(list) do
			if r.item then tracked[r.item] = true end
			for _, reagent in ipairs(r.reagents or {}) do tracked[reagent[1]] = true end
		end
	end
	return tracked
end
local function IsTracked(item)
	return Tracked()[item] or (ns.db.stock and ns.db.stock[item] ~= nil)
end
function ns.StockTrack(item)
	if item then Tracked()[item] = true end
end

-- His own characters ------------------------------------------------------

-- Each character seen with Bokföring: the name as UnitName gives it, and
-- the full roster name (Forever names have two words; UnitName gives the
-- first only), found by GUID.
local function NoteMe()
	local db, key = DB(), ns.MeKey()
	if not key then return end
	local c = db.chars[key] or {}
	c.name = (UnitName("player") or ""):lower()
	local guid = UnitGUID("player")
	if guid and GetNumGuildMembers and GetGuildRosterInfo then
		for i = 1, GetNumGuildMembers() do
			local info = { GetGuildRosterInfo(i) }
			if info[17] == guid and info[1] then c.full = info[1]:gsub("%-.*", ""):lower() end
		end
	end
	c.at = time()
	db.chars[key] = c
end

-- A mail name is his own: the full name, or a one-word name that is one
-- of his characters' first names.
local function IsOwn(name)
	if type(name) ~= "string" or name == "" then return false end
	name = name:gsub("%-.*", ""):lower()
	for _, c in pairs(DB().chars) do
		if c.full and c.full == name then return true end
		if not name:find(" ") and c.name == name then return true end
	end
	return false
end

-- What changed the bags ---------------------------------------------------

-- Expected changes: { item, n (+ in, - out), kind, each, till }. Kinds:
-- "buy" in at each, "received" in at the AH price, "craft" in at each (a
-- craft's product), "keep" a change that moves nothing in stock (a post,
-- a reagent already taken, mail to or from his own characters, an
-- auction coming back), "given" out at cost with no income.
local expect = {}
local function Expect(item, n, kind, each)
	if item and n and n ~= 0 then table.insert(expect, { item = item, n = n, kind = kind, each = each, till = GetTime() + WINDOW }) end
end

-- Windows open now, or closed a moment ago.
local open = {}
local function IsOpen(what)
	local v = open[what]
	return v == true or (v and v > GetTime()) or false
end
local function SetOpen(what, on)
	open[what] = on or GetTime() + AFTER
end

-- Out of the bags at the mailbox, before the mail is sent (an attachment
-- may leave the bag as it is attached): parked until the send says to
-- whom, or the mailbox closes.
local parked = {}

-- An AH buy straight into the bags (within a minute), or nil.
local function RecentBuy(item, oldest)
	local buys = DB().buys
	for i, b in ipairs(buys) do
		if b.item == item and b.at >= oldest then return b, i end
	end
end

-- Takes up to k from a waiting buy: their cost, and how many it covered.
local function FromBuy(b, i, k)
	local take = math.min(k, b.n)
	local each = b.money / b.n
	b.n, b.money = b.n - take, b.money - each * take
	if b.n <= 0 then table.remove(DB().buys, i) end
	return each, take
end

local function Handle(e, item, k)
	if e.kind == "buy" or e.kind == "craft" then
		Add(item, k, e.each)
	elseif e.kind == "received" then
		Add(item, k, Worth(item), "r")
	elseif e.kind == "given" then
		Out("given", item, k)
	end
	-- "keep": nothing moves.
end

-- A change in what this character holds of one item.
local function Apply(item, delta)
	local now = GetTime()
	for _, e in ipairs(expect) do
		if delta == 0 then break end
		if e.item == item and e.n ~= 0 and e.till >= now and (e.n > 0) == (delta > 0) then
			local k = math.min(math.abs(delta), math.abs(e.n))
			Handle(e, item, k)
			local sign = delta > 0 and 1 or -1
			e.n, delta = e.n - sign * k, delta - sign * k
		end
	end
	if delta > 0 then
		-- Back from the mailbox's attachment slot.
		if parked[item] then
			local k = math.min(delta, parked[item])
			parked[item] = parked[item] - k > 0 and parked[item] - k or nil
			delta = delta - k
		end
		local b, i = RecentBuy(item, time() - DIRECT)
		while delta > 0 and b do
			local each, k = FromBuy(b, i, delta)
			Add(item, k, each)
			delta = delta - k
			b, i = RecentBuy(item, time() - DIRECT)
		end
		if delta <= 0 then return end
		if IsOpen("merchant") then
			-- A buy the hook missed, or a buyback: the vendor's price.
			Add(item, delta, ns.Vendor(item) or ns.VendorSell(item))
		elseif IsOpen("trade") or IsOpen("guildbank") then
			Add(item, delta, Worth(item), "r")
		elseif IsOpen("bank") then
			-- The bank's count may only be known once it is open.
			Add(item, delta, Worth(item), "u")
		else
			-- Looted, gathered, a quest: his own, at the AH price.
			Add(item, delta, Worth(item))
		end
	elseif delta < 0 then
		local k = -delta
		if IsOpen("mail") then
			parked[item] = (parked[item] or 0) + k
		elseif IsOpen("merchant") then
			local cost, unknown = Take(item, k)
			Record("vendor", item, k, cost, ns.VendorSell(item) * k * (1 - ns.TaxRate()), unknown)
		elseif IsOpen("trade") or IsOpen("guildbank") then
			Out("given", item, k)
		else
			Out("used", item, k)
		end
	end
end

-- Expected changes that never came: a craft's product not seen counts as
-- used (the reagents went); the rest is dropped.
local function Expire()
	local now = GetTime()
	for i = #expect, 1, -1 do
		local e = expect[i]
		if e.n == 0 or e.till < now then
			if e.kind == "craft" and e.n > 0 then Record("used", e.item, 0, e.n * e.each) end
			table.remove(expect, i)
		end
	end
end

-- Counting ------------------------------------------------------------------

local last -- what this character held at the last look: [item] = count
local ready = false

local function Bags()
	local found = {}
	local slots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	local itemAt = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
	if not slots or not itemAt then return found end
	for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
		for slot = 1, slots(bag) or 0 do
			local item = itemAt(bag, slot)
			if item and IsTracked(item) then found[item] = true end
		end
	end
	return found
end

-- What he holds now (bags and bank) of the items in the bags, held last
-- time or expected; all tracked items with full.
local function Count(full)
	local items = full and Tracked() or Bags()
	local now = {}
	local function Look(item)
		if now[item] == nil then
			local n = ns.Have(item)
			now[item] = n > 0 and n or false
		end
	end
	for item in pairs(items) do Look(item) end
	for item in pairs(ns.db.stock) do if full then Look(item) end end
	for item in pairs(last or {}) do Look(item) end
	for _, e in ipairs(expect) do Look(e.item) end
	for item in pairs(parked) do Look(item) end
	local out = {}
	for item, n in pairs(now) do if n then out[item] = n end end
	return out
end

local function Save()
	local db = DB()
	db.held[ns.MeKey()] = { at = time(), items = last }
end

local function Diff()
	if not ready or not ns.db or (ns.Allowed and not ns.Allowed()) then return end
	local now = Count(IsOpen("bank"))
	for item, n in pairs(now) do
		local d = n - (last[item] or 0)
		if d ~= 0 then Apply(item, d) end
	end
	for item, n in pairs(last) do
		if not now[item] then Apply(item, -n) end
	end
	last = now
	Expire()
	Save()
end

local diffSoon = false
local function DiffSoon()
	if diffSoon then return end
	diffSoon = true
	-- A moment later, so the craft, mail or post that caused it is known.
	C_Timer.After(0.3, function()
		diffSoon = false
		Diff()
	end)
end

-- Reconcile -----------------------------------------------------------------

-- On the auction house now, as far as known: posts of the last three days
-- less what has sold or come back since; or his own listings as the
-- auction house last showed them, whichever is more.
local function OnAH(item)
	local db, since = ns.db, time() - ON_AH
	local first, n = nil, 0
	for _, p in ipairs(db.posts or {}) do
		if p.item == item and p.at >= since then
			n = n + (p.qty or 1)
			first = first and math.min(first, p.at) or p.at
		end
	end
	if first then
		local name = ns.CachedName(item)
		for _, store in ipairs({ db.sales or {}, db.returns or {} }) do
			for _, s in ipairs(name and store[name] or {}) do
				if s.at >= first then n = n - (s.count or 1) end
			end
		end
		n = math.max(0, n)
	end
	local listed = 0
	for _, l in pairs(DB().listed) do
		if time() - l.at < LISTED_FRESH then listed = listed + (l.items[item] or 0) end
	end
	return math.max(n, listed)
end

-- What all his characters hold, as last seen on each: bags and bank,
-- returned auctions waiting in the mail, mail between them, the AH.
local function HeldAll(item)
	local db, n = DB(), 0
	for _, h in pairs(db.held) do n = n + (h.items and h.items[item] or 0) end
	for _, m in pairs(db.mailHeld) do n = n + (m[item] or 0) end
	for _, t in ipairs(db.transit) do if t.item == item then n = n + t.n end end
	return n + OnAH(item)
end

-- mark: "o" the first time this character is seen (opening balance),
-- else "u".
local function Reconcile(mark)
	local db = DB()
	local items = {}
	for item in pairs(db.stock) do items[item] = true end
	for _, h in pairs(db.held) do
		for item in pairs(h.items or {}) do items[item] = true end
	end
	local added, trimmed = 0, 0
	for item in pairs(items) do
		local s, held = Entry(item), HeldAll(item)
		if held > s.n + 0.5 then
			Add(item, held - s.n, Worth(item), mark)
			added = added + 1
		elseif held < s.n - 0.5 then
			local k = s.n - held
			Out("trim", item, k)
			trimmed = trimmed + 1
		end
	end
	ns.reconciled = string.format("%s: %d added, %d trimmed", date("%H:%M"), added, trimmed)
end

-- Old records and empty entries out (see the top).
local function Prune()
	local db, now = DB(), time()
	for i = #db.ledger, 1, -1 do
		if db.ledger[i].at < now - KEEP then table.remove(db.ledger, i) end
	end
	for i = #db.buys, 1, -1 do
		if db.buys[i].at < now - MAIL_KEEP then table.remove(db.buys, i) end
	end
	for i = #db.transit, 1, -1 do
		if db.transit[i].at < now - MAIL_KEEP then table.remove(db.transit, i) end
	end
	for item, s in pairs(db.stock) do
		if s.n < 0.5 and (s.at or 0) < now - EMPTY_KEEP then db.stock[item] = nil end
	end
end

-- Hooks from History and Mail -------------------------------------------

-- An auction house buy, from the gold it took (History.lua): waits for the
-- item, in the bags within a minute or in the won-auction mail.
function ns.StockBought(item, n, money)
	if not ns.db or not item or not n or n <= 0 or not money or money <= 0 then return end
	ns.StockTrack(item)
	table.insert(DB().buys, { item = item, n = n, money = money, at = time() })
	DiffSoon()
end

-- A craft of one of his recipes (History.lua): the reagents leave stock at
-- their cost and the product comes in at the sum. Returns the cost.
local skillAt = {}
function ns.StockCraft(id, r)
	if not ns.db or not ready then return end
	local cost, unknown = 0, 0
	for _, reagent in ipairs(r.reagents or {}) do
		local c, u = Take(reagent[1], reagent[2])
		cost, unknown = cost + c, unknown + u
		Expect(reagent[1], -reagent[2], "keep")
	end
	local made = math.max(1, math.floor((r.qty or 1) + 0.5))
	if r.item then
		ns.StockTrack(r.item)
		Expect(r.item, made, "craft", cost / made)
	end
	-- A skill point from it (Zach 14/11: levelling cost apart): the skill
	-- a second later against the skill before.
	-- Against the skill as last noted, so crafts in a row ("Create all")
	-- do not count the same point twice.
	local profession = r.profession or "?"
	local before = skillAt[profession] or ns.MySkills()[profession]
	C_Timer.After(1, function()
		local after = ns.MySkills()[profession]
		local base = skillAt[profession] or before
		if after and base and after > base then
			Record("level", r.item, after - base, cost, nil, unknown)
			ns.lastLevel = string.format("%s +%d, %s", profession, after - base, date("%H:%M"))
		end
		skillAt[profession] = after
	end)
	DiffSoon()
	return cost
end

-- The skill before the first craft of a run (UNIT_SPELLCAST_START).
function ns.StockCraftStart(r)
	if r and r.profession and skillAt[r.profession] == nil then skillAt[r.profession] = ns.MySkills()[r.profession] end
end

-- An auction posted (History.lua): the item leaves the bags but stays in
-- stock; the deposit is noted on the post for an expiry later. From the
-- game's deposit sum where there is one, else the gold it took.
local postWaiting
function ns.StockPosted(post, location, duration)
	if not ns.db then return end
	ns.StockTrack(post.item)
	Expect(post.item, -post.qty, "keep")
	local ah = C_AuctionHouse
	local dep
	if ah and ah.CalculateCommodityDeposit then
		local ok, v = pcall(ah.CalculateCommodityDeposit, post.item, duration, post.qty)
		if ok and type(v) == "number" and v > 0 then dep = v end
	end
	if not dep and ah and ah.CalculateItemDeposit and location then
		local ok, v = pcall(ah.CalculateItemDeposit, location, duration, post.qty)
		if ok and type(v) == "number" and v > 0 then dep = v end
	end
	if dep then
		post.dep = dep
	else
		postWaiting = { post = post, money = GetMoney(), at = GetTime() }
	end
	DiffSoon()
end

-- A sold mail, first seen (Mail.lua): out of stock at cost; money is what
-- the mail brings less the deposit and the guild tax.
function ns.StockSale(name, count, money)
	if not ns.db then return end
	local item = ItemByName(name)
	if not item then return end
	local cost, unknown = Take(item, count or 1)
	Record("sale", item, count or 1, cost, money, unknown)
end

-- An expired or cancelled auction, first seen (Mail.lua): the deposit is
-- lost, so it is added to the item's cost (Zach 14/11).
function ns.StockReturned(name, count)
	if not ns.db then return end
	local item = ItemByName(name)
	local s = item and ns.db.stock[item]
	if not s or s.n < 0.5 then return end
	local posts = ns.db.posts or {}
	for i = #posts, 1, -1 do
		local p = posts[i]
		if p.item == item and p.dep and (p.qty or 0) > 0 then
			s.v = s.v + p.dep / p.qty * (count or 1)
			return
		end
	end
end

-- Returned auctions in this character's mailbox (Mail.lua, whenever the
-- inbox is read): still his stock.
function ns.StockMailHeld(list)
	if not ns.db then return end
	local out = {}
	for _, m in ipairs(list) do
		if m.id then out[m.id] = (out[m.id] or 0) + (m.count or 1) end
	end
	DB().mailHeld[ns.MeKey()] = out
end

-- The mailbox ---------------------------------------------------------------

local function Pattern(text)
	return "^" .. text:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
end

-- An attachment's item number and count.
local function InboxItem(index, a)
	if not GetInboxItem then return end
	local _, id, _, count = GetInboxItem(index, a)
	if type(id) ~= "number" and GetInboxItemLink then
		local link = GetInboxItemLink(index, a)
		id = link and tonumber(link:match("item:(%d+)"))
	end
	if type(id) == "number" then return id, count or 1 end
end

-- A mail about to be taken (TakeInboxItem, AutoLootMailItem): what comes
-- out of it and at what cost. Won auction: the buy waiting for it, else
-- the invoice's price; expired or cancelled: his own, already in stock;
-- from his own character: already in stock; from anyone else: received.
local function Taking(index, only)
	if not ns.db or not GetInboxHeaderInfo then return end
	local _, _, sender, subject = GetInboxHeaderInfo(index)
	local invoice, bid
	if GetInboxInvoiceInfo then
		local info = { GetInboxInvoiceInfo(index) }
		invoice, bid = info[1], info[4]
	end
	subject = subject or ""
	local won = invoice == "buyer" or subject:match(Pattern(AUCTION_WON_MAIL_SUBJECT or "Auction won: %s"))
	local back = subject:match(Pattern(AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s"))
		or subject:match(Pattern(AUCTION_REMOVED_MAIL_SUBJECT or "Auction cancelled: %s"))
	local own = not won and not back and IsOwn(sender)
	local first, lastA = only or 1, only or (ATTACHMENTS_MAX_RECEIVE or 16)
	for a = first, lastA do
		local item, count = InboxItem(index, a)
		if item then
			ns.StockTrack(item)
			if won then
				local b, i = RecentBuy(item, 0)
				local each
				if b then
					each = FromBuy(b, i, count)
				elseif type(bid) == "number" and bid > 0 then
					each = bid / count
				end
				if each then Expect(item, count, "buy", each) else Expect(item, count, "received") end
			elseif back then
				Expect(item, count, "keep")
			elseif own then
				Expect(item, count, "keep")
				local transit = DB().transit
				for i, t in ipairs(transit) do
					if t.item == item then
						t.n = t.n - count
						if t.n <= 0 then table.remove(transit, i) end
						break
					end
				end
			else
				Expect(item, count, "received")
			end
		end
	end
	DiffSoon()
end

-- Attachments of the mail being written, as the send window last showed.
local attached = {}
local function ReadAttached()
	local out = {}
	if not GetSendMailItem then return out end
	for a = 1, ATTACHMENTS_MAX_SEND or 12 do
		local _, id, _, count = GetSendMailItem(a)
		if type(id) ~= "number" and GetSendMailItemLink then
			local link = GetSendMailItemLink(a)
			id = link and tonumber(link:match("item:(%d+)"))
		end
		if type(id) == "number" then table.insert(out, { id, count or 1 }) end
	end
	return out
end

-- A mail sent: to his own character the units stay in stock (in the mail
-- until taken); to anyone else they are given away, at cost.
local function Sent(recipient)
	if not ns.db then return end
	local list = ReadAttached()
	if #list == 0 then list = attached end
	local own = IsOwn(recipient)
	for _, a in ipairs(list) do
		local item, count = a[1], a[2]
		if IsTracked(item) then
			if own then table.insert(DB().transit, { item = item, n = count, to = recipient, at = time() }) end
			-- Already out of the bags as it was attached: settle that first.
			local k = math.min(parked[item] or 0, count)
			if k > 0 then
				parked[item] = parked[item] - k > 0 and parked[item] - k or nil
				if not own then Out("given", item, k) end
			end
			if count > k then Expect(item, -(count - k), own and "keep" or "given") end
		end
	end
	attached = {}
	DiffSoon()
end

-- Left the bags at the mailbox and never sent: used.
local function Unpark()
	for item, k in pairs(parked) do Out("used", item, k) end
	parked = {}
end

-- His own auctions as the auction house shows them (where this client
-- has it): the surest count of what is up.
local function ReadOwned()
	local ah = C_AuctionHouse
	if not ah or not ah.GetNumOwnedAuctions or not ah.GetOwnedAuctionInfo then return end
	local items = {}
	for i = 1, ah.GetNumOwnedAuctions() or 0 do
		local ok, info = pcall(ah.GetOwnedAuctionInfo, i)
		-- Status 0 is up for sale; 1 sold, waiting for its mail.
		if ok and type(info) == "table" and info.itemKey and info.itemKey.itemID and (info.status or 0) == 0 then
			items[info.itemKey.itemID] = (items[info.itemKey.itemID] or 0) + (info.quantity or 1)
		end
	end
	DB().listed[ns.MeKey()] = { at = time(), items = items }
end

-- Start ---------------------------------------------------------------------

local function Hooks()
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
			if not item or not price or extended then return end
			stack = math.max(stack or 1, 1)
			ns.StockTrack(item)
			Expect(item, quantity or stack, "buy", price / stack)
		end)
	end
	if TakeInboxItem then hooksecurefunc("TakeInboxItem", function(index, a) Taking(index, a) end) end
	if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", function(index) Taking(index) end) end
	if SendMail then hooksecurefunc("SendMail", function(recipient) Sent(recipient) end) end
end

local function Start()
	local db = DB()
	NoteMe()
	Prune()
	local key = ns.MeKey()
	local first = db.held[key] == nil
	last = Count(true)
	ready = true
	Save()
	Reconcile(first and "o" or "u")
	if first then ns.Print("stock at cost starts on this character: what you hold is valued at today's AH price (opening balance).") end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "MERCHANT_SHOW", "MERCHANT_CLOSED",
	"TRADE_SHOW", "TRADE_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "MAIL_SHOW", "MAIL_CLOSED",
	"MAIL_SEND_INFO_UPDATE", "AUCTION_HOUSE_SHOW", "OWNED_AUCTIONS_UPDATED" }) do
	pcall(events.RegisterEvent, events, event)
end

-- The guild bank as an interaction window on newer clients.
local function GuildBanker(kind)
	local types = Enum and Enum.PlayerInteractionType
	return types and types.GuildBanker and kind == types.GuildBanker
end

events:SetScript("OnEvent", function(_, event, arg)
	if not ns.db then return end
	if event == "PLAYER_LOGIN" then
		Hooks()
		-- After the bags and the guild roster have loaded.
		C_Timer.After(5, function()
			if ns.Allowed and not ns.Allowed() then return end
			Start()
		end)
		return
	end
	if not ready then return end
	if event == "BAG_UPDATE_DELAYED" then
		DiffSoon()
	elseif event == "PLAYER_MONEY" then
		if postWaiting then
			local w = postWaiting
			postWaiting = nil
			local drop = w.money - GetMoney()
			if drop > 0 and GetTime() - w.at < WINDOW then w.post.dep = drop end
		end
	elseif event == "MERCHANT_SHOW" then
		SetOpen("merchant", true)
	elseif event == "MERCHANT_CLOSED" then
		SetOpen("merchant")
	elseif event == "TRADE_SHOW" then
		SetOpen("trade", true)
	elseif event == "TRADE_CLOSED" then
		SetOpen("trade")
	elseif event == "GUILDBANKFRAME_OPENED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and GuildBanker(arg)) then
		SetOpen("guildbank", true)
	elseif event == "GUILDBANKFRAME_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and GuildBanker(arg)) then
		SetOpen("guildbank")
	elseif event == "BANKFRAME_OPENED" then
		SetOpen("bank", true)
		DiffSoon()
	elseif event == "BANKFRAME_CLOSED" then
		SetOpen("bank")
	elseif event == "MAIL_SHOW" then
		SetOpen("mail", true)
	elseif event == "MAIL_SEND_INFO_UPDATE" then
		local list = ReadAttached()
		if #list > 0 then attached = list end
	elseif event == "MAIL_CLOSED" then
		SetOpen("mail")
		-- Once the last takes have landed: what was parked, then a check.
		C_Timer.After(AFTER + 0.5, function()
			Diff()
			Unpark()
			Reconcile("u")
		end)
	elseif event == "AUCTION_HOUSE_SHOW" then
		if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then pcall(C_AuctionHouse.QueryOwnedAuctions, {}) end
	elseif event == "OWNED_AUCTIONS_UPDATED" then
		ReadOwned()
	end
end)

-- Shown --------------------------------------------------------------------

-- Realised records since a time, per item and in all: { profit, income,
-- cost, n } per item; levelling { cost, points, crafts } apart.
function ns.Realised(since)
	local per, all, level = {}, { profit = 0, income = 0, cost = 0, n = 0 }, { cost = 0, points = 0, crafts = 0 }
	for _, l in ipairs(ns.db.ledger or {}) do
		if l.at >= since then
			if l.kind == "level" then
				level.cost, level.points, level.crafts = level.cost + l.cost, level.points + l.n, level.crafts + 1
			elseif l.kind == "sale" or l.kind == "vendor" then
				local p = per[l.item] or { profit = 0, income = 0, cost = 0, n = 0, unk = 0 }
				p.income, p.cost, p.n = p.income + (l.income or 0), p.cost + l.cost, p.n + l.n
				p.profit = p.income - p.cost
				p.unk = p.unk + (l.unk or 0)
				per[l.item] = p
				all.income, all.cost, all.n = all.income + (l.income or 0), all.cost + l.cost, all.n + l.n
			end
		end
	end
	all.profit = all.income - all.cost
	return per, all, level
end

-- Unsold stock: at cost and at today's price after cut and tax.
function ns.StockValue()
	local cost, value, n = 0, 0, 0
	for item, s in pairs(ns.db.stock or {}) do
		if s.n >= 0.5 then
			cost, n = cost + s.v, n + s.n
			local price = ns.AH(item)
			value = value + s.n * (price and ns.Keep(price) or ns.VendorSell(item) * (1 - ns.TaxRate()))
		end
	end
	return cost, value, n
end

-- For /bok test.
function ns.StockTest()
	local db, items, n = DB(), 0, 0
	for _, s in pairs(db.stock) do
		if s.n >= 0.5 then items, n = items + 1, n + s.n end
	end
	local chars = 0
	for _ in pairs(db.held) do chars = chars + 1 end
	return string.format("%d items (%d units) in stock; %d characters seen; %d records; %d buys waiting for mail; %d in mail between characters; last check %s; last skill-up %s",
		items, n, chars, #db.ledger, #db.buys, #db.transit, ns.reconciled or "not yet", ns.lastLevel or "none this session")
end
