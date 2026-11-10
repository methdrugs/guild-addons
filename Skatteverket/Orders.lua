-- Skatteverket, arbetsordrar (Zach 9/11): order a craft from a member
-- through Yrken. The order says how many, whose materials, how long the
-- one ordering can wait, and a note. A line in guild chat,
-- "@Namn du har en ny arbetsorder!", reaches the crafter on Discord too,
-- online or not, with what was ordered (Zach 9/11). Only for members with
-- the citizen rank or higher, both ends (Zach 9/11: a privilege for good,
-- honest members). The crafter accepts, declines with a reason, or marks it
-- done; the one ordering can cancel. An unanswered order runs out when the
-- wait is over. No prices: those are agreed in a whisper, and nothing here
-- moves gold. The minimap bolt shows a hammer while orders wait for you.
--
-- Whispers, hidden:
--   O;id;from;to;key;count;mats;until;stamp;state;reason;note
--        the whole order, sent to the other party and to the leader, who
--        keeps it for whoever is offline
--   D;id;state;reason;stamp     a new state: accepterad, klar, avböjd, avbruten
--   L;id;item:count,...;stamp   the orderer's materials sent so far, by mail
--        or trade (Zach 10/11); also the 14th field of O
-- Guild channel:
--   X        at login: send me my orders; whoever holds some answers by whisper

local _, ns = ...

local DAY = 86400
local KEEP_DAYS = 14
local WAITS = { 1, 2, 3, 7 }
local REASONS = { "Har inte materialet", "För dyrt", "Inte nu" }
local STATE = { ny = "Ny", accepterad = "Accepterad", klar = "Klar", ["avböjd"] = "Avböjd", avbruten = "Avbruten", ["utgången"] = "Utgången" }
local OPEN = { ny = true, accepterad = true }
-- Whose materials (Zach 9/11): the crafter's, against a tip of a tenth of
-- what the reagents cost, so nobody orders without putting in their share.
local MATS = { e = "Beställaren skickar materialet", h = "Hantverkaren löser materialet, mot 10 % dricks" }
local TIP = 0.10

local function Orders()
	ns.db.orders = ns.db.orders or {}
	return ns.db.orders
end

local function Clean(text)
	return ((text or ""):gsub("[;|\n]", " ")):sub(1, 80)
end

-- Open orders past their wait are out of date, for everyone alike.
local function State(o)
	if OPEN[o.state] and ns.Now() > o["until"] then return "utgången" end
	return o.state
end

-- Materials sent: { [itemID] = count } as "item:count,item:count".
local function EncodeSent(sent)
	local out = {}
	for item, n in pairs(sent or {}) do table.insert(out, item .. ":" .. n) end
	table.sort(out)
	return table.concat(out, ",")
end

local function DecodeSent(text, into)
	into = into or {}
	for item, n in (text or ""):gmatch("(%d+):(%d+)") do
		item, n = tonumber(item), tonumber(n)
		into[item] = math.max(into[item] or 0, n)
	end
	return into
end

local function Pack(o)
	return table.concat({ "O", o.id, o.from, o.to, o.key, o.count, o.mats, o["until"], o.stamp, o.state, o.reason or "", Clean(o.note), o.tip or "",
		EncodeSent(o.sent) }, ";")
end

-- To the other party, and to the leader who keeps it for the offline.
local function Share(o, msg)
	local me = ns.Me()
	for _, target in ipairs({ o.from, o.to, ns.Leader() }) do
		if target and target ~= me then ns.SendTo(target, msg) end
	end
end

local function Changed()
	if ns.RefreshOrderBadge then ns.RefreshOrderBadge() end
	if ns.RefreshWindow then ns.RefreshWindow("yrken") end
end

-- Orders waiting for this character to act on: new or accepted, to them.
function ns.OrdersToDo()
	if ns.Locked() then return 0 end
	local me, n = ns.Me(), 0
	for _, o in pairs(Orders()) do
		if o.to == me and OPEN[State(o)] then n = n + 1 end
	end
	return n
end

local function RecipeName(key)
	return ns.RecipeName and ns.RecipeName(key) or key
end

-- Ordering --------------------------------------------------------------

-- What the reagents of count crafts cost on the auction house, from
-- Auctionator's prices where it is installed; nil when unknown.
local function ReagentCost(key, count)
	local d = ns.RecipeData and ns.RecipeData(key)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not d or not d.reagents or #d.reagents == 0 or not (api and api.GetAuctionPriceByItemID) then return end
	local total = 0
	for _, r in ipairs(d.reagents) do
		local ok, price = pcall(api.GetAuctionPriceByItemID, "Skatteverket", r.itemID)
		if not ok or not price then return end
		total = total + price * r.count * count
	end
	return total
