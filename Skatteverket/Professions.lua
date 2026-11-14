-- Skatteverket, the registration data: every member's professions, read
-- from the game's own skill list (Zach 7/11), with main or alt, interests
-- and a skattenummer the guild leader hands out in signing order.
-- Professions are not secret, so they go over the guild channel.
--
-- Guild channel:
--   Y;number;main;interests;professions;race   a member's registration
--   Z;name,number,main,interests,professions,time,race;...   leader: those offline
-- Race since 0.27, for the leader's Lämnat tab (Zach 10/11); older clients
-- send none.
-- Whispers:
--   G          member -> leader: give me a skattenummer
--   N;number   leader -> member: your skattenummer
--
-- Professions travel as codes and levels, "MIN97/ENG107"; since 0.20 with
-- the cap too, "ENG165-225", for the skill bar (older clients skip it); interests as
-- letters, "PIL" (PvP, Instanser, Levla, Farma).

local _, ns = ...

-- name: as the skill list gives it on an English client; id: the skill
-- line, the same on every client language.
ns.PROFESSIONS = {
	{ code = "ALC", id = 171, name = "Alchemy", label = "Alkemi", icon = "Trade_Alchemy" },
	{ code = "BS", id = 164, name = "Blacksmithing", label = "Smide", icon = "Trade_BlackSmithing" },
	{ code = "ENC", id = 333, name = "Enchanting", label = "Förtrollning", icon = "Trade_Engraving" },
	{ code = "ENG", id = 202, name = "Engineering", label = "Ingenjör", icon = "Trade_Engineering" },
	{ code = "HER", id = 182, name = "Herbalism", label = "Örtplockning", icon = "Spell_Nature_NatureTouchGrow" },
	{ code = "LW", id = 165, name = "Leatherworking", label = "Läderarbete", icon = "INV_Misc_ArmorKit_17" },
	{ code = "MIN", id = 186, name = "Mining", label = "Gruvdrift", icon = "Trade_Mining" },
	{ code = "SKI", id = 393, name = "Skinning", label = "Flåning", icon = "INV_Misc_Pelt_Wolf_01" },
	{ code = "TAI", id = 197, name = "Tailoring", label = "Skrädderi", icon = "Trade_Tailoring" },
	{ code = "COO", id = 185, name = "Cooking", label = "Matlagning", icon = "INV_Misc_Food_15" },
	{ code = "FA", id = 129, name = "First Aid", label = "Första hjälpen", icon = "Spell_Holy_SealOfSacrifice" },
	{ code = "FIS", id = 356, name = "Fishing", label = "Fiske", icon = "Trade_Fishing" },
}
ns.INTERESTS = {
	{ letter = "P", label = "PvP" },
	{ letter = "I", label = "Instanser" },
	{ letter = "L", label = "Levla" },
	{ letter = "F", label = "Farma" },
}

local BY_NAME, BY_CODE, BY_ID = {}, {}, {}
for _, p in ipairs(ns.PROFESSIONS) do
	BY_NAME[p.name] = p
	BY_CODE[p.code] = p
	BY_ID[p.id] = p
end
ns.PROFESSION_BY_CODE = BY_CODE

function ns.Number(n)
	return (n and n > 0) and string.format("TS-%04d", n) or nil
end

-- This character's professions as code -> { rank, max }. The newer
-- profession API gives skill line ids, the same in every language; the
-- Classic skill list gives only names, and a collapsed header hides its
-- lines. The skill list found nothing on Forever (screenshot 7/11), so the
-- newer API goes first; /skatt yrkestest shows what each one sees.
local function FromProfessionAPI(list)
	if not GetProfessions or not GetProfessionInfo then return end
	for _, index in pairs({ GetProfessions() }) do
		local _, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
		local p = BY_ID[skillLine]
		if p then list[p.code] = { rank = rank or 0, max = maxRank or 0 } end
	end
end

local function FromSkillList(list)
	if not GetNumSkillLines or not GetSkillLineInfo then return end
	for i = 1, GetNumSkillLines() do
		local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
		local p = name and not isHeader and BY_NAME[name]
		if p and not list[p.code] then list[p.code] = { rank = rank or 0, max = maxRank or 0 } end
	end
end

function ns.ReadProfessions()
	local list = {}
	pcall(FromProfessionAPI, list)
	pcall(FromSkillList, list)
	return list
