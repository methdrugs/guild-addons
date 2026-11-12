-- Skatteverket: Folkvald representant (Zach 11/11; its own entry under
-- THÖNDERSTÖRM since 12/11, Intresseanmälan gone). The
-- guild's top roles, each described by what it does; the title is only an
-- example, and whoever applies may suggest a better one. A member applies
-- with a required "varför just jag" (200 characters), one application at a
-- time; a held role can be challenged. The guild leader alone sees the
-- applications. Places are decided by an anonymous vote: the first round
-- has an application period and a voting period (Thursday to Saturday
-- afternoon, then to Sunday evening), later the leader starts a vote for a
-- role, and an accepted challenge opens a three-day vote between holder
-- and challenger, with a raid warning to the holder that says only that
-- someone challenges. Votes go by whisper to the leader, whose saved data
-- keeps only the totals and which accounts have voted, never who voted
-- for whom; one vote per account. One candidate gets a yes/no vote, as
-- does each where the candidates are no more than the seats; ties are the
-- leader's to break. The ballot, with every candidate's reason, and the
-- results are official information for all members.
--
-- Guild channel, from the leader:
--   FR;stamp;application end;vote end;ballots made   the round, 0;0 for none
--   FS;stamp;role;name,name          who holds a role
--   FB;id;role;kind;ends;holder;candidates   a ballot: kind P (pick one) or J (yes/no each)
--   FC;id;name;i;n;title~reason      a candidate on it, in pieces
--   FT;id;winner,winner;name=count,...  a ballot's result (yes/no as name=yes/no)
--   FO;text                          a raid warning to everyone online
-- Guild channel, from anyone:
--   FQ                               ask the leader for all of the above
-- Whispers to the leader:
--   FA;role;challenge;target;i;n;title~reason   an application, in pieces
--   FV;key;choice;time               a vote; key is the ballot id, or id/name for yes/no
-- Whispers from the leader:
--   FN;clear;text                    a note for the member's to-do; clear 1 ends their application
--   FW;role                          you are being challenged (a raid warning)
-- Whispers to the leader, also:
--   FX;role                          I resign (Avgå)
-- Socialbidrag (FG, FH) is in Bidrag.lua; the tickets of Kontakta oss! and
-- Kontakta mig! (FK, FY, FZ, FP to the leader; FE, FJ, FD from him) in Contact.lua.

local _, ns = ...

-- The roles (Zach 11/11): the duty is what the role entitles; the title is
-- an example. Testpilot has three seats, every other role one.
ns.ROLES = {
	{ id = "skatt", title = "Generaldirektör för Skatteverket", seats = 1,
		duty = "Följer upp obetald skatt, svarar på frågor om Skatt och föreslår ändringar." },
	{ id = "swed", title = "VD för Swedbank", seats = 1,
		duty = "Sköter frågor om lån, följer upp återbetalningar och föreslår villkor." },
	{ id = "yrken", title = "Näringsminister", seats = 1,
		duty = "Ser till att varje yrke har hantverkare, får arbetsordrar att röra sig och hjälper nya hantverkare." },
	{ id = "bok", title = "Finansmarknadsminister", seats = 1,
		duty = "Håller koll på auktionshuset och priserna och tipsar om vad som lönar sig att tillverka och sälja." },
	{ id = "rekryt", title = "Arbetsmarknadsminister", seats = 1,
		duty = "Hittar och välkomnar nya medlemmar och svarar på deras frågor första veckan." },
	{ id = "infra", title = "Riksarkitekt", seats = 1,
		duty = "Bygger och sköter guildets kommunikationsplattform: text- och röstkanaler, behörigheter, struktur och bottar." },
	{ id = "ob", title = "Överbefälhavare", seats = 1,
		duty = "Planerar och leder raider, sätter tider och sköter raidens sammansättning." },
	{ id = "utb", title = "Utbildningsminister", seats = 1,
		duty = "Skriver och håller guiderna till guildets addons uppdaterade." },
	{ id = "press", title = "Pressansvarig", seats = 1,
		duty = "Sköter utskick och representerar guildet utåt." },
	{ id = "test", title = "Testpilot", seats = 3,
		duty = "Provar nya versioner innan de släpps och rapporterar det som går sönder." },
}

-- The guild leader on top of the list (Zach 12/11): not elected, never in
-- a round, only to contact.
ns.LEADER_ROLE = { id = "gl", title = "Teamleader, utvecklare och framtidsspekulant", seats = 1,
	duty = "Leder guildet, bygger THÖNDERSTÖRM-addonsen och tänker på skatten." }

