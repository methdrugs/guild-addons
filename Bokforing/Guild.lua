-- Bokföring is for THÖNDERSTÖRM (Zach 9/11). Saved data is shared by every
-- character on the WoW account, so once any of them has been seen in the
-- guild the account is a member's and its alts outside the guild are fine.
-- On an account never seen in the guild Bokföring stays off, and each such
-- character tells the guild leader once, by addon whisper, until the
-- leader's copy answers. Nothing shows on their side.
local _, ns = ...

local GUILD = "THÖNDERSTÖRM"
-- The leader's main, the full name as the guild roster shows it.
local LEADER = { "Boohbas Bonks" }
local PREFIX = "BokfG"
local RETRY = 1800

local state -- nil until the guild is known, then "member" or "outside"
local sentAt = 0

function ns.Allowed()
	return state ~= "outside"
end

local function Send(msg, target)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(PREFIX, msg, "WHISPER", target)
	end
end

local function Leader(name)
	if not name then return false end
	for _, leader in ipairs(LEADER) do
		if leader ~= "" and (name == leader or name:gsub("%-.*", "") == leader) then return true end
	end
	return false
end

-- Once per character, outside instances (addon messages are limited there),
-- again every half hour while the leader has not answered.
local function Tell()
	local guid = UnitGUID("player")
	if state ~= "outside" or not guid or ns.db.told[guid] then return end
	if IsInInstance() or time() - sentAt < RETRY then return end
	sentAt = time()
	local guild = GetGuildInfo("player") or "-"
	local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Bokforing", "Version") or "?"
	for _, leader in ipairs(LEADER) do
		if leader ~= "" then Send(string.format("?|%s|%d|%s", guild, UnitLevel("player") or 0, version), leader) end
	end
end

-- The game's "no player named X is currently playing" when the leader is
-- offline, hidden for the leader's names only.
local function Quiet(_, _, text)
	if issecretvalue and issecretvalue(text) then return false end
	if type(text) ~= "string" or not ERR_CHAT_PLAYER_NOT_FOUND_S or time() - sentAt > 10 then return false end
	for _, leader in ipairs(LEADER) do
		if leader ~= "" and text == string.format(ERR_CHAT_PLAYER_NOT_FOUND_S, leader) then return true end
	end
	return false
end
if ChatFrame_AddMessageEventFilter then ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", Quiet) end

-- The guild shows a little after login; until then Bokföring runs.
local function Decide(tries)
	if not ns.db then return end
	local guild = GetGuildInfo("player")
	if guild == GUILD then
		state, ns.db.member = "member", true
		return
	end
	if IsInGuild() and not guild and tries < 6 then
		C_Timer.After(10, function() Decide(tries + 1) end)
		return
	end
	if ns.db.member then
		state = "member"
		return
	end
	state = "outside"
	if ns.Hide then ns.Hide() end
	Tell()
end

-- The leader's side: who answered from outside, kept in saved data.
local function Heard(sender, msg)
	local guild, level, version = msg:match("^%?|(.*)|(%d+)|(.*)$")
	if not guild then return end
	local seen = ns.db.outside[sender]
	ns.db.outside[sender] = { at = time(), guild = guild, level = tonumber(level), version = version, n = (seen and seen.n or 0) + 1 }
	ns.Print(string.format("|cffff4040Bokföring outside the guild:|r %s, guild %s, level %s, version %s.",
		sender, guild == "-" and "none" or guild, level, version))
	Send("ok", sender)
end

-- /bok outside: every character heard from, newest first.
function ns.ListOutside()
	local list = {}
	for name, r in pairs(ns.db.outside) do table.insert(list, { name = name, r = r }) end
	table.sort(list, function(a, b) return a.r.at > b.r.at end)
	if #list == 0 then ns.Print("no one outside the guild so far.") return end
	for _, e in ipairs(list) do
		ns.Print(string.format("%s: guild %s, level %d, version %s, %s.", e.name, e.r.guild == "-" and "none" or e.r.guild,
			e.r.level or 0, e.r.version or "?", date("%d/%m %H:%M", e.r.at)))
	end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_GUILD_UPDATE", "CHAT_MSG_ADDON" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
	if not ns.db then return end
	ns.db.told = ns.db.told or {}
	ns.db.outside = ns.db.outside or {}
	if event == "PLAYER_LOGIN" then
		local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix
		if register then register(PREFIX) end
		C_Timer.After(10, function() Decide(0) end)
		C_Timer.NewTicker(RETRY, Tell)
	elseif event == "PLAYER_GUILD_UPDATE" then
		-- Joining the guild turns Bokföring on at once.
		if GetGuildInfo("player") == GUILD then state, ns.db.member = "member", true end
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, msg, channel, sender = ...
		if prefix ~= PREFIX or channel ~= "WHISPER" or type(msg) ~= "string" then return end
		if msg == "ok" then
			if Leader(sender) and UnitGUID("player") then ns.db.told[UnitGUID("player")] = true end
		else
			Heard(sender, msg)
		end
	end
end)