end

-- What the game offers, for finding out why a profession is not seen.
function ns.ProfessionTest()
	ns.Print(string.format("GetProfessions %s, GetNumSkillLines %s.",
		GetProfessions and "finns" or "saknas", GetNumSkillLines and tostring(GetNumSkillLines()) or "saknas"))
	if GetProfessions and GetProfessionInfo then
		for _, index in pairs({ GetProfessions() }) do
			local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
			ns.Print(string.format("  yrke: %s %s/%s, id %s", tostring(name), tostring(rank), tostring(maxRank), tostring(skillLine)))
		end
	end
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, isHeader, isExpanded, rank = GetSkillLineInfo(i)
			ns.Print(string.format("  rad %d: %s%s %s", i, tostring(name), isHeader and (isExpanded and " (rubrik, öppen)" or " (rubrik, stängd)") or "", isHeader and "" or tostring(rank)))
		end
	end
	local found = ns.EncodeProfessions(ns.ReadProfessions())
	ns.Print("Skatteverket ser: " .. (found ~= "" and found or "inga yrken"))
end

function ns.EncodeProfessions(list)
	local parts = {}
	for _, p in ipairs(ns.PROFESSIONS) do
		local skill = list[p.code]
		if skill then
			table.insert(parts, p.code .. skill.rank .. ((skill.max or 0) > 0 and ("-" .. skill.max) or ""))
		end
	end
	return table.concat(parts, "/")
end

function ns.DecodeProfessions(text)
	local list = {}
	for code, rank, max in (text or ""):gmatch("(%a+)(%d+)%-?(%d*)") do
		if BY_CODE[code] then list[code] = { rank = tonumber(rank), max = tonumber(max) } end
	end
	return list
end

function ns.InterestText(letters)
	local words = {}
	for _, i in ipairs(ns.INTERESTS) do
		if (letters or ""):find(i.letter, 1, true) then table.insert(words, i.label) end
	end
	return table.concat(words, ", ")
end

-- Keep a member's registration unless what we have is newer.
function ns.SetProfile(name, number, main, interests, profs, t)
	if not name then return end
	local db = ns.db
	local m = db.members[name] or { firstSeen = time() }
	db.members[name] = m
	if (m.profileAt or 0) > t then return end
	if number and number > 0 then m.number = number end
	m.main, m.interests, m.profs, m.profileAt = main, interests or "", profs or "", t
	ns.Changed()
	if ns.RefreshRegistry then ns.RefreshRegistry() end
end

local lastSent, profileDirty = nil, false

function ns.SendProfile()
	local reg = ns.char.reg
	local me = ns.Me()
	if not reg or not me or not ns.InOurGuild() then profileDirty = true return end
	local profs = ns.EncodeProfessions(ns.ReadProfessions())
	ns.Send(string.format("Y;%d;%d;%s;%s;%s", reg.number or 0, reg.main and 1 or 0, reg.interests or "", profs, UnitRace("player") or ""))
	lastSent, profileDirty = profs, false
	ns.SetProfile(me, reg.number, reg.main, reg.interests, profs, time())
	-- Professions, recipes and the skattenummer can each earn one.
	ns.CheckAchievementsSoon()
end

-- Ask the leader for a skattenummer until one comes; offline, it waits for
-- the roster to show the leader online.
local lastAsk = 0
function ns.RequestNumber()
	local reg = ns.char.reg
	if not reg or reg.number or GetTime() - lastAsk < 60 then return end
	local leader = ns.Leader()
	if leader and ns.SendTo(leader, "G") then lastAsk = GetTime() end
end

-- Signed members get the guild rank Medborgare (Zach 7/11); the leader
-- gives it, Skatteverket only shows who is still waiting for it.
ns.CITIZEN_RANK = "Medborgare"
-- Ranks that count as Medborgare wherever they sit in the guild's order:
-- the officers in Representant (Zach 12/11).
ns.EQUAL_RANKS = { Representant = true }

-- Whether a roster rank index counts as Medborgare or higher.
function ns.RankOk(rankIndex, citizen)
	if rankIndex <= citizen then return true end
	local name = GuildControlGetRankName and GuildControlGetRankName(rankIndex + 1)
	return name ~= nil and ns.EQUAL_RANKS[name] == true
