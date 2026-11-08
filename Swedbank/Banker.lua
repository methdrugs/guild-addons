-- Swedbank, the guild leader's side, on the Swedbank tab of the
-- THÖNDERSTÖRM panel with three bookmark tabs on its right edge (Zach
-- 8/11). Applications to approve
-- (with a weekly rate) or decline; Loans running, with Fill mail, Mark
-- sent, Add payment and Mark repaid; History of repaid and declined loans
-- with every date. This copy in SwedbankDB is the record.

local _, ns = ...

local ROWS, W = 12, 900
local TABS = { "Applications", "Loans", "History" }
local SIDE_TABS = { { "INV_Scroll_03", "Ansökningar" }, { "INV_Misc_Coin_02", "Lån" }, { "INV_Misc_Book_09", "Historik" } }
local COLS = {
	Applications = { { "Ansökt", 70 }, { "Låntagare", 120 }, { "Belopp", 100 }, { "Betala senast", 85 }, { "Anledning", 460 } },
	Loans = { { "Låntagare", 120 }, { "Belopp", 95 }, { "Ränta/v", 55 }, { "Skickat", 75 }, { "Dagar", 45 }, { "Räntor", 95 }, { "Återbetalt", 95 }, { "Att betala", 100 }, { "Betala senast", 85 } },
	History = { { "Låntagare", 120 }, { "Belopp", 95 }, { "Status", 90 }, { "Ansökt", 65 }, { "Avslutat", 65 }, { "Återbetalt", 95 }, { "Anledning", 305 } },
}
local IN_TAB = {
	Applications = { pending = true },
	Loans = { approved = true },
	History = { declined = true, repaid = true },
}

local frame, list
local tab, selected, offset = "Applications", {}, {}
local mailFor, mailSending

local function Loans()
	return ns.db.loans
end

local function Overdue(loan)
	return loan.status == "approved" and (loan.repayBy or 0) > 0 and time() > loan.repayBy
end

local function SendUpdate(loan, force)
	if not force and not ns.Online(loan.borrower) then return end
	local left, interest = ns.Due(loan)
	ns.Whisper(loan.borrower, string.format("UPD;%s;%s;%d;%s;%d;%d;%d;%d;%d;%d;%d;%d",
		loan.id, loan.status, loan.amount, tostring(loan.rate or 0), loan.sentAt or 0, loan.repayBy or 0,
		left, interest, time(), ns.PaidBack(loan), loan.closedAt or 0, ns.Unverified(loan)))
end

function ns.OnBankerMessage(sender, msg)
	if msg == "SYNC" then
		for _, loan in pairs(Loans()) do
			if loan.borrower == sender then SendUpdate(loan, true) end
		end
		ns.Whisper(sender, "END")
		return
	end
	if msg:match("^PAY;") then
		ns.OnBankPayment(sender, msg)
		return
	end
	local id, amount, repayBy, appliedAt, reason = msg:match("^APP;([^;]+);(%d+);(%d+);(%d+);(.*)$")
	if not id or ns.Online(sender) == nil then return end
	local loan = Loans()[id]
	if not loan then
		loan = {
			id = id, borrower = sender, amount = tonumber(amount), repayBy = tonumber(repayBy),
			appliedAt = tonumber(appliedAt), receivedAt = time(), reason = ns.Trim(reason, ns.REASON_BYTES),
			status = "pending", payments = {},
		}
		Loans()[id] = loan
		ns.Print(string.format("ny låneansökan från %s på %s. Öppna /swedbank.", sender, ns.Money(loan.amount)))
	end
	ns.Whisper(sender, "ACK;" .. id)
	SendUpdate(loan, true)
	ns.RefreshBanker()
end