end

function ns.PlaceOrder(to, key, count, mats, days, note)
	local me = ns.Me()
	if not me or not to or to == me or ns.Locked() then return end
	if not ns.IsCitizen(to) then
		ns.Print(to .. " är inte " .. ns.CITIZEN_RANK .. " och kan inte ta emot arbetsordrar.")
		return
	end
	local now = ns.Now()
	local o = { id = string.format("%x%03x", now, math.random(0, 4095)), from = me, to = to, key = key, count = count, mats = mats,
		["until"] = now + days * DAY, stamp = now, state = "ny", note = Clean(note), at = now }
	if mats == "h" then
		local cost = ReagentCost(key, count)
		if cost then o.tip = math.floor(cost * TIP) end
	end
	Orders()[o.id] = o
	Share(o, Pack(o))
	-- In guild chat so Discord passes it on, online or offline (Zach 9/11).
	SendChatMessage(string.format("@%s du har en ny arbetsorder: %s x%d! Titta under Arbetsorder i Yrken (/yrken).", to, RecipeName(key), count), "GUILD")
	ns.Print(string.format("arbetsorder skickad till %s: %s x%d.", to, RecipeName(key), count))
	-- Sending the materials (Zach 9/11): Bokföring lists what to buy.
	local d = ns.RecipeData and ns.RecipeData(key)
	if mats == "e" and d and d.reagents and BokforingAPI and BokforingAPI.ShopForOrder then
		local reagents = {}
		for _, r in ipairs(d.reagents) do table.insert(reagents, { r.itemID, r.count }) end
		BokforingAPI.ShopForOrder(RecipeName(key), reagents, count, to)
	end
	Changed()
end

local function SetState(o, state, reason)
	o.state, o.reason, o.stamp = state, reason, ns.Now()
	Share(o, table.concat({ "D", o.id, state, reason or "", o.stamp }, ";"))
	Changed()
end

-- Receiving -------------------------------------------------------------

local function Tell(o, old)
	local me = ns.Me()
	if o.to == me and not old then
		ns.Print(string.format("ny arbetsorder från %s: %s x%d, %s. Titta under Arbetsorder i Yrken.", o.from, RecipeName(o.key), o.count, MATS[o.mats] or "?"))
	elseif o.from == me and old and old.state ~= o.state then
		ns.Print(string.format("%s: din arbetsorder %s x%d är nu %s%s.", o.to, RecipeName(o.key), o.count, STATE[o.state]:lower(),
			o.reason and o.reason ~= "" and (" (" .. o.reason .. ")") or ""))
	end
end

function ns.OnOrder(sender, parts)
	local o = { id = parts[2], from = parts[3], to = parts[4], key = parts[5], count = tonumber(parts[6]), mats = parts[7],
		["until"] = tonumber(parts[8]), stamp = tonumber(parts[9]), state = parts[10], reason = parts[11] ~= "" and parts[11] or nil, note = parts[12], tip = tonumber(parts[13]) }
	if not (o.id and o.from and o.to and o.key and o.count and o["until"] and o.stamp and STATE[o.state]) then return end
	-- Nobody outside the guild roster, and only citizens.
	if ns.Online(sender) == nil or not ns.IsCitizen(sender) or ns.Locked() then return end
	-- Only a party to the order, or the leader passing it on, may send it.
	if sender ~= o.from and sender ~= o.to and sender ~= ns.Leader() then return end
	local old = Orders()[o.id]
	if old and old.stamp >= o.stamp then return end
	o.at = old and old.at or ns.Now()
	-- Sent materials only grow; keep what was known.
	o.sent = DecodeSent(parts[14], old and old.sent and DecodeSent(EncodeSent(old.sent)) or nil)
	Orders()[o.id] = o
	Tell(o, old)
	Changed()
end

function ns.OnOrderState(sender, parts)
	local o = Orders()[parts[2]]
	local state, stamp = parts[3], tonumber(parts[5])
	if not o or not STATE[state] or not stamp or stamp <= o.stamp or ns.Online(sender) == nil then return end
	if sender ~= o.from and sender ~= o.to and sender ~= ns.Leader() then return end
	local old = { state = o.state }
	o.state, o.reason, o.stamp = state, parts[4] ~= "" and parts[4] or nil, stamp
	Tell(o, old)
	Changed()
