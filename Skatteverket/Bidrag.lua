-- Skatteverket: Statligt socialbidrag (Zach 11/11), a side tab of the Skatt window (12/11).
-- Below level 15 a member may ask for up to three 6-slot bags, from level
-- 15 for up to three 8-slot bags; the two are separate, and the limit is
-- per account, every character together. The level of the character that
-- asks decides the size. The guild leader sees the requests, fills the
-- letter with bags from his own bags (any plain bag whose item text says
-- 6 or 8 slots) and presses Send himself, then Klar; the member gets a
-- note on the to-do, and with the 6-slot bags that the 8-slot ones can be
-- asked for at 15.
--
-- Whispers:
--   FG;size;count;level      member -> leader: a request
--   FH;size;count;declined   leader -> member: sent (declined 1: turned down)

local _, ns = ...

ns.BIDRAG_MAX = 3
ns.BIDRAG_LEVEL = 15

local Bag = C_Container or {}
local LAST_BAG = math.max(NUM_TOTAL_EQUIPPED_BAG_SLOTS or 0, (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 1))

local function B()
	local db = ns.db
	db.bidrag = db.bidrag or {}
	local b = db.bidrag
	-- This account's bags received, by size.
	b.got = b.got or {}
	-- Leader: requests by name, and what each account has been given.
	b.asks = b.asks or {}
	b.given = b.given or {}
	return b
end
ns.Bidrag = B

function ns.BidragSize(level)
	return (level or UnitLevel("player")) < ns.BIDRAG_LEVEL and 6 or 8
end

-- Left for this account at that size, as far as this account knows.
function ns.BidragLeft(size)
	return math.max(0, ns.BIDRAG_MAX - (B().got[size] or 0))
end

function ns.MyBidragAsk()
	return ns.FolkChar().bidrag
end

function ns.AskBidrag(count)
	local size = ns.BidragSize()
	count = math.min(count, ns.BidragLeft(size))
	if count < 1 then return end
	local c = ns.FolkChar()
	if c.bidrag then ns.Print("du har redan en ansökan om socialbidrag inne.") return end
	c.bidrag = { size = size, count = count, at = ns.Now() }
	local online = ns.ToLeader("FG", string.format("%d;%d;%d", size, count, UnitLevel("player")))
	ns.Print(string.format("ansökan om %d väsk%s med %d platser är %s.", count, count == 1 and "a" or "or", size,
		online and "skickad till guildledaren" or "sparad och skickas när guildledaren är online"))
	ns.RefreshWindow("folk")
end

-- Leader ----------------------------------------------------------------

local function Account(name)
	if name == ns.Me() then return ns.db.account end
	local m = ns.db.members[name]
	return m and m.account or name
end

function ns.BidragGiven(name, size)
	local g = B().given[Account(name)]
	return g and g[size] or 0
end

function ns.OnBidragAsk(sender, parts)
	local size, count, level = tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4])
	if (size ~= 6 and size ~= 8) or not count or not level then return end
	if ns.BidragSize(level) ~= size then return end
	-- Asks from the account's other characters count against it too.
	local left = ns.BIDRAG_MAX - ns.BidragGiven(sender, size)
	for name, a in pairs(B().asks) do
		if name ~= sender and a.size == size and Account(name) == Account(sender) then left = left - a.count end
	end
	if left < 1 then
		ns.ToMember(sender, string.format("FH;%d;0;1", size))
		return
	end
	B().asks[sender] = { size = size, count = math.min(count, left), level = level, at = ns.Now() }
	if sender ~= ns.Me() then ns.Print(string.format("|cffffd100%s söker socialbidrag: %d väskor med %d platser.|r Se Socialbidrag under Skatt.", sender, count, size)) end
	ns.RefreshWindow("folk")
	ns.RefreshTodo()
end

function ns.BidragDone(name, declined)
	local a = B().asks[name]
	if not a then return end
	B().asks[name] = nil
	if not declined then
		local acct = Account(name)
		B().given[acct] = B().given[acct] or {}
		B().given[acct][a.size] = (B().given[acct][a.size] or 0) + a.count
	end
	ns.ToMember(name, string.format("FH;%d;%d;%d", a.size, declined and 0 or a.count, declined and 1 or 0))
	ns.RefreshWindow("folk")
	ns.RefreshTodo()
