-- Skatteverket: guild tax for THÖNDERSTÖRM on WoW Forever.
-- Counts looted gold, vendor sales and auction house sales (not quest
-- rewards, mail from players or trades), keeps the tax owed, and deposits
-- it when the guild bank opens. Standings go over the guild addon channel
-- without amounts; amounts go by whisper to the guild leader only, and
-- wait in this character's saved data while the leader is offline. The
-- guild leader's side is in Leader.lua and the /skatt window in Window.lua.
--
-- Guild channel, no amounts:
--   T;version;last deposit;debt since;good since;has paid   a member's standing
--   B                                                       ask the leader for the standings
--   Q                                                       leader: everyone send your figures
--   R;rate in basis points;stamp                            leader: the tax rate
--   E;name,last deposit,debt since,last seen,good since,has paid;...   leader: standings
--   V;copper;server time[;reader]   the guild bank's balance, sent by whoever opened
--                                   the bank; the leader adds who read it when relaying
-- Whispers between a member and the leader, with amounts:
--   P;version;income total;paid;owed;last deposit;income since;rate stamp;debt since;good since
--   A;id;op;amount     leader -> member: F forgives the debt, C gives credit
--   K;id               member -> leader: adjustment applied
--   M;paid;last deposit   leader -> member: restore a lost record
-- Registration (Y, Z, G, N) is described in Professions.lua, recipe search
-- (W, J, U) in Recipes.lua.
--
-- Saved data survives new versions as long as the folder and the names
-- SkatteverketDB and SkatteverketCharDB never change. When the shape of
-- the data changes, raise ns.SCHEMA and add a step to Migrate().

local _, ns = ...

ns.GUILD = "THÖNDERSTÖRM"
ns.VERSION = "0.16"
ns.SCHEMA = 7
ns.PREFIX = "SKATT"
ns.GOOD_HOURS = 48
ns.NEGATIVE_DAYS = 7

local char, db
local lastMoney
local looting, lootGraceUntil, moneyMsgUntil, questUntil = false, 0, 0, 0
local merchantOpen, mailOpen, tradeOpen, bankOpen = false, false, false, false
local unclaimed, pendingDeposit, dirty, lastStanding, warnedVersion
local privateDirty = true

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Skatteverket:|r " .. text)
end
ns.Print = Print

function ns.Money(copper)
	copper = math.floor(copper or 0)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return string.format("%s%dg %ds %dc", sign, g, s, c) end
	if s > 0 then return string.format("%s%ds %dc", sign, s, c) end
	return string.format("%s%dc", sign, c)
end

-- "2g50s", "75s", "10c", "2" (gold), "2.5" or "2,5" (gold, with or without
-- g); nil for anything else. The whole text must parse, so "1g50" and
-- "2.5g" can never turn into another amount (review 6/11).
function ns.ParseMoney(text)
	text = (text or ""):lower():gsub("%s+", "")
	if text == "" then return nil end
	local whole, frac = text:match("^(%d+)[%.,](%d+)g?$")
	if whole then return math.floor(tonumber(whole .. "." .. frac) * 10000 + 0.5) end
	local gold = text:match("^(%d+)g?$")
	if gold then return tonumber(gold) * 10000 end
	local total, rest = 0, text
	for _, unit in ipairs({ { "g", 10000 }, { "s", 100 }, { "c", 1 } }) do
		local n, after = rest:match("^(%d+)" .. unit[1] .. "(.*)$")
		if n then
			total = total + tonumber(n) * unit[2]
			rest = after
		end
	end
	if rest ~= "" then return nil end
	return total
end

function ns.Short(name)
	if not name then return nil end
	if Ambiguate then return Ambiguate(name, "none") end
	return (name:gsub("%-.*", ""))
end

function ns.Day(t)
	return (t and t > 0) and date("%d/%m", t) or "aldrig"
end

function ns.InOurGuild()
	return GetGuildInfo("player") == ns.GUILD
end

function ns.BankOpen()
	return bankOpen
end

function ns.RequestRoster()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

-- The guild master's name and whether they are online, or nil before the roster loads.
function ns.Leader()
	for i = 1, GetNumGuildMembers() do
		local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
		if rankIndex == 0 and name then return ns.Short(name), online and true or false end
	end
end

-- nil if not in the guild, otherwise whether they are online.
function ns.Online(who)
	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
		if name and ns.Short(name) == who then return online and true or false end
	end
end

