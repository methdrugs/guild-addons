-- The THÖNDERSTÖRM panel's Nytt tab (Zach 8/11): who runs which version of
-- Skatteverket and of Swedbank, then the patch notes of both by date,
-- newest first, so one addon's history never buries the other's. Open to everyone in the
-- guild, signed or not. After an update it opens by itself once, for those
-- who have signed, unless turned off under Inställningar; a first-time
-- user does not get it.

local _, ns = ...

-- Newest first. Written for members: no amounts, nothing leader-only.
ns.NOTES = {
	{ "0.27", "2026-11-10", {
		"Arbetsorder: klicka på en order för att öppna den. Där står vad som är beställt (klicka på föremålet för att se det, shift-klicka för att länka det), antal, när den beställdes, vems material, dricks, reagenser, hur länge beställaren kan vänta och kommentaren. En ny order accepteras eller avböjs inne i ordern, så att den blir läst först.",
		"Om någon lämnar guildet medan du är offline säger Skatteverket till när du loggar in. /skatt lämnat visar de senaste 30 dagarna.",
		"Bokföring 0.6: fliken Today överst visar högst fem saker att göra just nu för att tjäna guld: vad som lönar sig att tillverka och hur många, vad du har i väskan att lägga upp, och efter en vecka med priser även fynd att köpa och sälja igen, och vilken tid på dygnet det brukar säljas dyrast. Allt inom en dagsbudget (/bok budget 50g, annars en fjärdedel av ditt guld).",
		"Bokföring 0.6: kryssrutan Level up sorterar recepten efter vad varje skillpoäng kostar eller ger i guld, och visar hur många du ska tillverka tills receptet blir grönt. Tillsammans med Can learn syns även recept du kan köpa och lära dig.",
		"Bokföring 0.6.1: knappen Read recipes längst ned (där Scan AH satt) läser in alla recept och receptföremål i spelet en gång, så att All recipes, Can learn och Need skill har något att visa; den blir grå när det är klart, och görs också av sig själv en minut efter inloggning. Priser och vad som säljer kommer från Auctionators skanningar.",
		"Bokföring: vanliga reagenser från försäljare (tråd, färg, flaskor, flux med mera) hamnar på försäljarlistan, inte på Auctionator-listan.",
	} },
	{ "0.26", "2026-11-10", {
		"Ny version: kommer det en nyare Skatteverket, Swedbank eller Bokföring visas en ruta när du loggar in, med vad som är nytt att hämta. Uppdatera i WowUp.",
		"Nytt visar också vem som kör vilken version av Bokföring.",
		"Bokföring 0.4: fliken Market visar priset över tid för det du har tillverkat, med låg och hög per dag de senaste 30 dagarna och vilka veckodagar som brukar ligga högt eller lågt.",
		"Bokföring: kolumnen Trend visar om priset går upp eller ned, och sökrutan hittar recept, föremål och reagenser.",
		"Bokföring: högerklicka på ett recept och välj Watch för att följa priset på något du inte har tillverkat. Högerklicka i Market för att sluta följa.",
		"Bokföring: History räknade fel på sålda saker när flera såldes för samma pris inom samma timme; det är rättat. Vill du börja om från noll: skriv /bok reset history. History visar nu också hur många du har lagt upp på AH (Posted) och hur många som ligger kvar (On AH).",
		"Bokföring 0.5: kryssrutorna Can learn och Need skill visar recepten du inte har lärt dig på den här karaktären, med skillen de kräver, lägst först: vad du kan lära dig nu och vad du ska sikta på. Klicka på ett recept för att se var det finns: tränare, försäljare (namn och zon) eller drop, och priset på AH.",
	} },
	-- 0.25, not 0.24: so much is new (Zach 9/11).
	{ "0.25", "2026-11-09", {
		"Bokföring (/bok, på engelska, kräver Auctionator): vilka av dina recept som tjänar mest och faktiskt säljer, inköpslistor till Auctionator, vad du håller på att tillverka och vad ditt craftande verkligen har gett.",
		"Arbetsorder: beställ ett recept av någon under Yrken (Beställ i deras receptfönster). Välj antal, vem som står för materialet (gör hantverkaren det: 10 % av reagenskostnaden i dricks) och hur länge du kan vänta. De får en rad i guildchatten, och ordern under Arbetsorder i Yrken, även om de är offline. Bara för Medborgare. En hammare på minimapknappen betyder att någon väntar på dig.",
		"Skatt, Yrken och Swedbank är egna fönster nu, som går att ha uppe samtidigt och flytta var för sig; de minns var du lämnade dem.",
		"Yrken (/yrken): välj yrke i listan högst upp (primära och sekundära för sig). Sökrutan bredvid söker recept i hela guildet.",
		"Min anmälan ligger nu under Inställningar.",
		"Högerklicka på minimapknappen för att välja Skatt, Yrken, Swedbank eller Bokföring (om du har det), och under strecket Nytt och Inställningar.",
		"Minimapknappen pulserar rött när din ställning är Negativ, tills skulden är betald.",
		"Recept som delas medan guildledaren är offline skickas igen vid nästa inloggning, så de når fram.",
	} },
	{ "0.22", "2026-11-08", {
		"THÖNDERSTÖRM-panelen: /skatt är nu guildets panel med flikarna Skatt, Yrken, Swedbank, Nytt och Inställningar, och blixten som porträtt.",
		"Nytt: fliken Nytt med patchnoteringar för Skatteverket och Swedbank, efter datum. Öppnas av sig själv en gång efter en uppdatering (/skatt nytt).",
		"Versioner: se vilken version av Skatteverket och Swedbank varje medlem kör. Gamla versioner i rött. Den som saknar Skatteverket står med för sig.",
		"Minimapknapp: blixten på grå, gul eller röd bakgrund efter din ställning. Håll muspekaren över den för att se din skatt. Klicka för att öppna, högerklicka för Swedbank, Shift+dra för att flytta.",
		"Fliken Inställningar: stäng av minimapknappen eller att Nytt öppnas efter en uppdatering.",
		"Level i stället för nivå på anmälan och i Yrken.",
		"Sigillet på anmälan kunde fastna och komma ned om och om igen; nu landar det en gång.",
	} },
	{ "0.21", "2026-11-07", { "Receptfönstret liknar det riktiga: grå markering, leveln direkt efter namnet, din egen level uppdateras direkt, reagenser visas som har/behöver (0/1)." } },
	{ "0.20", "2026-11-07", { "Det valda receptet visas med namnet i sin färg. Yrkesmätaren har ram och visar level/tak." } },
	{ "0.19", "2026-11-07", { "Klicka på en medlem i ett yrke för att se deras recept i ett eget fönster som liknar yrkesfönstret: kategorier, färger, sök, reagenser och Viska." } },
	{ "0.18", "2026-11-07", { "Recepten visas i samma ordning och kategorier som i spelets fönster, med färger." } },
	{ "0.17", "2026-11-07", { "Klicka på ett namn för att se medlemmens recept, färgade efter svårighet. Ger skillpoäng markeras. Håll muspekaren över för föremålet, shift-klicka för att länka." } },
	{ "0.16", "2026-11-07", {
		"Receptsök på fliken Yrken: hitta vem i guilden som kan göra något, klicka för att viska. Offline visas i grått.",
		"Min anmälan: se och ändra din anmälan (main/alt, intressen).",
		"/skatt öppnas när du är godkänd: signerad och med rangen Medborgare.",
	} },
	{ "0.15", "2026-11-07", {
		"/skatt är nu en klassisk panel med flikarna Skatt och Yrken.",
		"Yrken visar hur många som har varje yrke.",
		"Guildbankens senast kända saldo visas överst.",
	} },
	{ "0.14", "2026-11-07", { "Yrkesraden på anmälan: \"uppdateras automagiskt! Skatteverket har koll på dig serrö!\"" } },
	{ "0.13", "2026-11-07", { "Installeras och uppdateras nu via WowUp.", "Villkor och vanliga frågor (/skatt hjälp)." } },
	{ "0.12", "2026-11-07", {
		"Anmälan till Skatteverket: signera pergamentet en gång, med namn, level, yrken och intressen. Sigill och skattenummer.",
		"Yrkesregistret (/skatt yrken), uppdateras av sig själv.",
	} },
	{ "0.11", "2026-11-06", { "Rättningar: insättningar räknas säkrare, automatisk betalning tömmer aldrig väskan, belopp skrivs som 2.5 eller 2,5 guld, köper du tillbaka hos handlaren tas skatten bort." } },
	{ "0.10", "2026-11-06", { "Några koppar räcker inte längre för God ställning. Äldsta skulden betalas först." } },
	{ "0.9", "2026-11-06", { "De tre främsta heter nu Skatteverkets favorit #1–3." } },
	{ "0.8", "2026-11-06", { "Första /skatt öppnar fönstret direkt." } },
	{ "0.7", "2026-11-06", { "Alla känns igen på hela namnet (för- och efternamn)." } },
	{ "0.6", "2026-11-06", { "All text på svenska." } },
	{ "0.5", "2026-11-06", { "Belopp går bara till guildledaren. Guildkanalen visar bara ställning." } },
	{ "0.4", "2026-11-06", { "Skatteadel till de längsta perioderna i god ställning." } },
	{ "0.3", "2026-11-06", { "Medlemmar ser allas ställning, utan belopp." } },
	{ "0.2", "2026-11-06", { "Fönstret /skatt: din skatt, ställning, topp 3 och påminnelser. Din historik följer med mellan versioner." } },
	{ "0.1", "2026-11-06", { "Första versionen: skatt på lootat guld och försäljning hos handlare och auktionshuset, betalas in när du öppnar guildbanken." } },
}

