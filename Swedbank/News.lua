-- Swedbank's patch notes (Zach 8/11). They show on the Nytt tab of the
-- THÖNDERSTÖRM panel, merged by date with Skatteverket's, with everyone's
-- Swedbank version; Skatteverket draws that tab (News.lua there).

-- Newest first. Written for members: no amounts, nothing about who borrowed.
SwedbankPanel.NOTES = {
	{ "0.12", "2026-11-10", after = "reload", { "Guildledaren ser direkt när en betalning till guildbanken väntar på att kontrolleras." } },
	{ "0.11", "2026-11-10", after = "restart", { "Ny ränteregel: räntan räknas per påbörjad vecka, från dagen efter att guldet skickats. Betalar du samma dag kostar det inget; dag 1-7 en veckas ränta, dag 8-14 två, och så vidare. Brevet med lånet förklarar det.", "Mina lån: klicka på ett lån för att se allt om det: vad du lånat, räntan, vad du ska betala nu, när nästa veckas ränta läggs på och sista betaldag.", "Sista betaldag bestäms av guildledaren när lånet godkänns; datumet du skriver i ansökan är ett önskemål.", "Önskad ränta: skriv vilken ränta du hoppas på, minst 3 %. Guildledaren godkänner den, eller erbjuder en annan ränta som du accepterar eller avböjer under Mina lån. Accepterar du bekräftar ledaren lånet; avböjer du avslutas ansökan. Ett erbjudande gäller i 3 dagar.", "Guildledaren ser väntande låneansökningar och försenade lån som ett gult ! på blixten vid minikartan." } },
	{ "0.10", "2026-11-08", { "Swedbank är nu en flik i THÖNDERSTÖRM-panelen, med sidorna Ansök och Mina lån på sidan. Öppnas med /swedbank eller högerklick på blixten.", "Ansöka kräver att du är godkänd medborgare och har God ställning hos Skatteverket. Mina lån och återbetalning kräver inte God ställning, och den som har ett lån igång ser alltid Mina lån." } },
	{ "0.9", "2026-11-07", { "Rättade ett fel som hindrade medlemsfönstret från att öppnas." } },
	{ "0.8", "2026-11-06", { "Rättningar: en återbetalning i taget, Mina lån går att scrolla med öppna lån först, omöjliga datum (31/02) nekas, räntan tar komma." } },
	{ "0.7", "2026-11-06", { "Betalningar till guildbanken kontrolleras innan de räknas (Betalning kontrolleras)." } },
	{ "0.6", "2026-11-06", { "Ledaren ser låntagarnas insättningar i bankloggen. Låntagaren ser Betalning väntar på ledaren." } },
	{ "0.5", "2026-11-06", { "Betala tillbaka direkt till guildbanken från Mina lån." } },
	{ "0.4", "2026-11-06", { "Alla känns igen på hela namnet." } },
	{ "0.3", "2026-11-06", { "All text på svenska." } },
	{ "0.2", "2026-11-06", { "Varning till ledaren när någon som redan har ett lån ansöker." } },
	{ "0.1", "2026-11-06", { "Första versionen: ansök om lån i /swedbank, bara ledaren ser vem som lånat, enkel veckoränta." } },
}
