-- Skatteverket: the Folkvald representant window (Zach 11/11, renamed from Intresseanmälan 12/11), from the minimap
-- button's list under Bokföring: Folkvald representant (page 11) and
-- Socialbidrag (page 12) as side tabs. Members see the roles, who holds
-- them, and apply, challenge and vote; the guild leader also places holders
-- with a drop-down, reads the applications, accepts challenges, starts the
-- round and settles each vote. The rules are in Folk.lua and Bidrag.lua.
-- Side tabs again since 14/11 (Zach): Representanter (the roles) and
-- Medlemmar (every member, alts under their main).

local _, ns = ...

local ROW_H = 36
local page, bidrag, members
-- Which side tab is open: "rep" Representanter, "med" Medlemmar.
local side = "rep"

local function Text(parent, template, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetPoint(...)
	fs:SetJustifyH("LEFT")
	return fs
end

local function Button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local function Input(parent, width)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	return box
end

-- A framed box of several lines with a character count under it.
function ns.TextArea(parent, w, h, max, onChange)
	local holder = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	holder:SetSize(w, h)
	if holder.SetBackdrop then
		holder:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		holder:SetBackdropColor(0, 0, 0, 0.6)
	end
	local box = CreateFrame("EditBox", nil, holder)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontNormal")
	box:SetMaxLetters(max)
	box:SetPoint("TOPLEFT", 8, -8)
	box:SetWidth(w - 16)
	box:SetHeight(h - 16)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() box:SetFocus() end)
	holder.count = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	holder.count:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -2)
	box:SetScript("OnTextChanged", function(self)
		holder.count:SetText(ns.Len(self:GetText()) .. "/" .. max)
		if onChange then onChange() end
	end)
	holder.box = box
	return holder
end

-- A bookmark tab on the window's right edge, like the spellbook's; the
-- same as Window.lua's side tabs.
local function SideTab(parent, k, icon, tip, onClick)
	local tab = CreateFrame("CheckButton", nil, parent)
	tab:SetSize(32, 32)
	tab:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, -48 - (k - 1) * 48)
	local back = tab:CreateTexture(nil, "BACKGROUND")
	back:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
	back:SetSize(64, 64)
	back:SetPoint("TOPLEFT", -3, 11)
	tab:SetNormalTexture("Interface\\Icons\\" .. icon)
	local glow = tab:CreateTexture(nil, "HIGHLIGHT")
	glow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	glow:SetBlendMode("ADD")
	glow:SetAllPoints()
	local checked = tab:CreateTexture(nil, "OVERLAY")
	checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	checked:SetBlendMode("ADD")
	checked:SetAllPoints()
	tab:SetCheckedTexture(checked)
	tab:SetScript("OnClick", function()
		onClick()
		if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end
	end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(tip)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return tab
end

-- A context menu of choices, scrolling when long; nil on clients without one.
local function Menu(owner, build)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		if root.SetScrollMode then pcall(root.SetScrollMode, root, 400) end
		build(root)
	end)
end

local function Has(list, name)
	for _, n in ipairs(list) do
		if n == name then return true end
	end
end

