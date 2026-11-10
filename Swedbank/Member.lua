-- Swedbank, the member's side, on the Swedbank tab of the THÖNDERSTÖRM
-- panel with two bookmark tabs on its right edge (Zach 8/11): Ansök, the
-- application form, open only in good standing with Skatteverket; and Mina
-- lån, where a running loan can be paid back straight into the guild bank.
-- Applications and payments wait in this character's saved data until the
-- guild leader has confirmed them, so nothing is lost if the leader is
-- offline.

local _, ns = ...

local ROWS, W = 14, 520
local COLS = { { "Ansökt", 55 }, { "Belopp", 85 }, { "Status", 150 }, { "Ränta", 45 }, { "Kvar", 85 }, { "Senast", 60 } }
local frame, list, selected
local offset, tab = 0, 2
local lastSync, synced = 0, false
local bankOpen, pendingPay = false, nil

local STATUS = {
	sending = "Väntar på att ledaren loggar in",
	pending = "Väntar på godkännande",
	offered = "|cffffd100Erbjudande: svara|r",
	accepted = "Accepterat, väntar på ledaren",
	refused = "|cffff8040Avböjt av dig|r",
	expired = "|cff808080Erbjudandet gick ut|r",
	declined = "|cffff4040Nekat|r",
	repaid = "|cff40ff40Återbetalt|r",
}

-- Paid into the guild bank but not yet confirmed by the leader.
local function Unconfirmed(loan)
	local total = 0
	for _, p in pairs(loan.outbox or {}) do total = total + p.amount end
	return total
end

-- What a loan costs now, from the leader's last figures.
local function DueNow(loan)
	if loan.status ~= "approved" or not loan.sentAt then return loan.amount end
	-- Each week begun since the leader's figures adds the rate (Zach 10/11).
	local weeks = ns.WeeksAt(loan.sentAt, time()) - ns.WeeksAt(loan.sentAt, loan.asOf)
	local extra = loan.left * loan.rate * math.max(0, weeks)
	return math.max(0, loan.left + loan.interest + math.floor(extra) - Unconfirmed(loan) - (loan.unverified or 0))
end

local function Active(loan)
	return loan and loan.status == "approved" and loan.sentAt
end

local function StatusText(loan)
	if loan.status == "approved" then
		if not loan.sentAt then return "Godkänt, guldet är på väg" end
		if next(loan.outbox or {}) then return "|cffffd100Betalning väntar på ledaren|r" end
		if (loan.unverified or 0) > 0 then return "|cffffd100Betalning kontrolleras|r" end
		if (loan.repayBy or 0) > 0 and time() > loan.repayBy then return "|cffff4040Försenat|r" end
		return "|cffffd100Aktivt|r"
	end
	return STATUS[loan.status] or loan.status
end

-- Send what the leader has not confirmed yet, and ask for the latest figures.
local function Sync(force)
	local leader, online = ns.Leader()
	if not leader or not online then return end
	if not force and GetTime() - lastSync < 30 then return end
	lastSync = GetTime()
	for id, loan in pairs(ns.char.loans) do
		if loan.status == "sending" then
			ns.Whisper(leader, string.format("AP2;%s;%d;%d;%d;%d;%s", id, loan.amount, loan.repayBy or 0, loan.appliedAt,
				math.floor((loan.wishRate or ns.MIN_RATE) * 10000 + 0.5), loan.reason))
		end
		-- An answer to an offer, until the leader has it.
		if loan.answer then ns.Whisper(leader, string.format("ANS;%s;%s", id, loan.answer)) end
		for pid, p in pairs(loan.outbox or {}) do
			ns.Whisper(leader, string.format("PAY;%s;%s;%d;%d", id, pid, p.amount, p.t))
		end
	end
	ns.Whisper(leader, "SYNC")
end

local function Waiting()
	for _, loan in pairs(ns.char.loans) do
		if loan.status == "sending" or next(loan.outbox or {}) then return true end
	end
	return false
end

