-- Skickat (Zach 14/11): every mail sent from this account in the last 30
-- days, so he can check whether something went. A tab by the mailbox's
-- own tabs opens the list beside the mailbox: newest first, which
-- character sent it, to whom, the subject, the items, gold and C.O.D.;
-- search by name, subject or item. Kept in the account's saved data only,
-- never sent anywhere.

local _, ns = ...

local KEEP_DAYS = 30
local W, ROW_H = 380, 36
local pending, tab, panel
local rows = {}

local function List()
	ns.db.sent = ns.db.sent or {}
	return ns.db.sent
end

local function Prune()
	local cut, kept = time() - KEEP_DAYS * 86400, {}
	for _, m in ipairs(List()) do
		if m.at >= cut then table.insert(kept, m) end
	end
	ns.db.sent = kept
end

local function HasTemplate(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then return C_XMLUtil.GetTemplateInfo(name) ~= nil end
	return false
end

-- "5x Thorium Bar, Salt Shaker", the items of one mail.
local function Items(m)
	local out = {}
	for _, it in ipairs(m.items) do
		table.insert(out, (it.count or 1) > 1 and string.format("%dx %s", it.count, it.name) or it.name)
	end
	return table.concat(out, ", ")
end

local function Second(m)
	local parts = {}
	if m.subject and m.subject ~= "" then table.insert(parts, m.subject) end
	if #m.items > 0 then table.insert(parts, Items(m)) end
	if (m.money or 0) > 0 then table.insert(parts, ns.Money(m.money)) end
	if (m.cod or 0) > 0 then table.insert(parts, "postförskott " .. ns.Money(m.cod)) end
	return table.concat(parts, "  ·  ")
end

local function Matches(m, q)
	if q == "" then return true end
	local function Has(text) return text and text:lower():find(q, 1, true) end
	if Has(m.to) or Has(m.from) or Has(m.subject) then return true end
	for _, it in ipairs(m.items) do
		if Has(it.name) then return true end
	end
	return false
end

local function Tooltip(row)
	local m = row.mail
	if not m then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(string.format("Till %s", m.to))
	GameTooltip:AddLine(string.format("Från %s, %s", m.from, date("%d/%m %H:%M", m.at)), 1, 1, 1)
	if m.subject and m.subject ~= "" then GameTooltip:AddLine(m.subject, 1, 1, 1, true) end
	for _, it in ipairs(m.items) do GameTooltip:AddLine(string.format("%dx %s", it.count or 1, it.name), 0.8, 0.8, 0.8) end
	if (m.money or 0) > 0 then GameTooltip:AddDoubleLine("Guld", ns.Money(m.money), 1, 1, 1, 1, 1, 1) end
	if (m.cod or 0) > 0 then GameTooltip:AddDoubleLine("Postförskott", ns.Money(m.cod), 1, 1, 1, 1, 1, 1) end
	GameTooltip:Show()
end

local function Row(i)
	if rows[i] then return rows[i] end
	local row = CreateFrame("Frame", nil, panel.content)
	row:SetSize(W - 50, ROW_H)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	row.first = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.first:SetPoint("TOPLEFT", 2, -3)
	row.first:SetPoint("RIGHT", -2, 0)
	row.first:SetJustifyH("LEFT")
	row.first:SetWordWrap(false)
	row.second = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.second:SetPoint("TOPLEFT", row.first, "BOTTOMLEFT", 0, -3)
	row.second:SetPoint("RIGHT", -2, 0)
	row.second:SetJustifyH("LEFT")
	row.second:SetWordWrap(false)
	row:EnableMouse(true)
	row:SetScript("OnEnter", Tooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = row
	return row
end

local function Refresh()
	if not (panel and panel:IsShown()) then return end
	local q = (panel.search:GetText() or ""):lower()
	local list, n = List(), 0
	for i = #list, 1, -1 do
		local m = list[i]
		if Matches(m, q) then
			n = n + 1
			local row = Row(n)
			row.mail = m
			row.first:SetText(string.format("|cffffd100%s|r  till %s  |cff999999från %s|r", date("%d/%m %H:%M", m.at), m.to, m.from))
			row.second:SetText(Second(m))
			row:Show()
		end
	end
	for i = n + 1, #rows do rows[i]:Hide() end
	panel.content:SetHeight(math.max(1, n * ROW_H))
	panel.empty:SetText(n > 0 and "" or (q == "" and "Inga skickade brev de senaste 30 dagarna." or "Inget hittat."))
end

-- The mailbox's own frame (Zach 14/11: the dialog box did not feel
-- classic): ButtonFrameTemplate, its title bar, close button and inset,
-- without the portrait; the dialog box only where that template is missing.
local function BuildPanel()
	local classic = HasTemplate("ButtonFrameTemplate")
	if classic then
		panel = CreateFrame("Frame", "SkatteverketSentFrame", MailFrame, "ButtonFrameTemplate")
		if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, panel) end
		if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, panel) end
	else
		panel = CreateFrame("Frame", "SkatteverketSentFrame", MailFrame, BackdropTemplateMixin and "BackdropTemplate")
		panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
		local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -6, -6)
	end
	panel:SetSize(W, MailFrame:GetHeight())
	panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 2, 0)
	panel:EnableMouse(true)
	local title = panel.TitleText or (panel.TitleContainer and panel.TitleContainer.TitleText)
	if not title then
		title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOPLEFT", 20, -18)
	end
	title:SetText("Skickat, senaste 30 dagarna")
	local search = CreateFrame("EditBox", nil, panel, HasTemplate("SearchBoxTemplate") and "SearchBoxTemplate" or "InputBoxTemplate")
	search:SetSize(W - 50, 20)
	search:SetPoint("TOPLEFT", 24, -40)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", Refresh)
	panel.search = search
	local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 20, -68)
	scroll:SetPoint("BOTTOMRIGHT", -36, 16)
	panel.content = CreateFrame("Frame", nil, scroll)
	panel.content:SetSize(W - 50, 1)
	scroll:SetScrollChild(panel.content)
	panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	panel.empty:SetPoint("TOP", 0, -90)
	panel:SetScript("OnShow", Refresh)
	panel:Hide()
