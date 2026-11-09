-- Skatteverket, prestationer (Zach 8/11): achievements for tax, citizenship
-- and professions, a banner with a sound when one is earned (or a chat line,
-- under Inställningar), and the Prestationer tab where everyone's can be
-- looked at. They are easter eggs, not something to hunt for (Zach 8/11):
-- the tab shows only those earned, never the ones still to get. Shame achievements
-- (Skattesmitare, Ånger) are debuffs: red, minus points, never congratulated.
-- Swedbank achievements are private: only the borrower sees them, so nobody
-- learns who has borrowed. Paid-in-total tiers are coarse on purpose; no
-- amount is ever shown (Zach 8/11). Earned on this character, trusted as
-- they come; they are cosmetic.
--
-- Guild channel:
--   H;ids[;new ids]          a member's visible achievements, comma separated;
--                            new ids are announced as a chat line to the online
--   I;name=ids;name=ids...   leader: the achievements of members offline now

local _, ns = ...

-- On hold (Zach 9/11): he was not satisfied with where they ended up, so
-- the release goes out with them switched off: no tab, no banner, nothing
-- sent or relayed. The code stays for another look; true turns it all on.
ns.PRESTATIONER = false

local G, DAY = 10000, 86400

local function Me() return ns.Me() end

-- Order is the order on the tab. points < 0 marks a shame achievement.
ns.ACHIEVEMENTS = {
	{ "FS", "Första skatten", "Betala skatt för första gången.", 10, "INV_Misc_Coin_01", function(c) return c.paid > 0 end },
	{ "T1", "Småsparare", "Betala 1 guld i skatt totalt.", 5, "INV_Misc_Coin_02", function(c) return c.paid >= 1 * G end },
	{ "T2", "Hederlig medborgare", "Betala 10 guld i skatt totalt.", 10, "INV_Misc_Coin_03", function(c) return c.paid >= 10 * G end },
	{ "T3", "Stöttepelare", "Betala 50 guld i skatt totalt.", 15, "INV_Misc_Coin_04", function(c) return c.paid >= 50 * G end },
	{ "T4", "Skattekung", "Betala 250 guld i skatt totalt.", 20, "INV_Crown_01", function(c) return c.paid >= 250 * G end },
	{ "T5", "Statsbärare", "Betala 1000 guld i skatt totalt.", 25, "INV_Crown_02", function(c) return c.paid >= 1000 * G end },
	{ "FV", "Skatteverkets favorit", "Bli en av Skatteverkets tre favoriter.", 15, "Spell_Holy_SealOfWisdom",
		function() return Me() and ns.TopPayers()[Me()] ~= nil end },
	{ "O7", "Obruten", "Håll God ställning i 7 dagar i rad.", 10, "Spell_Nature_TimeStop",
		function(c) return ns.Standing(c) == "good" and c.goodSince and time() - c.goodSince >= 7 * DAY end },
	{ "O3", "Obruten i en månad", "Håll God ställning i 30 dagar i rad.", 20, "Spell_Nature_TimeStop",
		function(c) return ns.Standing(c) == "good" and c.goodSince and time() - c.goodSince >= 30 * DAY end },
	{ "CB", "Comeback", "Gå från Negativ till God ställning.", 10, "Spell_Holy_Resurrection",
		function(c) return c.achWasNegative and ns.Standing(c) == "good" end },
	{ "ME", "Medborgare", "Signera din anmälan till Skatteverket.", 5, "INV_Scroll_03", function(c) return c.reg ~= nil end },
	{ "GK", "Godkänd", "Få rangen Medborgare.", 5, "INV_Misc_Note_01", function(c) return c.reg ~= nil and not ns.Locked() end },
	{ "PI", "Pionjär", "Ha ett skattenummer bland de tio första.", 15, "INV_Misc_Note_02",
		function(c) return c.reg and c.reg.number and c.reg.number <= 10 end },
	{ "GE", "Gesäll", "Nå 150 i ett yrke.", 10, "INV_Misc_Gear_01", function() return ns.BestProfession() >= 150 end },
	{ "MA", "Mästare", "Nå 225 i ett yrke.", 20, "Trade_Engineering", function() return ns.BestProfession() >= 225 end },
	{ "RD", "Receptdelare", "Dela dina recept med guildet genom att öppna ditt yrkesfönster.", 5, "INV_Misc_Book_09",
		function(c) return next(c.recipes) ~= nil end },
	{ "SS", "Skattesmitare", "Hamna i Negativ ställning.", -10, "INV_Misc_Bone_HumanSkull_01",
		function(c) return ns.Standing(c) == "negative" end },
	{ "AN", "Ånger", "Köp tillbaka något du sålt, så att skatten dras tillbaka.", -5, "INV_Misc_Bag_10",
		function(c) return c.achBuyback end },
	-- Private: never sent, shown only to the borrower.
	{ "L1", "Första lånet", "Få ett lån från Swedbank godkänt och utbetalt.", 5, "INV_Misc_Bag_10",
		function() return ns.HasLoan(function(l) return l.sentAt end) end, true },
	{ "SF", "Skuldfri", "Betala tillbaka ett lån helt.", 10, "INV_Misc_Coin_04",
		function() return ns.HasLoan(function(l) return l.status == "repaid" end) end, true },
	{ "GT", "I god tid", "Betala tillbaka ett lån före sista dagen.", 10, "Spell_Nature_TimeStop",
		function() return ns.HasLoan(function(l) return l.status == "repaid" and (l.repayBy or 0) > 0 and (l.closedAt or 0) <= l.repayBy end) end, true },
}
local BY_ID = {}
for _, a in ipairs(ns.ACHIEVEMENTS) do BY_ID[a[1]] = a end

