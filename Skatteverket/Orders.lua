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
--   O, 15th field (0.30): raw materials item:count,... sent in place of the
--        recipe's reagents; 16th: what the crafter makes of them first,
--        item:crafts,... (Zach 10/11); 17th (0.31): who gets the finished
--        crafts when not the one ordering, set by the guild leader only
--        (Zach 11/11: a smith's crafts straight to the enchanter)
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

-- An ordered list "item:count,..." for raw materials and steps.
local function EncodeList(list, field)
	local out = {}
	for _, r in ipairs(list or {}) do table.insert(out, r.itemID .. ":" .. r[field]) end
	return table.concat(out, ",")
end

local function DecodeList(text, field)
	if not text or text == "" then return end
	local out = {}
	for item, n in text:gmatch("(%d+):(%d+)") do table.insert(out, { itemID = tonumber(item), [field] = tonumber(n) }) end
	return #out > 0 and out or nil
end

-- What the orderer sends in all, { itemID, need }: the raw materials when
-- the order has them (0.30), otherwise the recipe's reagents times count.
local function Reagents(o)
	local out = {}
	if o.raw then
		for _, r in ipairs(o.raw) do table.insert(out, { itemID = r.itemID, need = r.count }) end
		return out
	end
	local d = ns.RecipeData and ns.RecipeData(o.key)
	for _, r in ipairs(d and d.reagents or {}) do table.insert(out, { itemID = r.itemID, need = r.count * o.count }) end
	return out
end

local function Pack(o)
	return table.concat({ "O", o.id, o.from, o.to, o.key, o.count, o.mats, o["until"], o.stamp, o.state, o.reason or "", Clean(o.note), o.tip or "",
		EncodeSent(o.sent), EncodeList(o.raw, "count"), EncodeList(o.steps, "crafts"), o.deliver or "" }, ";")
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
	-- Making now follows the materials sent (review 11/11).
	if BokforingAPI and BokforingAPI.Refresh then BokforingAPI.Refresh() end
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

-- His own order declined or run out (Zach 11/11: a chat line was easy to
-- miss): on the bolt's ! until he has opened it.
local function Unnoticed(o)
	local state = State(o)
	return o.from == ns.Me() and not o.noticed and (state == "avböjd" or state == "utgången")
end

function ns.OrderNotices()
	local out = {}
	if not ns.db or ns.Locked() then return out end
	-- Once (0.32): orders that closed before the notices are no news.
	if not ns.db.ordersNoticed then
		for _, o in pairs(Orders()) do
			if not OPEN[State(o)] then o.noticed = true end
		end
		ns.db.ordersNoticed = true
	end
	for _, o in pairs(Orders()) do
		if Unnoticed(o) then
			local text = State(o) == "avböjd"
				and string.format("%s avböjde din order %s x%d%s", o.to:match("^(%S+)"), RecipeName(o.key), o.count, o.reason and (" (" .. o.reason .. ")") or "")
				or string.format("Din order %s x%d till %s gick ut", RecipeName(o.key), o.count, o.to:match("^(%S+)"))
			table.insert(out, { text = text, click = function() ns.ShowOrder(o) end })
		end
	end
	return out
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

function ns.PlaceOrder(to, key, count, mats, days, note, raw, steps, deliver)
	local me = ns.Me()
	if not me or not to or to == me or ns.Locked() then return end
	if not ns.IsCitizen(to) then
		ns.Print(to .. " är inte " .. ns.CITIZEN_RANK .. " och kan inte ta emot arbetsordrar.")
		return
	end
	local now = ns.Now()
	local o = { id = string.format("%x%03x", now, math.random(0, 4095)), from = me, to = to, key = key, count = count, mats = mats,
		["until"] = now + days * DAY, stamp = now, state = "ny", note = Clean(note), at = now }
	if mats == "e" and raw then o.raw, o.steps = raw, steps end
	if deliver and deliver ~= me and deliver ~= to then o.deliver = deliver end
	if mats == "h" then
		local cost = ReagentCost(key, count)
		if cost then o.tip = math.floor(cost * TIP) end
	end
	Orders()[o.id] = o
	Share(o, Pack(o))
	-- In guild chat so Discord passes it on, online or offline (Zach 9/11).
	-- With a recipient, both are named, so Discord reaches both and an
	-- older client still sees where it goes (Zach 11/11).
	if o.deliver then
		SendChatMessage(string.format("@%s du har en ny arbetsorder: %s x%d! Skicka det färdiga till @%s. Titta under Arbetsorder i Yrken (/yrken).",
			to, RecipeName(key), count, o.deliver), "GUILD")
	else
		SendChatMessage(string.format("@%s du har en ny arbetsorder: %s x%d! Titta under Arbetsorder i Yrken (/yrken).", to, RecipeName(key), count), "GUILD")
	end
	ns.Print(string.format("arbetsorder skickad till %s: %s x%d%s.", to, RecipeName(key), count, o.deliver and (", det färdiga till " .. o.deliver) or ""))
	-- Sending the materials (Zach 9/11): Bokföring lists what to buy.
	-- Raw materials go on the list in all, not per craft (Zach 10/11).
	if mats == "e" and BokforingAPI and BokforingAPI.ShopForOrder then
		local reagents = {}
		for _, r in ipairs(Reagents(o)) do table.insert(reagents, { r.itemID, r.need }) end
		if #reagents > 0 then BokforingAPI.ShopForOrder(RecipeName(key), reagents, count, to, true, o.id) end
	end
	Changed()
end

-- A cancelled order's materials already sent (Zach 10/11): the crafter
-- has them, so they count on the orderer's other open orders to the same crafter
-- that still need them, oldest first. Done once; the cancelled order keeps
-- its own count.
local function MoveSent(o)
	if o.moved or o.mats ~= "e" or not o.sent or not next(o.sent) then return end
	o.moved = true
	local left = {}
	for item, n in pairs(o.sent) do left[item] = n end
	local others = {}
	for _, other in pairs(Orders()) do
		if other ~= o and other.from == o.from and other.to == o.to and other.mats == "e" and OPEN[State(other)] then
			table.insert(others, other)
		end
	end
	table.sort(others, function(a, b) return a.at < b.at end)
	for _, other in ipairs(others) do
		local moved = {}
		for _, r in ipairs(Reagents(other)) do
			other.sent = other.sent or {}
			local give = math.min(left[r.itemID] or 0, math.max(0, r.need - (other.sent[r.itemID] or 0)))
			if give > 0 then
				other.sent[r.itemID] = (other.sent[r.itemID] or 0) + give
				left[r.itemID] = left[r.itemID] - give
				table.insert(moved, string.format("%d x %s", give, ns.ItemName(r.itemID) or "?"))
			end
		end
		if #moved > 0 then
			other.stamp = ns.Now()
			Share(other, table.concat({ "L", other.id, EncodeSent(other.sent), other.stamp }, ";"))
			ns.Print(string.format("material från den avbrutna ordern räknas nu på %s x%d till %s: %s.",
				ns.RecipeName and ns.RecipeName(other.key) or other.key, other.count, other.to, table.concat(moved, ", ")))
		end
	end
end

local function SetState(o, state, reason)
	o.state, o.reason, o.stamp = state, reason, ns.Now()
	Share(o, table.concat({ "D", o.id, state, reason or "", o.stamp }, ";"))
	if state == "avbruten" and o.from == ns.Me() then MoveSent(o) end
	-- The crafter takes on the materials (Zach 11/11): Bokföring lists what
	-- the bags lack.
	if state == "accepterad" and o.to == ns.Me() and o.mats == "h" and BokforingAPI and BokforingAPI.ShopForCraft then
		local reagents = {}
		for _, r in ipairs(Reagents(o)) do table.insert(reagents, { r.itemID, r.need }) end
		if #reagents > 0 then BokforingAPI.ShopForCraft(RecipeName(o.key), reagents, o.count, o.from, o.id) end
	end
	Changed()
end

-- Receiving -------------------------------------------------------------

local function Tell(o, old)
	local me = ns.Me()
	if o.to == me and not old then
		ns.Print(string.format("ny arbetsorder från %s: %s x%d, %s.%s Titta under Arbetsorder i Yrken.", o.from, RecipeName(o.key), o.count, MATS[o.mats] or "?",
			o.deliver and (" Skicka det färdiga till " .. o.deliver .. ".") or ""))
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
	o.raw, o.steps = DecodeList(parts[15], "count"), DecodeList(parts[16], "crafts")
	o.noticed = old and old.noticed
	-- A recipient only from the guild leader's orders (Zach 11/11).
	if parts[17] and parts[17] ~= "" and o.from == ns.Leader() then o.deliver = parts[17] end
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

-- Skicka råvaror (Zach 10/11): offered when the crafter levels on making
-- a reagent, ticked from the start; the line says what changes and why.
local COLOUR_WORD = { o = "orange", y = "gul", g = "grön" }
local function UpdateRaw()
	local count = math.max(tonumber(dialog.count:GetText()) or 1, 1)
	local raw, steps
	if dialog.mats == "e" and ns.RawPlan then raw, steps = ns.RawPlan(dialog.to, dialog.key, count) end
	dialog.raw, dialog.steps = raw, steps
	dialog.rawBox:SetShown(raw ~= nil)
	if not raw then return end
	local send, made = {}, {}
	for _, r in ipairs(raw) do table.insert(send, string.format("%d %s", r.count, ns.ItemName(r.itemID) or "...")) end
	for _, st in ipairs(steps) do
		table.insert(made, string.format("%d %s (%s för %s)", st.crafts, ns.ItemName(st.itemID) or "...", COLOUR_WORD[st.colour] or "?", dialog.to))
	end
	dialog.rawBox.text:SetText(string.format("Skicka råvaror: %s i stället för %s", table.concat(send, ", "), table.concat(made, ", ")))
end

-- A guild member from what was typed: the full name, or a first name or
-- the start of one when only one member matches. nil for empty; nil and
-- what is wrong when nobody or several match.
function ns.FindMember(text)
	text = strtrim(text or ""):lower()
	if text == "" then return end
	local roster = ns.RosterNames() or {}
	for name in pairs(roster) do
		if name:lower() == text then return name end
	end
	local hit
	for name in pairs(roster) do
		if name:lower():sub(1, #text) == text then
			if hit then return nil, "Flera i guildet börjar så, skriv hela namnet." end
			hit = name
		end
	end
	if not hit then return nil, "Ingen i guildet heter så." end
	return hit
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
	dialog:SetSize(380, 420)
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
	dialog.count:SetScript("OnTextChanged", function()
		if dialog.theirs then dialog.tip:SetText(TipText()) end
		if dialog.rawBox then UpdateRaw() end
	end)

	Label(dialog, "Material", 24, -106)
	dialog.own = Radio(dialog, "Jag skickar materialet", 136, -100)
	dialog.theirs = Radio(dialog, "Detta löser du!", 136, -124)
	dialog.tip = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	dialog.tip:SetPoint("TOPLEFT", 162, -146)
	dialog.tip:SetWidth(200)
	dialog.tip:SetJustifyH("LEFT")
	dialog.own:SetScript("OnClick", function() dialog.mats = "e" dialog.own:SetChecked(true) dialog.theirs:SetChecked(false) UpdateRaw() end)
	dialog.theirs:SetScript("OnClick", function() dialog.mats = "h" dialog.theirs:SetChecked(true) dialog.own:SetChecked(false) UpdateRaw() end)

	dialog.rawBox = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
	dialog.rawBox:SetSize(24, 24)
	dialog.rawBox:SetPoint("TOPLEFT", 132, -176)
	dialog.rawBox.text = dialog.rawBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dialog.rawBox.text:SetPoint("TOPLEFT", dialog.rawBox, "TOPRIGHT", 2, -5)
	dialog.rawBox.text:SetWidth(200)
	dialog.rawBox.text:SetJustifyH("LEFT")

	-- How long the one ordering can wait (Zach 9/11).
	Label(dialog, "Jag kan vänta", 24, -242)
	dialog.waits = {}
	for k, days in ipairs(WAITS) do
		local b = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
		b:SetSize(52, 22)
		b:SetPoint("TOPLEFT", 136 + (k - 1) * 56, -238)
		b:SetText(days == 1 and "1 dag" or (days .. " dgr"))
		b:SetScript("OnClick", function()
			dialog.days = days
			for _, other in ipairs(dialog.waits) do other:UnlockHighlight() end
			b:LockHighlight()
		end)
		b.days = days
		dialog.waits[k] = b
	end

	Label(dialog, "Anteckning", 24, -278)
	dialog.note = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	dialog.note:SetSize(214, 20)
	dialog.note:SetPoint("TOPLEFT", 140, -274)
	dialog.note:SetAutoFocus(false)
	dialog.note:SetMaxLetters(80)

	-- The guild leader only (Zach 11/11): someone else gets the finished
	-- crafts, so he is not the middleman. A first name is enough.
	dialog.deliverLabel = Label(dialog, "Skicka till", 24, -310)
	dialog.deliver = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	dialog.deliver:SetSize(150, 20)
	dialog.deliver:SetPoint("TOPLEFT", 140, -306)
	dialog.deliver:SetAutoFocus(false)
	dialog.deliver:SetMaxLetters(40)
	dialog.deliverHint = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	dialog.deliverHint:SetPoint("LEFT", dialog.deliver, "RIGHT", 8, 0)
	dialog.deliverHint:SetText("tomt: till dig")

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
		local raw = dialog.mats == "e" and dialog.raw and dialog.rawBox:GetChecked()
		local deliver
		if dialog.deliver:IsShown() then
			local problem
			deliver, problem = ns.FindMember(dialog.deliver:GetText())
			if problem then dialog.warn:SetText(problem) return end
			if deliver == dialog.to then dialog.warn:SetText("Skicka till kan inte vara hantverkaren själv.") return end
		end
		ns.PlaceOrder(dialog.to, dialog.key, count, dialog.mats, dialog.days, dialog.note:GetText(), raw and dialog.raw or nil, raw and dialog.steps or nil, deliver)
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
	dialog.rawBox:SetChecked(true)
	UpdateRaw()
	dialog.note:SetText("")
	dialog.deliver:SetText("")
	local leader = IsGuildLeader()
	dialog.deliverLabel:SetShown(leader)
	dialog.deliver:SetShown(leader)
	dialog.deliverHint:SetShown(leader)
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
	local need, sent = 0, 0
	for _, r in ipairs(Reagents(o)) do
		need = need + r.need
		sent = sent + math.min(o.sent and o.sent[r.itemID] or 0, r.need)
	end
	if need == 0 then return end
	if sent >= need then return "|cff40ff40material skickat|r", sent, need end
	if sent > 0 then return string.format("|cffff8040material %d/%d skickat|r", sent, need), sent, need end
	return "|cffff4040material inte skickat|r", sent, need
end

-- Fyll i brev (Zach 10/11): at an open mailbox, address the mail to the
-- crafter and attach the reagents still missing, splitting a stack to the
-- exact count. One item a step, a moment apart, since the bag slot is
-- locked while it moves. Twelve attachments a letter: when it is full he
-- sends it and presses again for the next. Never presses Send itself.
local Bag = C_Container or {}
local filling
-- The order the last letter was filled for: its materials count there
-- first, not on an older order to the same crafter (Zach 10/11: 4 Fine
-- Thread for the new order were counted on an old one).
local filledFor
-- The order whose finished crafts the crafter's last letter was filled
-- with, for Klar once they have all gone (Zach 11/11).
local craftsFor

-- Every bag worn, the reagent bag slot too (Zach 11/11: Tin Bar in an
-- Apprentice's Mining Bag was not found).
local LAST_BAG = math.max(NUM_TOTAL_EQUIPPED_BAG_SLOTS or 0, (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 1))

local function FindStack(item)
	local best
	for bag = 0, LAST_BAG do
		for slot = 1, (Bag.GetContainerNumSlots and Bag.GetContainerNumSlots(bag)) or 0 do
			local info = Bag.GetContainerItemInfo(bag, slot)
			if info and info.itemID == item and not info.isLocked then
				-- The smallest stack first, so big ones stay whole.
				if not best or info.stackCount < best.count then best = { bag = bag, slot = slot, count = info.stackCount } end
			end
		end
	end
	return best
end

local function FreeAttachment()
	for i = 1, ATTACHMENTS_MAX_SEND or 12 do
		if not GetSendMailItem(i) then return i end
	end
end

-- The finished crafts, for the crafter's letter to the recipient.
local function Crafts(o)
	local d = ns.RecipeData and ns.RecipeData(o.key)
	if not d or not d.item then return {} end
	return { { itemID = d.item, need = o.count * (d.makes or 1) } }
end

-- What still has to go in this letter: needed, minus sent, minus attached.
-- crafts: the crafter's letter of finished crafts, nothing counted as sent.
local function StillMissing(o, crafts)
	local attached = {}
	for i = 1, ATTACHMENTS_MAX_SEND or 12 do
		local _, item, _, count = GetSendMailItem(i)
		if item then attached[item] = (attached[item] or 0) + (count or 1) end
	end
	local out = {}
	for _, r in ipairs(crafts and Crafts(o) or Reagents(o)) do
		local left = r.need - (not crafts and o.sent and o.sent[r.itemID] or 0) - (attached[r.itemID] or 0)
		if left > 0 then table.insert(out, { item = r.itemID, count = left }) end
	end
	return out
end

local function FillStep()
	local f = filling
	if not f then return end
	if not (MailFrame and MailFrame:IsShown()) then filling = nil return end
	local missing = StillMissing(f.order, f.crafts)
	local nextItem
	for _, m in ipairs(missing) do
		if not f.lacking[m.item] then nextItem = m break end
	end
	if not nextItem then
		filling = nil
		local short = {}
		for item, n in pairs(f.lacking) do table.insert(short, string.format("%d x %s", n, ns.ItemName(item) or "?")) end
		if #short > 0 then
			ns.Print("finns inte i väskorna: " .. table.concat(short, ", ") .. ". Köp dem och tryck Fyll i brev igen.")
		end
		ns.Print("brevet till " .. f.to .. " är ifyllt. Kontrollera det och tryck Send." .. (f.crafts and " Ordern blir Klar när allt det färdiga har gått iväg." or ""))
		return
	end
	local free = FreeAttachment()
	if not free then
		filling = nil
		ns.Print("brevet är fullt (" .. (ATTACHMENTS_MAX_SEND or 12) .. " saker). Tryck Send och sedan Fyll i brev igen för nästa brev.")
		return
	end
	local stack = FindStack(nextItem.item)
	if not stack then
		f.lacking[nextItem.item] = nextItem.count
	elseif not CursorHasItem() then
		if stack.count > nextItem.count then
			Bag.SplitContainerItem(stack.bag, stack.slot, nextItem.count)
		else
			Bag.PickupContainerItem(stack.bag, stack.slot)
		end
		ClickSendMailItemButton(free)
		-- Not taken (a wrong item, a soulbound one): put it back, do not loop.
		if CursorHasItem() then
			ClearCursor()
			f.lacking[nextItem.item] = nextItem.count
		end
	end
	C_Timer.After(0.4, FillStep)
end

-- The letter's text box, as each client names it.
local function MailBody()
	local box = SendMailBodyEditBox or (MailEditBox and MailEditBox.ScrollBox and MailEditBox.ScrollBox.EditBox)
	return box and box.SetText and box
end

-- crafts: the crafter sends the finished crafts to the recipient the
-- guild leader named (Zach 11/11), instead of the orderer sending materials.
local function FillMail(o, crafts)
	if not (MailFrame and MailFrame:IsShown()) then
		ns.Print("gå till en brevlåda, öppna arbetsordern och tryck Fyll i brev.")
		return
	end
	if CursorHasItem() then ns.Print("släpp det du håller i först.") return end
	if not Bag.GetContainerItemInfo or not ClickSendMailItemButton then return end
	if #StillMissing(o, crafts) == 0 then
		ns.Print(crafts and "det färdiga är redan bifogat, eller så är receptet inte laddat än." or "allt material till den här ordern är redan skickat eller bifogat.")
		return
	end
	if MailFrameTab_OnClick then MailFrameTab_OnClick(nil, 2) end
	local to = crafts and o.deliver or o.to
	SendMailNameEditBox:SetText(to)
	if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(string.format("Arbetsorder: %s x%d", RecipeName(o.key), o.count)) end
	-- In the materials letter too (Zach 11/11), so the crafter sees it there.
	local body = MailBody()
	if body then
		if crafts then body:SetText(string.format("Från %s:s arbetsorder.", o.from))
		elseif o.deliver then body:SetText("yoyoyo! skicka allt till " .. o.deliver .. " sen :)") end
	end
	filling = { order = o, lacking = {}, crafts = crafts, to = to }
	if crafts then craftsFor = o else filledFor = o end
	FillStep()
end

-- Avbryt asks first (Zach 10/11), so a stray click cancels nothing.
StaticPopupDialogs["SKATTEVERKET_CANCEL_ORDER"] = {
	text = "Avbryta arbetsordern %s till %s?",
	button1 = YES or "Ja",
	button2 = NO or "Nej",
	OnAccept = function(_, data) data.done() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function ConfirmCancel(o, done)
	StaticPopup_Show("SKATTEVERKET_CANCEL_ORDER", string.format("%s x%d", RecipeName(o.key), o.count), o.to, { done = done })
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
	view.c = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
	view.c:SetSize(90, 22)
	view.c:SetPoint("RIGHT", view.a, "LEFT", -4, 0)
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
	if Unnoticed(o) then
		o.noticed = true
		Changed()
	end
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
	if o.deliver then table.insert(lines, "|cffffd100Skicka färdiga till:|r |cff40ff40" .. o.deliver .. "|r") end
	local status = SentStatus(o)
	if status then table.insert(lines, "|cffffd100Skickat:|r " .. status) end
	if o.tip then table.insert(lines, "|cffffd100Dricks:|r ungefär " .. ns.Money(o.tip)) end
	table.insert(lines, "|cffffd100Väntar till:|r " .. date("%d/%m %H:%M", o["until"]))
	-- One line a reagent (Zach 10/11: names showed as "..." while loading;
	-- the view is drawn again when they arrive), and what has been sent.
	view.waiting = false
	local list = Reagents(o)
	if #list > 0 then
		table.insert(lines, o.raw and "|cffffd100Råvaror|r (i stället för färdiga reagenser, så att hantverkaren får poäng):" or "|cffffd100Reagenser:|r")
		for _, r in ipairs(list) do
			local name = ns.ItemName(r.itemID)
			if not name then view.waiting = true end
			local need = r.need
			local sent = o.mats == "e" and (o.sent and o.sent[r.itemID] or 0)
			local mark = sent and (sent >= need and string.format("  |cff40ff40skickat %d/%d|r", sent, need)
				or string.format("  |cffff8040skickat %d/%d|r", sent, need)) or ""
			table.insert(lines, string.format("   %d x %s%s", need, name or "|cff808080laddar...|r", mark))
		end
	end
	-- What the crafter makes of the raw materials first (0.30).
	if o.steps then
		local made = {}
		for _, st in ipairs(o.steps) do
			local name = ns.ItemName(st.itemID)
			if not name then view.waiting = true end
			table.insert(made, string.format("%d x %s", st.crafts, name or "..."))
		end
		table.insert(lines, "|cffffd100Görs först:|r " .. table.concat(made, ", "))
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
		-- His materials, not all sent yet: fill the letter (Zach 10/11).
		local _, sent, need = SentStatus(o)
		ViewButton(view.a, (sent and sent < need) and "Fyll i brev" or nil, function() FillMail(o) end)
		ViewButton(view.b, "Avbryt", function() ConfirmCancel(o, After("avbruten")) end)
	else
		ViewButton(view.a, nil)
		ViewButton(view.b, nil)
	end
	-- The crafter's letter of finished crafts to the recipient (Zach 11/11).
	ViewButton(view.c, (incoming and state == "accepterad" and o.deliver) and "Fyll i brev" or nil, function() FillMail(o, true) end)
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

local function Delivered(target, items, prefer)
	local me, list = ns.Me(), {}
	for _, o in pairs(Orders()) do
		if o.from == me and o.mats == "e" and OPEN[State(o)] and Matches(target, o.to) then table.insert(list, o) end
	end
	table.sort(list, function(a, b)
		if (a == prefer) ~= (b == prefer) then return a == prefer end
		return a.at < b.at
	end)
	for _, o in ipairs(list) do
		local counted = {}
		for _, r in ipairs(Reagents(o)) do
			o.sent = o.sent or {}
			local need = r.need - (o.sent[r.itemID] or 0)
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
		local prefer = filledFor and Matches(target, filledFor.to) and filledFor or nil
		pendingMail = next(items) and { to = target, items = items, prefer = prefer } or nil
		-- The crafter's letter of finished crafts to the recipient.
		local o = craftsFor
		if pendingMail and o and o.deliver and Matches(target, o.deliver) then pendingMail.crafts = o end
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
		if pendingMail then Delivered(pendingMail.to, pendingMail.items, pendingMail.prefer) end
		-- Klar by itself once all the finished crafts have gone to the
		-- recipient (Zach 11/11), over one letter or several.
		local o = pendingMail and pendingMail.crafts
		local c = o and Crafts(o)[1]
		if c and State(o) == "accepterad" then
			o.craftsSent = (o.craftsSent or 0) + (pendingMail.items[c.itemID] or 0)
			if o.craftsSent >= c.need then
				SetState(o, "klar")
				craftsFor = nil
				ns.Print(string.format("allt det färdiga har gått till %s; arbetsordern %s x%d är Klar.", o.deliver, RecipeName(o.key), o.count))
				if ns.RefreshOrderView then ns.RefreshOrderView(o) end
			else
				ns.Print(string.format("%d av %d skickade till %s; fyll i nästa brev.", o.craftsSent, c.need, o.deliver))
			end
		end
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
-- Columns: x and width. Item (after the icon), the other party, the step word.
local COLS = { { 24, 112 }, { 140, 68 }, { 252, 72 } }
local STEPS_X = 212
-- The steps (Zach 10/11): grey ordered, yellow bought, blue sent, green done.
local GREY, YELLOW, BLUE, GREEN, RED = { 0.6, 0.6, 0.6 }, { 1, 0.82, 0 }, { 0.3, 0.6, 1 }, { 0.25, 1, 0.25 }, { 1, 0.25, 0.25 }
local EMPTY = { 0.22, 0.22, 0.22 }

local function Hex(c)
	return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

local function InBags(item)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(item, false) or 0 end
	return GetItemCount and GetItemCount(item, false) or 0
end

-- Where an order stands: steps filled (0 for a closed one), the word and
-- its colour. The orderer's materials take four steps: ordered, bought
-- (everything not yet sent is in his bags), sent, done; the crafter sees
-- received for sent. The crafter's own materials take three: ordered,
-- accepted, done.
local function Stage(o, incoming)
	local state = State(o)
	if not OPEN[state] and state ~= "klar" then return 0, 0, STATE[state], RED end
	if o.mats ~= "e" then
		if state == "klar" then return 3, 3, "Klar", GREEN end
		if state == "accepterad" then return 2, 3, "Accepterad", BLUE end
		return 1, 3, "Beställd", GREY
	end
	if state == "klar" then return 4, 4, "Klar", GREEN end
	local need, sent, ready = 0, 0, true
	for _, r in ipairs(Reagents(o)) do
		local n, got = r.need, math.min(o.sent and o.sent[r.itemID] or 0, r.need)
		need, sent = need + n, sent + got
		if not incoming and InBags(r.itemID) < n - got then ready = false end
	end
	if need > 0 and sent >= need then return 3, 4, incoming and "Mottaget" or "Skickat", BLUE end
	if sent > 0 then return 2, 4, string.format("%s %d/%d", incoming and "Mottaget" or "Skickat", sent, need), YELLOW end
	if not incoming and need > 0 and ready then return 2, 4, "Köpt", YELLOW end
	return 1, 4, "Beställd", GREY
end

-- For Bokföring's Making now: whether an order is still open (ny or
-- accepterad), nil for an order not known here (Zach 11/11).
function ns.OrderOpen(id)
	local o = Orders()[id]
	if not o then return nil end
	return OPEN[State(o)] == true
end

-- For Bokföring's Making now (Zach 11/11): true once the order no longer
-- waits for his materials (all sent, or closed), false while it does, nil
-- for an order not known here.
function ns.OrderMaterialsDone(id)
	local o = Orders()[id]
	if not o then return nil end
	if not OPEN[State(o)] then return true end
	local _, sent, need = SentStatus(o)
	if not need then return nil end
	return sent >= need
end

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
	page.empty:SetText("Inga pågående arbetsordrar. Beställ från någon under Yrken: öppna deras recept, välj ett och tryck Beställ.")
	page.closed = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	page.closed:SetSize(22, 22)
	page.closed:SetPoint("TOPLEFT", 260, -66)
	page.closed.text = page.closed.text or page.closed.Text or page.closed:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	page.closed.text:ClearAllPoints()
	page.closed.text:SetPoint("LEFT", page.closed, "RIGHT", 2, 0)
	page.closed.text:SetFontObject("GameFontHighlightSmall")
	page.closed:SetScript("OnClick", function(self)
		showClosed = self:GetChecked() and true or false
		offset = 0
		ns.RefreshOrders()
	end)
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, parent)
		row:SetSize(400, ROW_H)
		row:SetPoint("TOPLEFT", 20, -90 - (i - 1) * ROW_H)
		-- Headers and Bokföring's own work: one line across.
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", 4, 0)
		row.text:SetWidth(320)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		-- An order in columns (Zach 10/11): item, the other party, the steps
		-- as coloured squares, the step in a word, one button.
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(16, 16)
		row.icon:SetPoint("LEFT", 4, 0)
		row.cells = {}
		for c, col in ipairs(COLS) do
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("LEFT", col[1], 0)
			fs:SetWidth(col[2])
			fs:SetJustifyH("LEFT")
			fs:SetWordWrap(false)
			row.cells[c] = fs
		end
		row.steps = {}
		for k = 1, 4 do
			local t = row:CreateTexture(nil, "ARTWORK")
			t:SetSize(7, 7)
			t:SetPoint("LEFT", STEPS_X + (k - 1) * 9, 0)
			row.steps[k] = t
		end
		row.b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.b:SetSize(66, 20)
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
	-- Köpt follows the bags while the page is open.
	local bags = CreateFrame("Frame", nil, parent)
	bags:RegisterEvent("BAG_UPDATE_DELAYED")
	bags:SetScript("OnEvent", function() if parent:IsVisible() then ns.RefreshOrders() end end)
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

-- Closed (Zach 11/11): declined, cancelled, run out, or Klar for a day;
-- shown only with Visa avslutade. A notice not yet opened stays.
local showClosed = false
local function Closed(o)
	local state = State(o)
	if OPEN[state] or Unnoticed(o) then return false end
	if state == "klar" then return ns.Now() - o.stamp > DAY end
	return true
end

-- Three sections: to you, from you, then to yourself, Bokföring's shopping
-- lists still on the go (Zach 9/11); open ones first, newest first.
function ns.RefreshOrders()
	if not page then return end
	local me = ns.Me()
	local lines, closed = {}, 0
	for _, section in ipairs({ { "to", "Till dig", "Beställare" }, { "from", "Från dig", "Hantverkare" } }) do
		local list = {}
		for _, o in pairs(Orders()) do
			if o[section[1]] == me then
				if not Closed(o) or showClosed then table.insert(list, o) end
				if Closed(o) then closed = closed + 1 end
			end
		end
		table.sort(list, function(a, b)
			local oa, ob = OPEN[State(a)] and 1 or 0, OPEN[State(b)] and 1 or 0
			if oa ~= ob then return oa > ob end
			return a.at > b.at
		end)
		if #list > 0 then
			table.insert(lines, { header = section[2], who = section[3] })
			for _, o in ipairs(list) do table.insert(lines, { order = o, incoming = section[1] == "to" }) end
		end
	end
	local own = BokforingAPI and BokforingAPI.Work and BokforingAPI.Work() or {}
	if #own > 0 then
		table.insert(lines, { header = "Till dig själv" })
		for _, w in ipairs(own) do table.insert(lines, { work = w }) end
	end
	page.empty:SetShown(#lines == 0)
	page.closed.text:SetText(string.format("Visa avslutade (%d)", closed))
	page.closed:SetChecked(showClosed)
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
			row.icon:Hide()
			for _, t in ipairs(row.steps) do t:Hide() end
			for _, fs in ipairs(row.cells) do fs:SetText("") end
			Button(row.b, "Bokföring", function() BokforingAPI.ShowWork() end)
			row:Show()
		elseif line.header then
			-- The section, with the column names in grey.
			row.text:SetText("|cffffd100" .. line.header .. "|r")
			row.icon:Hide()
			for _, t in ipairs(row.steps) do t:Hide() end
			row.cells[1]:SetText("")
			row.cells[2]:SetText("|cff808080" .. (line.who or "") .. "|r")
			row.cells[3]:SetText(line.who and "|cff808080Steg|r" or "")
			row.b:Hide()
			row:Show()
		else
			local o, state = line.order, State(line.order)
			local d = ns.RecipeData and ns.RecipeData(o.key)
			row.text:SetText("")
			row.icon:SetTexture((d and d.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.icon:SetDesaturated(not OPEN[state] and state ~= "klar")
			row.icon:Show()
			row.cells[1]:SetText(string.format("%s%s x%d|r", (OPEN[state] or state == "klar") and "|cffffffff" or "|cff808080", RecipeName(o.key), o.count))
			-- The other party; the crafter in green once they have accepted.
			-- First names fit (Zach 10/11); the full name is in the tooltip.
			local who = (line.incoming and o.from or o.to):match("^(%S+)")
			local accepted = not line.incoming and (state == "accepterad" or state == "klar")
			row.cells[2]:SetText((accepted and Hex(GREEN) or "|cffffffff") .. who .. "|r")
			local filled, total, word, colour = Stage(o, line.incoming)
			for k, t in ipairs(row.steps) do
				local c = k <= filled and colour or EMPTY
				t:SetColorTexture(c[1], c[2], c[3])
				t:SetShown(k <= total)
			end
			row.cells[3]:SetText(Hex(colour) .. word .. "|r")
			-- One button a row; declining an accepted order is in the order.
			if line.incoming and state == "ny" then
				Button(row.b, "Öppna", function() ShowOrder(o) end)
			elseif line.incoming and state == "accepterad" then
				Button(row.b, "Klar", function() Act(o, "klar") end)
			elseif not line.incoming and OPEN[state] then
				Button(row.b, "Avbryt", function() ConfirmCancel(o, function() Act(o, "avbruten") end) end)
			else
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