end

-- The tab, after the mailbox's last one; it opens and closes the list.
-- The same template as the mailbox's own tabs, newest last (Zach 14/11:
-- PanelTabButtonTemplate looked different and overlapped Send Mail), and
-- the same gap as between Inbox and Send Mail.
local TAB_TEMPLATES = { "FriendsFrameTabTemplate", "CharacterFrameTabButtonTemplate", "PanelTabButtonTemplate" }
local function Build()
	if tab or not MailFrame then return end
	BuildPanel()
	local last = MailFrameTab2 or MailFrameTab1
	local template
	for _, t in ipairs(TAB_TEMPLATES) do
		if HasTemplate(t) then template = t break end
	end
	if last and template then
		tab = CreateFrame("Button", "SkatteverketSentTab", MailFrame, template)
		local x, y = -8, 0
		if MailFrameTab1 and MailFrameTab2 and MailFrameTab2.GetPoint then
			local _, rel, _, px, py = MailFrameTab2:GetPoint(1)
			if rel == MailFrameTab1 and px then x, y = px, py or 0 end
		end
		tab:SetPoint("LEFT", last, "RIGHT", x, y)
	else
		tab = CreateFrame("Button", nil, MailFrame, "UIPanelButtonTemplate")
		tab:SetSize(80, 22)
		tab:SetPoint("TOPLEFT", MailFrame, "BOTTOMLEFT", 170, 2)
	end
	tab:SetText("Skickat")
	if template then
		if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
		if PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, tab) end
	end
	tab:SetScript("OnClick", function() panel:SetShown(not panel:IsShown()) end)
end

if SendMail then
	hooksecurefunc("SendMail", function(target, subject)
		local items = {}
		for i = 1, ATTACHMENTS_MAX_SEND or 12 do
			local name, item, _, count = GetSendMailItem(i)
			if name then table.insert(items, { name = name, item = item, count = count or 1 }) end
		end
		pending = { at = time(), from = ns.Me() or UnitName("player"), to = target or "?", subject = subject, items = items,
			money = GetSendMailMoney and GetSendMailMoney() or 0, cod = GetSendMailCOD and GetSendMailCOD() or 0 }
	end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "MAIL_SHOW", "MAIL_SEND_SUCCESS", "MAIL_FAILED" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
	if not ns.db then return end
	if event == "MAIL_SHOW" then
		Build()
		Prune()
	elseif event == "MAIL_SEND_SUCCESS" then
		if pending then table.insert(List(), pending) end
		pending = nil
		Refresh()
	else
		pending = nil
	end
end)