-- The highest rank in any profession, 0 if none.
function ns.BestProfession()
	local best = 0
	for _, skill in pairs(ns.ReadProfessions()) do best = math.max(best, skill.rank or 0) end
	return best
end

-- Any of this character's Swedbank loans for which test is true.
function ns.HasLoan(test)
	for _, loan in pairs(SwedbankCharDB and SwedbankCharDB.loans or {}) do
		if test(loan) then return true end
	end
	return false
end

local function Visible(set)
	local ids = {}
	for _, a in ipairs(ns.ACHIEVEMENTS) do
		if set[a[1]] and not a[7] then table.insert(ids, a[1]) end
	end
	return table.concat(ids, ",")
end

local function Parse(text)
	local set = {}
	for id in (text or ""):gmatch("[^,]+") do if BY_ID[id] then set[id] = true end end
	return set
end

function ns.AchievementPoints(set)
	local points = 0
	for id in pairs(set) do points = points + (BY_ID[id] and BY_ID[id][4] or 0) end
	return points
end

-- Mine as a set, or a member's as last seen.
function ns.AchievementsOf(name)
	if name == Me() then
		local set = {}
		for id in pairs(ns.char.ach) do set[id] = true end
		return set
	end
	local m = ns.db.members[name]
	return Parse(m and m.ach)
end

function ns.SendAchievements(new)
	if not ns.PRESTATIONER or not ns.char or not ns.InOurGuild() then return end
	local ids = Visible(ns.char.ach)
	ns.Send("H;" .. ids .. (new and new ~= "" and (";" .. new) or ""))
	local me = Me()
	if me then
		local m = ns.db.members[me] or { firstSeen = time() }
		ns.db.members[me] = m
		m.ach = ids
	end
end

-- The banner (Zach 8/11): the classic dialog frame around quest log paper
-- (a piece from the middle of Media/Parchment.tga, clear of its torn
-- sides), the icon in an action-button slot, the texts in the quest fonts
-- and the quest log's brown ink. It fades in, stays five seconds and fades
-- out; nothing else moves, since growing it and writing the name in made
-- the text jump (8/11). One at a time. Achievement: "Vinnare!" and Seger
-- (Media/Seger.ogg: a quick climb on a real French horn up to a high D,
-- real CC0 recordings, art/seger.sh, Media/SOUNDS.txt; Zach's pick after
-- many rounds, 8/11).
-- Shame: "Skam" in dark red, and the warning sound (he called it perfect).
local MEDIA = "Interface\\AddOns\\Skatteverket\\Media\\"
-- The quest log's ink (as on the sign-up scroll); dark red for shame.
local INK, FADED, BLOOD = { 0.25, 0.18, 0.1 }, { 0.36, 0.3, 0.22 }, { 0.5, 0.05, 0.03 }
local SHAME_SOUNDS = { "RAID_WARNING", "UI_RAID_BOSS_WHISPER_WARNING", "IG_PLAYER_INVITE_DECLINE", "READY_CHECK" }
local function Sound(list)
	for _, key in ipairs(list) do
		if SOUNDKIT and SOUNDKIT[key] then
			PlaySound(SOUNDKIT[key])
			return key
		end
	end
