-- Skatteverket, the guild leader's side: takes in every member's amounts
-- (whispered, so nobody else sees them), sets the rate, forgives debt or
-- gives credit, serves the standings without amounts to members who log
-- in, restores a member's lost record, and reads the guild bank's money log.

local _, ns = ...

local lastRateBroadcast, lastBoard = 0, 0

function ns.BroadcastRate()
	local db = ns.db
	lastRateBroadcast = GetTime()
	ns.Send(string.format("R;%d;%d", math.floor(db.rate * 10000 + 0.5), db.rateStamp))
end

-- Sent only while the member is online; waiting ones go again with their next figures.
local function SendAdjustment(name, adj)
	ns.SendTo(name, string.format("A;%s;%s;%d", adj.id, adj.op, adj.amount))
end

-- P;version;income total;paid;owed;last deposit;income since;rate stamp;debt since;good since
function ns.OnPrivate(sender, parts)
	-- Only from people in the guild, so strangers cannot add rows (review 6/11).
	if not IsGuildLeader() or ns.Online(sender) == nil then return end
	local db = ns.db
	local m = db.members[sender] or { firstSeen = time() }
	db.members[sender] = m
	local paid = tonumber(parts[4]) or 0
	if (m.paid or 0) > paid and sender ~= ns.Me() then
		-- Their saved data was lost; send ours back and keep it until they answer.
		ns.SendTo(sender, string.format("M;%d;%d", m.paid, m.lastDeposit or 0))
	else
		m.version = parts[2]
		m.incomeTotal = tonumber(parts[3]) or 0
		m.paid = paid
		m.owed = tonumber(parts[5]) or 0
		m.lastDeposit = tonumber(parts[6]) or 0
		m.incomeSince = tonumber(parts[7]) or 0
		local debt, good = tonumber(parts[9]) or 0, tonumber(parts[10]) or 0
		m.debtSince = debt > 0 and debt or nil
		m.goodSince = good > 0 and good or nil
		m.hasPaid = paid > 0
	end
	m.lastSeen = time()
	if (tonumber(parts[8]) or 0) < db.rateStamp and GetTime() - lastRateBroadcast > 30 then
		ns.BroadcastRate()
	end
	for _, adj in ipairs(db.pending[sender] or {}) do
		SendAdjustment(sender, adj)
	end
	ns.Changed()
end

function ns.OnAck(sender, id)
	local list = ns.db.pending[sender]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i].id == id then table.remove(list, i) end
	end
	if #list == 0 then ns.db.pending[sender] = nil end
end

-- Everyone's standing without amounts, in messages under the 255 byte
-- limit, a little apart.
function ns.ServeBoard()
	if not IsGuildLeader() or GetTime() - lastBoard < 30 then return end
	lastBoard = GetTime()
	local chunks, chunk, length = {}, {}, 2
	local roster = ns.RosterNames()
	for name, m in pairs(ns.db.members) do
		-- Only people in the guild now.
		if not roster or roster[name] then
			local row = string.format("%s,%d,%d,%d,%d,%d", name, m.lastDeposit or 0, m.debtSince or 0,
				m.lastSeen or 0, m.goodSince or 0, m.hasPaid and 1 or 0)
			if length + #row + 1 > 250 then
				table.insert(chunks, "E;" .. table.concat(chunk, ";"))
				chunk, length = {}, 2
			end
			table.insert(chunk, row)
			length = length + #row + 1
		end
	end
	if #chunk > 0 then table.insert(chunks, "E;" .. table.concat(chunk, ";")) end
	for i, msg in ipairs(chunks) do
		C_Timer.After(i * 0.3, function() ns.Send(msg) end)
	end
end

-- The exact member or roster name for what the leader typed.
local function FindName(typed)
	typed = typed:lower()
	for name in pairs(ns.db.members) do
		if name:lower() == typed then return name end
	end
	for i = 1, GetNumGuildMembers() do
		local name = ns.Short(GetGuildRosterInfo(i))
		if name and name:lower() == typed then return name end
	end
