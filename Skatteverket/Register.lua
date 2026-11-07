-- Skatteverket, Anmälan till Skatteverket: a parchment scroll every member
-- signs once, new and old alike (Zach 7/11). The text writes itself in
-- like quest text, then the form fades in: name and level filled in,
-- professions read from the game and lit up, main or alt and interests
-- clicked. Signing writes the name in by hand, stamps the scroll, plays
-- the quest complete sound, says it in guild chat, asks the leader for a
-- skattenummer and fades the scroll away. Senare closes
-- it until the next login; /skatt anmälan opens it again to change main,
-- alt or interests. Tax data is never touched here.

local _, ns = ...

local W, H = 500, 740
-- Body and objective colours of the quest log (screenshot 7/11).
local INK = { 0.25, 0.18, 0.1 }
local FADED = { 0.36, 0.3, 0.22 }
-- Where signing is announced. "SAY" while testing, "GUILD" for release
-- (Zach 7/11); wowaddons publish refuses to push "SAY".
local ANNOUNCE = "GUILD"
-- Quest text speed and fade width, as the quest frame has them.
local CPS, GRADIENT = 25, 30
-- The scroll with rolls; Zach tried a loose sheet (7/11) and kept the
-- scroll as more premium. false shows the sheet (Media/Paper.tga).
local SCROLL = true

local scroll, page, faq, form, signBlock, icons, interestBoxes = nil, nil, nil, nil, nil, {}, {}
local mainBox, altBox
local choice = { main = true, interests = "" }

local function Sound(key)
	if SOUNDKIT and SOUNDKIT[key] then PlaySound(SOUNDKIT[key]) end
end

-- The seal landing: AUCTION_WINDOW_CLOSE, picked by Zach from about 30
-- game sounds (7/11).
local STAMP_SOUND = "AUCTION_WINDOW_CLOSE"