function ns.OnBankerLogin()
	if not IsGuildLeader() then return end
	local pending, overdue = 0, 0
	for _, loan in pairs(Loans()) do
		if loan.status == "pending" then pending = pending + 1 end
		if Overdue(loan) then overdue = overdue + 1 end
	end
	if pending > 0 or overdue > 0 then
		ns.Print(string.format("%d ansökningar väntar, %d lån är försenade. Öppna /swedbank.", pending, overdue))
	end
end

-- Fill in the send-mail form with the borrower and the gold; the leader
-- checks it and presses Send, which the game requires anyway.
local function FillMail(loan)
	if not (MailFrame and MailFrame:IsShown()) then
		ns.Print("gå till en brevlåda, välj lånet under Lån och tryck Fyll i brev.")
		return
	end
	if MailFrameTab_OnClick then MailFrameTab_OnClick(nil, 2) end
	SendMailNameEditBox:SetText(loan.borrower)
	SendMailSubjectEditBox:SetText("Swedbank: lån")
	if SendMailBodyEditBox then
		SendMailBodyEditBox:SetText(string.format("Lån på %s med %g %% ränta i veckan%s. Räntan räknas från i dag.",
			ns.Money(loan.amount), loan.rate * 100, (loan.repayBy or 0) > 0 and (", betala senast " .. ns.Day(loan.repayBy)) or ""))
	end
	if SendMailSendMoneyButton and not SendMailSendMoneyButton:GetChecked() then SendMailSendMoneyButton:Click() end
	if MoneyInputFrame_SetCopper and SendMailMoney then MoneyInputFrame_SetCopper(SendMailMoney, loan.amount) end
	mailFor = loan.id
	ns.Print("brevet till " .. loan.borrower .. " är ifyllt med " .. ns.Money(loan.amount) .. ". Kontrollera det och tryck Send.")
end

-- The loan counts as sent once that mail goes through, even if the mailbox
-- is closed before the game confirms it, and with the gold actually in the
-- mail (review 6/11).
hooksecurefunc("SendMail", function(recipient)
	local loan = mailFor and Loans()[mailFor]
	if loan and recipient and ns.Short(recipient):lower() == loan.borrower:lower() then
		mailSending = { id = loan.id, money = GetSendMailMoney and GetSendMailMoney() or 0 }
	end
end)

local function MarkSent(loan, money)
	if loan.sentAt then return end
	loan.sentAt = time()
	if money and money > 0 and money ~= loan.amount then
		ns.Print(string.format("brevet innehöll %s, inte %s; lånet räknas nu på %s.", ns.Money(money), ns.Money(loan.amount), ns.Money(money)))
		loan.amount = money
	end
	ns.Print("lånet till " .. loan.borrower .. " är markerat som skickat; räntan räknas från nu.")
	SendUpdate(loan)
end

local function MarkRepaid(loan)
	loan.status, loan.closedAt = "repaid", time()
	ns.Print("lånet till " .. loan.borrower .. " är markerat som återbetalt.")
	SendUpdate(loan)
end

-- Close the loan if verified payments cover it, otherwise tell the borrower.
local function Settle(loan)
	local _, _, due = ns.Due(loan)
	if due < 1 then MarkRepaid(loan) else SendUpdate(loan) end
end

-- via "bank" for a payment the borrower reports from the guild bank; it
-- stays unverified until the bank log or the leader confirms it.
local function AddPayment(loan, amount, t, via)
	local unverified = via == "bank"
	-- A payment the leader logs by hand may be one the borrower has already
	-- reported from the bank: confirm that one instead of counting it twice
	-- (review 6/11).
	if not unverified then
		for _, p in ipairs(loan.payments) do
			if p.verified == false and p.amount == amount then
				p.verified = true
				ns.Print(string.format("%s hade redan rapporterat %s från guildbanken; den betalningen är nu godkänd.", loan.borrower, ns.Money(amount)))
				Settle(loan)
				return
			end
		end
	end
	table.insert(loan.payments, { t = t or time(), amount = amount, via = via, verified = not unverified })
	table.sort(loan.payments, function(a, b) return a.t < b.t end)
	if unverified then
		ns.Print(string.format("%s säger sig ha betalat %s till guildbanken på sitt lån; kontrolleras mot bankloggen nästa gång du öppnar guildbanken.",
			loan.borrower, ns.Money(amount)))
		SendUpdate(loan)
		return
	end
	local _, _, due = ns.Due(loan)
	ns.Print(string.format("betalning på %s från %s noterad; %s kvar.", ns.Money(amount), loan.borrower, ns.Money(due)))
	Settle(loan)