end

-- The roster rank index of Medborgare (0 is the guild master), or nil
-- when the guild has no rank by that name.
function ns.CitizenRankIndex()
	if not GuildControlGetNumRanks or not GuildControlGetRankName then return end
	for i = 1, GuildControlGetNumRanks() do
		if GuildControlGetRankName(i) == ns.CITIZEN_RANK then return i - 1 end
	end
end

-- Name -> roster rank index, for everyone in the guild now.
function ns.RosterRanks()
	local ranks = {}
	for i = 1, GetNumGuildMembers() do
		local name, _, rankIndex = GetGuildRosterInfo(i)
		if name then ranks[ns.Short(name)] = rankIndex end
	end
	return ranks
end

-- nil: not signed. "ok": signed and Medborgare or higher. "promote":
-- signed, rank still below Medborgare. "norank": no Medborgare rank exists.
function ns.CitizenStatus(name, ranks, citizen)
	local m = ns.db.members[name]
	if not m or not m.number then return nil end
	if not citizen then return "norank" end
	local rank = ranks[name]
	if rank and not ns.RankOk(rank, citizen) then return "promote" end
	return "ok"
end

-- Everyone signed but still below Medborgare, for the leader's to-do.
function ns.ToPromote()
	local citizen, out = ns.CitizenRankIndex(), {}
	if not citizen or not IsGuildLeader() then return out end
	local ranks = ns.RosterRanks()
	for name in pairs(ns.db.members) do
		if ranks[name] and ns.CitizenStatus(name, ranks, citizen) == "promote" then table.insert(out, name) end
	end
	table.sort(out)
	return out
end

-- Leader, from the Ge Medborgare button (a click, Zach 7/11): give a
-- signed member the rank Medborgare. SetGuildMemberRank sets it in one go;
-- a client without it promotes one step per click.
function ns.PromoteToCitizen(name)
	local citizen = ns.CitizenRankIndex()
	if not citizen then ns.Print("ingen rang heter " .. ns.CITIZEN_RANK .. " i guildet.") return end
	for i = 1, GetNumGuildMembers() do
		local full, _, rankIndex = GetGuildRosterInfo(i)
		if full and ns.Short(full) == name then
			if rankIndex <= citizen then
				ns.Print(name .. " är redan " .. ns.CITIZEN_RANK .. " eller högre.")
			elseif SetGuildMemberRank then
				SetGuildMemberRank(i, citizen + 1)
				ns.Print(name .. " är nu " .. ns.CITIZEN_RANK .. ".")
			else
				GuildPromote(full)
				ns.Print(name .. " befordrad ett steg; tryck igen tills det står klar.")
			end
			ns.RequestRoster()
			return
		end
	end
	ns.Print(name .. " finns inte i guildet.")
end

-- Leader: the next number, once per name, and a notice when someone new
-- has signed (Zach 7/11).
function ns.OnRegister(sender)
	if not IsGuildLeader() or ns.Online(sender) == nil then return end
	local db = ns.db
	local m = db.members[sender] or { firstSeen = time() }
	db.members[sender] = m
	if not m.number then
		m.number = db.nextNumber
		db.nextNumber = db.nextNumber + 1
		if sender ~= ns.Me() then
			if SOUNDKIT and SOUNDKIT.READY_CHECK then PlaySound(SOUNDKIT.READY_CHECK) end
			local status = ns.CitizenStatus(sender, ns.RosterRanks(), ns.CitizenRankIndex())
			ns.Print(string.format("|cffffd100%s har signerat sin anmälan (%s).|r%s", sender, ns.Number(m.number),
				status == "promote" and (" Ge rangen " .. ns.CITIZEN_RANK .. ": /gpromote " .. sender) or ""))
			if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
				RaidNotice_AddMessage(RaidWarningFrame, "Skatteverket: " .. sender .. " har signerat", ChatTypeInfo["RAID_WARNING"])
			end
			ns.Changed()
		end
	end
	ns.SendTo(sender, "N;" .. m.number)
end

