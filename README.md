# THÖNDERSTÖRM-addons

Tre addons för WoW Forever:

- **Skatteverket** (guildskatt, `/skatt`) med **Yrken** (`/yrken`): vem i guildet som har vilket yrke, receptsök och arbetsordrar.
- **Swedbank** (guildlån, `/swedbank`).
- **Bokföring** (`/bok`): vilka av dina recept som tjänar mest på auktionshuset och faktiskt säljer, inköpslistor till Auctionator och vad ditt craftande verkligen har gett. På engelska. **Kräver [Auctionator](https://www.curseforge.com/wow/addons/auctionator)**; utan det är Bokföring avstängt.

Skatteverket och Swedbank fungerar bara för medlemmar i THÖNDERSTÖRM; för alla andra gör de ingenting.

## Installera med WowUp (rekommenderas)

1. Installera WowUp-CF (https://wowup.io) om du inte redan har det, och välj WoW Forever.
2. Klicka på **Get Addons** och sedan **Install from URL**.
3. Klistra in `https://github.com/methdrugs/guild-addons` och klicka **Import**, sedan **Install**.
4. För Bokföring: sök på **Auctionator** under Get Addons och installera det också.
5. Klart. WowUp uppdaterar addonsen själv när en ny version kommer.

## Installera för hand

Ladda ner zip-filen under **Releases** till höger, stäng WoW och packa upp. Kopiera mapparna Skatteverket, Swedbank och Bokforing direkt till `Interface\AddOns` i mappen `_forever_`. Vid en uppdatering: ta bort de gamla mapparna och kopiera in de nya.

Din skattehistorik, dina lån och din bokföring sparas i mappen WTF, inte i addon-mapparna, så de finns kvar vid uppdateringar. Ta aldrig bort mappen WTF.