end

-- Confirm (true) or throw out (false) the selected loan's unverified payments.
local function Review(loan, accept)
	local count = 0
	for i = #loan.payments, 1, -1 do
		local p = loan.payments[i]
		if p.verified == false then
			count = count + 1
			if accept then p.verified = true else table.remove(loan.payments, i) end
		end
	end
	if count == 0 then ns.Print("inga okontrollerade betalningar på det här lånet.") return end
	ns.Print(string.format("%d betalning%s från %s %s.", count, count > 1 and "ar" or "", loan.borrower, accept and "godkänd" or "avvisad"))
	Settle(loan)
end

-- PAY;loan id;payment id;amount;paid at: the borrower says they paid into
-- the guild bank. Logged once per payment id, unverified; confirmed every
-- time so the borrower stops resending.
function ns.OnBankPayment(sender, msg)
	local id, pid, amount, t = msg:match("^PAY;([^;]+);(%d+);(%d+);(%d+)$")
	local loan = id and Loans()[id]
	if not loan or loan.borrower ~= sender then return end
	loan.paymentIds = loan.paymentIds or {}
	amount, t = tonumber(amount), math.min(tonumber(t), time())
	if not loan.paymentIds[pid] then
		loan.paymentIds[pid] = true
		-- Already logged by hand from the bank log notice: link, do not add (review 6/11).
		local manual
		for _, p in ipairs(loan.payments) do
			if p.via ~= "bank" and not p.linkedPid and p.amount == amount and math.abs(p.t - t) < 3 * 86400 then
				manual = p
				break
			end
		end
		if manual then
			manual.linkedPid = pid
			ns.Print(string.format("%s rapporterade %s från guildbanken; den betalningen har du redan noterat.", sender, ns.Money(amount)))
		elseif loan.status == "approved" then
			AddPayment(loan, amount, t, "bank")
		else
			-- The loan is closed already: keep it on record and say so, rather
			-- than dropping gold that may be in the bank (review 6/11).
			table.insert(loan.payments, { t = t, amount = amount, via = "bank", verified = false })
			ns.Print(string.format("%s rapporterade %s till guildbanken på ett lån som redan är avslutat. Kolla bankloggen och ge tillbaka guldet om det stämmer.",
				sender, ns.Money(amount)))
		end
	end
	ns.Whisper(sender, "PACK;" .. pid)
	SendUpdate(loan, true)
	ns.RefreshBanker()
end

-- The guild bank's money log, read when the leader opens the bank. A
-- deposit from someone with a loan running that matches no logged payment
-- may be a repayment that has not reached the leader yet. Tax deposits sit
-- in the same log, so this only points them out; nothing is booked (Zach 6/11).
local function ReadBankLog()
	if not GetNumGuildBankMoneyTransactions then return end
	local now, deposits = time(), {}
	for i = 1, GetNumGuildBankMoneyTransactions() do
		local kind, name, amount, years, months, days, hours = GetGuildBankMoneyTransaction(i)
		if kind == "deposit" and name then
			local age = (((years or 0) * 365 + (months or 0) * 30 + (days or 0)) * 24 + (hours or 0)) * 3600
			table.insert(deposits, { name = ns.Short(name), amount = amount, t = now - age })
		end
	end
	ns.db.bankLog = { readAt = now, deposits = deposits }
end

