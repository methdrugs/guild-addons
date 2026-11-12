-- Skatteverket: Kontakta oss! as tickets (Zach 11/11, tickets 12/11). A
-- member picks the service and the type (Bugg, Förbättring, Ny addon-idé,
-- Annat) and writes up to 500 characters; Kontakta mig! on a row under
-- Folkvald representant opens the same form for that role. Every ticket
-- has a number, a status (Öppen, Stängd) and a thread of replies.
--
-- The guild leader's client holds every ticket and never deletes one, so
-- old cases can be traced. A ticket goes to him and to whoever holds the
-- role behind the service (Swedbank to VD för Swedbank and so on); a
-- service with no role, a vacant role or Testpilot goes to him only. When
-- a role changes hands its open tickets move to the new holder, and the
-- old one no longer sees them. The one who sent it, the holder or the
-- leader may answer in the thread, close it or open it again; the sender
-- is told when it is closed. The sender's other characters count as the
-- sender, and a new holder also gets the role's tickets closed in the last
-- 30 days (Zach 12/11).
--
-- Whispers to the leader, kept until he is online:
--   FK;id;cat;service;kind;i;n;text      a new ticket, in pieces
--   FY;id;i;n;text                       a reply
--   FZ;id                                close it
--   FP;id                                open it again
-- Whispers from the leader, kept on his client until they are online:
--   FE;id;num;cat;service;kind;from;at;status;closedBy;closedAt;count   the ticket
--   FJ;id;idx;by;at;i;n;text             one message of its thread
--   FD;id                                no longer yours (the role changed hands)

local _, ns = ...

-- What a ticket is about, and whose role answers it (Zach 12/11).
ns.SERVICES = {
	{ name = "Skatteverket", role = "skatt" },
	{ name = "Yrken", role = "yrken" },
	{ name = "Arbetsorder", role = "yrken" },
	{ name = "Swedbank", role = "swed" },
	{ name = "Bokföring", role = "bok" },
	{ name = "Folkvald representant", role = "gl" },
	{ name = "Socialbidrag", role = "gl" },
	{ name = "Allmänt", role = "gl" },
}
ns.CONTACT_TYPES = { "Bugg", "Förbättring", "Ny addon-idé", "Annat" }
local QUESTION = "Fråga"
local HISTORY = 30 * 86400
local TEXT_MAX, REPLY_MAX = 500, 300
local ROWS = 9

local function RoleTitle(cat)
	if cat == "gl" then return "Guildledaren" end
	local r = ns.ROLE[cat]
	return r and r.title or cat
end

-- "Swedbank – VD för Swedbank"; Kontakta mig! names the role itself.
local function Label(service, cat)
	local title = RoleTitle(cat)
	return service == title and title or (service .. " – " .. title)
end

-- Who answers besides the leader: the role's holders.
local function Handlers(cat)
	if cat == "gl" or ns.TO_LEADER[cat] or not ns.ROLE[cat] then return {} end
	return ns.Holders(cat)
end

local function Has(list, name)
	for _, n in ipairs(list) do if n == name then return true end end
end

-- The leader's own record of every ticket; everyone else's copies.
local function Hub()
	ns.db.ticketHub = ns.db.ticketHub or { seq = 0, list = {} }
	return ns.db.ticketHub
end
local function Copies()
	ns.db.tickets = ns.db.tickets or {}
	return ns.db.tickets
end
local function Store()
	return IsGuildLeader() and Hub().list or Copies()
end

local function Changed()
	ns.RefreshWindow("kontakt")
	ns.RefreshTodo()
end

local function Num(t)
	return t.num and ("#" .. t.num) or "#?"
end

-- Leader ----------------------------------------------------------------

-- Everyone who sees the ticket, the leader aside.
local function Parties(t)
	local me, out = ns.Me(), {}
	for _, name in ipairs(Handlers(t.cat)) do
		if name ~= me and not Has(out, name) then table.insert(out, name) end
	end
	if t.from ~= me and not Has(out, t.from) then table.insert(out, t.from) end
	return out