end

-- SegerA for everyone; the variations are being tried (Zach 8/11). All are
-- without the trombone stab, whose sizzle hurt like a hi-hat.
-- /skatt prestationstest steps through them on the leader's account
-- (db.achSound) to hear them in game.
local GOOD_SOUNDS = { "SegerA", "SegerB", "SegerC", "SegerD", "SegerE", "SegerF" }
local function Fanfare()
	local name = GOOD_SOUNDS[ns.db.achSound or 1] or GOOD_SOUNDS[1]
	if PlaySoundFile then PlaySoundFile(MEDIA .. name .. ".ogg", "Master") end
end

-- A font string in a quest font at its own size.
local function Ink(parent, template, size)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	local object = _G[template]
	local font = object and object:GetFont()
	if font then fs:SetFont(font, size, "") end
	fs:SetShadowOffset(0, 0)
	return fs
end

local banner, queue, showing = nil, {}, false
local function BuildBanner()
	banner = CreateFrame("Frame", "SkatteverketAchievementBanner", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	banner:SetSize(380, 96)
	banner:SetPoint("TOP", 0, -130)
	banner:SetFrameStrata("HIGH")
	banner:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24 })
	banner.paper = banner:CreateTexture(nil, "BACKGROUND")
	banner.paper:SetTexture(MEDIA .. "Parchment")
	banner.paper:SetTexCoord(0.15, 0.85, 0.42, 0.56)
	banner.paper:SetPoint("TOPLEFT", 6, -6)
	banner.paper:SetPoint("BOTTOMRIGHT", -6, 6)
	banner.slot = banner:CreateTexture(nil, "ARTWORK")
	banner.slot:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	banner.slot:SetSize(74, 74)
	banner.slot:SetPoint("LEFT", 6, -1)
	banner.icon = banner:CreateTexture(nil, "BORDER")
	banner.icon:SetSize(40, 40)
	banner.icon:SetPoint("CENTER", banner.slot, "CENTER", 0, 0)
	banner.title = Ink(banner, "QuestTitleFont", 13)
	banner.title:SetPoint("TOPLEFT", 74, -14)
	banner.name = Ink(banner, "QuestTitleFont", 19)
	banner.name:SetPoint("TOPLEFT", banner.title, "BOTTOMLEFT", 0, -4)
	banner.name:SetWidth(230)
	banner.name:SetJustifyH("LEFT")
	banner.desc = Ink(banner, "QuestFont", 12)
	banner.desc:SetPoint("TOPLEFT", banner.name, "BOTTOMLEFT", 0, -3)
	banner.desc:SetWidth(230)
	banner.desc:SetJustifyH("LEFT")
	banner.desc:SetWordWrap(false)
	banner.points = Ink(banner, "QuestTitleFont", 22)
	banner.points:SetPoint("RIGHT", -22, 4)
	banner.pointsLabel = Ink(banner, "QuestFont", 11)
	banner.pointsLabel:SetPoint("TOP", banner.points, "BOTTOM", 0, -1)
	banner.pointsLabel:SetText("poäng")
	banner:Hide()
end

local function ShowNext()
	local a = table.remove(queue, 1)
	if not a then showing = false return end
	showing = true
	if not banner then BuildBanner() end
	local shame = a[4] < 0
	local ink = shame and BLOOD or INK
	banner.paper:SetVertexColor(1, shame and 0.75 or 1, shame and 0.7 or 1)
	banner.icon:SetTexture("Interface\\Icons\\" .. a[5])
	banner.title:SetText(shame and "Skam" or "Vinnare!")
	banner.name:SetText(a[2])
	banner.desc:SetText(a[3])
	banner.points:SetText(shame and tostring(a[4]) or ("+" .. a[4]))
	for _, fs in ipairs({ banner.title, banner.name, banner.points }) do fs:SetTextColor(ink[1], ink[2], ink[3]) end
	banner.desc:SetTextColor(FADED[1], FADED[2], FADED[3])
	banner.pointsLabel:SetTextColor(FADED[1], FADED[2], FADED[3])
	if shame then Sound(SHAME_SOUNDS) else Fanfare() end
	banner:SetAlpha(0)
	banner:Show()
	local t = 0
	banner:SetScript("OnUpdate", function(self, elapsed)
		t = t + elapsed
		if t < 0.3 then
			self:SetAlpha(t / 0.3)
		elseif t < 5 then
			self:SetAlpha(1)
		elseif t < 5.6 then
			self:SetAlpha(1 - (t - 5) / 0.6)
		else
			self:SetScript("OnUpdate", nil)
			self:Hide()
			ShowNext()
		end
	end)
