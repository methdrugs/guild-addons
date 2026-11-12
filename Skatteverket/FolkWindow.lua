-- Skatteverket: the Folkvald representant window (Zach 11/11, renamed from Intresseanmälan 12/11), from the minimap
-- button's list under Bokföring: Folkvald representant (page 11) and
-- Socialbidrag (page 12) as side tabs. Members see the roles, who holds
-- them, and apply, challenge and vote; the guild leader also places holders
-- with a drop-down, reads the applications, accepts challenges, starts the
-- round and settles each vote. The rules are in Folk.lua and Bidrag.lua.

local _, ns = ...

local ROW_H = 36
local page, bidrag

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

local function ShowApply(role, target)
	ClearDetail()
	detail.mode, detail.role, detail.target = "apply", role, target
	local r = ns.ROLE[role]
	detail.title:SetText((target and "Utmana: " or "Sök: ") .. r.title)
	detail.sub:SetText(r.duty .. "\n|cffffd100Titeln är ett exempel.|r Har du ett bättre namn på rollen, skriv det.")
	detail.form:Show()
	detail.form.challenge:SetText(target and ("Du utmanar " .. target .. ". Guildledaren ser utmaningen först; godtar han den får " .. target .. " bara veta att någon utmanar.") or "")
	detail.form.titleBox:SetText("")
	detail.form.area.box:SetText("")
end

local function OpenDetail()
	page.list:Hide()
	detail:Show()
	detail.scroll:SetVerticalScroll(0)
end

local function CloseDetail()
	detail:Hide()
	detail.mode = nil
	page.list:Show()
	Refresh()
end

-- The roles list --------------------------------------------------------

-- What the row's button does for this member now.
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
		if app.role == role.id then return "Inskickad", nil end
		return nil
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
		return "Sök", function() ShowApply(role.id) OpenDetail() end
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
		return string.format("|cffffd100Valet är öppet.|r Sök en roll till %s. Röstning %s till %s.", ns.When(r.appEnd), ns.When(r.appEnd), ns.When(r.voteEnd))
	elseif phase == "val" then
		return string.format("|cffffd100Röstning pågår till %s.|r En röst per konto och roll, hemlig.", ns.When(r.voteEnd))
	elseif phase == "slut" then
		return "Röstningen är slut. Guildledaren fastställer resultatet."
	end
	return "Guildets ledare, valda av medlemmarna. Sök en ledig roll, eller utmana den som har den om du tror att du gör det bättre."
end

Refresh = function()
	if not page or not page:IsShown() then return end
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
		local label, click = Action(role)
		row.action:SetShown(label ~= nil)
		if label then
			row.action:SetText(label)
			row.action:SetScript("OnClick", click)
			if click then row.action:Enable() else row.action:Disable() end
		end
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
	warn:SetText("|cffffd100Officiell information:|r när röstningen öppnar visas ditt namn, ditt titelförslag och din motivering för alla medlemmar. Du kan ha en ansökan inne åt gången.")
	form.challenge = Text(form, "GameFontHighlightSmall", "TOPLEFT", 24, -390)
	form.challenge:SetWidth(640)
	form.send = Button(form, "Skicka", 120, function()
		local ok, why = ns.Apply(detail.role, form.area.box:GetText(), form.titleBox:GetText(), detail.target)
		if ok then CloseDetail() elseif why then ns.Print(why) end
	end)
	form.send:SetPoint("TOPLEFT", 24, -430)
	form.send:Disable()
	form:Hide()


	-- Ask the leader for the latest, at most once a minute.
	local asked = 0
	parent:SetScript("OnShow", function()
		CloseDetail()
		if not IsGuildLeader() and GetTime() - asked > 60 then
			asked = GetTime()
			ns.Send("FQ")
		end
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
	bidrag.asks:SetShown(leader and not bidrag.writing)
	bidrag.toggle:SetShown(leader)
	bidrag.toggle:SetText(bidrag.writing and "Ansökningar" or "Sök själv")
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
	parent:SetScript("OnShow", RefreshBidrag)
end