local function Ink(parent, size, color, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", "QuestFont")
	local font = QuestFont and QuestFont:GetFont()
	if font and size then fs:SetFont(font, size, "") end
	fs:SetTextColor(unpack(color or INK))
	fs:SetPoint(...)
	fs:SetJustifyH("LEFT")
	return fs
end

local function Title(parent, text, size, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", "QuestTitleFont")
	local font = QuestTitleFont and QuestTitleFont:GetFont()
	if font then fs:SetFont(font, size, "") end
	fs:SetTextColor(unpack(INK))
	fs:SetPoint(...)
	fs:SetText(text)
	return fs
end

-- A section heading, like "Description" in the quest log.
local function Heading(parent, text, x, y)
	local fs = Title(parent, text, 18, "TOPLEFT", x, y)
	fs:SetJustifyH("LEFT")
	return fs
end

local function Rule(parent, y)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetTexture("Interface\\QuestFrame\\UI-HorizontalBreak")
	rule:SetSize(W - 60, 24)
	rule:SetPoint("TOP", 0, y)
end

-- The rolled-up paper at the top or bottom, our own texture (Media/Roll.tga,
-- drawn by worldofwarcraft/art/roll.sh); the paper edge runs into
-- the middle of the roll. The bottom one is the same roll upside down, so
-- its shadow falls on the paper too.
local MEDIA = "Interface\\AddOns\\Skatteverket\\Media\\"
local function Roller(point, y, flip)
	local holder = CreateFrame("Frame", nil, scroll)
	holder:SetSize(W + 60, 70)
	holder:SetPoint(point, 0, y)
	holder:SetFrameLevel(scroll:GetFrameLevel() + 5)
	local roll = holder:CreateTexture(nil, "ARTWORK")
	roll:SetAllPoints()
	roll:SetTexture(MEDIA .. "Roll")
	if flip then roll:SetTexCoord(0, 1, 1, 0) end
end

local function Check(parent, label, onClick, ...)
	local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	box:SetSize(24, 24)
	box:SetPoint(...)
	local text = Ink(parent, 14, nil, "LEFT", box, "RIGHT", 2, 0)
	text:SetText(label)
	box:SetScript("OnClick", function(self)
		Sound(self:GetChecked() and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		onClick(self)
	end)
	return box
end

local function Button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 24)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local function ProfessionIcon(p, x, y)
	local b = CreateFrame("Button", nil, form)
	b:SetSize(34, 34)
	b:SetPoint("TOPLEFT", x, y)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexture("Interface\\Icons\\" .. p.icon)
	b.level = Ink(b, 11, nil, "TOP", b, "BOTTOM", 0, -2)
	b.level:SetJustifyH("CENTER")
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(p.label .. " (" .. p.name .. ")")
		local have = self.have
		GameTooltip:AddLine(have and string.format("%d/%d", have.rank, have.max) or "Har du inte", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b.p = p
	return b
end

local function Interests()
	local letters = ""
	for _, box in ipairs(interestBoxes) do
		if box:GetChecked() then letters = letters .. box.letter end
	end
	return letters
end

-- Grow the stamp from large and faint onto the paper.
local function Stamp()
	local s = scroll.stamp
	s:Show()
	local t = 0
	s:SetScript("OnUpdate", function(self, elapsed)
		t = t + elapsed
		local k = math.min(t / 0.25, 1)
		self:SetScale(2.5 - 1.5 * k)
		self:SetAlpha(k)
		if k >= 1 then
			self:SetScript("OnUpdate", nil)
			-- The sound when the seal lands, so it hits (Zach 7/11).
			Sound(STAMP_SOUND)
		end
	end)
end

-- The quest frame's way of showing text: letters fade in left to right.
-- In order (Zach 7/11): the intro writes itself; then the grand reveal,
-- the form fades in with a page sound; then a pause to look it over; then
-- the terms write themselves; then the signature line
-- fades in, and the buttons appear. A click on the paper
-- finishes it at once.
local REVEAL, VERIFY = 1.2, 3.5
local writing
local function Finish()
	writing = nil
	scroll.intro:SetAlphaGradient(4096, GRADIENT)
	scroll.terms:SetAlphaGradient(4096, GRADIENT)
	scroll.intro:SetAlpha(1)
	scroll.terms:SetAlpha(1)
	form:SetAlpha(1)
	signBlock:SetAlpha(1)
	scroll.buttons:Show()
	scroll:SetScript("OnUpdate", nil)
end

local function Write()
	if not scroll.intro.SetAlphaGradient then Finish() return end
	writing = { step = "intro", t = 0 }
	form:SetAlpha(0)
	signBlock:SetAlpha(0)
	scroll.terms:SetAlpha(0)
	scroll.buttons:Hide()
	scroll.intro:SetAlphaGradient(0, GRADIENT)
	scroll:SetScript("OnUpdate", function(_, elapsed)
		writing.t = writing.t + elapsed
		local step = writing.step
		if step == "intro" then
			if not scroll.intro:SetAlphaGradient(writing.t * CPS, GRADIENT) then
				writing.step, writing.t = "reveal", 0
				Sound("IG_ABILITY_PAGE_TURN")
			end
		elseif step == "reveal" then
			form:SetAlpha(math.min(writing.t / REVEAL, 1))
			if writing.t >= REVEAL then writing.step, writing.t = "verify", 0 end
		elseif step == "verify" then
			if writing.t >= VERIFY then
				writing.step, writing.t = "terms", 0
				scroll.terms:SetAlpha(1)
				scroll.terms:SetAlphaGradient(0, GRADIENT)
			end
		elseif step == "terms" then
			if not scroll.terms:SetAlphaGradient(writing.t * CPS, GRADIENT) then
				writing.step, writing.t = "sign", 0
			end
		else
			signBlock:SetAlpha(math.min(writing.t / REVEAL, 1))
			if writing.t >= REVEAL then Finish() end
		end
	end)
end

-- After signing the scroll waits a moment, then fades away (Zach 7/11).
local function FadeOut(delay)
	local t = -delay
	scroll:SetScript("OnUpdate", function(self, elapsed)
		t = t + elapsed
		if t > 0 then self:SetAlpha(math.max(1 - t / 0.8, 0)) end
		if t >= 0.8 then
			self:SetScript("OnUpdate", nil)
			self:Hide()
			self:SetAlpha(1)
		end
	end)
end

-- The registration itself; runs even if the scroll is closed mid-signature.
local signing
local function Complete()
	signing = nil
	Stamp()
	-- A keepsake: a screenshot of the sealed scroll, just after the seal has
	-- landed (Zach 7/11). It is saved on the member's own computer, in
	-- the game's Screenshots folder, like any other screenshot.
	-- Not when the scroll was closed mid-signature: nothing to show.
	if Screenshot and scroll:IsShown() then C_Timer.After(0.6, Screenshot) end
	ns.RequestNumber()
	ns.SendProfile()
	ns.RefreshScroll()
end

-- The name writes itself in by hand, then the stamp comes down with the
-- quest complete sound, then the scroll fades away. Signed already: Spara
-- keeps the new choices and closes.
local function Sign()
	if writing then Finish() end
	local char = ns.char
	if char.reg then
		char.reg.main, char.reg.interests = choice.main, Interests()
		Sound("IG_QUEST_LIST_CLOSE")
		scroll:Hide()
		ns.SendProfile()
		return
	end
	char.reg = { at = time(), main = choice.main, interests = Interests() }
	-- Said now, inside the click: the game lets an addon /say only from a
	-- click. Chat already shows who says it, so no name in the text (Zach 7/11).
	SendChatMessage("Jag har registrerat mig hos Skatteverket och är nu medborgare i " .. ns.GUILD .. "!", ANNOUNCE)
	local me = ns.Me() or UnitName("player")
	scroll.buttons:Hide()
	signing = true
	local sig = scroll.signature
	sig:SetText(me)
	if not sig.SetAlphaGradient then
		Complete()
		FadeOut(3)
		return
	end
	local t = 0
	sig:SetAlphaGradient(0, 12)
	scroll:SetScript("OnUpdate", function(self, elapsed)
		t = t + elapsed
		if sig:SetAlphaGradient(t * 14, 12) then return end
		Complete()
		FadeOut(3)
	end)
end

-- A line of text that works as a link: faded, darker under the mouse.
local function Link(parent, text, x, y, onClick)
	local b = CreateFrame("Button", nil, parent)
	local fs = Ink(b, 13, FADED, "LEFT", b, "LEFT", 0, 0)
	fs:SetText(text)
	b:SetSize(fs:GetStringWidth() + 4, 18)
	b:SetPoint("TOPLEFT", x, y)
	b:SetScript("OnEnter", function() fs:SetTextColor(unpack(INK)) end)
	b:SetScript("OnLeave", function() fs:SetTextColor(unpack(FADED)) end)
	b:SetScript("OnClick", onClick)
	return b
end

-- Page one is the registration, page two the terms and common questions.
local tabs = {}
local function ShowPage(n, quiet)
	if n == 2 and writing then Finish() end
	if not quiet then Sound("IG_ABILITY_PAGE_TURN") end
	if n == 2 then page:Hide() faq:Show() else faq:Hide() page:Show() end
	for i, tab in ipairs(tabs) do tab:SetChecked(i == n) end
end

-- Bookmark tabs on the right side of the scroll, like the spellbook's,
-- to flip between the pages; the link alone was easy to miss (Zach 7/11).
local function Tab(n, icon, tip)
	local tab = CreateFrame("CheckButton", nil, scroll)
	tab:SetSize(32, 32)
	tab:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 0, -90 - (n - 1) * 48)
	local back = tab:CreateTexture(nil, "BACKGROUND")
	back:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
	back:SetSize(64, 64)
	back:SetPoint("TOPLEFT", -3, 11)
	tab:SetNormalTexture("Interface\\Icons\\" .. icon)
	-- Glow textures made by hand with additive blending: given by path the
	-- client drew the checked one plain and the icon went black (Zach 7/11).
	local glow = tab:CreateTexture(nil, "HIGHLIGHT")
	glow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	glow:SetBlendMode("ADD")
	glow:SetAllPoints()
	local checked = tab:CreateTexture(nil, "OVERLAY")
	checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	checked:SetBlendMode("ADD")
	checked:SetAllPoints()
	tab:SetCheckedTexture(checked)
	tab:SetScript("OnClick", function() ShowPage(n) end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(tip)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
	tabs[n] = tab
end

-- Villkor och vanliga frågor (Zach 7/11): how to pay, the standings, the
-- commands, loans and citizenship, in the quest log's layout. The texts
-- are set when the page opens, so the rate is always the current one.
local faqTexts = {}
local FAQ = {
	{ "Hur betalar jag skatt?", "pay" },
	{ "Ställning", "standing" },
	{ "Kommandon", "commands" },
	{ "Lån", "loans" },
	{ "Medborgarskap", "citizen" },
}

local function SetFaqTexts()
	local rate = string.format("%g %%", ns.db.rate * 100)
	faqTexts.pay:SetText("Skatten, i dag " .. rate .. ", dras på guld du lootar och säljer till handlare eller på auktionshuset. Questbelöningar, post och byten beskattas aldrig. När du öppnar guildbanken betalas skatten av sig själv om du har hela beloppet på dig; annars trycker du Betala nu i /skatt.")
	faqTexts.standing:SetText("God: inget obetalt i mer än 48 timmar. Neutral: obetalt upp till en vecka. Negativ: obetalt i en vecka eller mer. Skatteverkets favorit #1-3 går till de längsta obrutna perioderna i god ställning. Guildet ser din ställning, beloppen ser bara guildledaren.")
	faqTexts.commands:SetText("/skatt - din skatt och allas ställning\n/skatt betala - betala vid guildbanken\n/skatt info - din skatt i chatten\n/skatt anmälan - din anmälan\n/skatt yrken - yrkesregistret\n/skatt hjälp - den här sidan\n/swedbank - låna guld av guildet")
	faqTexts.loans:SetText("Swedbank lånar ut guld med ränta per vecka. Ansök i /swedbank; bara guildledaren ser vem som har lånat.")
	faqTexts.citizen:SetText("När du har signerat får du ett skattenummer, och guildledaren ger dig rangen Medborgare.")
end

local function BuildFaq()
	faq = CreateFrame("Frame", nil, scroll)
	faq:SetAllPoints()
	Title(faq, "Villkor och vanliga frågor", 22, "TOP", 0, -46)
	Ink(faq, 13, FADED, "TOP", 0, -74):SetText("Skatteverket, " .. ns.GUILD)
	Rule(faq, -88)
	local x, prev = 34, nil
	for _, item in ipairs(FAQ) do
		local heading = Heading(faq, item[1], x, -112)
		if prev then
			heading:ClearAllPoints()
			heading:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -12)
		end
		local text = Ink(faq, 13, nil, "TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
		text:SetWidth(W - 2 * x)
		text:SetSpacing(2)
		faqTexts[item[2]] = text
		prev = text
	end
	local back = Button(faq, "Tillbaka", 110, function() ShowPage(1) end)
	back:SetPoint("BOTTOMLEFT", 34, 34)
	local close = Button(faq, "Stäng", 110, function()
		Sound("IG_QUEST_LIST_CLOSE")
		scroll:Hide()
	end)
	close:SetPoint("BOTTOMRIGHT", -34, 34)
	faq:Hide()
end

local function Build()
	scroll = CreateFrame("Frame", "SkatteverketScroll", UIParent)
	scroll:SetSize(W, H)
	scroll:SetPoint("CENTER", 0, 10)
	scroll:SetFrameStrata("DIALOG")
	scroll:SetClampedToScreen(true)
	scroll:SetMovable(true)
	scroll:EnableMouse(true)
	scroll:RegisterForDrag("LeftButton")
	scroll:SetScript("OnDragStart", scroll.StartMoving)
	scroll:SetScript("OnDragStop", scroll.StopMovingOrSizing)
	scroll:SetScript("OnMouseDown", function() if writing then Finish() end end)
	tinsert(UISpecialFrames, "SkatteverketScroll")

	-- A loose, handled sheet (Media/Paper.tga, worldofwarcraft/art/paper.sh,
	-- Zach 7/11); SCROLL brings back the parchment between two rolls.
	local parchment = scroll:CreateTexture(nil, "BACKGROUND")
	parchment:SetAllPoints()
	parchment:SetTexture(MEDIA .. (SCROLL and "Parchment" or "Paper"))
	if SCROLL then
		Roller("TOP", 35, false)
		Roller("BOTTOM", -35, true)
	end

	-- Page one, the registration; page two, the terms and questions (Zach 7/11).
	page = CreateFrame("Frame", nil, scroll)
	page:SetAllPoints()

	-- Laid out like the quest log (screenshot 7/11): headings in the quest
	-- title font like its "Description", body text below, the details in
	-- the lighter colour of its objective lines.
	Title(page, "Anmälan till Skatteverket", 22, "TOP", 0, -46)
	Ink(page, 13, FADED, "TOP", 0, -74):SetText(ns.GUILD)
	Rule(page, -88)

	local x = 34
	scroll.intro = Ink(page, 14, nil, "TOPLEFT", x, -116)
	scroll.intro:SetWidth(W - 2 * x)
	scroll.intro:SetSpacing(3)

	-- Everything that fades in after the intro.
	form = CreateFrame("Frame", nil, page)
	form:SetAllPoints()
	local y = -200
	Heading(form, "Uppgifter", x, y)
	Ink(form, 14, nil, "TOPLEFT", x, y - 26):SetText("Namn:")
	scroll.name = Ink(form, 14, nil, "TOPLEFT", x + 52, y - 26)
	scroll.who = Ink(form, 14, FADED, "TOPLEFT", x, y - 46)

	y = y - 72
	Heading(form, "Yrken", x, y)
	Ink(form, 11, FADED, "TOPLEFT", x + 62, y - 6):SetText("uppdateras automagiskt! Skatteverket har koll på dig serrö!")
	for i, p in ipairs(ns.PROFESSIONS) do
		local col, row = (i - 1) % 9, i <= 9 and 0 or 1
		local ix = row == 0 and (x + col * 48) or (x + 144 + col * 48)
		icons[i] = ProfessionIcon(p, ix, y - 26 - row * 56)
	end

	y = y - 136
	Heading(form, "Karaktär", x, y)
	mainBox = Check(form, "Huvudkaraktär", function() choice.main = true ns.RefreshScroll() end, "TOPLEFT", x, y - 22)
	altBox = Check(form, "Alt", function() choice.main = false ns.RefreshScroll() end, "TOPLEFT", x + 160, y - 22)

	y = y - 54
	Heading(form, "Intressen", x, y)
	-- Instanser is the long one; the boxes after it sit further right (screenshot 7/11).
	local spots = { 0, 84, 192, 276 }
	for i, interest in ipairs(ns.INTERESTS) do
		local box = Check(form, interest.label, function() end, "TOPLEFT", x + spots[i], y - 22)
		box.letter = interest.letter
		interestBoxes[i] = box
	end

	y = y - 54
	Heading(form, "Villkor", x, y)
	Link(form, "Läs villkor och vanliga frågor", x + 84, y - 4, function() ShowPage(2) end)
	scroll.terms = Ink(page, 14, nil, "TOPLEFT", x, y - 24)
	scroll.terms:SetWidth(W - 2 * x)
	scroll.terms:SetSpacing(2)

	y = y - 84
	-- The signature line comes last, revealed after the terms (Zach 7/11).
	signBlock = CreateFrame("Frame", nil, page)
	signBlock:SetAllPoints()
	Heading(signBlock, "Underskrift", x, y)
	y = y - 24
	-- Signed by hand: a script font shipped with the addon (Great Vibes,
	-- SIL Open Font License, Media/OFL.txt), written in slowly.
	local line = signBlock:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(INK[1], INK[2], INK[3], 0.6)
	line:SetSize(280, 1)
	line:SetPoint("TOPLEFT", x, y - 28)
	scroll.signature = signBlock:CreateFontString(nil, "OVERLAY", "QuestFont")
	if not scroll.signature:SetFont(MEDIA .. "GreatVibes-Regular.ttf", 30, "") then
		scroll.signature:SetFont(QuestFont:GetFont(), 18, "")
	end
	scroll.signature:SetTextColor(unpack(INK))
	scroll.signature:SetPoint("BOTTOMLEFT", line, "TOPLEFT", 6, -6)
	scroll.signDate = Ink(signBlock, 11, FADED, "TOPRIGHT", line, "BOTTOMRIGHT", 0, -2)
	scroll.signDate:SetJustifyH("RIGHT")

	-- The seal alone, no text (Zach 7/11), pressed at the end of the
	-- signature line, a little tilted; hidden until signed. A holder keeps
	-- its place while it scales.
	local holder = CreateFrame("Frame", nil, page)
	holder:SetSize(1, 1)
	holder:SetPoint("CENTER", line, "RIGHT", 56, 8)
	local stamp = CreateFrame("Frame", nil, holder)
	stamp:SetSize(76, 76)
	stamp:SetPoint("CENTER")
	stamp:SetFrameLevel(scroll:GetFrameLevel() + 10)
	local seal = stamp:CreateTexture(nil, "OVERLAY")
	-- Our own red wax seal with an S (Media/Seal.tga, worldofwarcraft/art/seal.sh, Zach 7/11).
	seal:SetTexture(MEDIA .. "Seal")
	seal:SetAllPoints()
	if seal.SetRotation then seal:SetRotation(-0.2) end
	stamp:Hide()
	scroll.stamp = stamp

	scroll.buttons = CreateFrame("Frame", nil, page)
	scroll.buttons:SetAllPoints()
	scroll.later = Button(scroll.buttons, "Senare", 110, function()
		Sound("IG_QUEST_LIST_CLOSE")
		scroll:Hide()
	end)
	scroll.later:SetPoint("BOTTOMLEFT", 34, 34)
	scroll.sign = Button(scroll.buttons, "Signera", 140, Sign)
	scroll.sign:SetPoint("BOTTOMRIGHT", -34, 34)

	BuildFaq()
	-- The addon version, small at the foot of both pages (Zach 7/11).
	Ink(scroll, 11, FADED, "BOTTOM", 0, 40):SetText("Skatteverket " .. ns.VERSION)
	Tab(1, "INV_Scroll_03", "Anmälan")
	Tab(2, "INV_Misc_Book_09", "Villkor och vanliga frågor")
	scroll:SetScript("OnHide", function(self)
		if writing then Finish() end
		-- Closed mid-signature: the registration still goes through.
		if signing then Complete() end
		self:SetScript("OnUpdate", nil)
		self:SetAlpha(1)
	end)
	scroll:Hide()
end

function ns.RefreshScroll()
	if not scroll or not scroll:IsShown() then return end
	local reg = ns.char.reg
	local me = ns.Me() or UnitName("player")
	scroll.name:SetText(me)
	scroll.who:SetText(string.format("Nivå %d %s %s", UnitLevel("player"), UnitRace("player") or "", UnitClass("player") or ""))

	local have = ns.ReadProfessions()
	for _, b in ipairs(icons) do
		b.have = have[b.p.code]
		b.icon:SetDesaturated(not b.have)
		b.icon:SetAlpha(b.have and 1 or 0.35)
		b.level:SetText(b.have and tostring(b.have.rank) or "")
	end

	mainBox:SetChecked(choice.main)
	altBox:SetChecked(not choice.main)

	-- Mid-signature the name is still writing itself; leave it alone.
	if signing then return end
	if reg then
		scroll.signature:SetText(me)
		scroll.signDate:SetText(date("%d/%m %Y", reg.at))
		scroll.stamp:Show()
		scroll.later:SetText("Stäng")
		scroll.sign:SetText("Spara")
	else
		scroll.signature:SetText("")
		scroll.signDate:SetText("")
		scroll.stamp:Hide()
		scroll.later:SetText("Senare")
		scroll.sign:SetText("Signera")
	end
end

-- Text that does not change while the scroll is open, set before it writes itself.
local function SetTexts()
	-- No greeting by name; the name stands in the form (Zach 7/11).
	scroll.intro:SetText(string.format("Skatteverket har noterat din ankomst till %s. Varje guldmynt du lootar eller säljer bär guildet framåt, och guildet glömmer inte dem som bär det. Fyll i din anmälan nedan och sätt ditt namn under.",
		ns.GUILD))
	scroll.terms:SetText(string.format("Jag förbinder mig att betala %g %% i skatt på lootat och sålt guld till %s. Guildet ser min ställning, beloppen ser bara guildledaren.",
		ns.db.rate * 100, ns.GUILD))
	SetFaqTexts()
end

-- Built at login, behind the loading screen, so the textures and the
-- script font are loaded before the scroll first opens (lag, Zach 7/11).
function ns.PreloadScroll()
	if not scroll then Build() end
end

function ns.ShowScroll()
	if not ns.InOurGuild() then
		ns.Print("den här karaktären är inte med i " .. ns.GUILD .. ".")
		return
	end
	if not scroll then Build() end
	ShowPage(1, true)
	local reg = ns.char.reg
	choice.main = not reg or reg.main ~= false
	for _, box in ipairs(interestBoxes) do
		box:SetChecked(reg and (reg.interests or ""):find(box.letter, 1, true) and true or false)
	end
	scroll.stamp:SetScale(1)
	scroll.stamp:SetAlpha(1)
	SetTexts()
	Sound("IG_QUEST_LIST_OPEN")
	scroll:Show()
	ns.RefreshScroll()
	-- Written out only before signing; a signed scroll opens complete.
	if reg then Finish() else Write() end
end

-- /skatt hjälp: the terms and questions page on its own.
function ns.ShowHelp()
	if not ns.InOurGuild() then
		ns.Print("den här karaktären är inte med i " .. ns.GUILD .. ".")
		return
	end
	ns.ShowScroll()
	ShowPage(2)
end
