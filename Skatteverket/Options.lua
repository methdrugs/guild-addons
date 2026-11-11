-- Skatteverket, the Inställningar tab (Zach 8/11): show the minimap button
-- or use the commands only, and whether Nytt opens by itself after an
-- update, and whether achievements come with a banner and a sound. Saved
-- for the whole account; open to everyone, signed or not.
-- The Guildmap section is gone (Zach 9/11): GuildMap spammed errors in PvP
-- until his interface locked, so members are no longer pointed to it.

local _, ns = ...

local page

local function Check(parent, label, y, get, set)
	local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	box:SetPoint("TOPLEFT", 24, y)
	local text = box.text or box.Text
	if not text then
		text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", box, "RIGHT", 4, 0)
	end
	text:SetFontObject("GameFontHighlight")
	text:SetText(label)
	box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	box.get = get
	return box
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
	hint:SetText("Utan minimapknappen: /skatt öppnar Skatt, /yrken Yrken, /swedbank Swedbank och /bok Bokföring; /skatt nytt visar vad som är nytt"
		.. (ns.PRESTATIONER and ", /skatt prestationer prestationer" or "") .. ". Inställningarna gäller alla dina karaktärer.")
end

function ns.RefreshOptions()
	if not page or not page:IsShown() then return end
	for _, box in ipairs(page.boxes) do box:SetChecked(box.get()) end
end
