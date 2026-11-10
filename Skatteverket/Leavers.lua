-- Skatteverket, who left the guild (Zach 10/11). Two ways in: the game's
-- line when someone leaves or is removed while you are online, and the
-- roster compared with the one seen last time, for whatever happened while
-- you were away (the game says nothing then, so Skatteverket does). The
-- leader gets each on the bolt's to-do with the tax and loans they owed,
-- and the Lämnat tab of the Skatt window lists them: name, class, race,
-- level, rank, raider (for the raid sign-up to come), when and how.
-- /skatt lämnat lists them in chat. Kept 30 days.

local _, ns = ...

local KEEP_DAYS = 30

local function Left()
	ns.db.left = ns.db.left or {}
	return ns.db.left
end

-- "Kalle har lämnat guildet", with what they owed for the leader.
local function Describe(name, e)
	local text = string.format("%s har %s guildet", name, e.by and ("sparkats ur") or "lämnat")
	if e.by then text = text .. " av " .. e.by end
	if not IsGuildLeader() then return text end
	local owes = {}
	if e.owed and e.owed >= 1 then table.insert(owes, ns.Money(e.owed) .. " i skatt") end
	if e.loan and e.loan >= 1 then table.insert(owes, ns.Money(e.loan) .. " i lån") end
	return text .. (#owes > 0 and (", skyldig " .. table.concat(owes, " och ")) or "")
end

-- fromChat: the game has already said it in chat.
local function Note(name, by, fromChat)
	if not name or name == "" then return end
	name = ns.Short(name)
	local e = Left()[name]
	if e and ns.Now() - e.at < 3600 then return end
	local m = ns.db.members[name]
	local r = ns.db.roster and type(ns.db.roster[name]) == "table" and ns.db.roster[name] or {}
	e = { at = ns.Now(), by = by and ns.Short(by) or nil, owed = m and m.owed or nil,
		loan = SwedbankPanel and SwedbankPanel.OwedBy and SwedbankPanel.OwedBy(name) or nil, seen = false,
		class = r.class, level = r.level, rank = r.rank, race = m and m.race, raider = m and m.raider,
		joined = m and m.firstSeen }
	Left()[name] = e
	if not fromChat then ns.Print(Describe(name, e) .. " (medan du var borta).") end
	if ns.RefreshTodo then ns.RefreshTodo() end
	if ns.RefreshWindow then ns.RefreshWindow("skatt") end
end

-- The bolt's to-do, the leader only: each one not yet seen; a click marks
-- it seen.
function ns.LeaverTodo()
	local out = {}
	if not IsGuildLeader() then return out end
	for name, e in pairs(Left()) do
		if not e.seen then
			table.insert(out, { text = Describe(name, e) .. " (" .. date("%d/%m", e.at) .. ")", click = function()
				e.seen = true
				if ns.RefreshTodo then ns.RefreshTodo() end
				ns.ShowTab(9)
			end })
		end
	end
	table.sort(out, function(a, b) return a.text < b.text end)
	return out
end

function ns.ListLeavers()
	local list = {}
	for name, e in pairs(Left()) do table.insert(list, { name = name, e = e }) end
	table.sort(list, function(a, b) return a.e.at > b.e.at end)
	if #list == 0 then ns.Print("ingen har lämnat guildet de senaste " .. KEEP_DAYS .. " dagarna.") return end
	for _, l in ipairs(list) do ns.Print(date("%d/%m %H:%M", l.e.at) .. ": " .. Describe(l.name, l.e) .. ".") end
end

-- The roster against the last one seen. A roster much smaller than the last
-- is still loading, not people leaving.
local function Compare()
	if not ns.db or not IsInGuild() or GetNumGuildMembers() == 0 then return end
	-- Kept with class, level and rank, for the Lämnat tab.
	local now = {}
	local n = 0
	for i = 1, GetNumGuildMembers() do
		local name, rank, _, level, class = GetGuildRosterInfo(i)
		if name then
			now[ns.Short(name)] = { class = class, level = level, rank = rank }
			n = n + 1
		end
	end
	local before = ns.db.roster
	if before then
		local count = 0
		for _ in pairs(before) do count = count + 1 end
		if n < count * 0.8 then return end
		for name in pairs(before) do
			if not now[name] then Note(name) end
		end
	end
	ns.db.roster = now
	for name, e in pairs(Left()) do
		-- Back in the guild, or long ago.
		if now[name] or ns.Now() - e.at > KEEP_DAYS * 86400 then Left()[name] = nil end
	end
end

-- The game's own lines, while online.
local function Pattern(text)
	if not text then return end
	text = text:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	return "^" .. text:gsub("%%s", "(.+)") .. "$"
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "GUILD_ROSTER_UPDATE", "CHAT_MSG_SYSTEM" }) do pcall(events.RegisterEvent, events, event) end
local soon = false
events:SetScript("OnEvent", function(_, event, text)
	if not ns.db or not ns.InOurGuild() then return end
	if event == "CHAT_MSG_SYSTEM" then
		if issecretvalue and issecretvalue(text) then return end
		if type(text) ~= "string" then return end
		local leave, kick = Pattern(ERR_GUILD_LEAVE_S), Pattern(ERR_GUILD_REMOVE_SS)
		local name = leave and text:match(leave)
		if name then Note(name, nil, true) return end
		local kicked, by
		if kick then kicked, by = text:match(kick) end
		if kicked then Note(kicked, by, true) end
		return
	end
	-- After the roster has settled.
	if soon then return end
	soon = true
	C_Timer.After(5, function()
		soon = false
		Compare()
	end)
end)