local function HolderText(role)
	local holders = ns.Holders(role.id)
	local text = #holders > 0 and table.concat(holders, ", ") or "|cff999999Vakant|r"
	if role.seats > 1 and #holders < role.seats then
		text = text .. string.format(" |cff999999(%d ledig%s)|r", role.seats - #holders, role.seats - #holders == 1 and "" or "a")
	end
	return text
end

-- The detail view: apply, a ballot, or the leader's applications --------

local detail
local Refresh

local function ClearDetail()
	for _, r in ipairs(detail.rows) do r:Hide() end
	detail.form:Hide()
	detail.settle:Hide()
	detail.startVote:Hide()
	detail.used = 0
end

-- A row on the detail list: a name, a text, up to two buttons.
local function DetailRow(name, text, buttons)
	detail.used = detail.used + 1
	local row = detail.rows[detail.used]
	if not row then
		row = CreateFrame("Frame", nil, detail.child)
		row:SetWidth(620)
		row.name = Text(row, "GameFontNormal", "TOPLEFT", 0, 0)
		row.text = Text(row, "GameFontHighlight", "TOPLEFT", 0, -18)
		row.text:SetWidth(440)
		row.text:SetWordWrap(true)
		row.b1 = Button(row, "", 80)
		row.b1:SetPoint("TOPRIGHT", -96, 0)
		row.b2 = Button(row, "", 80)
		row.b2:SetPoint("TOPRIGHT", -8, 0)
		detail.rows[detail.used] = row
	end
	row.name:SetText(name)
	row.text:SetText(text)
	for k, key in ipairs({ "b1", "b2" }) do
		local spec = buttons and buttons[k]
		row[key]:SetShown(spec ~= nil)
		if spec then
			row[key]:SetText(spec.label)
			row[key]:SetScript("OnClick", spec.click)
			if spec.disabled then row[key]:Disable() else row[key]:Enable() end
		end
	end
	local h = 22 + math.max(14, row.text:GetStringHeight())
	row:SetHeight(h)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", 0, -(detail.y or 0))
	detail.y = (detail.y or 0) + h + 10
	row:Show()
	return row
end

local function ShowBallot(b)
	ClearDetail()
	detail.mode, detail.ballot = "ballot", b
	local role = ns.ROLE[b.role]
	local now, leader = ns.Now(), IsGuildLeader()
	local ended = now >= b.ends
	detail.title:SetText("Omröstning: " .. role.title)
	local head = b.result and ("Avgjord. Vald: " .. (#b.result.winners > 0 and table.concat(b.result.winners, ", ") or "ingen") .. ".")
		or ended and "Röstningen är slut; guildledaren fastställer resultatet."
		or ("Pågår till " .. ns.When(b.ends) .. ". En röst per konto, hemlig: guildledaren ser bara summan.")
	if b.holder then head = head .. " Utmaning: " .. b.holder .. " försvarar platsen." end
	detail.sub:SetText(head .. "\n|cffffd100Officiell information för alla medlemmar:|r " .. role.duty)
	detail.y = 0
	if not ns.BallotComplete(b) then
		DetailRow("Hämtar kandidaterna…", "", nil)
		ns.AskBallot(b)
		return
	end
	local mine = ns.Folk().myVotes
	local counts, winners = {}
	if b.result then
		counts = b.result.counts
	elseif leader then
		counts, winners = ns.Totals(b)
		-- His choice starts from the rules' winners; ties are left to him.
		if detail.chosenFor ~= b.id then
			detail.chosenFor, detail.chosen = b.id, {}
			for _, w in ipairs(winners) do detail.chosen[w] = true end
		end
	end
	for _, name in ipairs(b.order) do
		local c = b.cands[name]
		local text = c.reason or ""
		if c.title and c.title ~= "" then text = "Förslag på titel: " .. c.title .. "\n" .. text end
		local label = name
		if counts[name] then
			label = label .. (b.kind == "J" and string.format("  |cffffffff(ja/nej %s)|r", counts[name]) or string.format("  |cffffffff(%s röster)|r", counts[name]))
		end
		local buttons
		if leader and ended and not b.result then
			buttons = { { label = detail.chosen[name] and "Vald" or "Inte vald", click = function()
				detail.chosen[name] = not detail.chosen[name] or nil
				ShowBallot(b)
			end } }
		elseif not ended and not b.result then
			if b.kind == "J" then
				local key = b.id .. "/" .. name
				local voted = mine[key]
				buttons = {
					{ label = voted == "J" and "Din: Ja" or "Ja", disabled = voted ~= nil, click = function() ns.Vote(b, key, "J") ShowBallot(b) end },
					{ label = voted == "N" and "Din: Nej" or "Nej", disabled = voted ~= nil, click = function() ns.Vote(b, key, "N") ShowBallot(b) end },
				}
			else
				local voted = mine[b.id]
				buttons = { nil, { label = voted == name and "Din röst" or "Rösta", disabled = voted ~= nil, click = function() ns.Vote(b, b.id, name) ShowBallot(b) end } }
			end
		end
		DetailRow(label, text, buttons)
	end
	if leader and ended and not b.result then
		detail.settle:Show()
		detail.settle:SetScript("OnClick", function()
			local list = {}
			for _, name in ipairs(b.order) do
				if detail.chosen[name] then table.insert(list, name) end
			end
			ns.Settle(b.id, list)
			detail.chosen, detail.chosenFor = nil, nil
			ShowBallot(b)
		end)
	end
	detail.child:SetHeight(detail.y)
end

local function ShowApps(role)
	ClearDetail()
	detail.mode, detail.role = "apps", role
	local r = ns.ROLE[role]
	detail.title:SetText("Ansökningar: " .. r.title)
	detail.sub:SetText("Bara du ser dem. En utmaning du godtar öppnar en omröstning i 3 dagar mellan innehavaren och utmanaren, och innehavaren får en raid warning om att någon utmanar.")
	detail.y = 0
	local apps = ns.AppsFor(role)
	if #apps == 0 then DetailRow("Inga ansökningar.", "", nil) end
	for _, a in ipairs(apps) do
		local label = a.name .. (a.challenge and ("  |cffff8040utmanar " .. (a.target or "?") .. "|r") or "") .. "  |cff999999" .. ns.When(a.at) .. "|r"
		local text = a.reason
		if a.title and a.title ~= "" then text = "Förslag på titel: " .. a.title .. "\n" .. text end
		local name = a.name
		DetailRow(label, text, {
			a.challenge and { label = "Godta", click = function() ns.AcceptChallenge(name) ShowApps(role) end } or nil,
			{ label = "Avböj", click = function() ns.DeclineApp(name) ShowApps(role) end },
		})
	end
	local plain = ns.AppsFor(role, false)
	if #plain > 0 and not ns.RoundPhase() and not ns.BallotFor(role) then
		detail.startVote:Show()
		detail.startVote:SetScript("OnClick", function() ns.StartRoleVote(role) ShowApps(role) end)
	end
	detail.child:SetHeight(detail.y)
end

-- app: Ändra ansökan (Zach 14/11), the form filled with what was sent.
local function ShowApply(role, target, app)
	ClearDetail()
	detail.mode, detail.role, detail.target, detail.edit = "apply", role, target, app ~= nil
	local r = ns.ROLE[role]
	detail.title:SetText((app and "Ändra ansökan: " or target and "Utmana: " or "Ansök: ") .. r.title)
	detail.sub:SetText(r.duty .. "\n|cffffd100Titeln är ett exempel.|r Har du ett bättre namn på rollen, skriv det.")
	detail.form:Show()
	detail.form.challenge:SetText(target and ("Du utmanar " .. target .. ". Guildledaren ser utmaningen först; godtar han den får " .. target .. " bara veta att någon utmanar.") or "")
	detail.form.titleBox:SetText(app and app.title or "")
	detail.form.area.box:SetText(app and app.reason or "")
end

local function OpenDetail()
	page.list:Hide()
	detail:Show()
	detail.scroll:SetVerticalScroll(0)
end

local function CloseDetail()
	detail:Hide()
	detail.mode = nil
	page.list:SetShown(side == "rep")
	Refresh()
end

-- The roles list --------------------------------------------------------

-- What the row's button does for this member now; a second label and
-- click for Dra tillbaka.
local function Action(role)
	local b = ns.BallotFor(role.id)
	local now = ns.Now()
	if b then
		if now < b.ends then return ns.Voted(b) and "Visa" or "Rösta", function() ShowBallot(b) OpenDetail() end end
		return IsGuildLeader() and "Fastställ" or "Visa", function() ShowBallot(b) OpenDetail() end
	end
	local phase = ns.RoundPhase()
	if phase == "val" or phase == "slut" then return nil end
	local app = ns.MyApp()
	if app then
		if app.role ~= role.id then return nil end
		-- Ändra ansökan and Dra tillbaka while applications are open, and
		-- outside a round too (Zach 14/11); never while voting runs (above).
		return "Ändra ansökan", function() ShowApply(role.id, app.target, app) OpenDetail() end,
			"Dra tillbaka", function()
				StaticPopupDialogs.SKATTEVERKET_DRA = StaticPopupDialogs.SKATTEVERKET_DRA or {
					text = "Dra tillbaka din ansökan till %s?", button1 = "Dra tillbaka", button2 = "Avbryt",
					OnAccept = function() ns.Withdraw() end, timeout = 0, whileDead = true, hideOnEscape = true }
				StaticPopup_Show("SKATTEVERKET_DRA", role.title)
			end
	end
	local me = ns.Me()
	local holders = ns.Holders(role.id)
	if Has(holders, me) and phase ~= "ans" then
		return "Avgå", function()
			StaticPopupDialogs.SKATTEVERKET_AVGA = StaticPopupDialogs.SKATTEVERKET_AVGA or {
				text = "Avgå som %s? Platsen blir ledig och guildet får veta det.", button1 = "Avgå", button2 = "Avbryt",
				OnAccept = function(_, data) ns.Resign(data) end, timeout = 0, whileDead = true, hideOnEscape = true }
			StaticPopup_Show("SKATTEVERKET_AVGA", role.title, nil, role.id)
		end
	end
	if phase == "ans" or #holders < role.seats then
		return "Ansök", function() ShowApply(role.id) OpenDetail() end
	end
	return "Utmana", function(self)
		if #holders == 1 then
			ShowApply(role.id, holders[1])
			OpenDetail()
			return
		end
		-- Several seats: whom to challenge.
		Menu(self, function(root)
			root:CreateTitle("Vem utmanar du?")
			for _, h in ipairs(holders) do
				if h ~= me then root:CreateButton(h, function() ShowApply(role.id, h) OpenDetail() end) end
			end
		end)
	end
end

-- Leader: place holders by hand; one seat is replaced, Testpilot's three
-- are switched on and off.
local function PlaceMenu(owner, role)
	local names = {}
	for name in pairs(ns.RosterNames() or {}) do table.insert(names, name) end
	table.sort(names)
	Menu(owner, function(root)
		root:CreateTitle(role.title)
		root:CreateButton("Vakant", function() ns.SetHolders(role.id, {}) end)
		for _, name in ipairs(names) do
			local holders = ns.Holders(role.id)
			local label = Has(holders, name) and (name .. " (har den)") or name
			root:CreateButton(label, function()
				local list = {}
				if role.seats > 1 then
					for _, h in ipairs(holders) do
						if h ~= name then table.insert(list, h) end
					end
					if not Has(holders, name) then
						table.insert(list, name)
						while #list > role.seats do table.remove(list, 1) end
					end
				else
					list = { name }
				end
				ns.SetHolders(role.id, list)
			end)
		end
	end)
end

local function PhaseText()
	local r, phase = ns.Folk().round, ns.RoundPhase()
	if phase == "ans" then
		return string.format("|cffffd100Valet är öppet.|r Ansök om en roll till %s. Röstning %s till %s.", ns.When(r.appEnd), ns.When(r.appEnd), ns.When(r.voteEnd))
	elseif phase == "val" then
		return string.format("|cffffd100Röstning pågår till %s.|r En röst per konto och roll, hemlig.", ns.When(r.voteEnd))
	elseif phase == "slut" then
		return "Röstningen är slut. Guildledaren fastställer resultatet."
	end
	return "Guildets ledare, valda av medlemmarna. Ansök om en ledig roll, eller utmana den som har den om du tror att du gör det bättre."
end

local RefreshMembers

Refresh = function()
	if not page or not page:IsShown() then return end
	if side == "med" then RefreshMembers() return end
	local leader = IsGuildLeader()
	if detail:IsShown() then
		if detail.mode == "ballot" and detail.ballot then ShowBallot(detail.ballot)
		elseif detail.mode == "apps" then ShowApps(detail.role) end
		return
	end
	page.phase:SetText(PhaseText())
	page.leaderRow.duty:SetText("|cffffffff" .. (ns.Leader() or "?") .. "|r  " .. ns.LEADER_ROLE.duty)
	for i, role in ipairs(ns.ROLES) do
		local row = page.rows[i]
		row.holder:SetText(HolderText(role))
		local label, click, label2, click2 = Action(role)
		row.action:SetShown(label ~= nil)
		if label then
			row.action:SetText(label)
			row.action:SetWidth(math.max(84, row.action:GetFontString():GetStringWidth() + 24))
			row.action:SetScript("OnClick", click)
			if click then row.action:Enable() else row.action:Disable() end
		end
		row.withdraw:SetShown(label2 ~= nil)
		if label2 then row.withdraw:SetScript("OnClick", click2) end
		row.action:ClearAllPoints()
		row.action:SetPoint("RIGHT", label2 and row.withdraw or row.contact, "LEFT", -4, 0)
		row.place:SetShown(leader)
		local n = #ns.AppsFor(role.id)
		row.apps:SetShown(leader and n > 0)
		row.apps:SetText(string.format("Ansökn. (%d)", n))
	end
	local phase = ns.RoundPhase()
	page.lead:SetShown(leader and not phase)
	page.leadInfo:SetShown(leader and phase ~= nil)
	if leader and phase then
		page.leadInfo:SetText("Ansökningarna blir omröstningar av sig själva när ansökan stänger (när du är online). Fastställ varje roll när röstningen är slut.")
	end
end
ns.RefreshFolk = Refresh


function ns.BuildFolk(parent)
	page = parent
	page.phase = Text(parent, "GameFontHighlight", "TOPLEFT", 24, -66)
	page.phase:SetWidth(730)

	local list = CreateFrame("Frame", nil, parent)
	list:SetAllPoints()
	page.list = list
	page.rows = {}
	-- Row 0 is the guild leader (Zach 12/11), then the elected roles.
	local function Row(i, role)
		local row = CreateFrame("Frame", nil, list)
		row:SetSize(732, ROW_H)
		row:SetPoint("TOPLEFT", 24, -100 - i * ROW_H)
		row.title = Text(row, "GameFontNormal", "TOPLEFT", 0, 0)
		row.title:SetWidth(236)
		row.title:SetWordWrap(false)
		row.title:SetText(role.title)
		row.holder = Text(row, "GameFontHighlight", "TOPLEFT", 240, 0)
		row.holder:SetWidth(130)
		row.holder:SetWordWrap(false)
		row.duty = Text(row, "GameFontDisableSmall", "TOPLEFT", 0, -15)
		row.duty:SetWidth(370)
		row.duty:SetWordWrap(false)
		row.duty:SetText(role.duty)
		-- A ticket in Kontakta oss!, for this role (Zach 12/11).
		row.contact = Button(row, "Kontakta mig!", 92, function() ns.ContactRole(role.id) end)
		row.contact:SetPoint("TOPRIGHT", 0, 0)
		return row
	end
	page.leaderRow = Row(0, ns.LEADER_ROLE)
	-- The long title gets the whole line, the name goes before the duty.
	page.leaderRow.title:SetWidth(620)
	page.leaderRow.holder:Hide()
	page.leaderRow.duty:SetWidth(620)
	page.leaderRow:EnableMouse(true)
	page.leaderRow:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(ns.LEADER_ROLE.title, 1, 0.82, 0)
		GameTooltip:AddLine(ns.LEADER_ROLE.duty, 1, 1, 1, true)
		GameTooltip:AddLine("Guildledaren, inte vald.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	page.leaderRow:SetScript("OnLeave", function() GameTooltip:Hide() end)
	for i, role in ipairs(ns.ROLES) do
		local row = Row(i, role)
		row.withdraw = Button(row, "Dra tillbaka", 100)
		row.withdraw:SetPoint("RIGHT", row.contact, "LEFT", -4, 0)
		row.withdraw:Hide()
		row.action = Button(row, "", 84)
		row.action:SetPoint("RIGHT", row.contact, "LEFT", -4, 0)
		row.place = Button(row, "Innehavare", 84, function(self) PlaceMenu(self, role) end)
		row.place:SetPoint("RIGHT", row.action, "LEFT", -4, 0)
		row.apps = Button(row, "", 84, function() ShowApps(role.id) OpenDetail() end)
		row.apps:SetPoint("RIGHT", row.place, "LEFT", -4, 0)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(role.title, 1, 0.82, 0)
			GameTooltip:AddLine(role.duty, 1, 1, 1, true)
			GameTooltip:AddLine("Titeln är ett exempel; den som söker får föreslå en bättre." .. (role.seats > 1 and (" " .. role.seats .. " platser.") or ""), 0.7, 0.7, 0.7, true)
			local holders = ns.Holders(role.id)
			if #holders > 0 then GameTooltip:AddLine("Innehavare: " .. table.concat(holders, ", "), 1, 1, 1, true) end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		page.rows[i] = row
	end

	-- The leader starts the round.
	local lead = CreateFrame("Frame", nil, list)
	lead:SetSize(672, 30)
	lead:SetPoint("BOTTOMLEFT", 24, 28)
	page.lead = lead
	Text(lead, "GameFontNormalSmall", "LEFT", 0, 0):SetText("Ansökan stänger")
	local appBox = Input(lead, 90)
	appBox:SetPoint("LEFT", 100, 0)
	Text(lead, "GameFontNormalSmall", "LEFT", 200, 0):SetText("Röstningen stänger")
	local voteBox = Input(lead, 90)
	voteBox:SetPoint("LEFT", 318, 0)
	local start = Button(lead, "Starta valet", 120, function() ns.StartRound(appBox:GetText(), voteBox:GetText()) end)
	start:SetPoint("LEFT", 420, 0)
	lead:SetScript("OnShow", function()
		local a, v = ns.DefaultRoundTimes()
		appBox:SetText(a)
		voteBox:SetText(v)
	end)
	page.leadInfo = Text(list, "GameFontDisableSmall", "BOTTOMLEFT", 24, 34)
	page.leadInfo:SetWidth(600)

	-- The detail view over the list.
	detail = CreateFrame("Frame", nil, parent)
	detail:SetAllPoints()
	detail:Hide()
	detail.rows = {}
	detail.title = Text(detail, "GameFontNormalLarge", "TOPLEFT", 24, -96)
	detail.sub = Text(detail, "GameFontHighlightSmall", "TOPLEFT", 24, -118)
	detail.sub:SetWidth(660)
	local back = Button(detail, "Tillbaka", 90, CloseDetail)
	back:SetPoint("BOTTOMRIGHT", -24, 28)
	detail.settle = Button(detail, "Fastställ", 120)
	detail.settle:SetPoint("BOTTOMLEFT", 24, 28)
	detail.startVote = Button(detail, "Starta omröstning (3 dagar)", 200)
	detail.startVote:SetPoint("BOTTOMLEFT", 24, 28)
	local scroll = CreateFrame("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 24, -162)
	scroll:SetPoint("BOTTOMRIGHT", -44, 60)
	detail.scroll = scroll
	detail.child = CreateFrame("Frame", nil, scroll)
	detail.child:SetSize(620, 10)
	scroll:SetScrollChild(detail.child)

	-- Apply or challenge.
	local form = CreateFrame("Frame", nil, detail)
	form:SetAllPoints()
	detail.form = form
	Text(form, "GameFontNormal", "TOPLEFT", 24, -172):SetText("Förslag på titel (valfritt)")
	form.titleBox = Input(form, 300)
	form.titleBox:SetMaxLetters(40)
	form.titleBox:SetPoint("TOPLEFT", 30, -190)
	Text(form, "GameFontNormal", "TOPLEFT", 24, -224):SetText("Varför just du? (krävs)")
	form.area = ns.TextArea(form, 600, 90, 200, function()
		if ns.Len(form.area.box:GetText()) >= 10 then form.send:Enable() else form.send:Disable() end
	end)
	form.area:SetPoint("TOPLEFT", 24, -242)
	local warn = Text(form, "GameFontHighlightSmall", "TOPLEFT", 24, -356)
	warn:SetWidth(640)
	warn:SetText("|cffffd100Officiell information:|r när röstningen öppnar visas ditt namn, ditt titelförslag och din motivering för alla medlemmar. Du kan ha en ansökan inne åt gången, och ändra eller dra tillbaka den så länge ansökan är öppen.")
	form.challenge = Text(form, "GameFontHighlightSmall", "TOPLEFT", 24, -390)
	form.challenge:SetWidth(640)
	form.send = Button(form, "Skicka", 120, function()
		local ok, why = ns.Apply(detail.role, form.area.box:GetText(), form.titleBox:GetText(), detail.target, detail.edit)
		if ok then CloseDetail() elseif why then ns.Print(why) end
	end)
	form.send:SetPoint("TOPLEFT", 24, -430)
	form.send:Disable()
	form:Hide()


	ns.BuildMembers(parent)
	page.tabs = {
		SideTab(parent, 1, "INV_Scroll_05", "Representanter", function() ns.FolkSide("rep") end),
		SideTab(parent, 2, "INV_Misc_Note_01", "Medlemmar", function() ns.FolkSide("med") end),
	}

	-- Ask the leader for the latest, at most once a minute; the side tab
	-- stays as it was left.
	local asked = 0
	parent:SetScript("OnShow", function()
		detail:Hide()
		detail.mode = nil
		ns.FolkSide(side)
		if not IsGuildLeader() and GetTime() - asked > 60 then
			asked = GetTime()
			ns.Send("FQ")
		end
	end)
end

-- Representanter or Medlemmar.
function ns.FolkSide(which)
	side = which
	if which == "med" then
		detail:Hide()
		detail.mode = nil
	end
	page.list:SetShown(which == "rep" and not detail:IsShown())
	page.phase:SetShown(which == "rep")
	members:SetShown(which == "med")
	page.tabs[1]:SetChecked(which == "rep")
	page.tabs[2]:SetChecked(which == "med")
	Refresh()
end

-- Medlemmar (Zach 14/11) ------------------------------------------------

-- One row per main with its alts under it, everyone in the roster: class,
-- level, rank, the Folkvald representant role held (in the professions'
-- place, Zach 14/11; they are on hover), skattenummer and last seen,
-- never any amounts.
-- Sorted by name, rank or last seen; a main and its alts move together,
-- by the main's name and rank and the latest any of them was seen.
local MEMBER_ROWS, MEMBER_H = 28, 16
local MEMBER_COLS = {
	{ "Namn", 170, "name" }, { "Klass", 80 }, { "Level", 40 }, { "Rank", 100 },
	{ "Representant", 200 }, { "Skattenr", 66 }, { "Senast sedd", 76, "seen" },
}
local memberList, memberOffset, memberSort = {}, 0, "name"

-- Seconds since the character was online (0 while online), from the
-- roster or the last time this client heard from them, whichever is later.
local function Away(index, online, m)
	if online then return 0 end
	local away
	if GetGuildRosterLastOnline then
		local y, mo, d, h = GetGuildRosterLastOnline(index)
		if y then away = (((y * 12 + (mo or 0)) * 30 + (d or 0)) * 24 + (h or 0)) * 3600 end
	end
	if m and (m.lastSeen or 0) > 0 then
		local since = math.max(0, time() - m.lastSeen)
		if not away or since < away then away = since end
	end
	return away
end

local function SeenText(r)
	if r.online then return "|cff40ff40online|r" end
	local a = r.away
	if not a then return "?" end
	if a < 3600 then return "< 1 tim" end
	if a < 86400 then return math.floor(a / 3600) .. " tim" end
	local d = math.floor(a / 86400)
	if d < 60 then return d == 1 and "1 dag" or (d .. " dagar") end
	return math.floor(d / 30) .. " mån"
end

-- Every role this character holds, in gold, or nothing; the guild leader's
-- own title too (Zach 14/11: his row said nothing).
local function RoleText(r)
	local titles = {}
	if r.rankIndex == 0 then table.insert(titles, ns.LEADER_ROLE.title) end
	for id, list in pairs(ns.db.folk and ns.db.folk.holders or {}) do
		for _, n in ipairs(list) do
			if n == r.name and ns.ROLE[id] then table.insert(titles, ns.ROLE[id].title) end
		end
	end
	return #titles > 0 and ("|cffffd100" .. table.concat(titles, ", ") .. "|r") or ""
end

-- The section a main stands in (Zach 14/11): Guildmaster, then the
-- officers (Representant), then Medborgare, by the main's rank; every
-- other rank (socials, Pöbeln, Bidragstagare, and any rank added later)
-- together under Bottenskrapet. Returns an order and a heading.
local function Section(r)
	if r.rankIndex == 0 then return 0, r.rank end
	if ns.EQUAL_RANKS[r.rank] then return 1, r.rank end
	if r.rank == ns.CITIZEN_RANK then return 2, r.rank end
	return 99, "Bottenskrapet"
end

local function ProfText(profs)
	local list, out = ns.DecodeProfessions(profs), {}
	for _, p in ipairs(ns.PROFESSIONS) do
		if list[p.code] then table.insert(out, p.label .. " " .. list[p.code].rank) end
	end
	return table.concat(out, ", ")
end

local function ClassText(r)
	local c = r.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.classFile]
	if not c then return r.class end
	local hex = c.colorStr or string.format("ff%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
	return "|c" .. hex .. r.class .. "|r"
end

-- memberList from the roster; returns how many people (mains and those
-- without alts).
local function BuildList()
	local db, info = ns.db, {}
	for i = 1, GetNumGuildMembers() do
		local full, rankName, rankIndex, level, class, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
		local name = ns.Short(full)
		if name then
			local m = db.members[name]
			info[name] = { name = name, rank = rankName or "", rankIndex = rankIndex or 99, level = level or 0,
				class = class or "", classFile = classFile, online = online and true or false, away = Away(i, online, m), m = m }
		end
	end
	-- A main no longer in the guild leaves its alts on rows of their own.
	local mainOf, heads = ns.MainOf(), {}
	for name in pairs(info) do
		local main = mainOf[name]
		if not main or not info[main] then main = name end
		heads[main] = heads[main] or { r = info[main], alts = {} }
		if main ~= name then table.insert(heads[main].alts, info[name]) end
	end
	local groups = {}
	for _, g in pairs(heads) do
		g.away = g.r.away
		for _, a in ipairs(g.alts) do
			a.alt = true
			if a.away and (not g.away or a.away < g.away) then g.away = a.away end
		end
		table.sort(g.alts, function(x, y) return x.name < y.name end)
		table.insert(groups, g)
	end
	for _, g in ipairs(groups) do g.order, g.section = Section(g.r) end
	local never = math.huge
	table.sort(groups, function(x, y)
		if x.order ~= y.order then return x.order < y.order end
		if memberSort == "seen" and (x.away or never) ~= (y.away or never) then return (x.away or never) < (y.away or never) end
		return x.r.name < y.r.name
	end)
	wipe(memberList)
	local section, headings = nil, 0
	for _, g in ipairs(groups) do
		if g.section ~= section then
			section, headings = g.section, headings + 1
			table.insert(memberList, { header = section })
		end
		table.insert(memberList, g.r)
		for _, a in ipairs(g.alts) do table.insert(memberList, a) end
	end
	return #groups, headings
end

RefreshMembers = function()
	if not members or not members:IsShown() then return end
	local people, headings = BuildList()
	memberOffset = math.max(0, math.min(memberOffset, #memberList - MEMBER_ROWS))
	for i, row in ipairs(members.rows) do
		local r = memberList[i + memberOffset]
		row.r = r
		if r and r.header then
			for c, fs in ipairs(row.cells) do fs:SetText(c == 1 and ("|cffffd100" .. r.header .. "|r") or "") end
			row.cells[1]:SetPoint("LEFT", 4, 0)
			row.cells[1]:SetWidth(MEMBER_COLS[1][2] - 6)
			row:Show()
		elseif r then
			local m = r.m
			local values = { r.alt and ("|cffb0b0b0" .. r.name .. "|r") or r.name, ClassText(r), r.level > 0 and r.level or "",
				r.rank, RoleText(r), m and ns.Number(m.number) or "-", SeenText(r) }
			for c, fs in ipairs(row.cells) do fs:SetText(values[c]) end
			-- Alts stand indented under their main.
			local indent = r.alt and 14 or 0
			row.cells[1]:SetPoint("LEFT", 4 + indent, 0)
			row.cells[1]:SetWidth(MEMBER_COLS[1][2] - 6 - indent)
			row:Show()
		else
			row:Hide()
		end
	end
	for _, h in ipairs(members.headers) do
		if h.key == memberSort then h.text:SetTextColor(1, 1, 1) else h.text:SetTextColor(1, 0.82, 0) end
	end
	local shown = #memberList > MEMBER_ROWS and string.format("Visar %d-%d av %d (scrolla). ", memberOffset + 1,
		math.min(memberOffset + MEMBER_ROWS, #memberList), #memberList) or ""
	members.count:SetText(shown .. string.format("%d medlemmar, %d karaktärer; efter rank, alts under sin huvudkaraktär. Klicka på Namn eller Senast sedd för att sortera inom varje rank.",
		people, #memberList - headings))
end

function ns.BuildMembers(parent)
	members = CreateFrame("Frame", nil, parent)
	members:SetAllPoints()
	members:Hide()
	Text(members, "GameFontHighlight", "TOPLEFT", 24, -66):SetText("Alla i guildet, med sina alts under huvudkaraktären.")
	members.headers, members.rows = {}, {}
	local x = 0
	for c, col in ipairs(MEMBER_COLS) do
		local h = CreateFrame("Button", nil, members)
		h:SetSize(col[2], 16)
		h:SetPoint("TOPLEFT", 24 + x, -96)
		h.text = Text(h, "GameFontNormalSmall", "LEFT", 4, 0)
		h.text:SetText(col[1])
		h.key = col[3]
		if h.key then
			h:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			h:SetScript("OnClick", function()
				memberSort, memberOffset = h.key, 0
				RefreshMembers()
			end)
		end
		members.headers[c] = h
		x = x + col[2]
	end
	for i = 1, MEMBER_ROWS do
		local row = CreateFrame("Frame", nil, members)
		row:SetSize(x, MEMBER_H)
		row:SetPoint("TOPLEFT", 24, -114 - (i - 1) * MEMBER_H)
		row.cells = {}
		local cx = 0
		for c, col in ipairs(MEMBER_COLS) do
			local fs = Text(row, "GameFontHighlightSmall", "LEFT", cx + 4, 0)
			fs:SetWidth(col[2] - 6)
			fs:SetWordWrap(false)
			row.cells[c] = fs
			cx = cx + col[2]
		end
		-- The whole line of professions, and the role, on hover.
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			local r = self.r
			if not r or r.header then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(r.name)
			local roles = RoleText(r)
			if roles ~= "" then GameTooltip:AddLine(roles, 1, 0.82, 0, true) end
			local profs = r.m and ProfText(r.m.profs) or ""
			GameTooltip:AddLine(profs ~= "" and profs or "Inga yrken delade.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		members.rows[i] = row
	end
	members.count = Text(members, "GameFontDisableSmall", "BOTTOMLEFT", 24, 34)
	members.count:SetWidth(720)
	members:EnableMouseWheel(true)
	members:SetScript("OnMouseWheel", function(_, delta)
		memberOffset = math.max(0, math.min(memberOffset - delta * 3, #memberList - MEMBER_ROWS))
		RefreshMembers()
	end)
end

-- Socialbidrag ----------------------------------------------------------

local function RefreshBidrag()
	if not bidrag or not bidrag:IsShown() then return end
	local leader = IsGuildLeader()
	local level = UnitLevel("player")
	local size = ns.BidragSize(level)
	local left = ns.BidragLeft(size)
	local ask = ns.MyBidragAsk()
	bidrag.form:SetShown(not leader or bidrag.writing)
	bidrag.asks:SetShown(leader and not bidrag.writing and not bidrag.history)
	bidrag.toggle:SetShown(leader)
	bidrag.toggle:SetText(bidrag.writing and "Ansökningar" or "Sök själv")
	bidrag.histToggle:SetShown(leader and not bidrag.writing)
	bidrag.histToggle:SetText(bidrag.history and "Ansökningar" or "Historik")
	-- The history (Zach 14/11): below the form for a member, a view of its
	-- own for the leader.
	local showHist = not leader or (bidrag.history and not bidrag.writing)
	bidrag.hist:SetShown(showHist)
	if showHist then
		bidrag.hist:ClearAllPoints()
		bidrag.hist:SetPoint("TOPLEFT", 24, leader and -130 or -200)
		local list = ns.BidragHistory()
		bidrag.histOffset = math.max(0, math.min(bidrag.histOffset or 0, #list - #bidrag.histRows))
		bidrag.histTitle:SetText(leader and "Givet, senaste 90 dagarna" or "Fått, senaste 90 dagarna")
		for i, fs in ipairs(bidrag.histRows) do
			local e = list[i + bidrag.histOffset]
			fs:SetText(e and string.format("%s   %s: %d väsk%s med %d platser", ns.When(e.at), e.name, e.count, e.count == 1 and "a" or "or", e.size) or "")
		end
		bidrag.histNone:SetShown(#list == 0)
	end
	if ask then
		bidrag.status:SetText(string.format("Din ansökan om %d väsk%s med %d platser skickades %s och väntar på guildledaren.",
			ask.count, ask.count == 1 and "a" or "or", ask.size, ns.When(ask.at)))
	elseif left == 0 then
		bidrag.status:SetText(string.format("Ditt konto har fått alla %d väskor med %d platser.", ns.BIDRAG_MAX, size)
			.. (size == 6 and (" På nivå " .. ns.BIDRAG_LEVEL .. " kan du söka väskor med 8 platser.") or ""))
	else
		bidrag.status:SetText(string.format("Du är nivå %d: du kan söka upp till %d väsk%s med %d platser.", level, left, left == 1 and "a" or "or", size))
	end
	for n, b in ipairs(bidrag.counts) do
		b:SetShown(not ask and n <= left)
		b:SetText(n == 1 and "1 väska" or (n .. " väskor"))
	end
	if not leader then return end
	local names = {}
	for name in pairs(ns.Bidrag().asks) do table.insert(names, name) end
	table.sort(names, function(x, y) return ns.Bidrag().asks[x].at < ns.Bidrag().asks[y].at end)
	for i, row in ipairs(bidrag.rows) do
		local name = names[i]
		row:SetShown(name ~= nil)
		if name then
			local a = ns.Bidrag().asks[name]
			row.name = name
			row.text:SetText(string.format("%s, nivå %d: %d × %d platser  |cff999999(kontot har fått %d, %s)|r",
				name, a.level, a.count, a.size, ns.BidragGiven(name, a.size), ns.When(a.at)))
		end
	end
	bidrag.none:SetShown(#names == 0)
end
ns.RefreshBidrag = RefreshBidrag

function ns.BuildBidrag(parent)
	bidrag = parent
	local intro = Text(parent, "GameFontHighlight", "TOPLEFT", 24, -70)
	intro:SetWidth(470)
	intro:SetText("|cffffd100Statligt socialbidrag.|r Under nivå " .. ns.BIDRAG_LEVEL .. " kan du få upp till 3 väskor med 6 platser, från nivå " .. ns.BIDRAG_LEVEL
		.. " upp till 3 väskor med 8 platser. Båda gäller ditt konto, alla dina karaktärer tillsammans, och karaktären som söker avgör storleken. Väskorna kommer med posten.")

	local form = CreateFrame("Frame", nil, parent)
	form:SetAllPoints()
	bidrag.form = form
	bidrag.status = Text(form, "GameFontNormal", "TOPLEFT", 24, -130)
	bidrag.status:SetWidth(470)
	bidrag.counts = {}
	for n = 1, ns.BIDRAG_MAX do
		local b = Button(form, "", 100, function() ns.AskBidrag(n) end)
		b:SetPoint("TOPLEFT", 24 + (n - 1) * 108, -160)
		bidrag.counts[n] = b
	end

	-- The leader's list.
	local asks = CreateFrame("Frame", nil, parent)
	asks:SetAllPoints()
	bidrag.asks = asks
	Text(asks, "GameFontNormal", "TOPLEFT", 24, -130):SetText("Ansökningar")
	bidrag.none = Text(asks, "GameFontDisable", "TOPLEFT", 24, -154)
	bidrag.none:SetText("Inga ansökningar.")
	bidrag.rows = {}
	for i = 1, 10 do
		local row = CreateFrame("Frame", nil, asks)
		row:SetSize(672, 26)
		row:SetPoint("TOPLEFT", 24, -150 - (i - 1) * 28)
		row.text = Text(row, "GameFontHighlight", "LEFT", 0, 0)
		row.text:SetWidth(400)
		local fill = Button(row, "Fyll i brev", 90, function() ns.FillBidrag(row.name) end)
		fill:SetPoint("RIGHT", -176, 0)
		local done = Button(row, "Klar", 80, function() ns.BidragDone(row.name) end)
		done:SetPoint("RIGHT", -88, 0)
		local no = Button(row, "Avböj", 80, function() ns.BidragDone(row.name, true) end)
		no:SetPoint("RIGHT", 0, 0)
		bidrag.rows[i] = row
	end
	bidrag.toggle = Button(parent, "", 110, function()
		bidrag.writing = not bidrag.writing
		RefreshBidrag()
	end)
	bidrag.toggle:SetPoint("BOTTOMRIGHT", -24, 28)
	-- The leader's history view (Zach 14/11).
	bidrag.histToggle = Button(parent, "", 110, function()
		bidrag.history = not bidrag.history
		bidrag.histOffset = 0
		RefreshBidrag()
	end)
	bidrag.histToggle:SetPoint("RIGHT", bidrag.toggle, "LEFT", -8, 0)

	-- The history: bags given, newest first; the wheel scrolls.
	local hist = CreateFrame("Frame", nil, parent)
	hist:SetSize(470, 300)
	bidrag.hist = hist
	bidrag.histTitle = Text(hist, "GameFontNormal", "TOPLEFT", 0, 0)
	bidrag.histNone = Text(hist, "GameFontDisable", "TOPLEFT", 0, -22)
	bidrag.histNone:SetText("Inga väskor än.")
	bidrag.histRows = {}
	for i = 1, 15 do
		local fs = Text(hist, "GameFontHighlight", "TOPLEFT", 0, -22 - (i - 1) * 18)
		fs:SetWidth(470)
		bidrag.histRows[i] = fs
	end
	hist:EnableMouseWheel(true)
	hist:SetScript("OnMouseWheel", function(_, delta)
		bidrag.histOffset = math.max(0, (bidrag.histOffset or 0) - delta * 3)
		RefreshBidrag()
	end)
	parent:SetScript("OnShow", RefreshBidrag)
end
