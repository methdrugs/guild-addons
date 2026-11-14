-- Skatteverket, the THÖNDERSTÖRM minimap button (Zach 8/11): a white
-- lightning bolt on a black disc in the game's gold ring, on the minimap's
-- edge. Click opens the panel, right-click a list of the guild's addons
-- (Skatt, Yrken, Swedbank, and Bokföring where installed; Zach 9/11), Shift+drag
-- moves it round the rim. The tooltip always says the tax owed. The
-- disc shows the tax standing (Zach 8/11, art/bolt.sh): one big white
-- bolt on grey for God, yellow for Neutral, red for Negativ, and a dimmed
-- bolt on grey until approved. Nothing more: the button is too small for
-- details (Zach 8/11). At Negativ a red glow round it breathes in and out
-- every 1.5 seconds, for as long as it lasts (0.23, Zach 8/11). Hidden or shown under Inställningar; the place and
-- the choice are saved for the whole account.

local _, ns = ...

local button

local MEDIA = "Interface\\AddOns\\Skatteverket\\Media\\"
local LOOKS = { good = "MinimapGood", neutral = "MinimapNeutral", negative = "MinimapNegative", locked = "MinimapLocked" }
local NAMES = { good = "God", neutral = "Neutral", negative = "Negativ", locked = "Ej godkänd" }

-- /skatt ikontest, the leader only: clicks step through the four looks
-- so they can be seen without a debt; nothing else changes.
local TEST = { "good", "neutral", "negative", "locked" }
local test

local function Settings()
	local db = ns.db
	db.minimap = db.minimap or { angle = 200 }
	return db.minimap
end

local function Place()
	local angle = math.rad(Settings().angle)
	local radius = Minimap:GetWidth() / 2 + 10
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
end

local function State()
	if test then return TEST[test] end
	if not ns.InOurGuild() or ns.Locked() then return "locked" end
	return ns.Standing(ns.char)
end

function ns.RefreshMinimap()
	if not button then return end
	if Settings().hide then button:Hide() return end
	button:Show()
	local state = State()
	button.icon:SetTexture(MEDIA .. (LOOKS[state] or LOOKS.good))
	if state == "negative" then
		button.glow:Show()
		if not button.pulse:IsPlaying() then button.pulse:Play() end
	else
		button.pulse:Stop()
		button.glow:Hide()
	end
end

-- What waits for him (Zach 10/11: something on the bolt that draws his
-- attention after being away): for the leader loan applications, late
-- loans and members to make Medborgare; for everyone work orders. A yellow
-- ! pulses on the bolt while anything waits, the tooltip lists it, and the
-- right-click menu has each as a button. It stays until it is dealt with.
function ns.Todo()
	local out = {}
	if ns.InOurGuild() and IsGuildLeader() then
		local pending, overdue, ledger = 0, 0, 0
		if SwedbankPanel and SwedbankPanel.LeaderTodo then pending, overdue, ledger = SwedbankPanel.LeaderTodo() end
		ledger = ledger or 0
		-- Loans mailed from his gold, or repayments mailed to him (Zach 10/11):
		-- settled by itself at the next guild bank visit.
		if ledger > 0 then
			table.insert(out, { text = string.format("Guildbanken är skyldig dig %s (lån du skickat)", ns.Money(ledger)), click = function() ns.ShowTab(6) end })
		elseif ledger < 0 then
			table.insert(out, { text = string.format("Sätt in %s i guildbanken (lånebetalningar)", ns.Money(-ledger)), click = function() ns.ShowTab(6) end })
		end
		if pending > 0 then
			table.insert(out, { text = string.format("%d låneansökning%s väntar", pending, pending == 1 and "" or "ar"), click = function() ns.ShowTab(6) end })
		end
		if overdue > 0 then
			table.insert(out, { text = string.format("%d lån är försenade", overdue), click = function() ns.ShowTab(6) end })
		end
		for _, name in ipairs(ns.ToPromote and ns.ToPromote() or {}) do
			table.insert(out, { text = string.format("Ge %s rangen %s", name, ns.CITIZEN_RANK), click = function() ns.PromoteToCitizen(name) end })
		end
	end
	-- An update waiting (Zach 11/11): Nytt says what.
	local behind = ns.Behind and ns.Behind() or {}
	if #behind > 0 then
		table.insert(out, { text = "Uppdatera: " .. table.concat(behind, ", "), click = function() ns.ShowTab(4) end, update = true })
	end
	-- Who left while he was away (Zach 10/11).
	for _, t in ipairs(ns.LeaverTodo and ns.LeaverTodo() or {}) do table.insert(out, t) end
	for _, t in ipairs(ns.OrderNotices and ns.OrderNotices() or {}) do table.insert(out, t) end
	-- Folkvald representant and Kontakta oss! (Zach 11/11).
	for _, list in ipairs({ ns.FolkTodo and ns.FolkTodo() or {}, ns.BidragTodo and ns.BidragTodo() or {}, ns.ContactTodo and ns.ContactTodo() or {} }) do
		for _, t in ipairs(list) do table.insert(out, t) end
	end
	local orders = ns.OrdersToDo and ns.OrdersToDo() or 0
	if orders > 0 then
		table.insert(out, { text = string.format("%d arbetsorder%s väntar på dig", orders, orders == 1 and "" or "ar"), click = function() ns.ShowTab(8) end })
	end
	return out
