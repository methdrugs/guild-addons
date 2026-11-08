-- Skatteverket, the THÖNDERSTÖRM minimap button (Zach 8/11): a white
-- lightning bolt on a black disc in the game's gold ring, on the minimap's
-- edge. Click opens the panel, right-click its Swedbank tab, Shift+drag
-- moves it round the rim. The tooltip always says the tax owed. The
-- disc shows the tax standing (Zach 8/11, art/bolt.sh): one big white
-- bolt on grey for God, yellow for Neutral, red for Negativ, and a dimmed
-- bolt on grey until approved. Nothing more: the button is too small for
-- details (Zach 8/11). Hidden or shown under Inställningar; the place and
-- the choice are saved for the whole account.

local _, ns = ...

local button

local MEDIA = "Interface\\AddOns\\Skatteverket\\Media\\"
local LOOKS = { good = "MinimapGood", neutral = "MinimapNeutral", negative = "MinimapNegative", locked = "MinimapLocked" }

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
	if not ns.InOurGuild() or ns.Locked() then return "locked" end
	return ns.Standing(ns.char)
end

function ns.RefreshMinimap()
	if not button then return end
	if Settings().hide then button:Hide() return end
	button:Show()
	button.icon:SetTexture(MEDIA .. (LOOKS[State()] or LOOKS.good))
end

local function Tooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine(ns.GUILD)
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
	GameTooltip:AddLine("Högerklick: Swedbank", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("Shift+dra: flytta knappen", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

-- Follows the cursor round the rim while Shift+dragged.
local function Drag()
	local mx, my = Minimap:GetCenter()
	local x, y = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	Settings().angle = math.deg(math.atan2(y / scale - my, x / scale - mx))
	Place()
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
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			ns.ToggleWindow(6)
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
	Place()
	ns.RefreshMinimap()
	-- The standing ages with time; recolour now and then.
	C_Timer.NewTicker(10, ns.RefreshMinimap)
end