end

local function Header(t)
	return table.concat({ "FE", t.id, t.num or 0, t.cat, t.service, t.kind, t.from, t.at, t.status, t.closedBy or "", t.closedAt or 0, #t.msgs }, ";")
end

local function PushMessage(t, idx, name)
	local m = t.msgs[idx]
	local pieces = ns.FolkPieces(m.text)
	for i, p in ipairs(pieces) do
		ns.ToMember(name, string.format("FJ;%s;%d;%s;%d;%d;%d;%s", t.id, idx, m.by, m.at, i, #pieces, p))
	end
end

local function Push(t, name)
	ns.ToMember(name, Header(t))
	for idx in ipairs(t.msgs) do PushMessage(t, idx, name) end
end

local function LeaderNew(sender, id, cat, service, kind, text)
	local hub = Hub()
	if not id or hub.list[id] then return end
	if cat ~= "gl" and not ns.ROLE[cat] then return end
	text = ns.CleanText(text, TEXT_MAX)
	if text == "" then return end
	hub.seq = hub.seq + 1
	local t = { id = id, num = hub.seq, cat = cat, service = ns.CleanText(service, 40), kind = ns.CleanText(kind, 20), from = sender,
		at = ns.Now(), status = "open", msgs = { { by = sender, at = ns.Now(), text = text } } }
	if sender ~= ns.Me() then t.unread = true end
	hub.list[id] = t
	for _, name in ipairs(Parties(t)) do Push(t, name) end
	if sender ~= ns.Me() then ns.Print(string.format("|cffffd100Nytt ärende %s: %s, %s från %s.|r Se Kontakta oss!.", Num(t), Label(t.service, t.cat), t.kind, sender)) end
	Changed()
end

local function MayAct(t, name)
	return name == t.from or ns.Account(name) == ns.Account(t.from) or name == ns.Me() or Has(Handlers(t.cat), name)
end

-- The sender's alt acting on it hears back too.
local function Also(t, sender)
	local list = Parties(t)
	if sender ~= ns.Me() and not Has(list, sender) then table.insert(list, sender) end
	return list
end

local function LeaderReply(sender, id, text)
	local t = Hub().list[id]
	if not t or t.status ~= "open" or not MayAct(t, sender) then return end
	text = ns.CleanText(text, REPLY_MAX)
	if text == "" then return end
	table.insert(t.msgs, { by = sender, at = ns.Now(), text = text })
	if sender ~= ns.Me() then t.unread = true end
	for _, name in ipairs(Also(t, sender)) do PushMessage(t, #t.msgs, name) end
	Changed()
end

local function LeaderClose(sender, id)
	local t = Hub().list[id]
	if not t or t.status ~= "open" or not MayAct(t, sender) then return end
	t.status, t.closedBy, t.closedAt = "closed", sender, ns.Now()
	for _, name in ipairs(Also(t, sender)) do ns.ToMember(name, Header(t)) end
	Changed()
end

local function LeaderReopen(sender, id)
	local t = Hub().list[id]
	if not t or t.status ~= "closed" or not MayAct(t, sender) then return end
	t.status, t.closedBy, t.closedAt = "open", nil, nil
	if sender ~= ns.Me() then t.unread = true end
	for _, name in ipairs(Also(t, sender)) do ns.ToMember(name, Header(t)) end
	Changed()
end

-- From Folkvald representant when a seat changes: the role's open tickets
-- go to the new holders and leave the old (Zach 12/11).
function ns.TicketsHandover(role, old, new)
	if not IsGuildLeader() or ns.TO_LEADER[role] then return end
	local me, since = ns.Me(), ns.Now() - HISTORY
	for _, t in pairs(Hub().list) do
		if t.cat == role and (t.status == "open" or (t.closedAt or 0) >= since) then
			for _, name in ipairs(old) do
				if not Has(new, name) and name ~= me and name ~= t.from then ns.ToMember(name, "FD;" .. t.id) end
			end
			for _, name in ipairs(new) do
				if not Has(old, name) and name ~= me then Push(t, name) end
			end
		end
	end
end

function ns.OnTicketToLeader(sender, parts)
	local kind = parts[1]
	if kind == "FK" then
		ns.ReceiveLong(sender, parts, function(head, text) LeaderNew(sender, head[1], head[2], head[3], head[4], text) end)
	elseif kind == "FY" then
		ns.ReceiveLong(sender, parts, function(head, text) LeaderReply(sender, head[1], text) end)
	elseif kind == "FZ" then
		LeaderClose(sender, parts[2])
	elseif kind == "FP" then
		LeaderReopen(sender, parts[2])
	else
		return false
	end
	return true
end

-- Members ---------------------------------------------------------------

local function OnHeader(parts)
	local id = parts[2]
	if not id then return end
	local list = Copies()
	local t = list[id]
	local fresh = not t
	t = t or { id = id, msgs = {} }
	if fresh and ns.Account(parts[7] or "") == ns.db.account then t.own = true end
	local was = t.status
	t.num, t.cat, t.service, t.kind, t.from = tonumber(parts[3]), parts[4], parts[5], parts[6], parts[7]
	t.at, t.status = tonumber(parts[8]) or ns.Now(), parts[9]
	t.closedBy, t.closedAt = parts[10] ~= "" and parts[10] or nil, tonumber(parts[11])
	list[id] = t
	local me = ns.Me()
	if fresh and t.from ~= me then
		t.unread = true
		ns.Print(string.format("|cffffd100Nytt ärende %s till dig: %s, %s från %s.|r Se Kontakta oss!.", Num(t), Label(t.service, t.cat), t.kind, t.from))
	end
	-- Closed or opened again: shown as news in the list.
	if was and was ~= t.status then t.unread = true end
	if was == "open" and t.status == "closed" and (t.own or t.from == me) and ns.Account(t.closedBy or "") ~= ns.db.account then
		local text = string.format("Ditt ärende %s (%s) är avslutat av %s.", Num(t), Label(t.service, t.cat), t.closedBy or "?")
		ns.AddNotice(text, 13)
		ns.Print(text)
	end
	Changed()
end

local function OnMessage(head, text)
	local t = Copies()[head[1]]
	local idx, by, at = tonumber(head[2]), head[3], tonumber(head[4])
	if not t or not idx or not by then return end
	-- My own reply was added when sent; the leader's copy puts it in place.
	for k, m in ipairs(t.msgs) do
		if k ~= idx and m.by == by and m.text == text then table.remove(t.msgs, k) break end
	end
	t.msgs[idx] = { by = by, at = at or ns.Now(), text = text }
	if by ~= ns.Me() then t.unread = true end
	Changed()
end

function ns.OnTicketFromLeader(parts)
	local kind = parts[1]
	if kind == "FE" then OnHeader(parts)
	elseif kind == "FJ" then ns.ReceiveLong(ns.Leader() or "", parts, OnMessage)
	elseif kind == "FD" then
		local t = Copies()[parts[2] or ""]
		if t and t.from ~= ns.Me() then Copies()[t.id] = nil Changed() end
	else
		return false
	end
	return true
end

-- Anyone ----------------------------------------------------------------

function ns.SendTicket(cat, service, kind, text)
	text = ns.CleanText(text, TEXT_MAX)
	if ns.Len(text) < 5 then return false end
	local me, now = ns.Me(), ns.Now()
	local id = string.format("%x%03x", now, math.random(0, 4095))
	if IsGuildLeader() then
		LeaderNew(me, id, cat, service, kind, text)
		ns.Print("ärendet är sparat.")
		return true
	end
	Copies()[id] = { id = id, own = true, cat = cat, service = service, kind = kind, from = me, at = now, status = "open", msgs = { { by = me, at = now, text = text } } }
	local online = ns.ToLeader("FK", table.concat({ id, cat, service, kind }, ";"), text)
	ns.Print("tack! Ditt ärende är " .. (online and "skickat." or "sparat och skickas när guildledaren är online.") .. " Du hittar det under Mina ärenden.")
	Changed()
	return true
end

local function Reply(t, text)
	text = ns.CleanText(text, REPLY_MAX)
	if text == "" then return end
	if IsGuildLeader() then LeaderReply(ns.Me(), t.id, text) return end
	table.insert(t.msgs, { by = ns.Me(), at = ns.Now(), text = text })
	ns.ToLeader("FY", t.id, text)
	Changed()
end

local function Close(t)
	if IsGuildLeader() then LeaderClose(ns.Me(), t.id) return end
	ns.ToLeader("FZ", t.id)
end

local function Reopen(t)
	if IsGuildLeader() then LeaderReopen(ns.Me(), t.id) return end
	ns.ToLeader("FP", t.id)
end

-- Mine: what this account sent, from any character; handled: what this
-- character answers for (copies are kept per account, so an alt does not
-- see its main's cases).
local function Mine(t) return t.own or t.from == ns.Me() end
local function Handled(t) return IsGuildLeader() or Has(Handlers(t.cat), ns.Me()) end

function ns.ContactTodo()
	local out = {}
	if not ns.db then return out end
	local mine, handled = 0, 0
	for _, t in pairs(Store()) do
		if t.unread then
			if Handled(t) and not Mine(t) then handled = handled + 1 elseif Mine(t) then mine = mine + 1 end
		end
	end
	if handled > 0 then
		table.insert(out, { text = string.format("%d ärende%s med nytt i Kontakta oss!", handled, handled == 1 and "" or "n"), click = function() ns.ShowTickets("cases") end })
	end
	if mine > 0 then
		table.insert(out, { text = string.format("Svar på %d av dina ärenden", mine), click = function() ns.ShowTickets("mine") end })
	end
	return out
end

-- The page --------------------------------------------------------------

local page
local chosen = { cat = nil, service = nil, kind = nil, direct = nil }
local view = { mode = "write", filter = nil, ticket = nil, closed = false }
local offset = 0

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

local STATUS = { open = "|cff40ff40Öppen|r", closed = "|cff999999Stängd|r" }

-- The sender, marked when no longer in the guild.
local function From(t)
	return ns.Online(t.from) == nil and (t.from .. " |cff999999(lämnat guildet)|r") or t.from
end

-- Tickets for the list in this view, newest first.
local function Listed()
	local out = {}
	for _, t in pairs(Store()) do
		local ok
		if view.mode == "mine" then ok = Mine(t)
		else ok = Handled(t) and (not view.filter or Label(t.service, t.cat) == view.filter) end
		if ok and (view.closed or t.status == "open" or t.unread) then table.insert(out, t) end
	end
	table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
	return out
end

-- The leader's categories: what the tickets are about, with open counts.
local function Categories()
	local counts, order = {}, {}
	for _, t in pairs(Hub().list) do
		local label = Label(t.service, t.cat)
		if not counts[label] then
			counts[label] = { open = 0, all = 0 }
			table.insert(order, label)
		end
		counts[label].all = counts[label].all + 1
		if t.status == "open" then counts[label].open = counts[label].open + 1 end
	end
	table.sort(order, function(a, b)
		if counts[a].open ~= counts[b].open then return counts[a].open > counts[b].open end
		return a < b
	end)
	local out = {}
	for _, label in ipairs(order) do
		if view.closed or counts[label].open > 0 then table.insert(out, { label = label, n = counts[label] }) end
	end
	return out
end

local function Thread(t)
	local lines = {}
	for _, m in ipairs(t.msgs) do
		table.insert(lines, string.format("|cffffd100%s|r  |cff999999%s|r\n%s", m.by, ns.When(m.at), m.text))
	end
	if t.status == "closed" then
		table.insert(lines, string.format("|cff999999Stängt av %s %s.|r", t.closedBy or "?", ns.When(t.closedAt)))
	end
	return table.concat(lines, "\n\n")
end

local function Refresh()
	if not page or not page:IsShown() then return end
	local mode = view.mode
	page.form:SetShown(mode == "write")
	page.list:SetShown(mode == "mine" or mode == "cases")
	page.ticket:SetShown(mode == "ticket")
	page.intro:SetShown(mode == "write")

	-- The buttons along the bottom.
	local mineN, casesN, holds = 0, 0, IsGuildLeader()
	for _, t in pairs(Store()) do
		if Handled(t) and not Mine(t) then
			if t.status == "open" or t.unread then casesN = casesN + 1 end
		elseif Mine(t) and t.unread then
			mineN = mineN + 1
		end
	end
	for _, role in ipairs(ns.ROLES) do if Has(ns.Holders(role.id), ns.Me()) then holds = true end end
	page.writeB:SetEnabled(mode ~= "write")
	page.mineB:SetText(mineN > 0 and string.format("Mina ärenden (%d)", mineN) or "Mina ärenden")
	page.mineB:SetEnabled(mode ~= "mine")
	page.casesB:SetShown(holds)
	page.casesB:SetText(casesN > 0 and string.format("Ärenden (%d)", casesN) or "Ärenden")
	page.casesB:SetEnabled(mode ~= "cases" or view.filter ~= nil)

	if mode == "write" then
		page.service:SetText(chosen.service and Label(chosen.service, chosen.cat) or "Välj tjänst")
		page.kind:SetText(chosen.kind or "Välj typ")
		page.kind:SetShown(not chosen.direct)
		page.kindLabel:SetShown(not chosen.direct)
		local to = chosen.cat and Handlers(chosen.cat) or {}
		local leader = ns.Leader() or "guildledaren"
		page.to:SetText(chosen.cat and ("Till: " .. leader .. (#to > 0 and (" och " .. table.concat(to, ", ")) or "") .. ". Bara ni läser det.") or "")
		local len = ns.Len(page.area.box:GetText())
		if chosen.cat and (chosen.kind or chosen.direct) and len >= 5 then page.send:Enable() else page.send:Disable() end
		return
	end

	if mode == "ticket" then
		local t = view.ticket
		if not t or not Store()[t.id] then
			view.mode = "mine"
			Refresh()
			return
		end
		t.unread = nil
		page.ticket.head:SetText(string.format("%s  %s, %s  %s\n|cff999999Från %s %s|r", Num(t), Label(t.service, t.cat), t.kind, STATUS[t.status] or t.status, From(t), ns.When(t.at)))
		page.ticket.text:SetText(Thread(t))
		page.ticket.child:SetHeight(page.ticket.text:GetStringHeight() + 8)
		local open = t.status == "open"
		page.ticket.reply:SetShown(open)
		page.ticket.send:SetShown(open)
		page.ticket.close:SetShown(open)
		page.ticket.reopen:SetShown(not open)
		local len = ns.Len(page.ticket.reply.box:GetText())
		if len >= 2 then page.ticket.send:Enable() else page.ticket.send:Disable() end
		ns.RefreshTodo()
		return
	end

	-- A list: the leader's categories first, then the tickets in one.
	local items = {}
	local categories = mode == "cases" and IsGuildLeader() and not view.filter
	if categories then
		for _, c in ipairs(Categories()) do
			table.insert(items, { text = string.format("%s  |cffffffff%d öppna|r%s", c.label, c.n.open, view.closed and (" |cff999999av " .. c.n.all .. "|r") or ""),
				click = function()
					view.filter, offset = c.label, 0
					Refresh()
				end })
		end
	else
		for _, t in ipairs(Listed()) do
			local who = mode == "mine" and "" or ("  " .. From(t))
			table.insert(items, { text = string.format("%s%s|r  %s, %s%s  %s  |cff999999%s|r", t.unread and "|cffffd100" or "|cffffffff", Num(t),
				Label(t.service, t.cat), t.kind, who, STATUS[t.status] or "", ns.When(t.at)),
				click = function()
					view.mode, view.ticket = "ticket", t
					Refresh()
				end })
		end
	end
	page.list.title:SetText(mode == "mine" and "Mina ärenden" or view.filter or (IsGuildLeader() and "Ärenden efter tjänst" or "Ärenden till dig"))
	page.list.back:SetShown(view.filter ~= nil)
	offset = math.max(0, math.min(offset, #items - ROWS))
	for i, row in ipairs(page.rows) do
		local item = items[offset + i]
		row:SetShown(item ~= nil)
		if item then
			row.text:SetText(item.text)
			row:SetScript("OnClick", item.click)
		end
	end
	page.list.empty:SetShown(#items == 0)
	page.list.count:SetText(#items > ROWS and string.format("%d-%d av %d (scrolla)", offset + 1, math.min(offset + ROWS, #items), #items) or "")
end
ns.RefreshContact = Refresh

local function Menu(owner, build)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	MenuUtil.CreateContextMenu(owner, build)
end

local function Show(mode)
	view.mode, view.filter, offset = mode, nil, 0
	Refresh()
end

-- From the to-do, and the Folkvald representant rows.
function ns.ShowTickets(mode)
	ns.ShowTab(13)
	Show(mode)
end

-- Kontakta mig!: a question for that role; the leader's row is Allmänt.
function ns.ContactRole(role)
	ns.ShowTab(13)
	if role == "gl" then
		chosen.cat, chosen.service, chosen.kind, chosen.direct = "gl", "Allmänt", nil, nil
	else
		chosen.cat, chosen.service, chosen.kind, chosen.direct = role, RoleTitle(role), nil, true
	end
	Show("write")
end

function ns.BuildContact(parent)
	page = parent
	page.intro = Text(parent, "GameFontHighlight", "TOPLEFT", 24, -70)
	page.intro:SetWidth(470)
	page.intro:SetText("Har du hittat en bugg, vill du se en förbättring eller har du en idé till en helt ny addon? Skriv till oss. Guildledaren och den som har rollen för tjänsten läser det, och ni kan skriva fram och tillbaka i ärendet.")

	-- Write.
	local form = CreateFrame("Frame", nil, parent)
	form:SetAllPoints()
	page.form = form
	Text(form, "GameFontNormal", "TOPLEFT", 24, -128):SetText("Tjänst")
	page.service = Button(form, "", 250, function(self)
		Menu(self, function(_, root)
			for _, s in ipairs(ns.SERVICES) do
				root:CreateButton(Label(s.name, s.role), function()
					chosen.cat, chosen.service, chosen.direct = s.role, s.name, nil
					Refresh()
				end)
			end
		end)
	end)
	page.service:SetPoint("TOPLEFT", 24, -146)
	page.kindLabel = Text(form, "GameFontNormal", "TOPLEFT", 284, -128)
	page.kindLabel:SetText("Typ")
	page.kind = Button(form, "", 180, function(self)
		Menu(self, function(_, root)
			for _, k in ipairs(ns.CONTACT_TYPES) do
				root:CreateButton(k, function()
					chosen.kind = k
					Refresh()
				end)
			end
		end)
	end)
	page.kind:SetPoint("TOPLEFT", 284, -146)
	page.to = Text(form, "GameFontHighlightSmall", "TOPLEFT", 24, -174)
	page.to:SetWidth(470)
	Text(form, "GameFontNormal", "TOPLEFT", 24, -196):SetText("Meddelande")
	page.area = ns.TextArea(form, 460, 170, TEXT_MAX, Refresh)
	page.area:SetPoint("TOPLEFT", 24, -214)
	page.send = Button(form, "Skicka", 120, function()
		if ns.SendTicket(chosen.cat, chosen.service, chosen.direct and QUESTION or chosen.kind, page.area.box:GetText()) then
			page.area.box:SetText("")
			page.area.box:ClearFocus()
			chosen.cat, chosen.service, chosen.kind, chosen.direct = nil, nil, nil, nil
			Show("mine")
		end
	end)
	page.send:SetPoint("TOPLEFT", 24, -400)

	-- Lists.
	local list = CreateFrame("Frame", nil, parent)
	list:SetAllPoints()
	page.list = list
	list.title = Text(list, "GameFontNormalLarge", "TOPLEFT", 24, -70)
	list.back = Button(list, "Tillbaka", 80, function()
		view.filter, offset = nil, 0
		Refresh()
	end)
	list.back:SetPoint("TOPRIGHT", -24, -66)
	local closed = CreateFrame("CheckButton", nil, list, "UICheckButtonTemplate")
	closed:SetSize(22, 22)
	closed:SetPoint("TOPLEFT", 20, -94)
	closed.label = Text(closed, "GameFontHighlightSmall", "LEFT", closed, "RIGHT", 2, 0)
	closed.label:SetText("Visa stängda")
	closed:SetScript("OnClick", function(self)
		view.closed = self:GetChecked() and true or false
		Refresh()
	end)
	page.rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, list)
		row:SetSize(470, 30)
		row:SetPoint("TOPLEFT", 24, -122 - (i - 1) * 32)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.text = Text(row, "GameFontHighlightSmall", "LEFT", 4, 0)
		row.text:SetWidth(462)
		row.text:SetWordWrap(false)
		page.rows[i] = row
	end
	list.empty = Text(list, "GameFontDisable", "TOPLEFT", 24, -126)
	list.empty:SetText("Inga ärenden här.")
	list.count = Text(list, "GameFontDisableSmall", "BOTTOMLEFT", 24, 56)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta
		Refresh()
	end)

	-- One ticket and its thread.
	local ticket = CreateFrame("Frame", nil, parent)
	ticket:SetAllPoints()
	page.ticket = ticket
	ticket.head = Text(ticket, "GameFontNormal", "TOPLEFT", 24, -70)
	ticket.head:SetWidth(470)
	local scroll = CreateFrame("ScrollFrame", nil, ticket, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 24, -110)
	scroll:SetPoint("BOTTOMRIGHT", -44, 200)
	ticket.child = CreateFrame("Frame", nil, scroll)
	ticket.child:SetSize(440, 10)
	scroll:SetScrollChild(ticket.child)
	ticket.text = Text(ticket.child, "GameFontHighlightSmall", "TOPLEFT", 0, 0)
	ticket.text:SetWidth(436)
	ticket.text:SetSpacing(2)
	ticket.reply = ns.TextArea(ticket, 460, 80, REPLY_MAX, Refresh)
	ticket.reply:SetPoint("BOTTOMLEFT", 24, 90)
	ticket.send = Button(ticket, "Svara", 100, function()
		Reply(view.ticket, ticket.reply.box:GetText())
		ticket.reply.box:SetText("")
		ticket.reply.box:ClearFocus()
		Refresh()
	end)
	ticket.send:SetPoint("BOTTOMLEFT", 24, 62)
	ticket.close = Button(ticket, "Stäng ärendet", 120, function() Close(view.ticket) end)
	ticket.close:SetPoint("LEFT", ticket.send, "RIGHT", 8, 0)
	ticket.reopen = Button(ticket, "Öppna igen", 120, function() Reopen(view.ticket) end)
	ticket.reopen:SetPoint("BOTTOMLEFT", 24, 62)
	local back = Button(ticket, "Tillbaka", 80, function()
		view.mode = Mine(view.ticket) and "mine" or "cases"
		Refresh()
	end)
	back:SetPoint("BOTTOMRIGHT", -24, 62)

	-- Along the bottom: write, mine, and the cases for those who answer.
	page.writeB = Button(parent, "Skriv", 90, function() Show("write") end)
	page.writeB:SetPoint("BOTTOMLEFT", 24, 28)
	page.mineB = Button(parent, "", 140, function() Show("mine") end)
	page.mineB:SetPoint("LEFT", page.writeB, "RIGHT", 6, 0)
	page.casesB = Button(parent, "", 130, function() Show("cases") end)
	page.casesB:SetPoint("LEFT", page.mineB, "RIGHT", 6, 0)
	parent:SetScript("OnShow", Refresh)
end