-- This borrower's deposits since the gold was sent, each marked whether a
-- logged payment of the same amount within two days matches it.
local function BankDeposits(loan)
	local log = ns.db.bankLog
	if not log or not loan.sentAt then return {} end
	local used, out = {}, {}
	for _, d in ipairs(log.deposits) do
		if d.name == loan.borrower and d.t >= loan.sentAt - 3600 then
			local match
			for i, p in ipairs(loan.payments or {}) do
				if not used[i] and p.amount == d.amount and math.abs(p.t - d.t) < 2 * 86400 then
					match = i
					break
				end
			end
			if match then used[match] = true end
			table.insert(out, { amount = d.amount, t = d.t, logged = match ~= nil, payment = match and loan.payments[match] })
		end
	end
	return out
end

-- A reported guild bank payment is real once a deposit by the borrower of
-- the same amount within two days shows in the bank log.
local function VerifyFromLog()
	for _, loan in pairs(Loans()) do
		if loan.status == "approved" then
			local changed = false
			for _, d in ipairs(BankDeposits(loan)) do
				if d.payment and d.payment.verified == false then
					d.payment.verified = true
					changed = true
					ns.Print(string.format("betalningen på %s från %s stämmer med bankloggen.", ns.Money(d.amount), loan.borrower))
				end
			end
			if changed then Settle(loan) end
		end
	end
end

local noticed = {}
local function NoticeUnlogged()
	for _, loan in pairs(Loans()) do
		if loan.status == "approved" then
			for _, d in ipairs(BankDeposits(loan)) do
				local key = loan.borrower .. d.amount .. ns.Day(d.t)
				if not d.logged and not noticed[key] then
					noticed[key] = true
					ns.Print(string.format("%s satte in %s i guildbanken %s; inte noterad som lånebetalning (kan vara skatt). Se fliken Lån.",
						loan.borrower, ns.Money(d.amount), ns.Day(d.t)))
				end
			end
		end
	end
end

function ns.OnBankerEvent(event, ...)
	if event == "MAIL_SEND_SUCCESS" and mailSending then
		local loan, money = Loans()[mailSending.id], mailSending.money
		mailSending, mailFor = nil, nil
		if loan then MarkSent(loan, money) end
	elseif event == "MAIL_FAILED" then
		mailSending = nil
	elseif event == "MAIL_CLOSED" then
		mailFor = nil
	elseif IsGuildLeader() and QueryGuildBankLog and (event == "GUILDBANKFRAME_OPENED"
		or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and Enum and Enum.PlayerInteractionType
			and ... == Enum.PlayerInteractionType.GuildBanker)) then
		QueryGuildBankLog((MAX_GUILDBANK_TABS or 6) + 1)
	elseif event == "GUILDBANKLOG_UPDATE" and IsGuildLeader() then
		ReadBankLog()
		VerifyFromLog()
		NoticeUnlogged()
	end
	ns.RefreshBanker()
end

local function Selected()
	local loan = selected[tab] and Loans()[selected[tab]]
	if loan and IN_TAB[tab][loan.status] then return loan end
	ns.Print("klicka på en rad först.")
end

local function Rows()
	local rows = {}
	for _, loan in pairs(Loans()) do
		if IN_TAB[tab][loan.status] then table.insert(rows, loan) end
	end
	table.sort(rows, function(a, b)
		if tab == "Loans" then
			local oa, ob = Overdue(a), Overdue(b)
			if oa ~= ob then return oa end
			return (a.sentAt or 0) < (b.sentAt or 0)
		elseif tab == "History" then
			return (a.closedAt or 0) > (b.closedAt or 0)
		end
		return (a.appliedAt or 0) < (b.appliedAt or 0)
	end)
	return rows
end

