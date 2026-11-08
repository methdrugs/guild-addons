-- Skatteverket, the Inställningar tab (Zach 8/11): show the minimap button
-- or use the commands only, and whether Nytt opens by itself after an
-- update. Saved for the whole account; open to everyone, signed or not.

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
	local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 28, -160)
	hint:SetWidth(440)
	hint:SetJustifyH("LEFT")
	hint:SetText("Utan knappen: /skatt öppnar panelen, /skatt nytt visar vad som är nytt, /swedbank öppnar Swedbank. Inställningarna gäller alla dina karaktärer.")
end

function ns.RefreshOptions()
	if not page or not page:IsShown() then return end
	for _, box in ipairs(page.boxes) do box:SetChecked(box.get()) end
end
