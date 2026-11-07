-- Skatteverket, Yrkesregister: every registered member's professions,
-- main or alt and interests, for the whole guild (Zach 7/11). Click a
-- profession icon to list only those who have it, highest level first.

local _, ns = ...

local ROWS, ROW_H, W = 16, 18, 760
local COLS = { { "Nr", 70 }, { "Namn", 160 }, { "Typ", 50 }, { "Yrken", 330 }, { "Intressen", 110 } }

local frame, rows, filters, sorted = nil, {}, {}, {}
local offset, filter = 0, nil

local function Text(parent, template, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetPoint(...)
	fs:SetJustifyH("LEFT")
	return fs
end

local function ProfessionText(profs, first)
	local list, parts = ns.DecodeProfessions(profs), {}
	if first and list[first] then
		table.insert(parts, "|cffffd100" .. ns.PROFESSION_BY_CODE[first].label .. " " .. list[first].rank .. "|r")
	end
	for _, p in ipairs(ns.PROFESSIONS) do
		if list[p.code] and p.code ~= first then table.insert(parts, p.label .. " " .. list[p.code].rank) end
	end
	return table.concat(parts, ", "), list
end

local function Build()
	frame = CreateFrame("Frame", "SkatteverketRegistry", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetSize(W, 480)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "SkatteverketRegistry")

	local header = frame:CreateTexture(nil, "ARTWORK")
	header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	header:SetSize(320, 64)
	header:SetPoint("TOP", 0, 12)
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", header, "TOP", 0, -14)
	title:SetText("Yrkesregister")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	Text(frame, "GameFontNormalSmall", "TOPLEFT", 24, -36):SetText("Klicka på ett yrke för att visa bara de som har det:")
	for i, p in ipairs(ns.PROFESSIONS) do
		local b = CreateFrame("Button", nil, frame)
		b:SetSize(30, 30)
		b:SetPoint("TOPLEFT", 24 + (i - 1) * 36, -54)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.icon:SetTexture("Interface\\Icons\\" .. p.icon)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetScript("OnClick", function()
			filter = filter ~= p.code and p.code or nil
			offset = 0
			ns.RefreshRegistry()
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:AddLine(p.label .. " (" .. p.name .. ")")
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b.code = p.code
		filters[i] = b
	end
	frame.filterText = Text(frame, "GameFontHighlightSmall", "TOPLEFT", 24 + #ns.PROFESSIONS * 36 + 8, -64)

	local x = 24
	for _, col in ipairs(COLS) do
		Text(frame, "GameFontNormalSmall", "TOPLEFT", x, -98):SetText(col[1])
		x = x + col[2]
	end
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, frame)
		row:SetSize(W - 40, ROW_H)
		row:SetPoint("TOPLEFT", 20, -112 - (i - 1) * ROW_H)
		row.cells = {}
		local cx = 4
		for c, col in ipairs(COLS) do
			local fs = Text(row, "GameFontHighlightSmall", "LEFT", cx, 0)
			fs:SetWidth(col[2] - 6)
			fs:SetWordWrap(false)
			row.cells[c] = fs
			cx = cx + col[2]
		end
		rows[i] = row
	end
	frame.count = Text(frame, "GameFontDisableSmall", "BOTTOMLEFT", 24, 50)
	frame.count:SetWidth(W - 48)

	local mine = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	mine:SetSize(120, 22)
	mine:SetText("Min anmälan")
	mine:SetPoint("BOTTOMLEFT", 24, 18)
	mine:SetScript("OnClick", ns.ShowScroll)
	local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	closeButton:SetSize(100, 22)
	closeButton:SetText("Stäng")
	closeButton:SetPoint("BOTTOMRIGHT", -24, 18)
	closeButton:SetScript("OnClick", function() frame:Hide() end)

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta, #sorted - ROWS))
		ns.RefreshRegistry()
	end)
	frame:Hide()
end

function ns.RefreshRegistry()
	if not frame or not frame:IsShown() then return end
	local db = ns.db
	local roster = ns.RosterNames()
	wipe(sorted)
	local levels = {}
	for name, m in pairs(db.members) do
		if m.profileAt and (not roster or roster[name]) then
			local list = ns.DecodeProfessions(m.profs)
			if not filter or list[filter] then
				table.insert(sorted, name)
				levels[name] = filter and list[filter].rank or 0
			end
		end
	end
	table.sort(sorted, function(a, b)
		if levels[a] ~= levels[b] then return levels[a] > levels[b] end
		local na, nb = db.members[a].number or 9999, db.members[b].number or 9999
		if na ~= nb then return na < nb end
		return a < b
	end)
	offset = math.max(0, math.min(offset, #sorted - ROWS))

	for _, b in ipairs(filters) do
		b.icon:SetDesaturated(filter ~= nil and b.code ~= filter)
	end
	frame.filterText:SetText(filter and ("Visar: " .. ns.PROFESSION_BY_CODE[filter].label) or "Visar: alla")

	for i, row in ipairs(rows) do
		local name = sorted[i + offset]
		local m = name and db.members[name]
		if m then
			local values = { ns.Number(m.number) or "-", name, m.main and "Main" or "Alt",
				ProfessionText(m.profs, filter), ns.InterestText(m.interests) }
			for c, fs in ipairs(row.cells) do fs:SetText(values[c]) end
			row:Show()
		else
			row:Hide()
		end
	end

	local missing = 0
	for i = 1, GetNumGuildMembers() do
		local name = ns.Short(GetGuildRosterInfo(i))
		if name and not (db.members[name] and db.members[name].profileAt) then missing = missing + 1 end
	end
	if #sorted == 0 then
		frame.count:SetText(filter and "Ingen registrerad har det yrket än." or "Ingen har registrerat sig än.")
	else
		frame.count:SetText(string.format("Visar %d-%d av %d (scrolla med mushjulet). Inte registrerade än: %d.",
			offset + 1, math.min(offset + ROWS, #sorted), #sorted, missing))
	end
end

function ns.ToggleRegistry()
	if not frame then Build() end
	if frame:IsShown() then frame:Hide() return end
	frame:Show()
	ns.RequestRoster()
	ns.RequestBoard()
	ns.RefreshRegistry()
end