end

function ns.OnOrderSent(sender, parts)
	local o = Orders()[parts[2]]
	if not o or ns.Online(sender) == nil then return end
	if sender ~= o.from and sender ~= ns.Leader() then return end
	o.sent = DecodeSent(parts[3], o.sent)
	Changed()
	if ns.RefreshOrderView then ns.RefreshOrderView(o) end
end

-- Someone logged in: the orders they are part of, from whoever holds them.
function ns.OnOrderRequest(sender)
	if not ns.IsCitizen(sender) then return end
	local now = ns.Now()
	for _, o in pairs(Orders()) do
		if (o.to == sender or o.from == sender) and now - o.stamp < KEEP_DAYS * DAY then ns.SendTo(sender, Pack(o)) end
	end
end

local function Prune()
	local now = ns.Now()
	for id, o in pairs(Orders()) do
		if now - math.max(o.stamp, o["until"]) > KEEP_DAYS * DAY then Orders()[id] = nil end
	end
end

-- The order dialog, from Yrken's recipe window ----------------------------

local dialog

local function HasTemplate(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then return C_XMLUtil.GetTemplateInfo(name) ~= nil end
	return true
end

local function Radio(parent, label, x, y)
	local b = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
	b:SetPoint("TOPLEFT", x, y)
	local text = b.text or b.Text or b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:ClearAllPoints()
	text:SetPoint("LEFT", b, "RIGHT", 4, 0)
	text:SetFontObject("GameFontHighlight")
	text:SetText(label)
	b.label = text
	return b
end

local function Label(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

-- The tip line under "Detta löser du!": a tenth of the reagents, in money
-- where Auctionator knows the prices.
local function TipText()
	local count = tonumber(dialog.count:GetText()) or 1
	local cost = ReagentCost(dialog.key, math.max(count, 1))
	return cost and string.format("dricks 10 %% av reagenskostnaden, ungefär %s", ns.Money(cost * TIP)) or "dricks 10 % av reagenskostnaden"
end

-- A classic panel like the other THÖNDERSTÖRM windows (Zach 9/11: the first
-- was a bare box), with the recipe's icon as portrait.
local function BuildDialog()
	local ok
	if HasTemplate("ButtonFrameTemplate") then ok, dialog = pcall(CreateFrame, "Frame", "SkatteverketOrderDialog", UIParent, "ButtonFrameTemplate") end
	if not ok or not dialog then
		dialog = CreateFrame("Frame", "SkatteverketOrderDialog", UIParent, BackdropTemplateMixin and "BackdropTemplate")
		dialog:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
	end
	dialog:SetSize(380, 360)
	dialog:SetPoint("CENTER")
	dialog:SetFrameStrata("DIALOG")
	dialog:SetToplevel(true)
	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
	tinsert(UISpecialFrames, "SkatteverketOrderDialog")
	dialog.titleText = dialog.TitleText or (dialog.TitleContainer and dialog.TitleContainer.TitleText)
	dialog.portraitTexture = dialog.portrait or dialog.Portrait or (dialog.PortraitContainer and dialog.PortraitContainer.portrait)

	-- Beside the portrait: what is ordered, and from whom.
	dialog.recipe = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	dialog.recipe:SetPoint("TOPLEFT", 66, -34)
	dialog.recipe:SetWidth(290)
	dialog.recipe:SetJustifyH("LEFT")

	Label(dialog, "Antal", 24, -74)
	dialog.count = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	dialog.count:SetSize(50, 20)
	dialog.count:SetPoint("TOPLEFT", 140, -70)
	dialog.count:SetAutoFocus(false)
	dialog.count:SetNumeric(true)
	dialog.count:SetMaxLetters(3)
	dialog.count:SetScript("OnTextChanged", function() if dialog.theirs then dialog.tip:SetText(TipText()) end end)

	Label(dialog, "Material", 24, -106)
	dialog.own = Radio(dialog, "Jag skickar materialet", 136, -100)
	dialog.theirs = Radio(dialog, "Detta löser du!", 136, -124)
	dialog.tip = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	dialog.tip:SetPoint("TOPLEFT", 162, -146)
	dialog.tip:SetWidth(200)
	dialog.tip:SetJustifyH("LEFT")
	dialog.own:SetScript("OnClick", function() dialog.mats = "e" dialog.own:SetChecked(true) dialog.theirs:SetChecked(false) end)
	dialog.theirs:SetScript("OnClick", function() dialog.mats = "h" dialog.theirs:SetChecked(true) dialog.own:SetChecked(false) end)

	-- How long the one ordering can wait (Zach 9/11).
	Label(dialog, "Jag kan vänta", 24, -186)
	dialog.waits = {}
	for k, days in ipairs(WAITS) do
		local b = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
		b:SetSize(52, 22)
		b:SetPoint("TOPLEFT", 136 + (k - 1) * 56, -182)
		b:SetText(days == 1 and "1 dag" or (days .. " dgr"))
		b:SetScript("OnClick", function()
			dialog.days = days
			for _, other in ipairs(dialog.waits) do other:UnlockHighlight() end
			b:LockHighlight()
		end)
		b.days = days
		dialog.waits[k] = b
	end

	Label(dialog, "Anteckning", 24, -222)
	dialog.note = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	dialog.note:SetSize(214, 20)
	dialog.note:SetPoint("TOPLEFT", 140, -218)
	dialog.note:SetAutoFocus(false)
	dialog.note:SetMaxLetters(80)

	dialog.warn = dialog:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
	dialog.warn:SetPoint("BOTTOM", 0, 40)

	-- Buttons in the strip under the inset, as on the Social window.
	local cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	cancel:SetSize(100, 22)
	cancel:SetPoint("BOTTOMRIGHT", -8, 4)
	cancel:SetText("Avbryt")
	cancel:SetScript("OnClick", function() dialog:Hide() end)
	local send = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	send:SetSize(100, 22)
	send:SetPoint("RIGHT", cancel, "LEFT", -4, 0)
	send:SetText("Beställ")
	send:SetScript("OnClick", function()
		local count = tonumber(dialog.count:GetText())
		if not count or count < 1 then dialog.warn:SetText("Skriv hur många.") return end
		-- The crafter must know what to expect (Zach 9/11): no default.
		if not dialog.mats then dialog.warn:SetText("Välj vem som står för materialet.") return end
		ns.PlaceOrder(dialog.to, dialog.key, count, dialog.mats, dialog.days, dialog.note:GetText())
		dialog:Hide()
	end)
	dialog:Hide()
end

function ns.OrderDialog(to, key)
	if not dialog then BuildDialog() end
	dialog.to, dialog.key, dialog.mats, dialog.days = to, key, nil, 7
	if dialog.titleText then dialog.titleText:SetText("Arbetsorder till " .. to) end
	local d = ns.RecipeData and ns.RecipeData(key)
	local icon = (d and d.icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
	if dialog.SetPortraitToAsset then dialog:SetPortraitToAsset(icon)
	elseif dialog.portraitTexture then dialog.portraitTexture:SetTexture(icon) end
	dialog.recipe:SetText(RecipeName(key))
	dialog.count:SetText("1")
	dialog.own:SetChecked(false)
	dialog.theirs:SetChecked(false)
	dialog.tip:SetText(TipText())
	dialog.note:SetText("")
	dialog.warn:SetText("")
	for _, b in ipairs(dialog.waits) do
		if b.days == dialog.days then b:LockHighlight() else b:UnlockHighlight() end
	end
	dialog:Show()
end

-- How far the orderer's materials are: sent, needed, and a coloured word
-- (Zach 10/11: Yrken should make it clear that they have been sent).
local function SentStatus(o)
	if o.mats ~= "e" then return end
	local d, need, sent = ns.RecipeData and ns.RecipeData(o.key), 0, 0
	for _, r in ipairs(d and d.reagents or {}) do
		need = need + r.count * o.count
		sent = sent + math.min(o.sent and o.sent[r.itemID] or 0, r.count * o.count)
	end
	if need == 0 then return end
	if sent >= need then return "|cff40ff40material skickat|r", sent, need end
	if sent > 0 then return string.format("|cffff8040material %d/%d skickat|r", sent, need), sent, need end
	return "|cffff4040material inte skickat|r", sent, need
end

-- The order itself (member feedback 10/11): clicked open from the list,
-- with everything about it, and the only place to accept or decline a new
-- one, so nobody accepts without reading it. The item is a link: hover for
-- its tooltip, click to open it as from chat, shift-click to link it.
local view
local ShowOrder

local function OpenLink(key)
	local link = ns.RecipeLink(key)
	if not link or not ItemRefTooltip then return end
	if not ItemRefTooltip:IsShown() then ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
	ItemRefTooltip:SetHyperlink(link)
	ItemRefTooltip:Show()
end

local function BuildView()
	local ok
	if HasTemplate("ButtonFrameTemplate") then ok, view = pcall(CreateFrame, "Frame", "SkatteverketOrderView", UIParent, "ButtonFrameTemplate") end
	if not ok or not view then
		view = CreateFrame("Frame", "SkatteverketOrderView", UIParent, BackdropTemplateMixin and "BackdropTemplate")
		view:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
	end
	view:SetSize(400, 400)
	view:SetPoint("CENTER", 0, 40)
	view:SetFrameStrata("DIALOG")
	view:SetToplevel(true)
	view:EnableMouse(true)
	view:SetMovable(true)
	view:RegisterForDrag("LeftButton")
	view:SetScript("OnDragStart", view.StartMoving)
	view:SetScript("OnDragStop", view.StopMovingOrSizing)
	tinsert(UISpecialFrames, "SkatteverketOrderView")
	view.titleText = view.TitleText or (view.TitleContainer and view.TitleContainer.TitleText)
	view.portraitTexture = view.portrait or view.Portrait or (view.PortraitContainer and view.PortraitContainer.portrait)

	-- The item, as a link.
	view.item = CreateFrame("Button", nil, view)
	view.item:SetSize(300, 36)
	view.item:SetPoint("TOPLEFT", 66, -30)
	view.item.icon = view.item:CreateTexture(nil, "ARTWORK")
	view.item.icon:SetSize(32, 32)
	view.item.icon:SetPoint("LEFT")
	view.item.text = view.item:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	view.item.text:SetPoint("LEFT", view.item.icon, "RIGHT", 8, 0)
	view.item.text:SetWidth(250)
	view.item.text:SetJustifyH("LEFT")
	view.item:RegisterForClicks("LeftButtonUp")
	view.item:SetScript("OnEnter", function(self)
		local link = view.order and ns.RecipeLink(view.order.key)
		if not link then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(link)
		GameTooltip:Show()
	end)
	view.item:SetScript("OnLeave", function() GameTooltip:Hide() end)
	view.item:SetScript("OnClick", function()
		local o = view.order
		if not o then return end
		if IsModifiedClick("CHATLINK") then
			local link = ns.RecipeChatLink(o.key)
			if link then ChatEdit_InsertLink(link) end
		else
			OpenLink(o.key)
		end
	end)

	view.body = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	view.body:SetPoint("TOPLEFT", 24, -80)
	view.body:SetWidth(352)
	view.body:SetJustifyH("LEFT")
	view.body:SetJustifyV("TOP")
	view.body:SetSpacing(3)

	-- Buttons in the strip under the inset, as on the order dialog.
	view.close = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
	view.close:SetSize(90, 22)
	view.close:SetPoint("BOTTOMRIGHT", -8, 4)
	view.close:SetText("Stäng")
	view.close:SetScript("OnClick", function() view:Hide() end)
	view.b = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
	view.b:SetSize(90, 22)
	view.b:SetPoint("RIGHT", view.close, "LEFT", -4, 0)
	view.a = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
	view.a:SetSize(90, 22)
	view.a:SetPoint("RIGHT", view.b, "LEFT", -4, 0)
	view:Hide()
end

local function ViewButton(b, label, onClick)
	if not label then
		b:Hide()
		return
	end
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	b:Show()
end

ShowOrder = function(o)
	if not view then BuildView() end
	view.order = o
	local me, state = ns.Me(), State(o)
	local incoming = o.to == me
	if view.titleText then view.titleText:SetText(incoming and ("Arbetsorder från " .. o.from) or ("Arbetsorder till " .. o.to)) end
	local d = ns.RecipeData and ns.RecipeData(o.key)
	local icon = (d and d.icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
	if view.SetPortraitToAsset then view:SetPortraitToAsset(icon) elseif view.portraitTexture then view.portraitTexture:SetTexture(icon) end
	view.item.icon:SetTexture(icon)
	local link = ns.RecipeChatLink(o.key)
	view.item.text:SetText(string.format("%s x%d", link or RecipeName(o.key), o.count))
	local lines = {
		"|cffffd100Beställd:|r " .. date("%d/%m %H:%M", o.at or o.stamp),
		string.format("|cffffd100Från:|r %s   |cffffd100Till:|r %s", o.from, o.to),
		"|cffffd100Material:|r " .. (MATS[o.mats] or "?"),
	}
	local status = SentStatus(o)
	if status then table.insert(lines, "|cffffd100Skickat:|r " .. status) end
	if o.tip then table.insert(lines, "|cffffd100Dricks:|r ungefär " .. ns.Money(o.tip)) end
	table.insert(lines, "|cffffd100Väntar till:|r " .. date("%d/%m %H:%M", o["until"]))
	-- One line a reagent (Zach 10/11: names showed as "..." while loading;
	-- the view is drawn again when they arrive), and what has been sent.
	view.waiting = false
	if d and d.reagents and #d.reagents > 0 then
		table.insert(lines, "|cffffd100Reagenser:|r")
		for _, r in ipairs(d.reagents) do
			local name = ns.ItemName(r.itemID)
			if not name then view.waiting = true end
			local need = r.count * o.count
			local sent = o.mats == "e" and (o.sent and o.sent[r.itemID] or 0)
			local mark = sent and (sent >= need and string.format("  |cff40ff40skickat %d/%d|r", sent, need)
				or string.format("  |cffff8040skickat %d/%d|r", sent, need)) or ""
			table.insert(lines, string.format("   %d x %s%s", need, name or "|cff808080laddar...|r", mark))
		end
	end
	table.insert(lines, "|cffffd100Kommentar:|r " .. ((o.note and o.note ~= "") and o.note or "|cff808080ingen|r"))
	table.insert(lines, "|cffffd100Status:|r " .. STATE[state] .. (o.reason and (" (" .. o.reason .. ")") or ""))
	view.body:SetText(table.concat(lines, "\n"))
	local function After(newState, reason)
		return function()
			SetState(o, newState, reason)
			ShowOrder(o)
		end
	end
	if incoming and state == "ny" then
		ViewButton(view.a, "Acceptera", After("accepterad"))
		ViewButton(view.b, "Avböj", function(self) ns.DeclineOrder(self, o) end)
	elseif incoming and state == "accepterad" then
		ViewButton(view.a, "Avböj", function(self) ns.DeclineOrder(self, o) end)
		ViewButton(view.b, "Klar", After("klar"))
	elseif not incoming and OPEN[state] then
		ViewButton(view.a, nil)
		ViewButton(view.b, "Avbryt", After("avbruten"))
	else
		ViewButton(view.a, nil)
		ViewButton(view.b, nil)
	end
	view:Show()
end
ns.ShowOrder = function(o) ShowOrder(o) end

-- Drawn again for news about the order shown, or names that loaded.
function ns.RefreshOrderView(o)
	if view and view:IsShown() and (not o or view.order == o) then ShowOrder(view.order) end
end
local names = CreateFrame("Frame")
names:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local soon = false
names:SetScript("OnEvent", function()
	if soon or not (view and view:IsShown() and view.waiting) then return end
	soon = true
	C_Timer.After(0.2, function()
		soon = false
		ns.RefreshOrderView()
	end)
end)

-- Materials sent (Zach 10/11): what the orderer mails or trades to the
-- crafter counts against the reagents of their open orders with that
-- crafter where the orderer sends the materials, oldest order first. Both
-- ends and the leader get the totals.
local function Matches(target, name)
	if not target or not name then return false end
	target, name = target:lower(), name:lower()
	return target == name or name:match("^(%S+)") == target
end

local function Delivered(target, items)
	local me, list = ns.Me(), {}
	for _, o in pairs(Orders()) do
		if o.from == me and o.mats == "e" and OPEN[State(o)] and Matches(target, o.to) then table.insert(list, o) end
	end
	table.sort(list, function(a, b) return a.at < b.at end)
	for _, o in ipairs(list) do
		local d = ns.RecipeData and ns.RecipeData(o.key)
		local counted = {}
		for _, r in ipairs(d and d.reagents or {}) do
			o.sent = o.sent or {}
			local need = r.count * o.count - (o.sent[r.itemID] or 0)
			local give = math.min(items[r.itemID] or 0, math.max(0, need))
			if give > 0 then
				o.sent[r.itemID] = (o.sent[r.itemID] or 0) + give
				items[r.itemID] = items[r.itemID] - give
				table.insert(counted, string.format("%d x %s", give, ns.ItemName(r.itemID) or "?"))
			end
		end
		if #counted > 0 then
			o.stamp = ns.Now()
			Share(o, table.concat({ "L", o.id, EncodeSent(o.sent), o.stamp }, ";"))
			ns.Print(string.format("material till %s för %s x%d: %s.", o.to, RecipeName(o.key), o.count, table.concat(counted, ", ")))
			Changed()
			if ns.RefreshOrderView then ns.RefreshOrderView(o) end
		end
	end
end

-- Mail: the attachments at SendMail, counted once the mail has gone.
local pendingMail
if SendMail then
	hooksecurefunc("SendMail", function(target)
		local items = {}
		for i = 1, ATTACHMENTS_MAX_SEND or 12 do
			local _, item, _, count = GetSendMailItem(i)
			if item then items[item] = (items[item] or 0) + (count or 1) end
		end
		pendingMail = next(items) and { to = target, items = items } or nil
	end)
end

-- Trade: what he put in, counted when the trade completes.
local trade
local function ReadTrade()
	if not trade then return end
	local items = {}
	for i = 1, MAX_TRADABLE_ITEMS or 6 do
		local link = GetTradePlayerItemLink and GetTradePlayerItemLink(i)
		local item = link and tonumber(link:match("item:(%d+)"))
		local count = item and select(3, GetTradePlayerItemInfo(i))
		if item then items[item] = (items[item] or 0) + (count or 1) end
	end
	trade.items = items
end

local tracker = CreateFrame("Frame")
for _, event in ipairs({ "MAIL_SEND_SUCCESS", "MAIL_FAILED", "TRADE_SHOW", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE",
	"TRADE_CLOSED", "UI_INFO_MESSAGE" }) do
	pcall(tracker.RegisterEvent, tracker, event)
end
tracker:SetScript("OnEvent", function(_, event, a, b)
	if not ns.db then return end
	if event == "MAIL_SEND_SUCCESS" then
		if pendingMail then Delivered(pendingMail.to, pendingMail.items) end
		pendingMail = nil
	elseif event == "MAIL_FAILED" then
		pendingMail = nil
	elseif event == "TRADE_SHOW" then
		trade = { with = UnitName("NPC") }
	elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
		ReadTrade()
	elseif event == "UI_INFO_MESSAGE" then
		-- The message is the second value on newer clients.
		local text = type(b) == "string" and b or a
		if issecretvalue and issecretvalue(text) then return end
		if trade and trade.items and text == ERR_TRADE_COMPLETE then
			Delivered(trade.with, trade.items)
			trade = nil
		end
	end
end)

-- The Arbetsorder page, a side tab of the Yrken window (Zach 9/11) ---------

local page, rows, offset = nil, {}, 0
local ROWS, ROW_H = 16, 22

local function Act(o, state, reason)
	SetState(o, state, reason)
end

local function Decline(owner, o)
	local function Done(reason)
		Act(o, "avböjd", reason)
		if view and view:IsShown() and view.order == o then ShowOrder(o) end
	end
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		Done(REASONS[3])
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Avböj, därför att:")
		for _, reason in ipairs(REASONS) do root:CreateButton(reason, function() Done(reason) end) end
	end)
end
ns.DeclineOrder = Decline

function ns.BuildOrders(parent)
	page = parent
	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 24, -70)
	title:SetText("Arbetsorder")
	page.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	page.empty:SetPoint("TOPLEFT", 24, -100)
	page.empty:SetWidth(390)
	page.empty:SetJustifyH("LEFT")
	page.empty:SetText("Inga arbetsordrar. Beställ från någon under Yrken: öppna deras recept, välj ett och tryck Beställ.")
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, parent)
		row:SetSize(400, ROW_H)
		row:SetPoint("TOPLEFT", 20, -90 - (i - 1) * ROW_H)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", 4, 0)
		row.text:SetWidth(230)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row.a = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.a:SetSize(76, 20)
		row.a:SetPoint("RIGHT", -84, 0)
		row.b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.b:SetSize(76, 20)
		row.b:SetPoint("RIGHT", -4, 0)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			local o = self.order
			if not o then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(string.format("%s x%d", RecipeName(o.key), o.count))
			GameTooltip:AddLine(string.format("Från %s till %s", o.from, o.to), 1, 1, 1)
			GameTooltip:AddLine(MATS[o.mats] or "?", 1, 1, 1)
			if o.tip then GameTooltip:AddLine("Dricks: ungefär " .. ns.Money(o.tip), 1, 0.82, 0) end
			GameTooltip:AddLine("Väntar till " .. date("%d/%m %H:%M", o["until"]), 1, 1, 1)
			if o.note and o.note ~= "" then GameTooltip:AddLine("Anteckning: " .. o.note, 1, 1, 1, true) end
			GameTooltip:AddLine("Status: " .. STATE[State(o)] .. (o.reason and (" (" .. o.reason .. ")") or ""), 1, 0.82, 0)
			GameTooltip:AddLine("Klicka för att öppna ordern.", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		-- Click an order to open it (member feedback 10/11).
		row:SetScript("OnMouseUp", function(self)
			if self.order then ShowOrder(self.order) end
		end)
		rows[i] = row
	end
	parent:EnableMouseWheel(true)
	parent:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, offset - delta * 3)
		ns.RefreshOrders()
	end)
