-- Skatteverket, the Inställningar tab (Zach 8/11): show the minimap button
-- or use the commands only, and whether Nytt opens by itself after an
-- update, and whether achievements come with a banner and a sound. Saved
-- for the whole account; open to everyone, signed or not.
-- The Guildmap section is gone (Zach 9/11): GuildMap spammed errors in PvP
-- until his interface locked, so members are no longer pointed to it.
-- Delar (Zach 14/11): a box per part. Skatt, Folkvald representant, Nytt,
-- Kontakta oss! and Inställningar are always on (ticked, greyed). Yrken
-- (Arbetsorder with it) turns off for this character only, kept in
-- SkatteverketCharDB like the recipes and professions it shares; turning
-- it off asks first and cancels the open orders (Orders.lua). Swedbank
-- and Bokföring are addons of their own: a box asks first, then turns the
-- addon off or on for this character and reloads the interface. Swedbank
-- stays on while a loan runs.

local _, ns = ...

local page

local function Check(parent, label, y, get, set, x)
	local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	box:SetPoint("TOPLEFT", x or 24, y)
	local text = box.text or box.Text
	if not text then
		text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", box, "RIGHT", 4, 0)
	end
	text:SetFontObject("GameFontHighlight")
	text:SetText(label)
	box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	box.get = get
	box.label = text
	return box
end

-- Delar -----------------------------------------------------------------

local AddOns = C_AddOns or {}
local Loaded = AddOns.IsAddOnLoaded or IsAddOnLoaded
local AddOnInfo = AddOns.GetAddOnInfo or GetAddOnInfo
local EnableAddOn = AddOns.EnableAddOn or EnableAddOn
local DisableAddOn = AddOns.DisableAddOn or DisableAddOn

local function IsLoaded(addon)
	return Loaded and Loaded(addon) and true or false
end

-- Why an addon that is not running cannot be turned on here: not
-- installed, or something it needs is missing (Bokföring: Auctionator).
local function Missing(addon)
	if not AddOnInfo then return nil end
	local ok, _, _, _, _, reason = pcall(AddOnInfo, addon)
	if not ok or reason == "MISSING" then return "inte installerat" end
	if reason == "DEP_MISSING" or reason == "DEP_DISABLED" then
		return addon == "Bokforing" and "kräver Auctionator" or "saknar något det behöver"
	end
end

-- Greyed with a reason, or nil when the box can be clicked.
local function AddOnLock(addon)
	if not IsLoaded(addon) then return Missing(addon) end
	if addon == "Swedbank" and SwedbankPanel and SwedbankPanel.HasLoan and SwedbankPanel.HasLoan() then
		return "du har ett lån som löper; betala tillbaka det först"
	end
	if not (EnableAddOn and DisableAddOn and ReloadUI) then return "spelet tillåter det inte här; använd AddOns i karaktärsvalet" end
end

-- For all his characters (Zach 14/11), as the AddOns list does with "All"
-- chosen: no character name.
local function SwitchAddOn(addon, on)
	local f = on and EnableAddOn or DisableAddOn
	if not f or not ReloadUI then return end
	if not pcall(f, addon) then
		ns.Print("det gick inte; använd AddOns i karaktärsvalet.")
		return
	end
	ReloadUI()
end