-- Tickets for these go to the leader only, not the holders (Zach 12/11:
-- Testpilot's three seats).
ns.TO_LEADER = { gl = true, test = true }
local ROLE = {}
for _, r in ipairs(ns.ROLES) do ROLE[r.id] = r end
ns.ROLE = ROLE

local REASON_MAX, TITLE_MAX = 200, 40
local CHALLENGE_DAYS = 3
local PIECE = 150
local DAYS = { "sön", "mån", "tis", "ons", "tor", "fre", "lör" }

-- Saved data ------------------------------------------------------------

-- Account-wide: what the leader has said (holders, the round, ballots),
-- the votes this account has cast, and on the leader's account the
-- applications, the totals and what waits for members who are offline.
local function F()
	local db = ns.db
	db.folk = db.folk or {}
	local f = db.folk
	f.holders = f.holders or {}
	f.holderStamp = f.holderStamp or {}
	f.round = f.round or { stamp = 0 }
	f.ballots = f.ballots or {}
	f.myVotes = f.myVotes or {}
	f.apps = f.apps or {}
	f.tally = f.tally or {}
	f.to = f.to or {}
	return f
end
ns.Folk = F

-- This character: its application, the notes on its to-do, and what waits
-- for the leader to come online.
local function C()
	local c = ns.char
	c.folk = c.folk or {}
	c.folk.notices = c.folk.notices or {}
	c.folk.out = c.folk.out or {}
	return c.folk
end
ns.FolkChar = C

-- Text ------------------------------------------------------------------

local function Len(text)
	local _, n = (text or ""):gsub("[^\128-\191]", "")
	return n
end
ns.Len = Len

-- The first max characters, never cutting a letter in two.
local function Cut(text, max)
	if Len(text) <= max then return text end
	local n, i = 0, 1
	while i <= #text do
		local b = text:byte(i)
		if b < 128 or b >= 192 then
			n = n + 1
			if n > max then break end
		end
		i = i + 1
	end
	return text:sub(1, i - 1)
end

-- Free text for a message: no field separators, no escape codes, no line
-- breaks, at most max characters.
function ns.CleanText(text, max)
	text = (text or ""):gsub("[\r\n]+", " "):gsub(";", ","):gsub("~", "-"):gsub("|", "/")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	return Cut(text, max)
end

-- Pieces of at most PIECE bytes, cut between letters.
local function Pieces(text)
	local out = {}
	while #text > PIECE do
		local cut = PIECE
		while cut > 1 do
			local b = text:byte(cut + 1)
			if not b or b < 128 or b >= 192 then break end
			cut = cut - 1
		end
		table.insert(out, text:sub(1, cut))
		text = text:sub(cut + 1)
	end
	table.insert(out, text)
	return out
end

-- "lör 14/11 14:00"
function ns.When(t)
	if not t or t <= 0 then return "?" end
	return DAYS[tonumber(date("%w", t)) + 1] .. " " .. date("%d/%m %H:%M", t)
end

-- "14/11 14:00" as a time this year, or nil.
local function ParseWhen(text)
	local d, mo, h, mi = (text or ""):match("^%s*(%d+)/(%d+)%s+(%d+):(%d+)%s*$")
	if not d then return nil end
	return time({ year = tonumber(date("%Y")), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi) })
end

-- Sending ---------------------------------------------------------------

-- One message every quarter second, so a burst never trips the client's
-- limit (rules: low traffic, spaced chunks).
local queue, draining = {}, false
local function Drain()
	local m = table.remove(queue, 1)
	if not m then draining = false return end
	if m.to then ns.SendTo(m.to, m.msg) else ns.Send(m.msg) end
	C_Timer.After(0.25, Drain)
end

local function Queue(msg, to)
	table.insert(queue, { msg = msg, to = to })
	if not draining then
		draining = true
		C_Timer.After(0.05, Drain)
	end
end
ns.FolkQueue = Queue