function ns.OnLogin()
	if IsGuildLeader() then return end
	Sync(true)
end

-- The gold left the bags: record the payment and tell the leader. A
-- payment counts once the gold has dropped by at least its amount below
-- what was carried at the click, however late the server confirms; it is
-- given up only if the bank closes without that drop (review 6/11).
local function ConfirmPay()
	local loan = ns.char.loans[pendingPay.loanId]
	local pay = pendingPay
	pendingPay = nil
	if not loan then return end
	loan.outbox = loan.outbox or {}
	local pid = string.format("%d%03d", time(), math.random(999))
	loan.outbox[pid] = { amount = pay.amount, t = time() }
	ns.Print(string.format("betalade %s till guildbanken för ditt lån; %s kvar.", ns.Money(pay.amount), ns.Money(DueNow(loan))))
	local _, online = ns.Leader()
	if not online then ns.Print("guildledaren får betalningen när hen loggar in.") end
	Sync(true)
	ns.RefreshMember()
end

local function OnMoney()
	if pendingPay and GetMoney() <= pendingPay.before - pendingPay.amount then ConfirmPay() end
end

local function SetBank(shown)
	bankOpen = shown
	if not shown and pendingPay then
		if GetMoney() <= pendingPay.before - pendingPay.amount then
			ConfirmPay()
		else
			ns.Print("insättningen på " .. ns.Money(pendingPay.amount) .. " gick inte igenom. Försök igen vid guildbanken.")
			pendingPay = nil
		end
	end
	ns.RefreshMember()
end