-- A red line for an application from someone who already owes the guild.
local function Warning(loan)
	if loan.status ~= "pending" then return "" end
	local running, overdue = 0, 0
	for _, other in pairs(Loans()) do
		if other.borrower == loan.borrower and other.status == "approved" then
			running = running + 1
			if Overdue(other) then overdue = overdue + 1 end
		end
	end
	local text = ""
	if running > 0 then
		text = string.format("|cffff4040Har redan %d lån igång%s.|r ", running, overdue > 0 and string.format(", %d försenade", overdue) or "")
	end
	-- Members apply only in good standing (Zach 8/11), but a macro can send
	-- an application anyway; say so here.
	local standing = SkatteverketAPI and SkatteverketAPI.MemberStanding(loan.borrower)
	if standing and standing ~= "good" then
		text = text .. string.format("|cffff4040Ställning hos Skatteverket: %s.|r ", standing == "neutral" and "Neutral" or "Negativ")
	end
	return text
end

local function Values(loan)
	local paid = ns.PaidBack(loan)
	if tab == "Applications" then
		return { ns.Day(loan.appliedAt), loan.borrower, ns.Money(loan.amount), ns.Day(loan.repayBy), Warning(loan) .. loan.reason }
	elseif tab == "Loans" then
		local _, _, due = ns.Due(loan)
		local repayBy = ns.Day(loan.repayBy)
		if Overdue(loan) then repayBy = "|cffff4040" .. repayBy .. "|r" end
		return {
			loan.borrower, ns.Money(loan.amount), string.format("%g%%", loan.rate * 100),
			loan.sentAt and ns.Day(loan.sentAt) or "|cffffd100inte skickat|r",
			loan.sentAt and tostring(math.floor((time() - loan.sentAt) / 86400)) or "-",
			ns.Money(paid + due - loan.amount), ns.Money(paid), ns.Money(due), repayBy,
		}
	end
	local status = loan.status == "repaid" and "|cff40ff40Återbetalt|r" or "|cffff4040Nekat|r"
	return { loan.borrower, ns.Money(loan.amount), status, ns.Day(loan.appliedAt), ns.Day(loan.closedAt), ns.Money(paid), loan.reason }
end