-- The Lämnat tab of the Skatt window, the leader only -------------------

-- Med sedan (Zach 10/11): when Skatteverket first saw them, to tell a day
-- from a month.
local COLS = { { "Namn", 160 }, { "Klass", 85 }, { "Ras", 80 }, { "Level", 45 }, { "Rang", 105 }, { "Raid", 45 },
	{ "Med sedan", 80 }, { "Lämnade", 95 }, { "Hur", 125 }, { "Skatt skyldig", 95 }, { "Lån skyldigt", 95 } }
local ROWS, ROW_H = 18, 18
local page, rows, offset = nil, {}, 0

function ns.BuildLeavers(parent)
	page = parent
	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 24, -70)
	title:SetText("Lämnat guildet, senaste " .. KEEP_DAYS .. " dagarna")
	local x = 24
	for _, c in ipairs(COLS) do
		local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h:SetPoint("TOPLEFT", x, -94)
		h:SetText(c[1])
		x = x + c[2]
	end
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, parent)
		row:SetSize(x - 20, ROW_H)
		row:SetPoint("TOPLEFT", 20, -108 - (i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.cells = {}
		local cx = 4
		for _, c in ipairs(COLS) do
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("LEFT", cx, 0)
			fs:SetWidth(c[2] - 6)
			fs:SetJustifyH("LEFT")
			fs:SetWordWrap(false)
			row.cells[#row.cells + 1] = fs
			cx = cx + c[2]
		end
		-- A click marks it seen on the bolt.
		row:SetScript("OnClick", function(self)
			local e = self.name and Left()[self.name]
			if e then
				e.seen = true
				if ns.RefreshTodo then ns.RefreshTodo() end
				ns.RefreshLeavers()
			end
		end)
		rows[i] = row
	end
	page.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	page.empty:SetPoint("TOPLEFT", 24, -120)
	page.empty:SetText("Ingen har lämnat guildet de senaste " .. KEEP_DAYS .. " dagarna.")
	page.note = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	page.note:SetPoint("BOTTOMLEFT", 24, 40)
	page.note:SetText("Nya i gult tills du klickat på dem. Raid fylls i när raidanmälan finns. Ras syns för den som har anmält sig.")
	parent:EnableMouseWheel(true)
	parent:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, offset - delta * 3)
		ns.RefreshLeavers()
	end)
end

function ns.RefreshLeavers()
	if not page or not page:IsShown() then return end
	local list = {}
	for name, e in pairs(Left()) do table.insert(list, { name = name, e = e }) end
	table.sort(list, function(a, b) return a.e.at > b.e.at end)
	offset = math.max(0, math.min(offset, #list - ROWS))
	page.empty:SetShown(#list == 0)
	for i, row in ipairs(rows) do
		local l = list[i + offset]
		row.name = l and l.name
		if l then
			local e = l.e
			local colour = e.seen and "|cffffffff" or "|cffffd100"
			local values = { colour .. l.name .. "|r", e.class or "?", e.race or "-", e.level and tostring(e.level) or "?", e.rank or "?",
				e.raider and "ja" or "-", e.joined and date("%d/%m", e.joined) or "?", date("%d/%m %H:%M", e.at), e.by and ("sparkad av " .. e.by) or "lämnade själv",
				(e.owed and e.owed >= 1) and ("|cffff4040" .. ns.Money(e.owed) .. "|r") or "-",
				(e.loan and e.loan >= 1) and ("|cffff4040" .. ns.Money(e.loan) .. "|r") or "-" }
			for c, fs in ipairs(row.cells) do fs:SetText(values[c]) end
			row:Show()
		else
			row:Hide()
		end
	end
end