function ns.Send(msg)
	if not IsInGuild() then return end
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(ns.PREFIX, msg, "GUILD")
	elseif SendAddonMessage then
		SendAddonMessage(ns.PREFIX, msg, "GUILD")
	end
end

-- Names in the guild right now as a set, or nil before the roster loads.
function ns.RosterNames()
	local n = GetNumGuildMembers()
	if n == 0 then return nil end
	local names = {}
	for i = 1, n do
		local name = ns.Short(GetGuildRosterInfo(i))
		if name then names[name] = true end
	end
	return names
end

-- This character's full name as the guild sees it. Forever names have two
-- words ("Boohbas Bonks"): the roster and addon messages use both, but
-- UnitName gives only the first, and first names are not unique (Zach
-- 6/11). Found by GUID in the roster, else by a single first-name match;
-- nil until the roster has loaded.
local myName
function ns.Me()
	if myName then return myName end
	local guid, first = UnitGUID("player"), UnitName("player")
	local match, count = nil, 0
	for i = 1, GetNumGuildMembers() do
		local info = { GetGuildRosterInfo(i) }
		local name = ns.Short(info[1])
		if name and guid and info[17] == guid then
			myName = name
			return name
		end
		if name and name:match("^(%S+)") == first then
			match, count = name, count + 1
		end
	end
	if count == 1 then
		myName = match
		return match
	end
end

local OnWhisper

-- A whisper to one member; to yourself it is handled at once. Returns
-- false when they are offline and nothing was sent.
function ns.SendTo(target, msg)
	if target == ns.Me() then
		OnWhisper(target, msg)
		return true
	end
	if not ns.Online(target) then return false end
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(ns.PREFIX, msg, "WHISPER", target)
	elseif SendAddonMessage then
		SendAddonMessage(ns.PREFIX, msg, "WHISPER", target)
	end
	return true
end

-- Standing from how long a debt has stood unpaid: no debt, or a debt
-- younger than 48 hours, is good; up to a week neutral; then negative.
-- debtSince is set only while at least 1 copper is owed.
function ns.Standing(m)
	if not m.debtSince then return "good" end
	local age = time() - m.debtSince
	if age <= ns.GOOD_HOURS * 3600 then return "good" end
	if age < ns.NEGATIVE_DAYS * 86400 then return "neutral" end
	return "negative"
end

ns.LABELS = {
	good = "|cff40ff40God|r",
	neutral = "|cffffd100Neutral|r",
	negative = "|cffff4040Negativ|r",
}