local function Detail(loan)
	local dates = string.format("%s, %s. Ansökt %s, godkänt %s, skickat %s, avslutat %s.", loan.borrower, ns.Money(loan.amount),
		ns.Day(loan.appliedAt), ns.Day(loan.approvedAt), ns.Day(loan.sentAt), ns.Day(loan.closedAt))
	if loan.rate then dates = dates .. string.format(" Ränta %g %% i veckan.", loan.rate * 100) end
	local payments = {}
	for _, p in ipairs(loan.payments or {}) do
		table.insert(payments, ns.Day(p.t) .. " " .. ns.Money(p.amount) .. (p.via == "bank" and " (guildbanken)" or "")
			.. (p.verified == false and " |cffff4040(ej kontrollerad)|r" or ""))
	end
	local bank
	if not loan.sentAt then
		bank = ""
	elseif not ns.db.bankLog then
		bank = "Bankloggen är inte läst än; öppna guildbanken."
	else
		local deposits = {}
		for _, d in ipairs(BankDeposits(loan)) do
			table.insert(deposits, ns.Day(d.t) .. " " .. ns.Money(d.amount) .. (d.logged and " (noterad)" or " |cffffd100(inte noterad)|r"))
		end
		bank = string.format("Insättningar i guildbanken (loggen läst %s): %s", ns.Day(ns.db.bankLog.readAt),
			#deposits > 0 and table.concat(deposits, ", ") or "inga")
	end
	return Warning(loan) .. dates, "Anledning: " .. loan.reason, "Betalningar: " .. (#payments > 0 and table.concat(payments, ", ") or "inga"), bank
end

function ns.BuildBanker(page, panel)
	frame = CreateFrame("Frame", nil, page)
	frame:SetAllPoints()
	frame.title = ns.Text(frame, "GameFontNormal", "TOPLEFT", 24, -70)
	frame.summary = ns.Text(frame, "GameFontHighlightSmall", "LEFT", frame.title, "RIGHT", 16, 0)

	-- Applications, Loans and History share the list.
	local main = CreateFrame("Frame", nil, frame)
	main:SetAllPoints()
	frame.main = main
	list = ns.List(main, -92, ROWS, 9, W)
	for _, row in ipairs(list.rows) do
		row:SetScript("OnClick", function() selected[tab] = row.id ns.RefreshBanker() end)
	end
	local y = -92 - 14 - ROWS * 18 - 10
	frame.details = {}
	for i = 1, 4 do
		frame.details[i] = ns.Text(main, "GameFontHighlightSmall", "TOPLEFT", 24, y - (i - 1) * 16)
		frame.details[i]:SetWidth(W - 48)
		frame.details[i]:SetWordWrap(false)
	end

	-- Applications: rate, Approve, Decline.
	local apps = CreateFrame("Frame", nil, main)
	apps:SetPoint("BOTTOMLEFT", 24, 34)
	apps:SetSize(W - 48, 24)
	ns.Text(apps, "GameFontNormalSmall", "LEFT", 0, 0):SetText("Ränta % i veckan")
	apps.rate = ns.Input(apps, 40)
	apps.rate:SetPoint("LEFT", 100, 0)
	apps.rate:SetText("5")
	local approve = ns.Button(apps, "Godkänn", 100, function()
		local loan, percent = Selected(), tonumber((apps.rate:GetText():gsub(",", ".")))
		if not loan then return end
		if not percent or percent < 0 then ns.Print("skriv veckoräntan, till exempel 5.") return end
		loan.status, loan.rate, loan.approvedAt = "approved", percent / 100, time()
		ns.Print(string.format("lån på %s till %s godkänt med %g %% ränta i veckan.", ns.Money(loan.amount), loan.borrower, percent))
		SendUpdate(loan)
		FillMail(loan)
		ns.RefreshBanker()
	end)
	approve:SetPoint("LEFT", apps.rate, "RIGHT", 10, 0)
	local decline = ns.Button(apps, "Neka", 100, function()
		local loan = Selected()
		if not loan then return end
		loan.status, loan.closedAt = "declined", time()
		ns.Print("ansökan från " .. loan.borrower .. " nekad.")
		SendUpdate(loan)
		ns.RefreshBanker()
	end)
	decline:SetPoint("LEFT", approve, "RIGHT", 8, 0)

	-- Loans: Fill mail, Mark sent, a payment, Mark repaid.
	local loans = CreateFrame("Frame", nil, main)
	loans:SetPoint("BOTTOMLEFT", 24, 34)
	loans:SetSize(W - 48, 24)
	local fill = ns.Button(loans, "Fyll i brev", 110, function()
		local loan = Selected()
		if loan then FillMail(loan) end
	end)
	fill:SetPoint("LEFT", 0, 0)
	local sent = ns.Button(loans, "Markera skickat", 130, function()
		local loan = Selected()
		if loan then MarkSent(loan) ns.RefreshBanker() end
	end)
	sent:SetPoint("LEFT", fill, "RIGHT", 8, 0)
	local paymentLabel = ns.Text(loans, "GameFontNormalSmall", "LEFT", sent, "RIGHT", 24, 0)
	paymentLabel:SetText("Betalning")
	loans.amount = ns.Input(loans, 80)
	loans.amount:SetPoint("LEFT", paymentLabel, "RIGHT", 10, 0)
	local add = ns.Button(loans, "Lägg till betalning", 150, function()
		local loan, amount = Selected(), ns.ParseMoney(loans.amount:GetText())
		if not loan then return end
		if not amount then ns.Print("skriv beloppet som betalats tillbaka, till exempel 10g.") return end
		AddPayment(loan, amount)
		loans.amount:SetText("")
		loans.amount:ClearFocus()
		ns.RefreshBanker()
	end)
	add:SetPoint("LEFT", loans.amount, "RIGHT", 8, 0)
	local repaid = ns.Button(loans, "Markera återbetalt", 150, function()
		local loan = Selected()
		if loan then MarkRepaid(loan) ns.RefreshBanker() end
	end)
	repaid:SetPoint("LEFT", add, "RIGHT", 24, 0)

	-- Second line: reported guild bank payments that the bank log has not confirmed.
	local review = CreateFrame("Frame", nil, loans)
	review:SetPoint("BOTTOMLEFT", loans, "TOPLEFT", 0, 4)
	review:SetSize(W - 48, 24)
	local accept = ns.Button(review, "Godkänn betalning", 150, function()
		local loan = Selected()
		if loan then Review(loan, true) ns.RefreshBanker() end
	end)
	accept:SetPoint("LEFT", 0, 0)
	local reject = ns.Button(review, "Avvisa betalning", 150, function()
		local loan = Selected()
		if loan then Review(loan, false) ns.RefreshBanker() end
	end)
	reject:SetPoint("LEFT", accept, "RIGHT", 8, 0)
	ns.Text(review, "GameFontDisableSmall", "LEFT", reject, "RIGHT", 12, 0):SetText("för betalningar som bankloggen inte har bekräftat")
	frame.controls = { Applications = apps, Loans = loans }

	frame.sideTabs = ns.SideTabs(frame, panel, SIDE_TABS, function(i)
		tab = TABS[i]
		ns.RefreshBanker()
	end)
	frame:SetScript("OnShow", ns.RequestRoster)

	main:EnableMouseWheel(true)
	main:SetScript("OnMouseWheel", function(_, delta)
		offset[tab] = (offset[tab] or 0) - delta
		ns.RefreshBanker()
	end)
	frame:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed > 1 then
			self.elapsed = 0
			ns.RefreshBanker()
		end
	end)
	frame:Hide()
end

function ns.ShowBanker(shown)
	if frame then frame:SetShown(shown) end
end

function ns.RefreshBanker()
	if not frame or not frame:IsShown() then return end
	for i, name in ipairs(TABS) do
		if name == tab then
			frame.sideTabs.Select(i)
			frame.title:SetText(SIDE_TABS[i][2])
		end
	end
	for name, controls in pairs(frame.controls) do
		if name == tab then controls:Show() else controls:Hide() end
	end

	local pending, active, out, overdue = 0, 0, 0, 0
	for _, loan in pairs(Loans()) do
		if loan.status == "pending" then pending = pending + 1 end
		if loan.status == "approved" then
			active = active + 1
			out = out + select(3, ns.Due(loan))
			if Overdue(loan) then overdue = overdue + 1 end
		end
	end
	frame.summary:SetText(string.format("%d ansökningar, %d lån igång, %s skyldigt guildet, %d försenade.", pending, active, ns.Money(out), overdue))

	list:SetColumns(COLS[tab])
	local rows = Rows()
	offset[tab] = math.max(0, math.min(offset[tab] or 0, #rows - ROWS))
	for i, row in ipairs(list.rows) do
		local loan = rows[i + offset[tab]]
		row.id = loan and loan.id
		if loan then
			local values = Values(loan)
			for c, cell in ipairs(row.cells) do cell:SetText(values[c] or "") end
			if loan.id == selected[tab] then row:LockHighlight() else row:UnlockHighlight() end
			row:Show()
		else
			row:Hide()
		end
	end

	local loan = selected[tab] and Loans()[selected[tab]]
	if loan and IN_TAB[tab][loan.status] then
		local a, b, c, d = Detail(loan)
		frame.details[1]:SetText(a)
		frame.details[2]:SetText(b)
		frame.details[3]:SetText(c)
		frame.details[4]:SetText(d)
	else
		frame.details[1]:SetText(#rows == 0 and "Inget här." or "Klicka på en rad för detaljer.")
		frame.details[2]:SetText("")
		frame.details[3]:SetText("")
		frame.details[4]:SetText("")
	end
end