function ns.OnMemberEvent(event, ...)
	if IsGuildLeader() then return end
	if event == "GUILD_ROSTER_UPDATE" then
		if not synced or Waiting() then Sync() end
	elseif event == "PLAYER_MONEY" then
		OnMoney()
	elseif event == "GUILDBANKFRAME_OPENED" then
		SetBank(true)
	elseif event == "GUILDBANKFRAME_CLOSED" then
		SetBank(false)
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
		local T = Enum and Enum.PlayerInteractionType
		if T and ... == T.GuildBanker then SetBank(event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW") end
	end
end

function ns.OnMemberMessage(msg)
	if IsGuildLeader() then return end
	if msg == "END" then
		synced = true
	elseif msg:match("^ACK;") then
		local loan = ns.char.loans[msg:sub(5)]
		if loan and loan.status == "sending" then
			loan.status = "pending"
			ns.Print("din ansökan om " .. ns.Money(loan.amount) .. " har nått guildledaren.")
		end
	elseif msg:match("^PACK;") then
		local pid = msg:sub(6)
		for _, loan in pairs(ns.char.loans) do
			if loan.outbox then loan.outbox[pid] = nil end
		end
	elseif msg:match("^UPD;") then
		local id, status, amount, rate, sentAt, repayBy, left, interest, asOf, paid, closedAt, unverified = strsplit(";", msg:sub(5))
		if not id or not status then return end
		-- Removed by the leader (Zach 10/11): gone here too.
		if status == "removed" then
			if ns.char.loans[id] then
				ns.char.loans[id] = nil
				ns.Print("guildledaren har tagit bort ett lån eller en ansökan från din lista.")
			end
			ns.RefreshMember()
			return
		end
		local loan = ns.char.loans[id] or { id = id, reason = "", appliedAt = 0 }
		ns.char.loans[id] = loan
		local before, wasSent = loan.status, loan.sentAt
		-- Our answer is on its way: keep it until the leader has it.
		if loan.answer and status == "offered" then status = loan.answer == "1" and "accepted" or "refused" else loan.answer = nil end
		loan.status, loan.amount, loan.rate = status, tonumber(amount) or 0, tonumber(rate) or 0
		sentAt, repayBy, closedAt = tonumber(sentAt) or 0, tonumber(repayBy) or 0, tonumber(closedAt) or 0
		loan.sentAt = sentAt > 0 and sentAt or nil
		loan.repayBy = repayBy
		loan.closedAt = closedAt > 0 and closedAt or nil
		loan.left, loan.interest, loan.asOf = tonumber(left) or 0, tonumber(interest) or 0, tonumber(asOf) or time()
		loan.paid = tonumber(paid) or 0
		-- Reported by us, not yet confirmed by the bank log or the leader.
		loan.unverified = tonumber(unverified) or 0
		local money = ns.Money(loan.amount)
		if status ~= before then
			if status == "approved" then
				ns.Print(string.format("ditt lån på %s är godkänt med %g %% ränta per påbörjad vecka, betala senast %s. Guldet kommer med posten.", money, loan.rate * 100, ns.Day(loan.repayBy)))
			elseif status == "offered" then
				ns.Print(string.format("guildledaren erbjuder %g %% ränta per påbörjad vecka på lånet om %s, betala senast %s. Svara under Swedbank, Mina lån.",
					loan.rate * 100, money, ns.Day(loan.repayBy)))
			elseif status == "expired" then
				ns.Print("erbjudandet om lånet på " .. money .. " gick ut efter 3 dagar utan svar; ansök igen om du vill.")
			elseif status == "declined" then
				ns.Print("din ansökan om " .. money .. " har nekats.")
			elseif status == "repaid" then
				ns.Print("ditt lån på " .. money .. " är återbetalt. Tack!")
			end
		end
		if loan.sentAt and not wasSent and status == "approved" then
			ns.Print("guldet för ditt lån på " .. money .. " har skickats. Räntan börjar räknas i morgon; se lånet under Mina lån.")
		end
	end
	ns.RefreshMember()
end

-- Applying takes good standing with Skatteverket (Zach 8/11); paying back never does.
-- Only an approved member applies (Zach 8/11); someone not approved sees
-- this page only because a loan is running.
local function MayApply()
	if not SkatteverketAPI or SkatteverketAPI.Locked() then return false, "locked" end
	local standing = SkatteverketAPI.Standing()
	return standing == "good", standing
end

local function Submit()
	local may, why = MayApply()
	if not may then
		ns.Print(why == "locked" and "du behöver vara godkänd medborgare för att ansöka om lån." or "du behöver God ställning hos Skatteverket för att ansöka om lån.")
		return
	end
	local amount = ns.ParseMoney(frame.amount:GetText())
	if not amount or amount < 1 then ns.Print("skriv ett belopp, till exempel 50g.") return end
	local repayBy, repayText = 0, frame.repayBy:GetText()
	if repayText ~= "" then
		repayBy = ns.ParseDate(repayText)
		if not repayBy then ns.Print("skriv datumet som dd/mm, till exempel 24/12.") return end
	end
	local percent = tonumber(((frame.rate:GetText() or ""):gsub(",", ".")))
	if not percent or percent < ns.MIN_RATE * 100 then ns.Print(string.format("önskad ränta: minst %g %%.", ns.MIN_RATE * 100)) return end
	local reason = ns.Trim(frame.reason:GetText(), ns.REASON_BYTES)
	if reason == "" then ns.Print("skriv vad lånet ska användas till.") return end
	local id = string.format("%s-%d-%03d", UnitName("player"), time(), math.random(999))
	ns.char.loans[id] = { id = id, amount = amount, reason = reason, repayBy = repayBy, appliedAt = time(), status = "sending", wishRate = percent / 100 }
	frame.rate:SetText("5")
	frame.amount:SetText("")
	frame.repayBy:SetText("")
	frame.reason:SetText("")
	local _, online = ns.Leader()
	if online then
		ns.Print("ansökan om " .. ns.Money(amount) .. " skickad till guildledaren.")
	else
		ns.Print("ansökan om " .. ns.Money(amount) .. " sparad; den skickas när guildledaren loggar in.")
	end
	Sync(true)
	ns.RefreshMember()
end

-- Pay into the guild bank; the click is what the game requires for a deposit.
local function PayBack()
	local loan = selected and ns.char.loans[selected]
	if not Active(loan) then ns.Print("klicka på ett aktivt lån först.") return end
	if not bankOpen then ns.Print("öppna guildbanken först.") return end
	-- One deposit at a time, so a double click cannot pay twice and record once (review 6/11).
	if pendingPay then ns.Print("en betalning pågår redan.") return end
	local amount = ns.ParseMoney(frame.payAmount:GetText())
	if not amount or amount < 1 then ns.Print("skriv ett belopp, till exempel 10g.") return end
	if amount > GetMoney() then ns.Print("du har inte så mycket guld på dig.") return end
	pendingPay = { loanId = loan.id, amount = amount, before = GetMoney() }
	DepositGuildBankMoney(amount)
	frame.payAmount:ClearFocus()
end

local function Layout()
	frame.apply:SetShown(tab == 1)
	frame.loans:SetShown(tab == 2)
	frame.sideTabs.Select(tab)
end

-- One loan opened from Mina lån (Zach 10/11: click up the current loan
-- and see what is going on): what was lent, the rule, interest so far,
-- what is due now, when the next week's interest is added, and the last day.
local view
local function BuildView()
	local ok
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("ButtonFrameTemplate") then
		ok, view = pcall(CreateFrame, "Frame", "SwedbankLoanView", UIParent, "ButtonFrameTemplate")
	end
	if not ok or not view then
		view = CreateFrame("Frame", "SwedbankLoanView", UIParent, BackdropTemplateMixin and "BackdropTemplate")
		view:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
	end
	view:SetSize(380, 340)
	view:SetPoint("CENTER", 0, 40)
	view:SetFrameStrata("DIALOG")
	view:SetToplevel(true)
	view:EnableMouse(true)
	view:SetMovable(true)
	view:RegisterForDrag("LeftButton")
	view:SetScript("OnDragStart", view.StartMoving)
	view:SetScript("OnDragStop", view.StopMovingOrSizing)
	tinsert(UISpecialFrames, "SwedbankLoanView")
	local title = view.TitleText or (view.TitleContainer and view.TitleContainer.TitleText)
	if title then title:SetText("Mitt lån") end
	local portrait = view.portrait or view.Portrait or (view.PortraitContainer and view.PortraitContainer.portrait)
	if view.SetPortraitToAsset then view:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Coin_02") elseif portrait then portrait:SetTexture("Interface\\Icons\\INV_Misc_Coin_02") end
	view.body = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	view.body:SetPoint("TOPLEFT", 24, -70)
	view.body:SetWidth(332)
	view.body:SetJustifyH("LEFT")
	view.body:SetJustifyV("TOP")
	view.body:SetSpacing(3)
	local close = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
	close:SetSize(90, 22)
	close:SetPoint("BOTTOMRIGHT", -8, 4)
	close:SetText("Stäng")
	close:SetScript("OnClick", function() view:Hide() end)
	-- An offer: accept (back to the leader to confirm) or refuse (ends it).
	local function Answer(yes)
		local loan = view.loan
		if not loan or loan.status ~= "offered" then return end
		loan.answer = yes and "1" or "0"
		loan.status = yes and "accepted" or "refused"
		local leader, online = ns.Leader()
		if leader and online then ns.Whisper(leader, string.format("ANS;%s;%s", loan.id, loan.answer)) end
		ns.Print(yes and "du har accepterat erbjudandet; guildledaren bekräftar lånet." or "du har avböjt erbjudandet; ansökan är avslutad.")
		ns.RefreshMember()
		view.show(loan)
	end
	view.refuse = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
	view.refuse:SetSize(90, 22)
	view.refuse:SetPoint("RIGHT", close, "LEFT", -4, 0)
	view.refuse:SetText("Avböj")
	view.refuse:SetScript("OnClick", function() Answer(false) end)
	view.accept = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
	view.accept:SetSize(90, 22)
	view.accept:SetPoint("RIGHT", view.refuse, "LEFT", -4, 0)
	view.accept:SetText("Acceptera")
	view.accept:SetScript("OnClick", function() Answer(true) end)
	view:Hide()
end

local ShowLoan
ShowLoan = function(loan)
	if not loan then return end
	if not view then
		BuildView()
		view.show = function(l) ShowLoan(l) end
	end
	view.loan = loan
	local gold, label = "|cffffd100", "|r "
	local lines = {
		gold .. "Lånat:" .. label .. ns.Money(loan.amount),
		gold .. "Status:" .. label .. StatusText(loan),
	}
	if loan.wishRate then table.insert(lines, gold .. "Din önskade ränta:" .. label .. string.format("%g %%", loan.wishRate * 100)) end
	if loan.rate and loan.rate > 0 then
		table.insert(lines, gold .. (loan.status == "offered" and "Erbjuden ränta:" or "Ränta:") .. label
			.. string.format("%g %% per påbörjad vecka på det som är kvar", loan.rate * 100))
	end
	if loan.status == "offered" then
		table.insert(lines, "|cffffd100Guildledaren erbjuder den här räntan och sista dagen. Acceptera så bekräftar ledaren lånet; avböj så avslutas ansökan. Svara inom 3 dagar, annars går erbjudandet ut.|r")
	end
	if loan.sentAt then
		local now = time()
		local weeks = ns.WeeksAt(loan.sentAt, now)
		table.insert(lines, gold .. "Skickat:" .. label .. ns.Day(loan.sentAt) .. ", räntan räknas från " .. ns.Day(ns.InterestStart(loan.sentAt)))
		table.insert(lines, gold .. "Påbörjade veckor:" .. label .. weeks)
		table.insert(lines, gold .. "Betalt hittills:" .. label .. ns.Money(loan.paid or 0))
		table.insert(lines, gold .. "Att betala nu:" .. label .. ns.Money(DueNow(loan)))
		if loan.status == "approved" and loan.rate and loan.rate > 0 then
			local nextAt = ns.NextInterest(loan.sentAt, now)
			table.insert(lines, gold .. "Nästa ränta:" .. label .. string.format("%s, +%s om det inte är betalt", ns.Day(nextAt),
				ns.Money(math.floor((loan.left or loan.amount) * loan.rate))))
		end
	else
		table.insert(lines, gold .. "Skickat:" .. label .. "inte än; räntan börjar dagen efter att guldet skickats")
	end
	if (loan.repayBy or 0) > 0 then
		local days = math.ceil((loan.repayBy - time()) / 86400)
		table.insert(lines, gold .. "Betala senast:" .. label .. ns.Day(loan.repayBy)
			.. (days < 0 and " |cffff4040(försenat)|r" or days == 0 and " (i dag)" or string.format(" (om %d dag%s)", days, days == 1 and "" or "ar")))
	end
	if loan.reason and loan.reason ~= "" then table.insert(lines, gold .. "Anledning:" .. label .. loan.reason) end
	table.insert(lines, " ")
	table.insert(lines, "|cffa0a0a0Betalar du samma dag som guldet skickas kostar det ingen ränta. Varje ny påbörjad vecka läggs räntan på det som är kvar. Betalningar går först till räntan, sedan till lånet. Betala tillbaka under Mina lån vid guildbanken.|r")
	view.body:SetText(table.concat(lines, "\n"))
	view.accept:SetShown(loan.status == "offered")
	view.refuse:SetShown(loan.status == "offered")
	view:Show()
end

function ns.BuildMember(page, panel)
	frame = CreateFrame("Frame", nil, page)
	frame:SetAllPoints()

	-- Page 1: Ansök.
	local apply = CreateFrame("Frame", nil, frame)
	apply:SetAllPoints()
	frame.apply = apply
	ns.Text(apply, "GameFontNormal", "TOPLEFT", 24, -70):SetText("Låneansökan")
	frame.applicant = ns.Text(apply, "GameFontHighlight", "TOPLEFT", 24, -92)
	ns.Text(apply, "GameFontNormalSmall", "TOPLEFT", 24, -122):SetText("Belopp (t.ex. 50g)")
	frame.amount = ns.Input(apply, 90)
	frame.amount:SetPoint("TOPLEFT", 150, -118)
	ns.Text(apply, "GameFontNormalSmall", "TOPLEFT", 24, -150):SetText("Betala senast")
	frame.repayBy = ns.Input(apply, 60)
	frame.repayBy:SetPoint("TOPLEFT", 150, -146)
	ns.Text(apply, "GameFontDisableSmall", "LEFT", frame.repayBy, "RIGHT", 10, 0):SetText("dd/mm, valfritt; ett önskemål, guildledaren bestämmer")
	-- The rate the member hopes for, 3 % at least (Zach 10/11).
	ns.Text(apply, "GameFontNormalSmall", "TOPLEFT", 24, -178):SetText("Önskad ränta")
	frame.rate = ns.Input(apply, 40)
	frame.rate:SetPoint("TOPLEFT", 150, -174)
	-- 5 % filled in, 3 % the floor (Zach 10/11).
	frame.rate:SetText("5")
	ns.Text(apply, "GameFontHighlightSmall", "LEFT", frame.rate, "RIGHT", 6, 0):SetText("% per påbörjad vecka")
	ns.Text(apply, "GameFontDisableSmall", "LEFT", frame.rate, "RIGHT", 140, 0):SetText("3 % är absolut minimum")
	ns.Text(apply, "GameFontNormalSmall", "TOPLEFT", 24, -206):SetText("Anledning")
	frame.reason = ns.Input(apply, W - 180, Submit)
	frame.reason:SetPoint("TOPLEFT", 150, -202)
	frame.reason:SetMaxBytes(ns.REASON_BYTES + 1)
	frame.submit = ns.Button(apply, "Skicka", 100, Submit)
	frame.submit:SetPoint("TOPLEFT", 146, -230)
	frame.submitHint = ns.Text(apply, "GameFontDisableSmall", "LEFT", frame.submit, "RIGHT", 12, 0)
	frame.submitHint:SetWidth(W - 290)
	local terms = ns.Text(apply, "GameFontHighlightSmall", "TOPLEFT", 24, -274)
	terms:SetWidth(W - 48)
	terms:SetText("Bara guildledaren ser din ansökan och dina lån. Du behöver God ställning hos Skatteverket för att ansöka. Räntan räknas per påbörjad vecka på det som är kvar av lånet, från dagen efter att guldet skickats: betalar du samma dag kostar det inget, dag 1-7 en veckas ränta, dag 8-14 två. Du önskar en ränta, minst 3 %; guildledaren godkänner den eller erbjuder en annan, som du accepterar eller avböjer. Guildledaren bestämmer sista betaldag. Betalningar går först till räntan, sedan till lånet. Betala tillbaka under Mina lån när du står vid guildbanken.")

	-- Page 2: Mina lån.
	local loans = CreateFrame("Frame", nil, frame)
	loans:SetAllPoints()
	frame.loans = loans
	ns.Text(loans, "GameFontNormal", "TOPLEFT", 24, -70):SetText("Mina lån")
	list = ns.List(loans, -90, ROWS, #COLS, W)
	list:SetColumns(COLS)
	for _, row in ipairs(list.rows) do
		row:SetScript("OnClick", function()
			selected = row.id
			local loan = ns.char.loans[row.id]
			if Active(loan) then frame.payAmount:SetText(string.format("%dg%ds%dc", math.floor(DueNow(loan) / 10000), math.floor(DueNow(loan) / 100) % 100, DueNow(loan) % 100)) end
			-- And open it, with everything about it (Zach 10/11).
			ShowLoan(loan)
			ns.RefreshMember()
		end)
	end
	frame.empty = ns.Text(loans, "GameFontDisableSmall", "TOPLEFT", 24, -108)

	-- Pay back: amount (filled with all that is due when a loan is clicked) and the button.
	frame.payHint = ns.Text(loans, "GameFontDisableSmall", "BOTTOMLEFT", 24, 62)
	ns.Text(loans, "GameFontNormalSmall", "BOTTOMLEFT", 24, 40):SetText("Betala tillbaka")
	frame.payAmount = ns.Input(loans, 100, PayBack)
	frame.payAmount:SetPoint("BOTTOMLEFT", 130, 34)
	frame.pay = ns.Button(loans, "Betala till guildbanken", 170, PayBack)
	frame.pay:SetPoint("LEFT", frame.payAmount, "RIGHT", 10, 0)
	loans:EnableMouseWheel(true)
	loans:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta
		ns.RefreshMember()
	end)

	frame.sideTabs = ns.SideTabs(frame, panel, { { "INV_Scroll_03", "Ansök om lån" }, { "INV_Misc_Coin_02", "Mina lån" } }, function(i)
		tab = i
		Layout()
		ns.RefreshMember()
	end)
	frame:SetScript("OnShow", function()
		-- Mina lån when there are loans, the form when there are none.
		tab = next(ns.char.loans) and 2 or 1
		Layout()
		Sync()
	end)
	frame:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed > 1 then
			self.elapsed = 0
			ns.RefreshMember()
		end
	end)
	frame:Hide()
