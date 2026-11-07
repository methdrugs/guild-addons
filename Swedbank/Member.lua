-- Swedbank, the member's side: the application form and "My loans", where
-- a running loan can be paid back straight into the guild bank.
-- Applications and payments wait in this character's saved data until the
-- guild leader has confirmed them, so nothing is lost if the leader is
-- offline.

local _, ns = ...

local ROWS, W, H = 8, 600, 470
local COLS = { { "Ansökt", 70 }, { "Belopp", 100 }, { "Status", 160 }, { "Ränta", 60 }, { "Att betala", 100 }, { "Betala senast", 80 } }
local frame, list, selected
local offset = 0
local lastSync, synced = 0, false
local bankOpen, pendingPay = false, nil

local STATUS = {
	sending = "Väntar på att ledaren loggar in",
	pending = "Väntar på godkännande",
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
	local extra = loan.left * loan.rate * (time() - loan.asOf) / ns.WEEK
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
			ns.Whisper(leader, string.format("APP;%s;%d;%d;%d;%s", id, loan.amount, loan.repayBy or 0, loan.appliedAt, loan.reason))
		end
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
		local loan = ns.char.loans[id] or { id = id, reason = "", appliedAt = 0 }
		ns.char.loans[id] = loan
		local before, wasSent = loan.status, loan.sentAt
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
				ns.Print(string.format("ditt lån på %s är godkänt med %g %% ränta i veckan. Guldet kommer med posten.", money, loan.rate * 100))
			elseif status == "declined" then
				ns.Print("din ansökan om " .. money .. " har nekats.")
			elseif status == "repaid" then
				ns.Print("ditt lån på " .. money .. " är återbetalt. Tack!")
			end
		end
		if loan.sentAt and not wasSent and status == "approved" then
			ns.Print("guldet för ditt lån på " .. money .. " har skickats. Räntan räknas från i dag.")
		end
	end
	ns.RefreshMember()
end

local function Submit()
	local amount = ns.ParseMoney(frame.amount:GetText())
	if not amount or amount < 1 then ns.Print("skriv ett belopp, till exempel 50g.") return end
	local repayBy, repayText = 0, frame.repayBy:GetText()
	if repayText ~= "" then
		repayBy = ns.ParseDate(repayText)
		if not repayBy then ns.Print("skriv datumet som dd/mm, till exempel 24/12.") return end
	end
	local reason = ns.Trim(frame.reason:GetText(), ns.REASON_BYTES)
	if reason == "" then ns.Print("skriv vad lånet ska användas till.") return end
	local id = string.format("%s-%d-%03d", UnitName("player"), time(), math.random(999))
	ns.char.loans[id] = { id = id, amount = amount, reason = reason, repayBy = repayBy, appliedAt = time(), status = "sending" }
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

local function Build()
	frame = ns.Dialog("SwedbankMemberFrame", W, H, "Swedbank")
	ns.Text(frame, "GameFontNormal", "TOPLEFT", 24, -34):SetText("Låneansökan")
	frame.applicant = ns.Text(frame, "GameFontHighlight", "TOPLEFT", 24, -56)
	ns.Text(frame, "GameFontNormalSmall", "TOPLEFT", 24, -84):SetText("Belopp (t.ex. 50g)")
	frame.amount = ns.Input(frame, 90)
	frame.amount:SetPoint("TOPLEFT", 150, -80)
	ns.Text(frame, "GameFontNormalSmall", "TOPLEFT", 270, -84):SetText("Betala senast (dd/mm, valfritt)")
	frame.repayBy = ns.Input(frame, 60)
	frame.repayBy:SetPoint("TOPLEFT", 450, -80)
	ns.Text(frame, "GameFontNormalSmall", "TOPLEFT", 24, -112):SetText("Anledning")
	frame.reason = ns.Input(frame, 420, Submit)
	frame.reason:SetPoint("TOPLEFT", 150, -108)
	frame.reason:SetMaxBytes(ns.REASON_BYTES + 1)
	local submit = ns.Button(frame, "Skicka", 100, Submit)
	submit:SetPoint("TOPLEFT", 146, -136)
	ns.Text(frame, "GameFontDisableSmall", "LEFT", submit, "RIGHT", 12, 0):SetText("Bara guildledaren ser din ansökan och dina lån.")

	ns.Text(frame, "GameFontNormal", "TOPLEFT", 24, -176):SetText("Mina lån")
	list = ns.List(frame, -196, ROWS, #COLS, W)
	list:SetColumns(COLS)
	for _, row in ipairs(list.rows) do
		row:SetScript("OnClick", function()
			selected = row.id
			local loan = ns.char.loans[row.id]
			if Active(loan) then frame.payAmount:SetText(string.format("%dg%ds%dc", math.floor(DueNow(loan) / 10000), math.floor(DueNow(loan) / 100) % 100, DueNow(loan) % 100)) end
			ns.RefreshMember()
		end)
	end
	frame.empty = ns.Text(frame, "GameFontDisableSmall", "TOPLEFT", 24, -214)

	-- Pay back: amount (filled with all that is due when a loan is clicked) and the button.
	ns.Text(frame, "GameFontNormalSmall", "BOTTOMLEFT", 24, 58):SetText("Betala tillbaka")
	frame.payAmount = ns.Input(frame, 100, PayBack)
	frame.payAmount:SetPoint("BOTTOMLEFT", 130, 52)
	frame.pay = ns.Button(frame, "Betala till guildbanken", 170, PayBack)
	frame.pay:SetPoint("LEFT", frame.payAmount, "RIGHT", 10, 0)
	frame.payHint = ns.Text(frame, "GameFontDisableSmall", "LEFT", frame.pay, "RIGHT", 10, 0)

	local close = ns.Button(frame, "Stäng", 100, function() frame:Hide() end)
	close:SetPoint("BOTTOMRIGHT", -24, 18)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta
		ns.RefreshMember()
	end)
	frame:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed > 1 then
			self.elapsed = 0
			ns.RefreshMember()
		end
	end)
end

function ns.RefreshMember()
	if not frame or not frame:IsShown() then return end
	frame.applicant:SetText("Sökande: " .. (ns.Me() or UnitName("player")))
	local sorted = {}
	for _, loan in pairs(ns.char.loans) do table.insert(sorted, loan) end
	-- Open loans first (running, then waiting), newest first within each; the
	-- list scrolls with the mouse wheel, so no loan drops out of reach (review 6/11).
	local order = { approved = 1, pending = 2, sending = 2 }
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

function ns.ToggleMember()
	if not frame then Build() end
	if frame:IsShown() then frame:Hide() return end
	frame:Show()
	Sync()
	ns.RefreshMember()
end