end

-- force: the test command shows the banner even when banners are off.
local function Announce(a, force)
	if ns.db.showBanners == false and not force then
		if a[4] < 0 then
			ns.Print(string.format("|cffff4040skam: %s (%d).|r", a[2], a[4]))
		else
			ns.Print(string.format("|cffffd100ny prestation: %s (+%d).|r", a[2], a[4]))
		end
		return
	end
	table.insert(queue, a)
	if not showing then ShowNext() end
end

-- Look for newly earned ones; each gets a banner and a sound, also the
-- ones a member already qualified for when this version arrived (Zach 8/11).
local lastCheck = 0
function ns.CheckAchievements()
	if not ns.PRESTATIONER then return end
	local char = ns.char
	if not char or not ns.InOurGuild() or not Me() then return end
	lastCheck = GetTime()
	if ns.Standing(char) == "negative" then char.achWasNegative = true end
	local new = {}
	for _, a in ipairs(ns.ACHIEVEMENTS) do
		if not char.ach[a[1]] then
			local ok, earned = pcall(a[6], char)
			if ok and earned then
				char.ach[a[1]] = time()
				Announce(a)
				if not a[7] then table.insert(new, a[1]) end
			end
		end
	end
	if #new > 0 then
		ns.SendAchievements(table.concat(new, ","))
		ns.Changed()
	end
end

-- Not more often than every ten seconds from the busy events.
function ns.CheckAchievementsSoon()
	if not ns.PRESTATIONER then return end
	if GetTime() - lastCheck > 10 then ns.CheckAchievements() end
end

-- H;ids[;new]: a member's achievements, and a chat line for new ones.
function ns.OnAchievements(sender, parts)
	if not ns.PRESTATIONER then return end
	if sender == Me() then return end
	local m = ns.db.members[sender] or { firstSeen = time() }
	ns.db.members[sender] = m
	m.ach = Visible(Parse(parts[2]))
	for id in (parts[3] or ""):gmatch("[^,]+") do
		local a = BY_ID[id]
		if a and not a[7] then
			if a[4] < 0 then
				ns.Print(string.format("|cffff4040%s drabbades av %s.|r", sender, a[2]))
			else
				ns.Print(string.format("|cffffd100%s fick prestationen %s.|r", sender, a[2]))
			end
		end
	end
	ns.Changed()
end

-- I;name=ids;...: from the leader, for members offline now. Achievements
-- only ever grow, so the longer list wins.
function ns.OnAchievementBoard(parts)
	if not ns.PRESTATIONER then return end
	local me = Me()
	for i = 2, #parts do
		local name, ids = (parts[i] or ""):match("^([^=]+)=(.*)$")
		if name and name ~= me then
			local m = ns.db.members[name] or { firstSeen = time() }
			ns.db.members[name] = m
			local have, got = Parse(m.ach), Parse(ids)
			local nh, ng = 0, 0
			for _ in pairs(have) do nh = nh + 1 end
			for _ in pairs(got) do ng = ng + 1 end
			if ng > nh then m.ach = ids end
		end
	end
	ns.Changed()
end

-- Rows for the leader's board, everyone in the guild now.
function ns.AchievementRows(roster)
	if not ns.PRESTATIONER then return {} end
	local rows = {}
	for name, m in pairs(ns.db.members) do
		if m.ach and m.ach ~= "" and (not roster or roster[name]) then table.insert(rows, name .. "=" .. m.ach) end
	end
	return rows
end