function ns.OnNumber(number)
	local reg = ns.char.reg
	if not reg or not number or number < 1 or reg.number == number then return end
	reg.number = number
	-- Not on the scroll: a surprise in chat once signed (Zach 7/11), after
	-- the scroll has faded away when the number comes at once.
	C_Timer.After(4, function()
		ns.Print("|cffffd100Grattis, medborgare! Ditt skattenummer är " .. ns.Number(number) .. ".|r")
		ns.Print("En bild av din anmälan finns i din Screenshots-mapp, visa gärna upp den i Discord!")
	end)
	ns.SendProfile()
	if ns.RefreshScroll then ns.RefreshScroll() end
end

function ns.OnProfile(sender, parts)
	if sender == ns.Me() then return end
	ns.SetProfile(sender, tonumber(parts[2]), parts[3] == "1", parts[4], parts[5], time())
	local m = ns.db.members[sender]
	if m and parts[6] and parts[6] ~= "" then m.race = parts[6] end
end

function ns.OnProfileBoard(parts)
	local me = ns.Me()
	for i = 2, #parts do
		local name, number, main, interests, profs, t, race = strsplit(",", parts[i])
		t = tonumber(t)
		if name and t and name ~= me then
			ns.SetProfile(name, tonumber(number), main == "1", interests, profs, t)
			if race and race ~= "" and ns.db.members[name] then ns.db.members[name].race = race end
		end
	end
end

-- Leader: the rows for ServeBoard.
function ns.ProfileRows(roster)
	local rows = {}
	for name, m in pairs(ns.db.members) do
		if m.profileAt and (not roster or roster[name]) then
			table.insert(rows, string.format("%s,%d,%d,%s,%s,%d,%s", name, m.number or 0, m.main and 1 or 0,
				m.interests or "", m.profs or "", m.profileAt, m.race or ""))
		end
	end
	return rows
end

-- This character's registration was lost from its own saved data (Zach
-- 8/11, after many tests) but the guild's record still has its
-- skattenummer: take it back quietly, with no scroll and nothing said in
-- guild chat. The number comes only from the leader, so nobody can sign
-- themselves up this way.
local function RestoreRegistration()
	local me = ns.Me()
	local m = me and ns.db.members[me]
	if not m or (m.number or 0) < 1 then return false end
	ns.char.reg = { at = m.profileAt or m.firstSeen or time(), main = m.main ~= false, interests = m.interests or "", number = m.number }
	ns.Print("din anmälan (" .. ns.Number(m.number) .. ") är återställd från guildets register.")
	ns.SendProfile()
	ns.Changed()
	return true
end

-- The guild leader only: count as signed without the scroll and without
-- the line in guild chat (Zach 8/11). The skattenummer is handed out as usual.
function ns.SignQuietly()
	if not IsGuildLeader() then ns.Print("bara guildledaren kan göra det.") return end
	if ns.char.reg then ns.Print("du är redan anmäld.") return end
	if RestoreRegistration() then return end
	ns.char.reg = { at = time(), main = true, interests = "" }
	ns.Print("du är anmäld, utan något i guildchatten.")
	ns.RequestNumber()
	ns.SendProfile()
	ns.Changed()
end

local shownThisSession = false
local function OfferScroll()
	if shownThisSession or ns.char.reg or not ns.InOurGuild() then return end
	-- Wait for the roster: the full name is needed to look up the record.
	if not ns.Me() then return end
	shownThisSession = true
	if RestoreRegistration() then return end
	ns.ShowScroll()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
	if not ns.char then return end
	if event == "PLAYER_LOGIN" then
		ns.PreloadScroll()
		C_Timer.After(25, function()
			if ns.char.reg then
				ns.SendProfile()
				ns.RequestNumber()
			else
				OfferScroll()
			end
		end)
		-- A profession that went up goes out at most every five minutes.
		C_Timer.NewTicker(300, function()
			if profileDirty then ns.SendProfile() end
		end)
	elseif event == "SKILL_LINES_CHANGED" then
		if ns.char.reg and ns.EncodeProfessions(ns.ReadProfessions()) ~= lastSent then profileDirty = true end
		if ns.RefreshScroll then ns.RefreshScroll() end
	elseif event == "PLAYER_GUILD_UPDATE" then
		-- Just joined: the scroll is the welcome.
		C_Timer.After(5, OfferScroll)
	elseif event == "GUILD_ROSTER_UPDATE" then
		ns.RequestNumber()
		if ns.char.reg and lastSent == nil and ns.Me() then ns.SendProfile() end
	end
end)