end

function ns.RefreshTodo()
	if not button or not button.notice then return end
	-- Orders have their own hammer and an update Nytt's note (Zach 11/11:
	-- not the !); the ! is for the rest.
	local others, update = 0, false
	for _, t in ipairs(ns.Todo()) do
		if t.update then update = true
		elseif not t.text:find("arbetsorder") then others = others + 1 end
	end
	-- /skatt ikontest shows it too, to see it without an update.
	update = update or test ~= nil
	button.update:SetShown(update)
	if update then
		if not button.updatePulse:IsPlaying() then button.updatePulse:Play() end
	else
		button.updatePulse:Stop()
	end
	button.notice:SetShown(others > 0)
	if others > 0 then
		if not button.noticePulse:IsPlaying() then button.noticePulse:Play() end
	else
		button.noticePulse:Stop()
	end
end

local function Tooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine(ns.GUILD)
	if test then
		GameTooltip:AddLine("Ikontest: " .. NAMES[TEST[test]], 1, 0.82, 0)
		GameTooltip:AddLine("Klicka för nästa, /skatt ikontest för att sluta.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
		return
	end
	local state = State()
	if not ns.InOurGuild() then
		GameTooltip:AddLine("Inte med i " .. ns.GUILD .. ".", 0.5, 0.5, 0.5)
	else
		if state == "locked" then
			GameTooltip:AddLine("Inte godkänd medborgare än.", 0.5, 0.5, 0.5)
		else
			local top = ns.TopPayers()[ns.Me() or ""]
			GameTooltip:AddLine("Ställning: " .. (top and ns.TopLabel(top) or ns.LABELS[state]), 1, 1, 1)
		end
		-- Taxed whether approved or not, so always shown (Zach 8/11).
		GameTooltip:AddLine("Skatt att betala: " .. ns.Money(math.max(ns.char.owed, 0)), 1, 1, 1)
		-- How much play time is left before the standing drops (Zach 10/11).
		local debt, _, standing = ns.AccountState()
		local function Hours(s)
			s = math.max(0, math.floor(s / 60))
			return s >= 60 and string.format("%d h %d min", math.floor(s / 60), s % 60) or string.format("%d min", s)
		end
		if debt > 0 and standing == "good" then
			GameTooltip:AddLine("Speltid kvar till Neutral: " .. Hours(ns.GOOD_PLAY - debt), 1, 0.82, 0)
		elseif debt > 0 and standing == "neutral" then
			GameTooltip:AddLine("Speltid kvar till Negativ: " .. Hours(ns.NEGATIVE_PLAY - debt), 1, 0.4, 0.4)
		end
	end
	local todo = ns.Todo()
	if #todo > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Att göra:", 1, 0.82, 0)
		for _, t in ipairs(todo) do GameTooltip:AddLine("  " .. t.text, 1, 1, 1) end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Vänsterklick: öppna panelen", 0.7, 0.7, 0.7)
	-- Only the parts that are on (Delar, Zach 14/11).
	local parts = { "Skatt" }
	if ns.YrkenOn() then table.insert(parts, "Yrken") end
	if SwedbankPanel then table.insert(parts, "Swedbank") end
	if BokforingAPI then table.insert(parts, "Bokföring") end
	local last = table.remove(parts)
	GameTooltip:AddLine("Högerklick: välj " .. (#parts > 0 and (table.concat(parts, ", ") .. " eller ") or "") .. last, 0.7, 0.7, 0.7)
	GameTooltip:AddLine("Shift+dra: flytta knappen", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

-- Right-click: the guild's addons to open (Zach 9/11). Bokföring is its
-- own addon with its own panel, listed when it is installed.
function ns.AddonMenu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		ns.ToggleWindow(6)
		return
	end
	GameTooltip:Hide()
	local menu = MenuUtil.CreateContextMenu(owner, function(_, root)
		-- What waits for him first, each a click away (Zach 10/11).
		local todo = ns.Todo()
		if #todo > 0 then
			root:CreateTitle("Att göra")
			for _, t in ipairs(todo) do root:CreateButton(t.text, t.click) end
			if root.CreateDivider then root:CreateDivider() end
		end
		root:CreateTitle("THÖNDERSTÖRM")
		-- Right under the title (Zach 12/11): who leads, and contact them.
		root:CreateButton("Folkvald representant", function() ns.ShowTab(11) end)
		root:CreateButton("Skatt", function() ns.ShowTab(1) end)
		-- Yrken and Swedbank only while on (Delar, Zach 14/11).
		if ns.YrkenOn() then root:CreateButton("Yrken", function() ns.ShowTab(2) end) end
		if SwedbankPanel then root:CreateButton("Swedbank", function() ns.ShowTab(6) end) end
		if BokforingAPI then root:CreateButton("Bokföring", function() BokforingAPI.Toggle() end) end
		-- Not addons of their own: below a line (Zach 9/11).
		if root.CreateDivider then root:CreateDivider() end
		root:CreateButton("Nytt", function() ns.ShowTab(4) end)
		root:CreateButton("Kontakta oss!", function() ns.ShowTab(13) end)
		root:CreateButton("Inställningar", function() ns.ShowTab(5) end)
	end)
	-- Open to the left of the button, not over the minimap (Zach 9/11).
	if menu and menu.ClearAllPoints then
		menu:ClearAllPoints()
		menu:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT", 0, 0)
	end
end

function ns.RefreshOrderBadge()
	ns.RefreshTodo()
	if not button or not button.hammer then return end
	local todo = ns.OrdersToDo and ns.OrdersToDo() or 0
	button.hammer:SetShown(todo > 0)
	if todo > 0 then
		if not button.hammerPulse:IsPlaying() then button.hammerPulse:Play() end
	else
		button.hammerPulse:Stop()
	end
end

-- Follows the cursor round the rim while Shift+dragged.
local function Drag()
	local mx, my = Minimap:GetCenter()
	local x, y = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	Settings().angle = math.deg(math.atan2(y / scale - my, x / scale - mx))
	Place()
end

function ns.IconTest()
	if not IsGuildLeader() then ns.Print("bara guildledaren kan göra det.") return end
	if not button then return end
	if test then
		test = nil
		ns.Print("ikontest av; knappen visar din ställning igen.")
	else
		test = 1
		ns.Print("ikontest: klicka på minimapknappen för att se God, Neutral, Negativ och Ej godkänd; lappen nere till vänster är uppdateringen. /skatt ikontest igen för att sluta.")
	end
	ns.RefreshMinimap()
	ns.RefreshTodo()
end

function ns.BuildMinimap()
	if button or not Minimap then return end
	button = CreateFrame("Button", "SkatteverketMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 6, -5)
	button.icon = icon
	-- The red pulse, behind the ring, faded in and out.
	local glow = button:CreateTexture(nil, "BACKGROUND")
	glow:SetTexture(MEDIA .. "MinimapGlow")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(1, 0.15, 0.1)
	glow:SetSize(44, 44)
	glow:SetPoint("CENTER", icon, "CENTER")
	glow:Hide()
	button.glow = glow
	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.15)
	fade:SetToAlpha(1)
	fade:SetDuration(0.75)
	fade:SetSmoothing("IN_OUT")
	button.pulse = pulse
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	button:SetScript("OnClick", function(_, mouse)
		if test and mouse ~= "RightButton" then
			test = test % #TEST + 1
			ns.RefreshMinimap()
			Tooltip(button)
		elseif mouse == "RightButton" then
			ns.AddonMenu(button)
		else
			ns.ToggleWindow(1)
		end
	end)
	button:SetScript("OnDragStart", function(self)
		if not IsShiftKeyDown() then return end
		self:SetScript("OnUpdate", Drag)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", Tooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- A hammer in the corner while work orders wait for you (Zach 9/11),
	-- pulsing like the red standing.
	local hammer = button:CreateTexture(nil, "OVERLAY", nil, 2)
	hammer:SetTexture("Interface\\Icons\\INV_Hammer_20")
	hammer:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	hammer:SetSize(13, 13)
	hammer:SetPoint("BOTTOMRIGHT", -2, 3)
	hammer:Hide()
	local hammerPulse = hammer:CreateAnimationGroup()
	hammerPulse:SetLooping("BOUNCE")
	local hammerFade = hammerPulse:CreateAnimation("Alpha")
	hammerFade:SetFromAlpha(0.45)
	hammerFade:SetToAlpha(1)
	hammerFade:SetDuration(0.8)
	hammerFade:SetSmoothing("IN_OUT")
	button.hammer, button.hammerPulse = hammer, hammerPulse
	-- A yellow ! in the top corner while something waits for him.
	local notice = button:CreateTexture(nil, "OVERLAY", nil, 3)
	notice:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
	notice:SetSize(14, 14)
	notice:SetPoint("TOPLEFT", 1, -1)
	notice:Hide()
	local noticePulse = notice:CreateAnimationGroup()
	noticePulse:SetLooping("BOUNCE")
	local noticeFade = noticePulse:CreateAnimation("Alpha")
	noticeFade:SetFromAlpha(0.4)
	noticeFade:SetToAlpha(1)
	noticeFade:SetDuration(0.7)
	noticeFade:SetSmoothing("IN_OUT")
	button.notice, button.noticePulse = notice, noticePulse
	-- Nytt's note while an update waits (Zach 11/11), slow and soft.
	local update = button:CreateTexture(nil, "OVERLAY", nil, 2)
	update:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
	update:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	update:SetSize(13, 13)
	update:SetPoint("BOTTOMLEFT", 2, 3)
	update:Hide()
	local updatePulse = update:CreateAnimationGroup()
	updatePulse:SetLooping("BOUNCE")
	local updateFade = updatePulse:CreateAnimation("Alpha")
	updateFade:SetFromAlpha(0.55)
	updateFade:SetToAlpha(1)
	updateFade:SetDuration(1.4)
	updateFade:SetSmoothing("IN_OUT")
	button.update, button.updatePulse = update, updatePulse
	Place()
	ns.RefreshMinimap()
	ns.RefreshOrderBadge()
	-- The standing ages with time; recolour now and then.
	C_Timer.NewTicker(10, ns.RefreshMinimap)
end

-- New ranks and new signatures show in the roster.
local roster = CreateFrame("Frame")
roster:RegisterEvent("GUILD_ROSTER_UPDATE")
local soon = false
roster:SetScript("OnEvent", function()
	if soon or not ns.db then return end
	soon = true
	C_Timer.After(2, function()
		soon = false
		ns.RefreshTodo()
	end)
end)