local GOLD, WHITE, RED, GREY = "|cffffd100", "|cffffffff", "|cffff4040", "|cff808080"

local page

-- Each version's lines grouped by panel (Zach 10/11: everything stood under
-- Skatteverket though several lines were about Bokföring and the rest).
-- A line that starts with a panel's name ("Bokföring 0.6: ...",
-- "Arbetsorder: ...") goes under that panel, the version in its heading;
-- other lines are Skatteverket's own.
local PANELS = { "Skatteverket", "Yrken", "Arbetsorder", "Swedbank", "Bokföring" }
local PANEL_COLOUR = "|cff80c0ff"

local function Grouped(lines)
	local groups, heads = {}, {}
	for _, line in ipairs(lines) do
		local panel, extra, rest
		for _, p in ipairs(PANELS) do
			if line:sub(1, #p) == p then
				extra, rest = line:sub(#p + 1):match("^([^:]*):%s*(.+)$")
				if rest then panel = p break end
			end
		end
		if panel then
			local version = extra:match("^%s*(%d[%d%.]*)%s*$")
			-- The newest version named for the panel in this release.
			local had = heads[panel] and heads[panel]:match("(%d[%d%.]*)$")
			if version then
				if not had or ns.VersionNumber(version) > ns.VersionNumber(had) then heads[panel] = panel .. " " .. version end
			elseif extra:match("%S") then
				rest = extra:match("^%s*(.-)%s*$") .. ": " .. rest
			end
		else
			panel, rest = "Skatteverket", line
		end
		groups[panel] = groups[panel] or {}
		-- "fliken Today ..." reads as the start of a sentence.
		table.insert(groups[panel], (rest:gsub("^%l", string.upper)))
	end
	local out = {}
	for _, p in ipairs(PANELS) do
		if groups[p] then table.insert(out, { head = heads[p] or p, lines = groups[p] }) end
	end
	return out
end

local function Notes()
	-- Both lists are newest first; merge by date, Skatteverket first on the same day.
	local all = {}
	for i, v in ipairs(ns.NOTES) do table.insert(all, { "Skatteverket", v, 0, i }) end
	for i, v in ipairs(SwedbankPanel and SwedbankPanel.NOTES or {}) do table.insert(all, { "Swedbank", v, 1, i }) end
	table.sort(all, function(a, b)
		if a[2][2] ~= b[2][2] then return a[2][2] > b[2][2] end
		if a[3] ~= b[3] then return a[3] < b[3] end
		return a[4] < b[4]
	end)
	local out = {}
	for _, e in ipairs(all) do
		local v = e[2]
		table.insert(out, string.format("%s%s %s|r  %s%s|r", GOLD, e[1], v[1], GREY, v[2]))
		local groups = e[1] == "Skatteverket" and Grouped(v[3]) or { { lines = v[3] } }
		for _, g in ipairs(groups) do
			-- A heading only when the version touches more than its own panel.
			if g.head and (#groups > 1 or g.head ~= "Skatteverket") then table.insert(out, PANEL_COLOUR .. "  " .. g.head .. "|r") end
			for _, line in ipairs(g.lines) do table.insert(out, WHITE .. (g.head and "    - " or "- ") .. line .. "|r") end
		end
		table.insert(out, " ")
	end
	return table.concat(out, "\n")
end

-- Everyone in the guild now, grouped by version, newest first; offline in
-- grey, versions older than the newest seen in red (Zach 8/11). field is
-- "version", "swed" or "bok"; Swedbank's own Nytt tab reads this same data.
function ns.VersionGroups(field)
	local db, groups, newest = ns.db, {}, 0
	local online = {}
	local roster = {}
	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
		name = ns.Short(name)
		if name then
			roster[name] = true
			online[name] = isOnline and true or false
		end
	end
	if not next(roster) then return {}, 0 end
	for name in pairs(roster) do
		local m = db.members[name]
		local v = m and m[field]
		if name == ns.Me() then v = field == "version" and ns.VERSION or field == "bok" and ns.BokforingVersion() or ns.SwedbankVersion() end
		if not m and name ~= ns.Me() then v = "none" elseif not v or v == "" then v = "?" end
		groups[v] = groups[v] or {}
		table.insert(groups[v], name)
		newest = math.max(newest, ns.VersionNumber(v))
	end
	local order = {}
	for v, names in pairs(groups) do
		table.sort(names, function(a, b)
			if online[a] ~= online[b] then return online[a] end
			return a < b
		end)
		table.insert(order, { version = v, names = names, old = ns.VersionNumber(v) > 0 and ns.VersionNumber(v) < newest })
	end
	-- Real versions newest first, then "-" (not running), "?" (not known yet), "none".
	local LAST = { ["-"] = 1, ["?"] = 2, none = 3 }
	table.sort(order, function(a, b)
		local la, lb = LAST[a.version] or 0, LAST[b.version] or 0
		if la ~= lb then return la < lb end
		return ns.VersionNumber(a.version) > ns.VersionNumber(b.version)
	end)
	for _, g in ipairs(order) do
		for i, name in ipairs(g.names) do
			if not online[name] then g.names[i] = GREY .. name .. "|r" end
		end
	end
	return order
end

-- One block per addon; red for old versions and for missing addons.
local LABELS = {
	version = { title = "Skatteverket", ["?"] = "Okänd version", none = "Saknar Skatteverket" },
	swed = { title = "Swedbank", ["-"] = "Saknar Swedbank", ["?"] = "Okänd (Skatteverket 0.21 eller äldre)", none = "Saknar Skatteverket" },
	bok = { title = "Bokföring", ["-"] = "Saknar Bokföring", ["?"] = "Okänd (Skatteverket 0.25 eller äldre)", none = "Saknar Skatteverket" },
}

local function Block(field)
	local labels = LABELS[field]
	local out = { GOLD .. "Versioner av " .. labels.title .. "|r  " .. GREY .. "(grått: offline, senast kända version)|r" }
	for _, g in ipairs(ns.VersionGroups(field)) do
		local label = labels[g.version] or (labels.title .. " " .. g.version)
		local colour = (g.old or g.version == "none" or g.version == "-") and RED or WHITE
		table.insert(out, string.format("%s%s (%d):|r %s", colour, label, #g.names, table.concat(g.names, ", ")))
	end
	table.insert(out, " ")
	return table.concat(out, "\n")
end

local function Versions()
	if #ns.VersionGroups("version") == 0 then return GREY .. "Guildlistan har inte laddats än.|r\n " end
	return Block("version") .. "\n" .. Block("swed") .. "\n" .. Block("bok")
end

function ns.BuildNews(parent)
	page = parent
	local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 24, -70)
	scroll:SetPoint("BOTTOMRIGHT", -40, 34)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT")
	text:SetJustifyH("LEFT")
	text:SetSpacing(2)
	page.scroll, page.child, page.text = scroll, child, text
end

function ns.LayoutNews(width)
	if not page then return end
	page.child:SetWidth(width - 70)
	page.text:SetWidth(width - 74)
end

function ns.RefreshNews()
	if not page or not page:IsShown() then return end
	page.text:SetText(Versions() .. "\n" .. Notes())
	page.child:SetHeight(page.text:GetStringHeight() + 8)
end

-- What the popup has been shown for: both versions, so an update of either opens it.
local function Seen()
	return ns.VERSION .. "/" .. ns.SwedbankVersion()
end

-- Once per new version, for those who have signed; out of combat, and
-- with a chat line in case the window is closed at once (Zach 8/11).
function ns.NewsAtLogin()
	local char = ns.char
	if not char or char.seenNotes == Seen() or not ns.InOurGuild() then return end
	if not char.reg or ns.db.showNews == false then
		char.seenNotes = Seen()
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		C_Timer.After(10, ns.NewsAtLogin)
		return
	end
	char.seenNotes = Seen()
	ns.Print(ns.GUILD .. ": Skatteverket " .. ns.VERSION .. ", Swedbank " .. ns.SwedbankVersion() .. " – se vad som är nytt: /skatt nytt")
	ns.ShowTab(4)
end