-- The hidden standing: the three longest unbroken runs in good standing
-- among members who have paid at least once, so a low level can beat a
-- high one (Zach 6/11). goodSince is when the run started.
function ns.TopPayers()
	local list, roster = {}, ns.RosterNames()
	for name, m in pairs(db.members) do
		if m.hasPaid and m.goodSince and ns.Standing(m) == "good" and (not roster or roster[name]) then
			table.insert(list, name)
		end
	end
	table.sort(list, function(a, b)
		local ga, gb = db.members[a].goodSince, db.members[b].goodSince
		if ga ~= gb then return ga < gb end
		return a < b
	end)
	local top = {}
	for i = 1, math.min(3, #list) do top[list[i]] = i end
	return top
end

function ns.TopLabel(place)
	return string.format("|cffff8000Skatteverkets favorit #%d|r", place)
end

-- /skatt is closed until the character is approved (Zach 7/11): signed,
-- and given the rank Medborgare or higher by the leader. "unsigned" or
-- "waiting" while closed, nil when open. The guild leader always gets in;
-- a guild without a Medborgare rank lets the signed in. Paying and the
-- help page stay open.
function ns.Locked()
	if IsGuildLeader() then return nil end
	if not (char and char.reg) then return "unsigned" end
	local citizen = ns.CitizenRankIndex()
	local _, _, rankIndex = GetGuildInfo("player")
	if citizen and rankIndex and rankIndex > citizen then return "waiting" end
	return nil
end

function ns.Changed()
	if ns.RefreshWindow then ns.RefreshWindow() end
end

-- Keep this character's own row in the list current.
function ns.UpdateSelf()
	if not char or not ns.InOurGuild() then return end
	local me = ns.Me()
	if not me then return end
	-- 0.6 and older kept this character under the first name only as well
	-- (Zach 6/11); drop that row unless someone in the guild has that name.
	local first = UnitName("player")
	if first ~= me and db.members[first] and ns.Online(first) == nil then db.members[first] = nil end
	local m = db.members[me] or { firstSeen = char.firstSeen }
	db.members[me] = m
	m.version, m.incomeTotal, m.paid, m.owed = ns.VERSION, char.incomeTotal, char.paid, char.owed
	m.lastDeposit, m.incomeSince, m.debtSince, m.lastSeen = char.lastDeposit or 0, char.incomeSince, char.debtSince, time()
	m.goodSince, m.hasPaid = char.goodSince, char.paid > 0
	ns.Changed()
end

-- The amounts, to the leader only. If the leader is offline they wait,
-- and go out when the roster shows the leader online.
local function SendPrivate()
	local leader = ns.Leader()
	privateDirty = true
	if not leader then return end
	local msg = string.format("P;%s;%d;%d;%d;%d;%d;%d;%d;%d", ns.VERSION,
		math.floor(char.incomeTotal), math.floor(char.paid), math.floor(char.owed),
		char.lastDeposit or 0, math.floor(char.incomeSince), db.rateStamp, char.debtSince or 0, char.goodSince or 0)
	if ns.SendTo(leader, msg) then privateDirty = false end
end

local function SendStatus()
	if not char or not ns.InOurGuild() then return end
	dirty = false
	ns.Send(string.format("T;%s;%d;%d;%d;%d", ns.VERSION, char.lastDeposit or 0, char.debtSince or 0,
		char.goodSince or 0, char.paid > 0 and 1 or 0))
	SendPrivate()
end
ns.SendStatus = SendStatus

local lastBoardRequest = 0
function ns.RequestBoard()
	if GetTime() - lastBoardRequest < 10 then return end
	lastBoardRequest = GetTime()
	ns.Send("B")
	if IsGuildLeader() then ns.Send("Q") end
end

-- What is owed, kept as dated slices oldest first, so a payment or credit
-- clears the oldest debt first and the clock runs from the oldest slice
-- still unpaid. A partial payment therefore only moves the clock as far as
-- it pays: a few copper now and then no longer keeps anyone in good
-- standing (review finding 6/11). Under 1 copper is not a debt and does
-- not age. Call after every change to char.owed.
local function Reconcile()
	local target = math.max(char.owed, 0)
	local now = time()
	if target < 1 then
		char.debts = target > 0 and { { t = now, amount = target } } or {}
		char.debtSince = nil
		return
	end
	local total = 0
	for _, d in ipairs(char.debts) do total = total + d.amount end
	if target > total then
		local last = char.debts[#char.debts]
		if last and now - last.t < 3600 then
			last.amount = last.amount + (target - total)
		else
			table.insert(char.debts, { t = now, amount = target - total })
		end
	else
		local cut = total - target
		while cut > 0 and char.debts[1] do
			local d = char.debts[1]
			if d.amount <= cut then
				cut = cut - d.amount
				table.remove(char.debts, 1)
			else
				d.amount = d.amount - cut
				cut = 0
			end
		end
	end
	char.debtSince = char.debts[1] and char.debts[1].t or now
end

local function AddIncome(copper)
	if copper <= 0 or not ns.InOurGuild() then return end
	char.incomeTotal = char.incomeTotal + copper
	char.incomeSince = char.incomeSince + copper
	char.owed = char.owed + copper * db.rate
	Reconcile()
	dirty = true
	ns.UpdateSelf()
end

-- Money that is never taxed: trades, player mail, the guild bank, quests.
local function Excluded()
	return tradeOpen or mailOpen or bankOpen or GetTime() < questUntil
end

local function InContext()
	local now = GetTime()
	return looting or now < lootGraceUntil or merchantOpen or now < moneyMsgUntil
end

-- Buying back an item sold to a vendor undoes the tax on that sale.
local function RemoveIncome(copper)
	if not copper or copper <= 0 or not ns.InOurGuild() then return end
	local back = math.min(copper, char.incomeTotal)
	char.incomeTotal = char.incomeTotal - back
	char.incomeSince = math.max(0, char.incomeSince - back)
	char.owed = char.owed - back * db.rate
	Reconcile()
	dirty = true
	ns.UpdateSelf()
end
if BuybackItem and GetBuybackItemInfo then
	hooksecurefunc("BuybackItem", function(index)
		if merchantOpen then RemoveIncome(select(3, GetBuybackItemInfo(index))) end
	end)
end

-- A deposit in flight: the amount and the gold carried before it. It counts
-- as paid once the gold has dropped by at least the amount, however late the
-- server confirms and whatever else changed in the same update; it is given
-- up only if the bank closes without that drop (review 6/11).
local function Deposit(manual)
	if not bankOpen or pendingDeposit or not ns.InOurGuild() then return end
	local owed = math.floor(char.owed)
	if owed < 1 then return end
	local amount = math.min(owed, GetMoney())
	if not manual then
		if db.autoBlocked then
			Print("du är skyldig " .. ns.Money(owed) .. ". Tryck Betala nu i /skatt.")
			return
		end
		-- Automatically only the whole tax, so nobody leaves the bank with
		-- empty bags (review 6/11); Betala nu pays what they can.
		if amount < owed then
			Print(string.format("du är skyldig %s men har bara %s på dig. Tryck Betala nu i /skatt för att betala det du kan.",
				ns.Money(owed), ns.Money(GetMoney())))
			return
		end
	end
	if amount < 1 then return end
	pendingDeposit = { amount = amount, before = GetMoney(), manual = manual }
	DepositGuildBankMoney(amount)
	ns.Changed()
end

function ns.Pay()
	if not bankOpen then Print("öppna guildbanken först.") return end
	if pendingDeposit then Print("en betalning pågår redan.") return end
	if math.floor(char.owed) < 1 then Print("du är inte skyldig något.") return end
	Deposit(true)
end

function ns.Paying()
	return pendingDeposit ~= nil
end

local function ConfirmDeposit()
	local amount = pendingDeposit.amount
	pendingDeposit = nil
	local wasGood = ns.Standing(char) == "good"
	char.paid = char.paid + amount
	char.owed = char.owed - amount
	char.incomeSince = 0
	char.lastDeposit = time()
	Reconcile()
	if not wasGood then char.goodSince = time() end
	Print(string.format("betalade %s till %s.", ns.Money(amount), ns.GUILD))
	if char.owed >= 1 then Print("kvar att betala: " .. ns.Money(char.owed)) end
	ns.UpdateSelf()
	SendStatus()
end

local function OnMoney()
	local now = GetMoney()
	if pendingDeposit and now <= pendingDeposit.before - pendingDeposit.amount then ConfirmDeposit() end
	if not lastMoney then lastMoney = now return end
	local delta = now - lastMoney
	lastMoney = now
	if delta <= 0 or Excluded() then return end
	if InContext() then
		AddIncome(delta)
	else
		-- Maybe looted money whose chat line has not arrived yet.
		unclaimed = { amount = delta, t = GetTime() }
	end
end

-- CHAT_MSG_MONEY: "You loot ..." or "Your share of the loot is ...".
local function OnLootMessage()
	if Excluded() then return end
	if unclaimed and GetTime() - unclaimed.t < 1 then
		AddIncome(unclaimed.amount)
		unclaimed = nil
	else
		moneyMsgUntil = GetTime() + 1
	end
end

-- Auction house sales arrive as mail with a seller invoice. Each mail
-- counts once until the inbox updates, so a double click is not taxed
-- twice while two identical sales both are (review 6/11).
local takenMail = {}
local function OnTakeMail(index)
	if not char or not ns.InOurGuild() or takenMail[index] then return end
	local _, _, _, _, money = GetInboxHeaderInfo(index)
	if not money or money <= 0 then return end
	local invoiceType = GetInboxInvoiceInfo and GetInboxInvoiceInfo(index)
	if invoiceType ~= "seller" then return end
	takenMail[index] = true
	AddIncome(money)
end
hooksecurefunc("TakeInboxMoney", OnTakeMail)
if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", OnTakeMail) end

-- The guild bank's balance, which the game gives only while the bank is
-- open (Zach 7/11). Not a member's own amount, so everyone may see it; it
-- always names who read it, since any client can send one.
local bankSendAt = 0
function ns.Now()
	return GetServerTime and GetServerTime() or time()
end

function ns.SendBank()
	local bank = db.bank
	if bank then ns.Send(string.format("V;%d;%d;%s", bank.amount, bank.at, bank.by or "")) end
end

local function ReadBank()
	if not bankOpen or not GetGuildBankMoney or not ns.InOurGuild() then return end
	local amount = GetGuildBankMoney()
	-- 0 before the bank has loaded; a guild bank that is truly empty shows as unread.
	if not amount or amount <= 0 then return end
	local changed = not db.bank or db.bank.amount ~= amount
	db.bank = { amount = amount, at = ns.Now(), by = ns.Me() or UnitName("player") }
	ns.Changed()
	-- One message a few seconds after the last change, and none for an unchanged balance.
	if changed then
		bankSendAt = GetTime() + 3
		C_Timer.After(3.1, function()
			if GetTime() >= bankSendAt then ns.SendBank() end
		end)
	end
end

local function OnBankBalance(sender, parts)
	local amount, at = tonumber(parts[2]), tonumber(parts[3])
	if not amount or not at or amount < 0 or at > ns.Now() + 300 then return end
	if db.bank and db.bank.at >= at then return end
	-- Only the leader may name another reader; anyone else is the reader.
	local by = sender
	if sender == ns.Leader() and parts[4] and parts[4] ~= "" then by = parts[4] end
	db.bank = { amount = amount, at = at, by = by }
	ns.Changed()
end

local function SetBank(shown)
	bankOpen = shown
	if shown then
		C_Timer.After(1, function() Deposit(false) end)
		C_Timer.After(2, ReadBank)
		if ns.OnBankOpened then ns.OnBankOpened() end
	elseif pendingDeposit then
		if GetMoney() <= pendingDeposit.before - pendingDeposit.amount then
			ConfirmDeposit()
		else
			Print("insättningen på " .. ns.Money(pendingDeposit.amount) .. " gick inte igenom. Tryck Betala nu i /skatt nästa gång du är vid guildbanken.")
			pendingDeposit = nil
		end
	end
	ns.Changed()
end

-- The game refused a deposit that no click started: from now on only
-- Betala nu pays, and this is said once (review 6/11).
local function OnBlocked(addon)
	if addon ~= "Skatteverket" or not pendingDeposit then return end
	local auto = not pendingDeposit.manual
	pendingDeposit = nil
	if auto and not db.autoBlocked then
		db.autoBlocked = true
		Print("spelet tillåter inte automatisk betalning. Tryck Betala nu i /skatt vid guildbanken.")
	end
	ns.Changed()
end

-- Newer clients report windows through the interaction manager.
local function Interaction(kind, shown)
	local T = Enum and Enum.PlayerInteractionType
	if not T then return end
	if kind == T.Merchant then merchantOpen = shown
	elseif kind == T.GuildBanker then SetBank(shown)
	elseif kind == T.MailInfo then mailOpen = shown
	elseif kind == T.TradePartner then tradeOpen = shown
	end
end

-- A chat line, plus a raid warning when it matters, when the debt is old.
local function Remind()
	if not char or not ns.InOurGuild() then return end
	local standing = ns.Standing(char)
	lastStanding = standing
	local text
	if standing == "negative" then
		text = "|cffff4040din skatt på " .. ns.Money(char.owed) .. " har varit obetald i över en vecka. Du har negativ ställning; besök guildbanken.|r"
	elseif standing == "neutral" then
		text = "din skatt på " .. ns.Money(char.owed) .. " har varit obetald i över 48 timmar. Besök guildbanken för att få tillbaka god ställning."
	elseif not char.lastDeposit and char.owed >= 1 then
		Print("du har inte betalat någon skatt än; du är skyldig " .. ns.Money(char.owed) .. ". Besök guildbanken.")
		return
	else
		return
	end
	Print(text)
	if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
		RaidNotice_AddMessage(RaidWarningFrame, "Skatteverket: obetald guildskatt", ChatTypeInfo["RAID_WARNING"])
	end
end

local function VersionNumber(v)
	local major, minor = tostring(v or ""):match("^(%d+)%.(%d+)")
	return major and (tonumber(major) * 1000 + tonumber(minor)) or 0
end

local function CheckVersion(v)
	if not warnedVersion and VersionNumber(v) > VersionNumber(ns.VERSION) then
		warnedVersion = true
		Print("det finns en nyare Skatteverket (" .. v .. "); be guildledaren om den. Din skattehistorik följer med.")
	end
end

local function OnPublic(sender, parts)
	CheckVersion(parts[2])
	if sender == ns.Me() then return end
	local m = db.members[sender] or { firstSeen = time() }
	db.members[sender] = m
	m.version = parts[2]
	m.lastDeposit = tonumber(parts[3]) or 0
	local debt, good = tonumber(parts[4]) or 0, tonumber(parts[5]) or 0
	m.debtSince = debt > 0 and debt or nil
	m.goodSince = good > 0 and good or nil
	m.hasPaid = parts[6] == "1"
	m.lastSeen = time()
	ns.Changed()
end

-- The standings of members who are offline now, from the guild leader.
local function OnBoard(parts)
	local me = ns.Me()
	for i = 2, #parts do
		local name, lastDeposit, debtSince, lastSeen, goodSince, hasPaid = strsplit(",", parts[i])
		lastSeen = tonumber(lastSeen)
		if name and lastSeen and name ~= me then
			local m = db.members[name]
			if not m or (m.lastSeen or 0) < lastSeen then
				m = m or { firstSeen = lastSeen }
				db.members[name] = m
				debtSince, goodSince = tonumber(debtSince) or 0, tonumber(goodSince) or 0
				m.lastDeposit, m.lastSeen = tonumber(lastDeposit) or 0, lastSeen
				m.debtSince = debtSince > 0 and debtSince or nil
				m.goodSince = goodSince > 0 and goodSince or nil
				m.hasPaid = hasPaid == "1"
			end
		end
	end
	ns.Changed()
end

-- The leader's copy is bigger than ours: this character's record was lost.
local function Restore(paid, lastDeposit)
	if not paid or paid <= char.paid then return end
	char.paid = paid
	char.lastDeposit = math.max(char.lastDeposit or 0, lastDeposit or 0)
	Print("din skattehistorik har återställts från guildledaren: " .. ns.Money(paid) .. " betalt totalt.")
	ns.UpdateSelf()
	SendStatus()
end

function ns.ApplyAdjustment(id, op, amount)
	if not id then return end
	if not char.applied[id] then
		char.applied[id] = true
		local wasGood = ns.Standing(char) == "good"
		if op == "F" then
			if char.owed > 0 then char.owed = 0 end
			Print("guildledaren har efterskänkt din skatteskuld.")
		elseif op == "C" and amount then
			char.owed = char.owed - amount
			Print("guildledaren gav dig " .. ns.Money(amount) .. " i skattekredit.")
		end
		Reconcile()
		if not wasGood and ns.Standing(char) == "good" then char.goodSince = time() end
		ns.UpdateSelf()
	end
	local leader = ns.Leader()
	if leader then ns.SendTo(leader, "K;" .. id) end
	SendStatus()
end

OnWhisper = function(sender, msg)
	local parts = { strsplit(";", msg) }
	local kind = parts[1]
	if IsGuildLeader() then
		if kind == "P" and ns.OnPrivate then ns.OnPrivate(sender, parts)
		elseif kind == "K" and ns.OnAck then ns.OnAck(sender, parts[2])
		elseif kind == "G" then ns.OnRegister(sender)
		end
	end
	if sender == ns.Leader() then
		if kind == "A" then ns.ApplyAdjustment(parts[2], parts[3], tonumber(parts[4]))
		elseif kind == "M" then Restore(tonumber(parts[2]), tonumber(parts[3]))
		elseif kind == "N" then ns.OnNumber(tonumber(parts[2]))
		end
	end
end

local function OnAddonMessage(prefix, msg, channel, sender)
	if prefix ~= ns.PREFIX or not char or not ns.InOurGuild() then return end
	sender = ns.Short(sender)
	if channel == "WHISPER" then
		OnWhisper(sender, msg)
		return
	end
	if channel ~= "GUILD" then return end
	local parts = { strsplit(";", msg) }
	local kind = parts[1]
	local fromLeader = sender == ns.Leader()
	if kind == "T" then
		OnPublic(sender, parts)
	elseif kind == "S" then
		-- A member still on 0.4 or older; it sends amounts openly.
		CheckVersion(parts[2])
	elseif kind == "B" then
		if ns.ServeBoard then ns.ServeBoard() end
	elseif kind == "Q" and fromLeader then
		C_Timer.After(math.random() * 5, SendStatus)
	elseif kind == "E" and fromLeader then
		OnBoard(parts)
	elseif kind == "V" and ns.Online(sender) ~= nil then
		OnBankBalance(sender, parts)
	elseif kind == "W" then
		ns.OnRecipes(sender, parts)
	elseif kind == "J" then
		ns.OnRecipeRequest(sender, parts[2])
	elseif kind == "U" and fromLeader then
		ns.OnRelayedRecipes(parts)
	elseif kind == "Y" then
		ns.OnProfile(sender, parts)
	elseif kind == "Z" and fromLeader then
		ns.OnProfileBoard(parts)
	elseif kind == "R" and fromLeader then
		local bp, stamp = tonumber(parts[2]), tonumber(parts[3])
		if bp and stamp and stamp > db.rateStamp then
			db.rate, db.rateStamp = bp / 10000, stamp
			Print(string.format("guildskatten är nu %g %%.", bp / 100))
			ns.Changed()
		end
	end
end

-- Bring data saved by an older version up to ns.SCHEMA. Never drop paid
-- totals or deposit dates here; they are what standing is judged on.
local function Migrate()
	if (db.schema or 1) < 2 then
		-- 0.1 had no debt clock: start it at the last deposit, or first sight.
		for _, m in pairs(db.members) do
			if (m.owed or 0) >= 1 and not m.debtSince then
				m.debtSince = (m.lastDeposit or 0) > 0 and m.lastDeposit or m.firstSeen or time()
			end
		end
		db.behindCopper, db.behindDays = nil, nil
	end
	if (db.schema or 1) < 4 then
		-- 0.5 judges standing by the debt clock alone and keeps "has paid" apart from amounts.
		for _, m in pairs(db.members) do
			if (m.owed or 0) < 1 then m.debtSince = nil end
			if m.hasPaid == nil then m.hasPaid = (m.paid or 0) > 0 end
		end
	end
	if (char.schema or 1) < 2 then
		if char.owed >= 1 and not char.debtSince then
			char.debtSince = char.lastDeposit or char.firstSeen
		end
	end
	if (char.schema or 1) < 3 then
		-- 0.3 had no streak: count it from the first deposit we know of.
		char.goodSince = char.goodSince or char.lastDeposit or char.firstSeen
	end
	if (char.schema or 1) < 4 then
		if char.owed < 1 then char.debtSince = nil end
	end
	if (char.schema or 1) < 5 then
		-- 0.9 kept one clock; what is owed becomes one slice dated by it.
		char.debts = char.owed >= 1 and { { t = char.debtSince or time(), amount = char.owed } } or {}
		Reconcile()
	end
	if (db.schema or 1) < 6 then
		-- 0.12 adds registration: skattenummer handed out from 1. Tax data
		-- stays as it is; everyone, old members too, signs the scroll once.
		db.nextNumber = db.nextNumber or 1
	end
	-- 0.15 keeps the guild bank's last known balance in db.bank, empty until
	-- someone reads it, and every member's recipes in db.recipes and this
	-- character's own in char.recipes (both made in Init).
	db.schema, char.schema = ns.SCHEMA, ns.SCHEMA
end

local function Init()
	SkatteverketDB = SkatteverketDB or {}
	db = SkatteverketDB
	db.rate = db.rate or 0.05
	db.rateStamp = db.rateStamp or 0
	db.members = db.members or {}
	db.pending = db.pending or {}
	db.recipes = db.recipes or {}
	SkatteverketCharDB = SkatteverketCharDB or {}
	char = SkatteverketCharDB
	char.incomeTotal = char.incomeTotal or 0
	char.incomeSince = char.incomeSince or 0
	char.paid = char.paid or 0
	char.owed = char.owed or 0
	char.firstSeen = char.firstSeen or time()
	char.applied = char.applied or {}
	char.debts = char.debts or {}
	char.recipes = char.recipes or {}
	ns.db, ns.char = db, char
	Migrate()
end

local events = CreateFrame("Frame")
for _, event in ipairs({
	"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_MONEY", "CHAT_MSG_MONEY", "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE",
	"LOOT_OPENED", "LOOT_CLOSED", "QUEST_FINISHED",
	"MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED",
	"GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANK_UPDATE_MONEY",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
	"MAIL_INBOX_UPDATE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}) do
	-- Not every client has every event; an unknown one would raise an error.
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "Skatteverket" then Init() end
	elseif not char then
		return
	elseif event == "PLAYER_LOGIN" then
		lastMoney = GetMoney()
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(ns.PREFIX) end
		ns.RequestRoster()
		C_Timer.After(15, function()
			ns.UpdateSelf()
			SendStatus()
			ns.RequestBoard()
			if IsGuildLeader() and ns.BroadcastRate then ns.BroadcastRate() end
		end)
		C_Timer.After(20, Remind)
		-- The roster says when the leader comes online; ask for it now and then.
		C_Timer.NewTicker(60, ns.RequestRoster)
		C_Timer.NewTicker(300, function()
			if dirty then SendStatus() end
			-- Remind again whenever the standing drops a step.
			local standing = ns.InOurGuild() and ns.Standing(char)
			if standing and standing ~= lastStanding and standing ~= "good" then Remind() end
			lastStanding = standing
		end)
	elseif event == "GUILD_ROSTER_UPDATE" then
		if privateDirty and ns.InOurGuild() then SendPrivate() end
		-- The full name of this character is known only once the roster is in.
		if ns.Me() and not (db.members[ns.Me()]) then ns.UpdateSelf() end
		if ns.OnEvent then ns.OnEvent(event, ...) end
	elseif event == "PLAYER_MONEY" then OnMoney()
	elseif event == "CHAT_MSG_MONEY" then OnLootMessage()
	elseif event == "CHAT_MSG_ADDON" then OnAddonMessage(...)
	elseif event == "LOOT_OPENED" then looting = true
	elseif event == "LOOT_CLOSED" then looting = false lootGraceUntil = GetTime() + 2
	elseif event == "QUEST_FINISHED" then questUntil = GetTime() + 2
	elseif event == "MERCHANT_SHOW" then merchantOpen = true
	elseif event == "MERCHANT_CLOSED" then merchantOpen = false
	elseif event == "MAIL_SHOW" then mailOpen = true
	elseif event == "MAIL_CLOSED" then mailOpen = false
	elseif event == "MAIL_INBOX_UPDATE" then wipe(takenMail)
	elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then OnBlocked(...)
	elseif event == "TRADE_SHOW" then tradeOpen = true
	elseif event == "TRADE_CLOSED" then tradeOpen = false
	elseif event == "GUILDBANKFRAME_OPENED" then SetBank(true)
	elseif event == "GUILDBANKFRAME_CLOSED" then SetBank(false)
	elseif event == "GUILDBANK_UPDATE_MONEY" then ReadBank()
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then Interaction(..., true)
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then Interaction(..., false)
	elseif ns.OnEvent then ns.OnEvent(event, ...)
	end
end)
ns.events = events

local LEADER_COMMANDS = { rate = true, forgive = true, credit = true, sync = true }

SLASH_SKATTEVERKET1 = "/skatt"
SlashCmdList.SKATTEVERKET = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	-- Swedish words, with the English ones of earlier versions still working.
	cmd = ({ betala = "pay", sats = "rate", ["efterskänk"] = "forgive", kredit = "credit", synka = "sync", lista = "list",
		["anmälan"] = "register", anmalan = "register", yrken = "professions",
		["hjälp"] = "help", hjalp = "help" })[cmd] or cmd
	if cmd == "" or cmd == "list" then
		ns.ToggleWindow()
	elseif cmd == "register" then
		ns.ShowScroll()
	elseif cmd == "help" then
		ns.ShowHelp()
	elseif cmd == "yrkestest" then
		ns.ProfessionTest()
	elseif cmd == "recepttest" then
		ns.RecipeTest()
	elseif cmd == "professions" then
		if not ns.InOurGuild() then Print("den här karaktären är inte med i " .. ns.GUILD .. ".") return end
		ns.ToggleWindow(2)
	elseif cmd == "info" then
		local locked = ns.Locked()
		if locked == "unsigned" then Print("anmäl dig till Skatteverket först: /skatt anmälan.") return end
		if locked == "waiting" then Print("din anmälan väntar på att guildledaren ger dig rangen " .. ns.CITIZEN_RANK .. ".") return end
		if not ns.InOurGuild() then Print("den här karaktären är inte med i " .. ns.GUILD .. ", inget beskattas.") return end
		Print(string.format("skattesats %g %%. Skyldig nu %s. Inkomst sedan senaste insättningen %s. Betalt totalt %s. Senaste insättning %s.",
			db.rate * 100, ns.Money(char.owed), ns.Money(char.incomeSince), ns.Money(char.paid),
			char.lastDeposit and date("%d/%m %H:%M", char.lastDeposit) or "aldrig"))
	elseif cmd == "pay" then
		ns.Pay()
	elseif LEADER_COMMANDS[cmd] then
		if not IsGuildLeader() then Print("bara guildledaren kan göra det.") return end
		ns.LeaderCommand(cmd, rest)
	else
		Print("/skatt öppnar fönstret, /skatt info visar din skatt, /skatt betala betalar vid guildbanken, /skatt anmälan visar din anmälan, /skatt yrken visar yrkesregistret, /skatt hjälp visar villkor och vanliga frågor.")
		Print("Guildledaren: /skatt sats 5, /skatt efterskänk Namn, /skatt kredit Namn 2g50s, /skatt synka.")
	end
end