-- /skatt prestationstest, the leader only: an achievement banner with the
-- next candidate sound; /skatt prestationstest skam shows the shame banner.
function ns.AchievementTest(arg)
	if not IsGuildLeader() then ns.Print("bara guildledaren kan göra det.") return end
	if arg == "skam" then Announce(BY_ID.SS, true) return end
	local db = ns.db
	db.achSound = (db.achSound or 0) % #GOOD_SOUNDS + 1
	ns.Print(string.format("ljud %d av %d: %s. Kör /skatt prestationstest igen för nästa; det senaste blir kvar.",
		db.achSound, #GOOD_SOUNDS, GOOD_SOUNDS[db.achSound]))
	Announce(BY_ID.FS, true)
end

-- The Prestationer tab: everyone in the guild on the left, by points; the
-- selected member's achievements on the right, earned ones lit.
local page, people, rows, selected, offset = nil, {}, {}, nil, 0
local PEOPLE_ROWS, ROWS = 22, 22

function ns.BuildAchievements(parent)
	page = parent
	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 24, -70)
	title:SetText("Medlemmar")
	for i = 1, PEOPLE_ROWS do
		local b = CreateFrame("Button", nil, parent)
		b:SetSize(160, 18)
		b:SetPoint("TOPLEFT", 20, -88 - (i - 1) * 18)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("LEFT", 4, 0)
		b.text:SetWidth(120)
		b.text:SetJustifyH("LEFT")
		b.text:SetWordWrap(false)
		b.points = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		b.points:SetPoint("RIGHT", -4, 0)
		b:SetScript("OnClick", function(self) selected = self.name ns.RefreshAchievements() end)
		people[i] = b
	end
	parent:EnableMouseWheel(true)
	parent:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta
		ns.RefreshAchievements()
	end)
	page.header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	page.header:SetPoint("TOPLEFT", 200, -70)
	page.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	page.empty:SetPoint("TOPLEFT", 200, -92)
	page.empty:SetText("Inga prestationer än.")
	for i = 1, ROWS do
		local r = CreateFrame("Frame", nil, parent)
		r:SetSize(290, 18)
		r:SetPoint("TOPLEFT", 196, -88 - (i - 1) * 18)
		r:EnableMouse(true)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(16, 16)
		r.icon:SetPoint("LEFT", 4, 0)
		r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
		r.points = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		r.points:SetPoint("RIGHT", -4, 0)
		r:SetScript("OnEnter", function(self)
			if not self.a then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.a[2], 1, 1, 1)
			GameTooltip:AddLine(self.a[3], 1, 0.82, 0, true)
			if self.a[7] then GameTooltip:AddLine("Bara du ser den här.", 0.6, 0.6, 0.6) end
			if self.at then GameTooltip:AddLine("Fick den " .. date("%d/%m %Y", self.at), 0.6, 0.6, 0.6) end
			GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = r
	end
end

function ns.RefreshAchievements()
	if not page or not page:IsShown() then return end
	local me = Me()
	selected = selected or me
	-- Everyone in the guild now, by points.
	local list = {}
	for i = 1, GetNumGuildMembers() do
		local name = ns.Short(GetGuildRosterInfo(i))
		if name then table.insert(list, { name = name, points = ns.AchievementPoints(ns.AchievementsOf(name)) }) end
	end
	table.sort(list, function(a, b)
		if a.points ~= b.points then return a.points > b.points end
		return a.name < b.name
	end)
	offset = math.max(0, math.min(offset, #list - PEOPLE_ROWS))
	for i, b in ipairs(people) do
		local p = list[i + offset]
		b.name = p and p.name
		if p then
			b.text:SetText(p.name == me and ("|cffffd100" .. p.name .. "|r") or p.name)
			b.points:SetText(tostring(p.points))
			if p.name == selected then b:LockHighlight() else b:UnlockHighlight() end
			b:Show()
		else
			b:Hide()
		end
	end

	local set = selected and ns.AchievementsOf(selected) or {}
	page.header:SetText(string.format("%s  |cffffffff%d poäng|r", selected or "", ns.AchievementPoints(set)))
	-- Only those earned: the rest are secret (Zach 8/11).
	local shown = {}
	for _, a in ipairs(ns.ACHIEVEMENTS) do
		if set[a[1]] and (not a[7] or selected == me) then table.insert(shown, a) end
	end
	page.empty:SetShown(#shown == 0)
	for i, r in ipairs(rows) do
		local a = shown[i]
		r.a = a
		if a then
			local has = set[a[1]]
			r.at = has and selected == me and ns.char.ach[a[1]] or nil
			r.icon:SetTexture("Interface\\Icons\\" .. a[5])
			r.icon:SetDesaturated(not has)
			r.icon:SetAlpha(has and 1 or 0.4)
			local shame = a[4] < 0
			local colour = not has and "|cff808080" or shame and "|cffff4040" or "|cffffffff"
			r.text:SetText(colour .. a[2] .. (a[7] and " (privat)" or "") .. "|r")
			r.points:SetText((not has and "|cff808080" or shame and "|cffff4040" or "") .. a[4] .. (has and not shame and "" or "|r"))
			r:Show()
		else
			r:Hide()
		end
	end
end