ns.FolkPieces = Pieces
-- kind;head;i;n;piece for each piece of text.
local function SendLong(kind, head, text, to)
	local pieces = Pieces(text or "")
	for i, p in ipairs(pieces) do
		Queue(string.format("%s;%s;%d;%d;%s", kind, head, i, #pieces, p), to)
	end
end
ns.SendLong = SendLong

-- Pieces put back together; calls done(head fields, text) once all are in.
local buffers = {}
local function Receive(sender, parts, done)
	local n, i = tonumber(parts[#parts - 1]), tonumber(parts[#parts - 2])
	if not n or not i or n < 1 or n > 20 then return end
	local head = {}
	for k = 2, #parts - 3 do head[#head + 1] = parts[k] end
	local key = sender .. ";" .. parts[1] .. ";" .. table.concat(head, ";")
	local b = buffers[key]
	if not b or b.n ~= n then
		b = { n = n, got = 0, pieces = {} }
		buffers[key] = b
	end
	if not b.pieces[i] then
		b.pieces[i] = parts[#parts]
		b.got = b.got + 1
	end
	if b.got == n then
		buffers[key] = nil
		done(head, table.concat(b.pieces))
	end
end
ns.ReceiveLong = Receive

-- To the leader, now if online, else when he next is: kept in this
-- character's saved data until then.
local function FlushOut()
	local c = ns.char and C()
	if not c or #c.out == 0 then return end
	local leader, online = ns.Leader()
	if not leader or not online then return end
	local out = c.out
	c.out = {}
	for _, m in ipairs(out) do
		if m.text then SendLong(m.kind, m.head, m.text, leader) else Queue(m.kind .. ";" .. m.head, leader) end
	end
end

function ns.ToLeader(kind, head, text)
	table.insert(C().out, { kind = kind, head = head, text = text })
	FlushOut()
	local _, online = ns.Leader()
	return online
end

-- Leader to a member, kept on the leader's account while they are offline.
local function FlushTo()
	if not IsGuildLeader() or not ns.db then return end
	local f = F()
	for name, list in pairs(f.to) do
		local online = ns.Online(name)
		if online == nil then
			f.to[name] = nil
		elseif online then
			f.to[name] = nil
			for _, msg in ipairs(list) do Queue(msg, name) end
		end
	end
end

function ns.ToMember(name, msg)
	local f = F()
	f.to[name] = f.to[name] or {}
	table.insert(f.to[name], msg)
	FlushTo()
end

local function Note(name, text, clear)
	ns.ToMember(name, string.format("FN;%d;%s", clear and 1 or 0, ns.CleanText(text, 200)))
end
ns.FolkNote = Note

local function Warn(text)
	if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
		RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
	end
	if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
	ns.Print(text)
end
ns.RaidWarn = Warn

local function Changed()
	ns.RefreshWindow("folk")
	ns.RefreshTodo()
end

-- The round and ballots -------------------------------------------------

local function Account(name)
	if name == ns.Me() then return ns.db.account end
	local m = ns.db.members[name]
	return m and m.account or name
end
ns.Account = Account

-- "ans" while applications are open, "val" while the round's vote runs,
-- "slut" once it has ended until the leader has settled it, nil for none.
function ns.RoundPhase()
	local r = F().round
	if not r.appEnd or r.appEnd == 0 then return nil end
	local now = ns.Now()
	if now < r.appEnd then return "ans" end
	if now < r.voteEnd then return "val" end
	if not r.done then return "slut" end
end

local function Holders(role)
	return F().holders[role] or {}
end
ns.Holders = Holders

function ns.HoldsRole(name)
	for id, list in pairs(F().holders) do
		for _, n in ipairs(list) do
			if n == name then return id end
		end
	end
end

-- The open ballot for a role, or the last unsettled one.
local function BallotFor(role)
	local best
	for id, b in pairs(F().ballots) do
		if b.role == role and not b.result and (not best or b.ends > best.ends) then best = b best.id = id end
	end
	return best
end
ns.BallotFor = BallotFor

local function Complete(b)
	return b.order and #b.order == b.n
end
ns.BallotComplete = Complete

-- Keys a voter votes on: the ballot, or each candidate on a yes/no ballot.
function ns.VoteKeys(b)
	if b.kind == "P" then return { b.id } end
	local keys = {}
	for _, name in ipairs(b.order or {}) do keys[#keys + 1] = b.id .. "/" .. name end
	return keys
end

local function Voted(b)
	local mine = F().myVotes
	for _, key in ipairs(ns.VoteKeys(b)) do
		if mine[key] then return true end
	end
	return false
end
ns.Voted = Voted

local function BroadcastRound()
	local r = F().round
	ns.Send(string.format("FR;%d;%d;%d;%d", r.stamp or 0, r.appEnd or 0, r.voteEnd or 0, r.made and 1 or 0))
end

local function BroadcastHolders(role)
	local f = F()
	ns.Send(string.format("FS;%d;%s;%s", f.holderStamp[role] or 0, role, table.concat(Holders(role), ",")))
end

local function BroadcastBallot(id)
	local b = F().ballots[id]
	if not b then return end
	Queue(string.format("FB;%s;%s;%s;%d;%s;%d", id, b.role, b.kind, b.ends, b.holder or "", #b.order))
	for _, name in ipairs(b.order) do
		local c = b.cands[name]
		SendLong("FC", id .. ";" .. name, (c.title or "") .. "~" .. (c.reason or ""))
	end
	if b.result then
		local counts = {}
		for name, v in pairs(b.result.counts) do counts[#counts + 1] = name .. "=" .. v end
		Queue(string.format("FT;%s;%s;%s", id, table.concat(b.result.winners, ","), table.concat(counts, ",")))
	end
end

-- Everything, for a member who asks (at most once a minute).
local servedAt = 0
local function Serve()
	if not IsGuildLeader() or GetTime() - servedAt < 60 then return end
	servedAt = GetTime()
	BroadcastRound()
	for _, r in ipairs(ns.ROLES) do Queue(string.format("FS;%d;%s;%s", F().holderStamp[r.id] or 0, r.id, table.concat(Holders(r.id), ","))) end
	local now = ns.Now()
	for id, b in pairs(F().ballots) do
		-- Open ballots, and results of the last week.
		if not b.result or now - (b.result.at or 0) < 7 * 86400 then BroadcastBallot(id) end
	end
end

-- Leader: a new ballot from the applications to a role.
local function MakeBallot(role, ends, apps, holder)
	local f = F()
	local id = role .. "." .. ns.Now()
	local b = { role = role, ends = ends, holder = holder, cands = {}, order = {} }
	if holder then
		b.cands[holder] = { title = "", reason = "Nuvarande innehavare." }
		table.insert(b.order, holder)
	end
	for _, a in ipairs(apps) do
		if not b.cands[a.name] then
			b.cands[a.name] = { title = a.title, reason = a.reason }
			table.insert(b.order, a.name)
		end
		f.apps[a.name] = nil
		Note(a.name, string.format("Din ansökan till %s är med i omröstningen, som pågår till %s.", ROLE[role].title, ns.When(ends)), true)
	end
	b.n = #b.order
	-- A challenge is always holder against challenger; otherwise yes/no
	-- when there are no more candidates than seats (Zach 11/11).
	b.kind = (not holder and #b.order <= ROLE[role].seats) and "J" or "P"
	b.id = id
	f.ballots[id] = b
	BroadcastBallot(id)
	return b
end

local function AppsFor(role, challenge)
	local list = {}
	for name, a in pairs(F().apps) do
		if a.role == role and (challenge == nil or (a.challenge and true or false) == challenge) then
			a.name = name
			table.insert(list, a)
		end
	end
	table.sort(list, function(x, y) return (x.at or 0) < (y.at or 0) end)
	return list
end
ns.AppsFor = AppsFor

-- Leader: at the round's application end, every role with applications
-- gets its ballot. A role nobody applied for goes vacant, held or not:
-- everyone applies again, holders too (Zach 12/11).
local function MakeRound()
	local f = F()
	local r = f.round
	if r.made or not r.appEnd or ns.Now() < r.appEnd then return end
	r.made = true
	local opened = {}
	for _, role in ipairs(ns.ROLES) do
		local apps = AppsFor(role.id)
		if #apps > 0 then
			MakeBallot(role.id, r.voteEnd, apps)
			table.insert(opened, role.title)
		elseif #(f.holders[role.id] or {}) > 0 then
			ns.SetHolders(role.id, {})
		end
	end
	r.stamp = ns.Now()
	BroadcastRound()
	if #opened > 0 then
		local text = "Folkvald representant: röstningen är öppen till " .. ns.When(r.voteEnd) .. ". Rösta under Folkvald representant."
		Queue("FO;" .. text)
		Warn(text)
	end
	Changed()
end

function ns.StartRound(appText, voteText)
	if not IsGuildLeader() then return end
	local appEnd, voteEnd = ParseWhen(appText), ParseWhen(voteText)
	if not appEnd or not voteEnd then ns.Print("skriv tiderna som 14/11 14:00.") return end
	if appEnd <= ns.Now() or voteEnd <= appEnd then ns.Print("ansökan måste stänga i framtiden och röstningen efter den.") return end
	local f = F()
	f.round = { stamp = ns.Now(), appEnd = appEnd, voteEnd = voteEnd }
	BroadcastRound()
	local text = "Folkvald representant: sök en roll under Folkvald representant till " .. ns.When(appEnd) .. ". Röstning till " .. ns.When(voteEnd) .. ". Alla söker, även den som har en roll i dag."
	Queue("FO;" .. text)
	Warn(text)
	-- In guild chat too, so the Discord bot passes it on (Zach 12/11).
	SendChatMessage(text, "GUILD")
	Changed()
end

-- Defaults for the first round (Zach 11/11): applications to Saturday
-- afternoon, the vote to Sunday evening.
function ns.DefaultRoundTimes()
	local t = date("*t")
	local ahead = (7 - t.wday) % 7
	if ahead == 0 and t.hour >= 14 then ahead = 7 end
	local sat = time({ year = t.year, month = t.month, day = t.day + ahead, hour = 14, min = 0 })
	local sun = time({ year = t.year, month = t.month, day = t.day + ahead + 1, hour = 20, min = 0 })
	return date("%d/%m %H:%M", sat), date("%d/%m %H:%M", sun)
end

-- Leader: a vote for one role now, three days, from its applications.
function ns.StartRoleVote(role)
	local apps = AppsFor(role, false)
	if #apps == 0 then return end
	local ends = ns.Now() + CHALLENGE_DAYS * 86400
	MakeBallot(role, ends, apps)
	local text = string.format("Folkvald representant: omröstning om %s till %s. Rösta under Folkvald representant.", ROLE[role].title, ns.When(ends))
	Queue("FO;" .. text)
	Warn(text)
	Changed()
end

-- Leader: a challenge accepted. Holder against challenger for three days;
-- the holder gets a raid warning that says only that someone challenges
-- (Zach 11/11), the guild one that the vote is open.
function ns.AcceptChallenge(name)
	local a = F().apps[name]
	if not a or not a.challenge then return end
	a.name = name
	local holder = a.target
	local still = false
	for _, h in ipairs(Holders(a.role)) do
		if h == holder then still = true end
	end
	if not still then
		F().apps[name] = nil
		Note(name, "Din utmaning gäller inte längre: " .. (holder or "?") .. " har inte platsen som " .. ROLE[a.role].title .. ".", true)
		Changed()
		return
	end
	local ends = ns.Now() + CHALLENGE_DAYS * 86400
	MakeBallot(a.role, ends, { a }, holder)
	ns.ToMember(holder, "FW;" .. a.role)
	local text = string.format("Folkvald representant: platsen som %s är utmanad. Rösta under Folkvald representant till %s.", ROLE[a.role].title, ns.When(ends))
	Queue("FO;" .. text)
	Warn(text)
	Changed()
end

function ns.DeclineApp(name)
	local a = F().apps[name]
	if not a then return end
	F().apps[name] = nil
	Note(name, string.format("Din %s till %s avböjdes av guildledaren.", a.challenge and "utmaning" or "ansökan", ROLE[a.role].title), true)
	Changed()
end

-- Leader: a holder placed by hand (the drop-down).
function ns.SetHolders(role, names)
	local f = F()
	-- The role's open tickets follow the seat (Zach 12/11).
	if ns.TicketsHandover then ns.TicketsHandover(role, f.holders[role] or {}, names) end
	f.holders[role] = names
	f.holderStamp[role] = ns.Now()
	BroadcastHolders(role)
	Changed()
end

-- Leader: the totals of a ballot, and the winners by the rules; tied at
-- the last seat are left for him.
function ns.Totals(b)
	local tally = F().tally
	local counts, winners, tied = {}, {}, {}
	if b.kind == "J" then
		for _, name in ipairs(b.order) do
			local t = tally[b.id .. "/" .. name]
			local yes, no = t and t.counts.J or 0, t and t.counts.N or 0
			counts[name] = yes .. "/" .. no
			if yes > no then table.insert(winners, name) elseif yes == no and yes > 0 then table.insert(tied, name) end
		end
	else
		local t = tally[b.id]
		local list = {}
		for _, name in ipairs(b.order) do
			counts[name] = t and t.counts[name] or 0
			table.insert(list, name)
		end
		table.sort(list, function(x, y) return counts[x] > counts[y] end)
		local seats = b.holder and 1 or ROLE[b.role].seats
		local cut = counts[list[seats]]
		for i, name in ipairs(list) do
			if counts[name] > 0 then
				if i <= seats and counts[name] ~= cut then table.insert(winners, name)
				elseif counts[name] == cut then table.insert(tied, name) end
			end
		end
		-- Nobody tied with the last seat: it is simply won.
		if #tied > 0 and #winners + #tied <= seats then
			for _, name in ipairs(tied) do table.insert(winners, name) end
			tied = {}
		end
	end
	return counts, winners, tied
end

-- Leader: settle a ballot with the winners he confirmed.
function ns.Settle(id, winners)
	local f = F()
	local b = f.ballots[id]
	if not b or b.result then return end
	local counts = ns.Totals(b)
	b.result = { winners = winners, counts = counts, at = ns.Now() }
	local holders = {}
	if b.holder then
		-- A challenge: the challenger takes the holder's seat, or not.
		for _, h in ipairs(Holders(b.role)) do
			if h == b.holder and winners[1] and winners[1] ~= b.holder then h = winners[1] end
			table.insert(holders, h)
		end
	else
		for _, w in ipairs(winners) do table.insert(holders, w) end
	end
	ns.SetHolders(b.role, holders)
	BroadcastBallot(id)
	for _, name in ipairs(b.order) do
		local won = false
		for _, w in ipairs(winners) do
			if w == name then won = true end
		end
		if name ~= b.holder or not won then
			Note(name, string.format("Folkvald representant: %s. %s", ROLE[b.role].title,
				won and "Grattis, du är vald!" or "Du blev inte vald den här gången."), false)
		end
	end
	local text = string.format("Folkvald representant: %s: %s.", ROLE[b.role].title, #winners > 0 and table.concat(winners, ", ") or "ingen vald")
	Queue("FO;" .. text)
	Warn(text)
	-- The round is done when all its ballots are settled.
	local r = f.round
	if r.made and not r.done then
		local open = false
		for _, other in pairs(f.ballots) do
			if other.ends == r.voteEnd and not other.result then open = true end
		end
		if not open then
			r.done = true
			r.stamp = ns.Now()
			BroadcastRound()
		end
	end
	Changed()
end

-- Member side -----------------------------------------------------------

function ns.MyApp()
	return C().app
end

-- Apply (or challenge target). Returns false with a reason when it cannot.
function ns.Apply(role, reason, title, target)
	reason = ns.CleanText(reason, REASON_MAX)
	title = ns.CleanText(title, TITLE_MAX)
	if Len(reason) < 10 then return false, "skriv varför just du passar, minst några ord." end
	local c = C()
	if c.app then return false, "du har redan en ansökan inne." end
	c.app = { role = role, at = ns.Now(), challenge = target and true or nil, target = target }
	local online = ns.ToLeader("FA", string.format("%s;%d;%s", role, target and 1 or 0, target or ""), title .. "~" .. reason)
	ns.Print(string.format("din %s till %s är %s.", target and "utmaning" or "ansökan", ROLE[role].title,
		online and "skickad till guildledaren" or "sparad och skickas när guildledaren är online"))
	Changed()
	return true
end

function ns.Vote(b, key, choice)
	local mine = F().myVotes
	if mine[key] or ns.Now() >= b.ends then return end
	mine[key] = choice
	ns.ToLeader("FV", string.format("%s;%s;%d", key, choice, ns.Now()))
	Changed()
end

-- The to-do: votes not yet cast, and notes from the leader; for the
-- leader applications, challenges and ballots to settle.
function ns.FolkTodo()
	local out = {}
	if not ns.db or not ns.InOurGuild() then return out end
	local f, now = F(), ns.Now()
	local unvoted = 0
	for _, b in pairs(f.ballots) do
		if not b.result and now < b.ends and Complete(b) and not Voted(b) then unvoted = unvoted + 1 end
	end
	if unvoted > 0 then
		table.insert(out, { text = string.format("Rösta: Folkvald representant (%d)", unvoted), click = function() ns.ShowTab(11) end })
	end
	local c = C()
	for i, n in ipairs(c.notices) do
		table.insert(out, { text = n.text, click = function()
			table.remove(c.notices, i)
			ns.ShowTab(n.page or 11)
		end })
	end
	if IsGuildLeader() then
		local apps, challenges, settle = 0, 0, 0
		for _, a in pairs(f.apps) do
			if a.challenge then challenges = challenges + 1 elseif not ns.RoundPhase() then apps = apps + 1 end
		end
		for _, b in pairs(f.ballots) do
			if not b.result and now >= b.ends then settle = settle + 1 end
		end
		if apps > 0 then table.insert(out, { text = string.format("%d ansökning%s till Folkvald representant", apps, apps == 1 and "" or "ar"), click = function() ns.ShowTab(11) end }) end
		if challenges > 0 then table.insert(out, { text = string.format("%d utmaning%s väntar", challenges, challenges == 1 and "" or "ar"), click = function() ns.ShowTab(11) end }) end
		if settle > 0 then table.insert(out, { text = string.format("%d omröstning%s att fastställa", settle, settle == 1 and "" or "ar"), click = function() ns.ShowTab(11) end }) end
	end
	return out
end

function ns.AddNotice(text, page)
	table.insert(C().notices, { text = text, page = page, at = ns.Now() })
	ns.RefreshTodo()
end

-- Messages --------------------------------------------------------------

local function OnApp(sender, head, text)
	local role, challenge, target = head[1], head[2] == "1", head[3]
	if not ROLE[role] then return end
	local title, reason = text:match("^(.-)~(.*)$")
	reason = ns.CleanText(reason or text, REASON_MAX)
	title = ns.CleanText(title or "", TITLE_MAX)
	local f = F()
	local phase = ns.RoundPhase()
	if phase == "val" or phase == "slut" then
		Note(sender, "Ansökan är stängd medan omröstningen pågår. Sök igen efter resultatet.", true)
		return
	end
	-- One open application per member (Zach 11/11); a new one replaces it.
	f.apps[sender] = { role = role, reason = reason, title = title, at = ns.Now(),
		challenge = (challenge and phase ~= "ans") or nil, target = target ~= "" and target or nil }
	if sender ~= ns.Me() then
		ns.Print(string.format("|cffffd100%s %s %s.|r Se Folkvald representant.", sender,
			f.apps[sender].challenge and "utmanar om" or "söker", ROLE[role].title))
		if SOUNDKIT and SOUNDKIT.READY_CHECK then PlaySound(SOUNDKIT.READY_CHECK) end
	end
	Changed()
end

local function OnVote(sender, parts)
	local key, choice, t = parts[2], parts[3], tonumber(parts[4])
	if not key or not choice then return end
	local id, cand = key:match("^([^/]+)/(.+)$")
	id = id or key
	local b = F().ballots[id]
	if not b or b.result then return end
	-- Cast before the end; late only by the time it took to reach him.
	if not t or t > b.ends or ns.Now() > b.ends + 2 * 86400 then return end
	if b.kind == "J" then
		if not cand or not b.cands[cand] or (choice ~= "J" and choice ~= "N") then return end
	elseif cand or not b.cands[choice] then
		return
	end
	local tally = F().tally
	local tl = tally[key] or { counts = {}, voted = {} }
	tally[key] = tl
	-- Only that this account has voted, and the totals (Zach 11/11).
	local acct = Account(sender)
	if tl.voted[acct] then return end
	tl.voted[acct] = true
	tl.counts[choice] = (tl.counts[choice] or 0) + 1
	Changed()
end

local function OnRound(parts)
	local f = F()
	local stamp = tonumber(parts[2]) or 0
	if stamp < (f.round.stamp or 0) then return end
	local appEnd, voteEnd = tonumber(parts[3]) or 0, tonumber(parts[4]) or 0
	if appEnd == 0 then
		f.round = { stamp = stamp }
	else
		f.round = { stamp = stamp, appEnd = appEnd, voteEnd = voteEnd, made = parts[5] == "1" }
	end
	Changed()
end

local function OnHolders(parts)
	local f = F()
	local stamp, role = tonumber(parts[2]) or 0, parts[3]
	if not ROLE[role] or stamp < (f.holderStamp[role] or 0) then return end
	local names = {}
	for name in (parts[4] or ""):gmatch("[^,]+") do table.insert(names, name) end
	f.holders[role], f.holderStamp[role] = names, stamp
	Changed()
end

local function OnBallot(parts)
	local id, role, kind, ends = parts[2], parts[3], parts[4], tonumber(parts[5])
	if not id or not ROLE[role] or not ends then return end
	local f = F()
	local b = f.ballots[id] or { cands = {}, order = {} }
	b.id, b.role, b.kind, b.ends = id, role, kind, ends
	b.holder = parts[6] ~= "" and parts[6] or nil
	b.n = tonumber(parts[7]) or 0
	f.ballots[id] = b
	Changed()
end

local function OnCandidate(head, text)
	local id, name = head[1], head[2]
	local b = F().ballots[id]
	if not b or not name then return end
	local title, reason = text:match("^(.-)~(.*)$")
	if not b.cands[name] then table.insert(b.order, name) end
	b.cands[name] = { title = title or "", reason = reason or text }
	Changed()
end

local function OnResult(parts)
	local b = F().ballots[parts[2] or ""]
	if not b then return end
	local winners, counts = {}, {}
	for name in (parts[3] or ""):gmatch("[^,]+") do table.insert(winners, name) end
	for name, v in (parts[4] or ""):gmatch("([^,=]+)=([^,]+)") do counts[name] = tonumber(v) or v end
	b.result = { winners = winners, counts = counts, at = ns.Now() }
	Changed()
end

-- Avgå (Zach 12/11): a holder keeps the role until they resign or lose a
-- challenge; the guild hears it, and the seat is open to apply for.
function ns.Resign(role)
	if not ROLE[role] then return end
	local online = ns.ToLeader("FX", role)
	ns.Print("du avgår som " .. ROLE[role].title .. (online and "." or "; guildledaren får veta det när hen är online."))
end

local function OnResign(sender, parts)
	local role = parts[2]
	if not ROLE[role or ""] then return end
	local list, found = {}, false
	for _, h in ipairs(Holders(role)) do
		if h == sender then found = true else table.insert(list, h) end
	end
	if not found then return end
	ns.SetHolders(role, list)
	local text = string.format("Folkvald representant: %s har avgått som %s. Platsen kan sökas under Folkvald representant.", sender, ROLE[role].title)
	Queue("FO;" .. text)
	Warn(text)
end

function ns.OnFolk(sender, parts, whisper)
	if ns.Online(sender) == nil or not ns.db then return end
	local kind = parts[1]
	local fromLeader = sender == ns.Leader()
	if whisper then
		if IsGuildLeader() and ns.OnTicketToLeader and ns.OnTicketToLeader(sender, parts) then return end
		if fromLeader and ns.OnTicketFromLeader and ns.OnTicketFromLeader(parts) then return end
		if IsGuildLeader() then
			if kind == "FA" then Receive(sender, parts, function(head, text) OnApp(sender, head, text) end)
			elseif kind == "FV" then OnVote(sender, parts)
			elseif kind == "FG" and ns.OnBidragAsk then ns.OnBidragAsk(sender, parts)
			elseif kind == "FX" then OnResign(sender, parts)
			end
		end
		if fromLeader then
			if kind == "FN" then
				if parts[2] == "1" then C().app = nil end
				ns.AddNotice(parts[3] or "", 11)
				ns.Print(parts[3] or "")
				Changed()
			elseif kind == "FW" and ROLE[parts[2] or ""] then
				local text = "Du utmanas om din plats som " .. ROLE[parts[2]].title .. "! Guildet röstar under Folkvald representant."
				Warn(text)
				ns.AddNotice(text, 11)
			elseif kind == "FH" and ns.OnBidragGiven then ns.OnBidragGiven(parts)
			end
		end
		return
	end
	if sender == ns.Me() then return end
	if kind == "FQ" then
		if IsGuildLeader() then C_Timer.After(2 + math.random() * 3, Serve) end
	elseif fromLeader then
		if kind == "FR" then OnRound(parts)
		elseif kind == "FS" then OnHolders(parts)
		elseif kind == "FB" then OnBallot(parts)
		elseif kind == "FC" then Receive(sender, parts, OnCandidate)
		elseif kind == "FT" then OnResult(parts)
		elseif kind == "FO" and parts[2] then
			Warn(parts[2])
		end
	end
end

-- Ticks -----------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event)
	if not ns.db or not ns.char then return end
	if event == "PLAYER_LOGIN" then
		-- Settled ballots older than a month are history.
		local f = F()
		for id, b in pairs(f.ballots) do
			if b.result and ns.Now() - (b.result.at or 0) > 30 * 86400 then
				f.ballots[id] = nil
				for key in pairs(f.tally) do
					if key == id or key:sub(1, #id + 1) == id .. "/" then f.tally[key] = nil end
				end
			end
		end
		C_Timer.After(35, function()
			if not ns.InOurGuild() then return end
			if IsGuildLeader() then Serve() else ns.Send("FQ") end
		end)
		C_Timer.NewTicker(15, function()
			if not ns.InOurGuild() then return end
			if IsGuildLeader() then MakeRound() end
			ns.RefreshTodo()
		end)
	else
		FlushOut()
		FlushTo()
	end
end)
