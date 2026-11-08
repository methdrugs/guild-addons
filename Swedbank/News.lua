-- Swedbank's patch notes (Zach 8/11). They show on the Nytt tab of the
-- THÖNDERSTÖRM panel, merged by date with Skatteverket's, with everyone's
-- Swedbank version; Skatteverket draws that tab (News.lua there).

-- Newest first. Written for members: no amounts, nothing about who borrowed.
SwedbankPanel.NOTES = {
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