end

function ns.BidragTodo()
	local out = {}
	if not ns.db or not IsGuildLeader() or not ns.InOurGuild() then return out end
	local n = 0
	for _ in pairs(B().asks) do n = n + 1 end
	if n > 0 then
		table.insert(out, { text = string.format("%d ansökning%s om socialbidrag", n, n == 1 and "" or "ar"), click = function() ns.ShowTab(12) end })
	end
	return out
end

-- Member: the leader's answer.
function ns.OnBidragGiven(parts)
	local size, count, declined = tonumber(parts[2]), tonumber(parts[3]) or 0, parts[4] == "1"
	if not size then return end
	ns.FolkChar().bidrag = nil
	local text
	if declined then
		text = string.format("Socialbidrag: din ansökan om väskor med %d platser avböjdes.", size)
	else
		B().got[size] = (B().got[size] or 0) + count
		text = string.format("Socialbidrag: %d väsk%s med %d platser är skickad%s till dig.", count, count == 1 and "a" or "or", size, count == 1 and "" or "e")
		if size == 6 then text = text .. " När du når nivå " .. ns.BIDRAG_LEVEL .. " kan du söka 3 väskor med 8 platser." end
	end
	ns.AddNotice(text, 12)
	ns.Print(text)
	ns.RefreshWindow("folk")
end

-- Filling the letter ----------------------------------------------------

local Instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local tip
local function Slots(bag, slot)
	if not tip then
		tip = CreateFrame("GameTooltip", "SkatteverketBagTip", nil, "GameTooltipTemplate")
	end
	tip:SetOwner(WorldFrame, "ANCHOR_NONE")
	tip:ClearLines()
	tip:SetBagItem(bag, slot)
	for i = 1, tip:NumLines() do
		local line = _G["SkatteverketBagTipTextLeft" .. i]
		local n = line and line:GetText() and line:GetText():match("^(%d+) Slot")
		if n then return tonumber(n) end
	end
end

-- Plain bags of that many slots in his bags, not profession bags.
local function FindBags(size)
	local out = {}
	for bag = 0, LAST_BAG do
		for slot = 1, (Bag.GetContainerNumSlots and Bag.GetContainerNumSlots(bag)) or 0 do
			local info = Bag.GetContainerItemInfo(bag, slot)
			if info and not info.isLocked then
				local _, _, _, _, _, class, sub = Instant(info.itemID)
				if class == 1 and sub == 0 and Slots(bag, slot) == size then
					table.insert(out, { bag = bag, slot = slot })
				end
			end
		end
	end
	return out
end

function ns.FillBidrag(name)
	local a = B().asks[name]
	if not a then return end
	if not (MailFrame and MailFrame:IsShown()) then ns.Print("öppna en brevlåda först.") return end
	if CursorHasItem() then ns.Print("släpp det du håller i först.") return end
	if not Bag.GetContainerItemInfo or not ClickSendMailItemButton then return end
	if MailFrameTab_OnClick then MailFrameTab_OnClick(nil, 2) end
	SendMailNameEditBox:SetText(name)
	if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText("Statligt socialbidrag") end
	local bags = FindBags(a.size)
	local want, put = math.min(a.count, #bags), 0
	-- One bag at a time, as Fyll i brev does for orders.
	local function Step()
		if put >= want or not (MailFrame and MailFrame:IsShown()) then
			if put < a.count then
				ns.Print(string.format("bara %d av %d väskor med %d platser fanns i dina väskor.", put, a.count, a.size))
			end
			ns.Print("brevet till " .. name .. " är ifyllt. Kontrollera det, tryck Send och sedan Klar.")
			return
		end
		local free
		for k = 1, ATTACHMENTS_MAX_SEND or 12 do
			if not GetSendMailItem(k) then free = k break end
		end
		if not free then want = put Step() return end
		local spot = bags[put + 1]
		Bag.PickupContainerItem(spot.bag, spot.slot)
		ClickSendMailItemButton(free)
		if CursorHasItem() then
			ClearCursor()
			want = put
		else
			put = put + 1
		end
		C_Timer.After(0.4, Step)
	end
	Step()
end