end

-- A loan approved and not yet repaid.
function ns.HasLoan()
	for _, loan in pairs(ns.char.loans) do
		if loan.status == "approved" then return true end
	end
	return false
end

function ns.ShowMember(shown)
	if frame then frame:SetShown(shown) end
end

function ns.RefreshMember()
	if not frame or not frame:IsShown() then return end
	frame.applicant:SetText("Sökande: " .. (ns.Me() or UnitName("player")))
	local may, standing = MayApply()
	if may then
		frame.submit:Enable()
		frame.submitHint:SetText("")
	else
		frame.submit:Disable()
		if standing == "locked" then
			frame.submitHint:SetText("|cffff4040Kräver att du är godkänd medborgare.|r")
		else
			frame.submitHint:SetText("|cffff4040Kräver God ställning hos Skatteverket" .. (standing and (" (du har " .. (standing == "neutral" and "Neutral" or "Negativ") .. ")") or "") .. ".|r")
		end
	end
	local sorted = {}
	for _, loan in pairs(ns.char.loans) do table.insert(sorted, loan) end
	-- Open loans first (running, then waiting), newest first within each; the
	-- list scrolls with the mouse wheel, so no loan drops out of reach (review 6/11).
	-- An offer to answer on top (Zach 10/11).
	local order = { offered = 0, approved = 1, accepted = 2, pending = 2, sending = 2 }
	table.sort(sorted, function(a, b)
		local oa, ob = order[a.status] or 3, order[b.status] or 3
		if oa ~= ob then return oa < ob end
		return (a.appliedAt or 0) > (b.appliedAt or 0)
	end)
	offset = math.max(0, math.min(offset, #sorted - ROWS))
	for i, row in ipairs(list.rows) do
		local loan = sorted[i + offset]
		row.id = loan and loan.id
		if loan then
			local values = {
				ns.Day(loan.appliedAt), ns.Money(loan.amount), StatusText(loan),
				loan.rate and loan.rate > 0 and string.format("%g%%", loan.rate * 100) or "-",
				loan.status == "approved" and ns.Money(DueNow(loan)) or "-", ns.Day(loan.repayBy),
			}
			for c, value in ipairs(values) do row.cells[c]:SetText(value) end
			if loan.id == selected then row:LockHighlight() else row:UnlockHighlight() end
			row:Show()
		else
			row:Hide()
		end
	end
	frame.empty:SetText(#sorted == 0 and "Inga lån än." or "")

	local loan = selected and ns.char.loans[selected]
	if Active(loan) and bankOpen and not pendingPay then
		frame.pay:Enable()
		frame.payHint:SetText("")
	else
		frame.pay:Disable()
		frame.payHint:SetText(not Active(loan) and "Klicka på ett aktivt lån." or pendingPay and "Betalningen pågår." or "Öppna guildbanken.")
	end
end