StaticPopupDialogs["SKATTEVERKET_PART_ADDON"] = {
	text = "%s %s för alla dina karaktärer? Gränssnittet laddas om.",
	button1 = YES or "Ja",
	button2 = NO or "Nej",
	OnAccept = function(_, data) SwitchAddOn(data.addon, data.on) end,
	OnHide = function() ns.RefreshOptions() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["SKATTEVERKET_PART_YRKEN"] = {
	text = "Stänga av Yrken och Arbetsorder för den här karaktären?%s",
	button1 = YES or "Ja",
	button2 = NO or "Nej",
	OnAccept = function()
		ns.CloseOpenOrders()
		ns.char.parts = ns.char.parts or {}
		ns.char.parts.yrken = false
		ns.DropRecipes()
		ns.CloseWindow("yrken")
		ns.RefreshOrderBadge()
		ns.Print("Yrken och Arbetsorder är avstängda på den här karaktären; dina recept syns inte längre för guildet.")
	end,
	OnHide = function() ns.RefreshOptions() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function SetYrken(on)
	if on == ns.YrkenOn() then return end
	if on then
		ns.char.parts.yrken = nil
		ns.ShareRecipesAgain()
		ns.RefreshOrderBadge()
		ns.Print("Yrken och Arbetsorder är på igen; dina recept delas med guildet.")
		ns.RefreshOptions()
		return
	end
	local n = #ns.OpenOrders()
	StaticPopup_Show("SKATTEVERKET_PART_YRKEN", n > 0
		and string.format(" Dina %d öppna arbetsorder%s avbryts, och den andra parten får veta det.", n, n == 1 and "" or "ar") or "")
end

local function AddOnBox(parent, label, addon, y, x)
	local box = Check(parent, label, y,
		function() return IsLoaded(addon) end,
		function(on)
			if on == IsLoaded(addon) then return end
			StaticPopup_Show("SKATTEVERKET_PART_ADDON", on and "Slå på" or "Stänga av", label, { addon = addon, on = on })
		end, x)
	box.lock = function() return AddOnLock(addon) end
	return box
end

local function BuildParts(parent, anchor)
	local delar = CreateFrame("Frame", nil, parent)
	delar:SetSize(480, 190)
	delar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -28, -14)
	local title = delar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 24, 0)
	title:SetText("Delar")
	local note = delar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("LEFT", title, "RIGHT", 8, 0)
	note:SetText("Yrken gäller den här karaktären, Swedbank och Bokföring alla dina karaktärer")
	-- Always on, left; can be turned off, right.
	for i, name in ipairs({ "Skatt", "Folkvald representant", "Nytt", "Kontakta oss!", "Inställningar" }) do
		local box = Check(delar, name, -18 - (i - 1) * 24, function() return true end, function() end)
		box.lock = function() return "alltid på" end
		table.insert(page.boxes, box)
	end
	local yrken = Check(delar, "Yrken och Arbetsorder", -18, ns.YrkenOn, SetYrken, 250)
	table.insert(page.boxes, yrken)
	table.insert(page.boxes, AddOnBox(delar, "Swedbank", "Swedbank", -42, 250))
	table.insert(page.boxes, AddOnBox(delar, "Bokföring", "Bokforing", -66, 250))
	-- Why a box on the right is greyed.
	page.why = delar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	page.why:SetPoint("TOPLEFT", 254, -96)
	page.why:SetWidth(220)
	page.why:SetJustifyH("LEFT")
end

function ns.BuildOptions(parent)
	page = parent
	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 24, -70)
	title:SetText("Inställningar")
	page.boxes = {
		Check(parent, "Visa minimapknapp", -94,
			function() return not (ns.db.minimap and ns.db.minimap.hide) end,
			function(on)
				ns.db.minimap = ns.db.minimap or { angle = 200 }
				ns.db.minimap.hide = not on
				ns.RefreshMinimap()
			end),
		Check(parent, "Visa nyheter efter uppdatering", -122,
			function() return ns.db.showNews ~= false end,
			function(on) ns.db.showNews = on end),
	}
	-- For those who find the banner annoying (Zach 8/11): a chat line
	-- instead. Not while Prestationer is on hold (Zach 9/11).
	if ns.PRESTATIONER then
		table.insert(page.boxes, Check(parent, "Visa banner och ljud för prestationer", -150,
			function() return ns.db.showBanners ~= false end,
			function(on) ns.db.showBanners = on end))
	end
	-- Bokföring's lists (Zach 11/11), where it is installed.
	local y = ns.PRESTATIONER and -178 or -150
	if BokforingAPI and BokforingAPI.KeepLists then
		table.insert(page.boxes, Check(parent, "Bokföring: ta bort klara listor ur Auctionator", y,
			function() return not BokforingAPI.KeepLists() end,
			function(on) BokforingAPI.KeepLists(not on) end))
		y = y - 28
	end
	local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 28, y - 10)
	hint:SetWidth(440)
	hint:SetJustifyH("LEFT")
	hint:SetText("Utan minimapknappen: /skatt öppnar Skatt, /yrken Yrken, /swedbank Swedbank och /bok Bokföring; /skatt nytt visar vad som är nytt, /installningar visar inställningar"
		.. (ns.PRESTATIONER and ", /skatt prestationer prestationer" or "") .. ". Inställningarna gäller alla dina karaktärer, utom Delar.")
	BuildParts(parent, hint)
end

function ns.RefreshOptions()
	if not page or not page:IsShown() then return end
	local why = {}
	for _, box in ipairs(page.boxes) do
		box:SetChecked(box.get())
		local lock = box.lock and box.lock()
		if lock then box:Disable() else box:Enable() end
		box.label:SetFontObject(lock and "GameFontDisable" or "GameFontHighlight")
		if lock and lock ~= "alltid på" then table.insert(why, box.label:GetText() .. ": " .. lock .. ".") end
	end
	if page.why then page.why:SetText(table.concat(why, " ")) end
end