end

-- op "F" clears the debt, "C" gives amount copper of credit.
function ns.Adjust(name, op, amount)
	local db = ns.db
	local adj = { id = string.format("%d%03d", time(), math.random(999)), op = op, amount = amount or 0 }
	db.pending[name] = db.pending[name] or {}
	table.insert(db.pending[name], adj)
	local m = db.members[name]
	if m and m.owed then
		if op == "F" and m.owed > 0 then m.owed = 0 end
		if op == "C" then m.owed = m.owed - adj.amount end
		if m.owed < 1 then m.debtSince = nil end
	end
	ns.Print(string.format("%s för %s skickad; gäller när de är online.",
		op == "F" and "Efterskänkning" or "Kredit på " .. ns.Money(adj.amount), name))
	SendAdjustment(name, adj)
	ns.Changed()
end

-- The guild bank keeps only the latest money transactions; sum the deposits in it.
function ns.OnBankOpened()
	if not IsGuildLeader() or not QueryGuildBankLog then return end
	pcall(ns.events.RegisterEvent, ns.events, "GUILDBANKLOG_UPDATE")
	QueryGuildBankLog((MAX_GUILDBANK_TABS or 6) + 1)
end

function ns.OnEvent(event)
	if event == "GUILDBANKLOG_UPDATE" and GetNumGuildBankMoneyTransactions then
		-- Loan repayments land in the same log; leave out every deposit that
		-- matches a Swedbank guild bank payment (same name and amount within
		-- two days) when Swedbank is on this account too (review 6/11).
		local repayments = {}
		for _, loan in pairs(SwedbankDB and SwedbankDB.loans or {}) do
			for _, p in ipairs(loan.payments or {}) do
				if p.via == "bank" then table.insert(repayments, { name = loan.borrower, amount = p.amount, t = p.t }) end
			end
		end
		local sums, now = {}, time()
		for i = 1, GetNumGuildBankMoneyTransactions() do
			local kind, name, amount, years, months, days, hours = GetGuildBankMoneyTransaction(i)
			if kind == "deposit" and name then
				name = ns.Short(name)
				local t = now - (((years or 0) * 365 + (months or 0) * 30 + (days or 0)) * 24 + (hours or 0)) * 3600
				local loan
				for j, r in ipairs(repayments) do
					if r.name == name and r.amount == amount and math.abs(r.t - t) < 2 * 86400 then
						loan = table.remove(repayments, j)
						break
					end
				end
				if not loan then sums[name] = (sums[name] or 0) + amount end
			end
		end
		ns.db.bankLog = { readAt = now, sums = sums }
		ns.Changed()
	elseif event == "GUILD_ROSTER_UPDATE" then
		ns.Changed()
	end
end

function ns.LeaderCommand(cmd, rest)
	local db = ns.db
	if cmd == "sync" then
		ns.Send("Q")
		ns.Print("bad alla som är online om sina siffror.")
	elseif cmd == "rate" then
		local percent = tonumber((rest:gsub(",", ".")))
		if not percent or percent < 0 or percent > 100 then ns.Print("så här: /skatt sats 5") return end
		db.rate, db.rateStamp = percent / 100, time()
		ns.BroadcastRate()
		ns.Print(string.format("skattesatsen är nu %g %%, skickad till alla som är online.", percent))
		ns.Changed()
	elseif cmd == "forgive" then
		local name = FindName(rest)
		if not name then ns.Print("ingen medlem som heter " .. rest .. ".") return end
		ns.Adjust(name, "F", 0)
	elseif cmd == "credit" then
		-- The amount is the last word; the name before it may be two words.
		local typed, amountText = rest:match("^(.-)%s+(%S+)$")
		local name, amount = typed and FindName(typed), ns.ParseMoney(amountText)
		if not name or not amount then ns.Print("så här: /skatt kredit Namn 2g50s") return end
		ns.Adjust(name, "C", amount)
	end
end
