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
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Vänsterklick: öppna panelen", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("Högerklick: välj Skatt, Yrken, Swedbank" .. (BokforingAPI and " eller Bokföring" or ""), 0.7, 0.7, 0.7)
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
		root:CreateTitle("THÖNDERSTÖRM")
		root:CreateButton("Skatt", function() ns.ShowTab(1) end)
		root:CreateButton("Yrken", function() ns.ShowTab(2) end)
		root:CreateButton("Swedbank", function() ns.ShowTab(6) end)
		if BokforingAPI then root:CreateButton("Bokföring", function() BokforingAPI.Toggle() end) end
		-- Not addons of their own: below a line (Zach 9/11).
		if root.CreateDivider then root:CreateDivider() end
		root:CreateButton("Nytt", function() ns.ShowTab(4) end)
		root:CreateButton("Inställningar", function() ns.ShowTab(5) end)
	end)
	-- Open to the left of the button, not over the minimap (Zach 9/11).
	if menu and menu.ClearAllPoints then
		menu:ClearAllPoints()
		menu:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT", 0, 0)
	end
end

function ns.RefreshOrderBadge()
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
		ns.Print("ikontest: klicka på minimapknappen för att se God, Neutral, Negativ och Ej godkänd. /skatt ikontest igen för att sluta.")
	end
	ns.RefreshMinimap()
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
	Place()
	ns.RefreshMinimap()
	ns.RefreshOrderBadge()
	-- The standing ages with time; recolour now and then.
	C_Timer.NewTicker(10, ns.RefreshMinimap)
end