end

local function Button(b, label, onClick)
	if not label then
		b:Hide()
		return
	end
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	b:Show()
end

-- Three sections: to you, from you, then to yourself, Bokföring's shopping
-- lists still on the go (Zach 9/11); open ones first, newest first.
function ns.RefreshOrders()
	if not page then return end
	local me = ns.Me()
	local lines = {}
	for _, section in ipairs({ { "to", "Till dig" }, { "from", "Från dig" } }) do
		local list = {}
		for _, o in pairs(Orders()) do
			if o[section[1]] == me then table.insert(list, o) end
		end
		table.sort(list, function(a, b)
			local oa, ob = OPEN[State(a)] and 1 or 0, OPEN[State(b)] and 1 or 0
			if oa ~= ob then return oa > ob end
			return a.at > b.at
		end)
		if #list > 0 then
			table.insert(lines, { header = section[2] })
			for _, o in ipairs(list) do table.insert(lines, { order = o, incoming = section[1] == "to" }) end
		end
	end
	local own = BokforingAPI and BokforingAPI.Work and BokforingAPI.Work() or {}
	if #own > 0 then
		table.insert(lines, { header = "Till dig själv" })
		for _, w in ipairs(own) do table.insert(lines, { work = w }) end
	end
	page.empty:SetShown(#lines == 0)
	offset = math.max(0, math.min(offset, #lines - ROWS))
	for i, row in ipairs(rows) do
		local line = lines[i + offset]
		row.order = line and line.order
		if not line then
			row:Hide()
		elseif line.work then
			local w = line.work
			row.text:SetText(string.format("|cffffffff%s|r  %d av %d gjorda%s", w.name, w.made, w.crafts,
				w.missing > 0 and string.format(", |cffff4040%d reagenser saknas|r", w.missing) or ""))
			Button(row.a, nil)
			Button(row.b, "Bokföring", function() BokforingAPI.ShowWork() end)
			row:Show()
		elseif line.header then
			row.text:SetText("|cffffd100" .. line.header .. "|r")
			row.a:Hide()
			row.b:Hide()
			row:Show()
		else
			local o, state = line.order, State(line.order)
			local who = line.incoming and o.from or o.to
			local colour = OPEN[state] and "|cffffffff" or "|cff808080"
			-- To the crafter: whose materials, in their words.
			local mats = line.incoming and (o.mats == "e" and "deras material, " or ("ditt material" .. (o.tip and (" +" .. ns.Money(o.tip)) or "") .. ", ")) or ""
			-- Materials the orderer sends: how far along, while the order is open.
			local status = OPEN[state] and SentStatus(o)
			if status then mats = (line.incoming and "" or mats) .. status .. ", " end
			row.text:SetText(string.format("%s%s x%d|r  %s, %s%s", colour, RecipeName(o.key), o.count, who, mats, STATE[state]:lower()))
			if line.incoming and state == "ny" then
				-- Accepted only from the opened order, after reading it.
				Button(row.a, nil)
				Button(row.b, "Öppna", function() ShowOrder(o) end)
			elseif line.incoming and state == "accepterad" then
				Button(row.a, "Avböj", function(self) Decline(self, o) end)
				Button(row.b, "Klar", function() Act(o, "klar") end)
			elseif not line.incoming and OPEN[state] then
				Button(row.a, nil)
				Button(row.b, "Avbryt", function() Act(o, "avbruten") end)
			else
				Button(row.a, nil)
				Button(row.b, nil)
			end
			row:Show()
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	C_Timer.After(45, function()
		if not ns.db or not ns.InOurGuild() then return end
		Prune()
		ns.Send("X")
		Changed()
	end)
	-- Orders run out with time; the badge follows.
	C_Timer.NewTicker(60, function() if ns.db and ns.RefreshOrderBadge then ns.RefreshOrderBadge() end end)
end)
