-- The THÖNDERSTÖRM panel's Nytt tab (Zach 8/11): who runs which version of
-- Skatteverket and of Swedbank, then the patch notes of both by date,
-- newest first, so one addon's history never buries the other's. Open to everyone in the
-- guild, signed or not. After an update it opens by itself once, for those
-- who have signed, unless turned off under Inställningar; a first-time
-- user does not get it.

local _, ns = ...

-- Newest first. Written for members: no amounts, nothing leader-only.
-- after (Zach 10/11, every release from 0.26 on): "reload" when /reload is
-- enough, "restart" when the release adds files the game only reads at
-- start; shown in red under the version.
ns.NOTES = {
	{ "0.34", "2026-11-12", after = "restart", {
		"Folkvald representant 0.4: guildets ledare, valda av medlemmarna (högerklicka blixten, överst under THÖNDERSTÖRM). Varje roll beskrivs med vad den innebär; titeln är ett exempel och du får föreslå en bättre. Sök med en motivering på högst 200 tecken, en ansökan åt gången. Har någon redan rollen kan du utmana; godtar guildledaren utmaningen röstar guildet i 3 dagar.",
		"Folkvald representant 0.4: Kontakta mig! på varje rad öppnar ett ärende i Kontakta oss! till den som har rollen och guildledaren (till guildledaren om rollen är vakant).",
		"Folkvald representant: rösterna är hemliga, en röst per konto och roll. Guildledaren ser bara summan, aldrig vem som röstat på vem. Kandidaterna, deras motiveringar och resultatet är officiell information för alla medlemmar.",
		"Statligt socialbidrag (fliken med väskan i Skatt, öppen för alla i guildet): under nivå 15 kan du få upp till 3 väskor med 6 platser, från nivå 15 upp till 3 väskor med 8 platser, per konto. De kommer med posten.",
		"Kontakta oss! (högerklicka blixten): skicka en bugg, en förbättring, en idé till en helt ny addon eller något annat, för den tjänst det gäller. Det blir ett ärende med nummer som guildledaren och den som har rollen för tjänsten läser (Swedbank – VD för Swedbank och så vidare). Ni skriver fram och tillbaka i ärendet, och du, rollen eller guildledaren kan stänga det och öppna det igen. Mina ärenden visar ärenden från alla dina karaktärer; byter rollen ägare följer de öppna ärendena och de som stängts senaste 30 dagarna med.",
		"Nytt: varje version heter THÖNDERSTÖRM, med Skatteverket, Yrken, Arbetsorder, Folkvald representant, Swedbank och Bokföring och deras egna versioner under. Överst står vilka versioner du kör.",
		"Arbetsorder 0.4: under reagenserna i någons receptfönster, och när du beställer, står vad materialet kostar att köpa och skicka (porto 30c per hög). Bocka i Använd mina material så räknas det du redan har i väskorna bort. Råvaror räknas när hantverkaren levlar på dem, inte när yrket är på 300.",
		"Folkvald representant: alla söker, även den som har en roll i dag. En roll som ingen söker blir vakant när ansökan stänger.",
		"Arbetsorder: rutan Visa avslutade går att bocka i igen.",
		"Folkvald representant: du har din roll tills du avgår (knappen Avgå på din rad) eller förlorar en utmaning. Avgår någon får guildet veta det och platsen kan sökas.",
		"Yrken 0.4: sökrutan heter Sök i alla yrken och hittar också recept som använder det du söker som reagens, markerade (reagens).",
	} },
	{ "0.33", "2026-11-11", after = "reload", {
		"/skatt version visar vilka versioner du kör, och om någon i guildet har en nyare och vem.",
		"Arbetsorder: accepterar du en order där du löser materialet gör Bokföring en inköpslista i Auctionator med det som inte redan finns i dina väskor, och ordern syns under Making now tills den är klar. Köpen räknas som Arbetsordrar i Bokförings historik.",
	} },
	{ "0.32", "2026-11-11", after = "reload", {
		"Nytt: har någon i guildet en nyare version än du visar blixten en liten lapp, samma som Nytt-fliken, med Uppdatera och vilka versioner när du håller muspekaren över,, och Nytt visar dem överst, tills du har uppdaterat. Vem som kör vilken version har en egen flik, Versioner, i Nytt.",
		"Arbetsorder: listan visar bara pågående ordrar. Avböjda, avbrutna, utgångna och de som varit Klar i ett dygn syns med rutan Visa avslutade.",
		"Arbetsorder: avböjer någon din order, eller går den ut, syns det på blixtens ! tills du har öppnat ordern.",
		"Skatt: depositionen du får tillbaka när något säljs på AH räknas inte längre som inkomst. Det är dina egna pengar. Tack @Tungan Lingonsson som hittade det!",
		"Bokföring 0.6.4: vinsten räknar nu med guildskatten, inte bara AH:s 5 %. Försäljningar i historiken räknas utan depositionen och efter skatt. Tack igen, Tungan!",
		"Bokföring 0.6.4: en vara som en försäljare bara har några få av räknas inte längre som försäljarvara, och raderna \"vendor:\" säger vilken försäljare och var. Sparade försäljarpriser har nollställts en gång; de kommer tillbaka när du öppnar försäljarna.",
		"Bokföring 0.6.4: en arbetsorder där du skickar materialet ligger kvar i Making now tills allt är skickat, inte bara köpt.",
		"Bokföring 0.6.4: History räknar Net som inkomst minus vad de sålda kostade, så det du inte sålt än syns inte som förlust. Ny kolumn Stock: det du har i väskor, bank och på AH till dagens pris, och överst Potential: inkomst + lager - utgifter.",
		"Bokföring 0.6.4: sökrutan föreslår namn när du skriver (\"swi\" ger Swiftness Potion), med om du kan receptet, kan lära dig det eller behöver mer skill. Välj med piltangenterna och Enter, eller klicka. Sökningen hackar inte längre när inget hittas.",
		"Bokföring 0.6.4: håll muspekaren över något du har craftat (i väskan eller på AH) så visar Bokföring vad det kostade, vad du får för det på AH nu efter AH:s 5 % och guildskatten, vinsten och lägsta pris utan förlust (Break-even).",
	} },
	{ "0.31", "2026-11-11", after = "reload", {
		"Arbetsorder: en order kan säga vem som ska få det färdiga, om det inte är den som beställde. Det står i ordern (Skicka färdiga till), i raden i guildchatten och i brevet med materialet. Som hantverkare har du då en knapp Fyll i brev i ordern: brevet adresseras till mottagaren och det färdiga läggs i. Du trycker Send själv, och ordern blir Klar av sig själv när allt det färdiga har gått iväg.",
		"Bokföring 0.6.3: kan ge Skatteverket priser på material. Ett fel vid AH-skanning är rättat (en vara som inte fanns ute tidigare samma dag).",
		"Bokföring 0.6.3: klara inköpslistor tas bort ur Auctionator av sig själva: allt köpt, allt craftat, Done i Making now, eller äldre än tre dagar. Vill du behålla dem, kryssa ur rutan under Inställningar.",
	} },
	{ "0.30", "2026-11-10", after = "reload", {
		"Arbetsorder: avbryter du en order räknas materialet du redan skickat på dina andra öppna ordrar till samma hantverkare som behöver det. Listan visar bara förnamnet; hela namnet syns när du håller muspekaren över raden.",
		"Arbetsorder: material i ett brev som Fyll i brev har fyllt i räknas på den ordern först, inte på en äldre order till samma hantverkare.",
		"Arbetsorder: gör hantverkaren själv en av reagenserna och ger det fortfarande poäng (orange, gul eller grön för hen), föreslår ordern att du skickar råvarorna i stället, till exempel Wool Cloth i stället för Bolt of Woolen Cloth. Rutan är ikryssad från början och går att kryssa ur. Fyll i brev, stegen, det som räknas som skickat och Bokförings inköpslista går då efter råvarorna, och ordern visar vad hantverkaren gör först.",
		"Arbetsorder: när du själv skickar materialet har ordern en knapp Fyll i brev. Öppna en brevlåda, öppna ordern och tryck: brevet adresseras till hantverkaren och det material som saknas läggs i, delat till exakt antal. Du kontrollerar och trycker Send själv. Får inte allt plats i ett brev (12 saker), skicka det och tryck igen för nästa; det som inte finns i väskorna står i chatten.",
		"Arbetsorder: listan i kolumner, med steg i färg: Beställd (grått), Köpt (gult, allt material ligger i dina väskor), Skickat (blått, hos hantverkaren Mottaget), Klar (grönt). Hantverkarens namn blir grönt när ordern är accepterad. Står hantverkaren för materialet: Beställd, Accepterad, Klar.",
		"Yrken: fönstret med någons recept har samma mått som spelets eget yrkesfönster: smalare, den blå färdighetsraden som i originalet, rader och reagensrutor i samma storlek.",
		"Arbetsorder: Avbryt frågar först, så att ett felklick inte avbryter något. Avböj en accepterad order gör du inne i ordern.",
		"Rutan om en ny version visas först när den finns i WowUp, inte redan när guildledaren har testat den.",
		"Bokföring 0.6.2: myntet för att hämta sålda auktioner syns bara i inkorgen, inte under Send Mail.",
	} },
	{ "0.28", "2026-11-10", after = "reload", {
		"Ställningen räknas nu i speltid, inte i dagar: obetald skatt åldras bara medan du är inloggad, så en ledig helg kostar ingenting. God: upp till 8 timmars speltid med obetald skatt. Neutral: 8 till 12 timmar. Negativ: mer än 12 timmar.",
		"Alla dina karaktärer på samma konto räknas tillsammans: den bästa ställningen gäller för alla, så länge den karaktären har betalat skatt någon gång. En alt drar aldrig ned din main.",
		"Håll muspekaren över blixten för att se hur mycket speltid som är kvar innan ställningen sjunker.",
		"Alla börjar från noll med den nya ställningen; ingen blir Neutral eller Negativ av bytet. Skatteverkets favorit räknas också i speltid och börjar om.",
		"Ett ? uppe till höger i varje fönster visar alla kommandon; klicka för att få dem i chatten.",
		"Rutan om en ny version säger i rött om du ska skriva /reload eller starta om spelet efter uppdateringen i WowUp, även om du hoppar över flera versioner.",
		"Nytt visar under varje version, i rött, om den kräver /reload eller omstart, och delar upp det nya per fönster.",
		"Bokföring 0.6.1: knappen Read recipes längst ned (där Scan AH satt) läser in alla recept och receptföremål i spelet en gång, så att All recipes, Can learn och Need skill har något att visa; den blir grå när det är klart, och görs också av sig själv en minut efter inloggning. Priser och vad som säljer kommer från Auctionators skanningar.",
		"Bokföring 0.6.1: kryssar du Can learn eller Need skill visas även recept vars föremål inte finns på AH.",
		"Bokföring: ett ? uppe till höger visar Bokförings kommandon.",
	} },
	{ "0.27", "2026-11-10", after = "restart", {
		"Arbetsorder: klicka på en order för att öppna den. Där står vad som är beställt (klicka på föremålet för att se det, shift-klicka för att länka det), antal, när den beställdes, vems material, dricks, reagenser, hur länge beställaren kan vänta och kommentaren. En ny order accepteras eller avböjs inne i ordern, så att den blir läst först.",
		"Arbetsorder: material du skickar till hantverkaren med post eller byte räknas in på ordern, så att ni båda ser material skickat (grönt), hur långt det har kommit eller inte skickat (rött).",
		"Om någon lämnar guildet medan du är offline säger Skatteverket till när du loggar in. /skatt lämnat visar de senaste 30 dagarna.",
		"Bokföring 0.6: fliken Today överst visar högst fem saker att göra just nu för att tjäna guld: vad som lönar sig att tillverka och hur många, vad du har i väskan att lägga upp, och efter en vecka med priser även fynd att köpa och sälja igen, och vilken tid på dygnet det brukar säljas dyrast. Allt inom en dagsbudget (/bok budget 50g, annars en fjärdedel av ditt guld); knappen +25% of my gold höjer dagens budget.",
		"Bokföring 0.6: kryssrutan Level up sorterar recepten efter vad varje skillpoäng kostar eller ger i guld, och visar hur många du ska tillverka tills receptet blir grönt. Tillsammans med Can learn syns även recept du kan köpa och lära dig.",
		"Bokföring: vanliga reagenser från försäljare (tråd, färg, flaskor, flux med mera) hamnar på försäljarlistan, inte på Auctionator-listan.",
	} },
	{ "0.26", "2026-11-10", after = "restart", {
		"Ny version: kommer det en nyare Skatteverket, Swedbank eller Bokföring visas en ruta när du loggar in, med vad som är nytt att hämta. Uppdatera i WowUp.",
		"Nytt visar också vem som kör vilken version av Bokföring.",
		"Bokföring 0.4: fliken Market visar priset över tid för det du har tillverkat, som en kurva genom det lägsta priset vid varje skanning de senaste 30 dagarna, och vilka veckodagar som brukar ligga högt eller lågt.",
		"Bokföring: kolumnen Trend visar om priset går upp eller ned, och sökrutan hittar recept, föremål och reagenser.",
		"Bokföring: högerklicka på ett recept och välj Watch för att följa priset på något du inte har tillverkat. Högerklicka i Market för att sluta följa.",
		"Bokföring: History räknade fel på sålda saker när flera såldes för samma pris inom samma timme; det är rättat. Vill du börja om från noll: skriv /bok reset history. History visar nu också hur många du har lagt upp på AH (Posted) och hur många som ligger kvar (On AH).",
		"Bokföring 0.5: kryssrutorna Can learn och Need skill visar recepten du inte har lärt dig på den här karaktären, med skillen de kräver, lägst först: vad du kan lära dig nu och vad du ska sikta på. Klicka på ett recept för att se var det finns: tränare, försäljare (namn och zon) eller drop, och priset på AH.",
		"Bokföring 0.5: kolumnen Skill visar i färg hur receptet är för dig; för recept du inte har lärt dig är färgen uppskattad (~), och blir säkrare när guildmedlemmar har receptet. Högerklicka på ett recept du inte har och välj Buy för att lägga själva receptet på en Auctionator-lista.",
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
local PANELS = { "Skatteverket", "Yrken", "Arbetsorder", "Folkvald representant", "Swedbank", "Bokföring" }
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

-- One release of the pack per Skatteverket version, headed THÖNDERSTÖRM
-- (Zach 12/11). A Swedbank version goes under the first release on or
-- after its date, the pack being what ships; its lines read "Swedbank
-- 0.12: ...", so it gets its heading with the version.
local function Notes()
	local releases = {}
	for i = #ns.NOTES, 1, -1 do
		local v = ns.NOTES[i]
		table.insert(releases, 1, { version = v[1], date = v[2], after = v.after, lines = { unpack(v[3]) } })
	end
	local swed = SwedbankPanel and SwedbankPanel.NOTES or {}
	for i = #swed, 1, -1 do
		local s = swed[i]
		local home
		for k = #releases, 1, -1 do
			if releases[k].date >= s[2] then home = releases[k] break end
		end
		home = home or releases[1]
		if home then
			for _, line in ipairs(s[3]) do table.insert(home.lines, "Swedbank " .. s[1] .. ": " .. line) end
			if s.after == "restart" or (s.after == "reload" and not home.after) then home.after = s.after end
		end
	end
	local out = {}
	for _, r in ipairs(releases) do
		table.insert(out, string.format("%s%s %s|r  %s%s|r", GOLD, ns.GUILD, r.version, GREY, r.date))
		-- What to do after updating, in red (Zach 10/11).
		if r.after == "restart" then
			table.insert(out, RED .. "  EFTER UPPDATERINGEN: STARTA OM SPELET HELT (/reload räcker inte den här gången)|r")
		elseif r.after == "reload" then
			table.insert(out, RED .. "  EFTER UPPDATERINGEN: SKRIV /reload|r")
		end
		for _, g in ipairs(Grouped(r.lines)) do
			local head = g.head == "Skatteverket" and ("Skatteverket " .. r.version) or g.head
			table.insert(out, PANEL_COLOUR .. "  " .. head .. "|r")
			for _, line in ipairs(g.lines) do table.insert(out, WHITE .. "    - " .. line .. "|r") end
		end
		table.insert(out, " ")
	end
	return table.concat(out, "\n")
end

-- What this client runs, every part with its number (Zach 12/11).
local function Running()
	local parts = { "Skatteverket " .. ns.VERSION }
	for _, p in ipairs(ns.PARTS) do table.insert(parts, p.name .. " " .. p.version) end
	table.insert(parts, "Swedbank " .. ns.SwedbankVersion())
	local bok = ns.BokforingVersion and ns.BokforingVersion()
	if bok and bok ~= "" and bok ~= "-" then table.insert(parts, "Bokföring " .. bok) end
	return string.format("%sDu kör %s %s:|r %s%s|r\n \n", GOLD, ns.GUILD, ns.VERSION, WHITE, table.concat(parts, ", "))
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

-- Page 4 Nytt: what to update, then the notes; page 10 Versioner: who
-- runs what, for everyone (Zach 11/11).
local shownPage
function ns.RefreshNews(n)
	if not page or not page:IsShown() then return end
	if n ~= shownPage then
		shownPage = n
		page.scroll:SetVerticalScroll(0)
	end
	if n == 10 then
		page.text:SetText(Versions())
		page.child:SetHeight(page.text:GetStringHeight() + 8)
		return
	end
	-- What this client is behind on, first (Zach 11/11). Its notes are in
	-- the new version, so only the numbers here.
	local behind = ns.Behind and ns.Behind() or {}
	local top = ""
	if #behind > 0 then
		top = RED .. "Uppdatera:|r\n" .. WHITE .. "    " .. table.concat(behind, "\n    ") .. "|r\n"
			.. GREY .. "Uppdatera guild-addons i WowUp och skriv /reload. Vad som är nytt står här efteråt.|r\n \n"
	end
	page.text:SetText(top .. Running() .. Notes())
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
