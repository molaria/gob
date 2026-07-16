# Gott och Blandat (gob.betelkyrkan.se)

Sajt för kören Gott och Blandat vid Equmeniakyrkan Betel i Örebro (fram till 2026 kallad Betelkyrkan - domänen gob.betelkyrkan.se lever kvar). Drupal 11, Composer-hanterad. Publik presentationssida plus intranät för ca 40 körmedlemmar: kalendarium med anmälan, notregister med lyssning, medlemsmatrikel, fikalista.

## GRUNDBULT: extrem enkelhet för medlemmarna

Många av körens medlemmar är ovana vid webben. Allt som byggs ska vara omedelbart begripligt för en inloggad körmedlem: vad man ska göra och hur, utan instruktioner.

- Kärnfunktioner (anmälan, avanmälan, ändra besked) ska synas och gå att använda direkt - aldrig gömda bakom klick, utfällning, menyer eller extra steg.
- Knappar säger vad som händer ("Kommer", "Kommer inte"), aldrig tekniska ord.
- Status ska alltid synas: medlemmen ska se sitt eget läge (Anmäld / Avanmäld / Ej svarat) utan att göra något.
- Stora klickytor, tydliga färger enligt designsystemet, aldrig färg ensam som betydelsebärare.
- Vid varje ny funktion: fråga "förstår en webbovan körmedlem detta på tre sekunder?" Om inte, gör om.

Detta är en grundbult i allt som byggs på sajten och väger tyngre än teknisk eller visuell elegans.

## Miljö

- Lokal utveckling via DDEV. Kör alltid drush och composer genom DDEV: `ddev drush ...`, `ddev composer ...`.
- Docroot: `web/`. Lokal adress: https://gob.ddev.site
- Produktion: `mol@e-pro.se -p 1369`, `/var/www/gob.betelkyrkan.se/` (äldre layout, migreras till `web/`-docroot vid driftsättning). Produktion rörs aldrig härifrån utan uttrycklig överenskommelse.
- Databas lokalt: MySQL 8.4, collation `utf8mb4_sv_0900_ai_ci` (`.ddev/mysql/collation.cnf`).
- Privata filer lokalt: `../private/` (utanför docroot, gitignorerad). På servern `/var/www/private/`.

## Konfiguration

- Konfigurationen är exporterad till `config/sync` och versionshanteras.
- Efter varje ändring av innehållstyper, fält, vyer eller block: kör `ddev drush config:export` och commita YAML-diffen.
- Inga ändringar i datamodellen utan motsvarande config-export.
- Engångsskript läggs i `_import/` (gitignorerad) och körs med `ddev drush php:script`.

## Arbetssätt

- Visa förslag och invänta godkännande innan större saker implementeras. Små granskbara steg, en sak i taget. Inga oombedda förbättringar.
- Innan ändringar som rör befintligt innehåll: ta en ögonblicksbild med `ddev snapshot`.
- Verifiera i webbläsaren efter varje ändring, gärna mot live-DOM, inte bara skärmdump.

## Kodstil

- Eget tema `gob` (`web/themes/custom/gob/`), genererat från starterkit som systersajten noter. Designtokens i `css/tokens.css`, komponenter i `css/components/`. Ingen Bootstrap, ingen Tailwind.
- Egen CSS och vanilla JS (Drupal.behaviors där BigPipe kräver det). Rubriker: Nunito 800, självhostad.
- Engelska kommentarer och identifierare i kod. Svenska för gränssnittstext och innehåll.
- Typografi i text: aldrig em-streck. Tankstreck (–) för intervall, annars bindestreck.

## Kända fallgropar (Drupal 11)

- Twig: `.entity` på ett TOMT referensfält returnerar värdnoden via `getEntity()` - använd `.0.entity`. Samma mönster för `.value` som kan ge en array - använd `.0.value`.
- Views-fältet `flag_flagged` renderar strängen `0`/`1`, aldrig tom - jämför mot `'1'`.
- Twig-sandboxen tillåter inte `.count` på fältlistor - använd `|length`.
- Datum lagras i UTC; konvertera alltid via Europe/Stockholm vid skapande (sommartid/vintertid skiljer).

## Klart (hösten 2026-arbetet)

- Eget tema `gob` med designsystem enligt godkänd skiss, Nunito självhostad.
- Kalendariet: händelsekort med accordion, trelägesanmälan i hopfällt läge ("Kommer du? Ja/Nej", statuschip + Ändra), fika- och programlistor, sluttidsfält (time_field).
- Apple-lik navigering: tunn blur-list, rullgardiner utan symboler som öppnas vid hover/fokus, hamburgarmeny på mobil, välkomstrad för inloggade.
- Admin-menyn dold och åtkomstskyddad för vanliga medlemmar (epost/telefon-vyerna kräver administrator eller kalendarium_admin).
- Matrikeln: klientsökning, sortering, kombinerat löpnummer (13:1).
- Städat: sticky-modulen avinstallerad, asset injector-snuttarna avstängda.

## Anmälan: trelägesmodellen (klar 2026-07-16)

- Modulen `gob_attendance`: tabellen `gob_attendance` (uid, nid, status attending/declined, changed; ingen rad = ej svarat), service `gob_attendance.manager`, rutt `/anmalan/{node}/{ja|nej}` (inloggning + CSRF-token, kräver anmälningsbar kalendariumnod) med bekräftelsemeddelanden.
- Vyn kalendarium är rensad från flaggfält/relationer och kör cache none (raderna varierar per användare); status och svarslänkar injiceras i preprocess från modulen.
- Närvarosidan (`gob_attending`) portad till nya tabellen; `FlagStatusResolver` borttagen.
- 939 flaggningar migrerade till 853 besked (583 anmälda, 270 avanmälda) med samma resolverlogik, stickprovsverifierat inklusive ändringspar.
- Flaggdata och flag-modulen ligger KVAR orörda som säkerhetsnät. Städkandidater när modellen bevisat sig i drift: modulerna flag och kalendarium_deltagande, de fyra flaggorna, flaggningstabellens data.

## Pågående och planerat

- Notregistret omdesignat 2026-07-16: katalograder med snabbsök (`notes-filter.js`). Titeln länkar till redigeringsformuläret för behöriga (edit_node-fältet måste vara exclude: false - exkluderade vyfält når inte mallen). Ljudfiler är dolda bakom Lyssna-knappen som öppnar stämmixern (`player.js` + `player.css`): dialog-popup med Web Audio, samtidig uppspelning, volym/Tyst/Solo per stämma, spellista som JSON i knappen i nodens fältordning, fullskärm på mobil. Gamla vue-audio-mixer-snuttarna (unpkg-CDN) är rensade ur 13 musiknoders brödtext. Städkandidater: views_accordion, jquery_ui_accordion, jquery_ui.
- Publika startsidan ombyggd 2026-07-16 (`page--front.html.twig` + `hero.css`): säljande hero (mottot som H1, "Gör din röst hörd" är bara byline i loggan), porträttplats som väntar på `web/themes/custom/gob/images/mats-olof.jpg` (döljs tills filen finns), CTA till Bilda. Sektionen "Här hör du oss nästa gång" hämtas ur vyn `konserter`: kalendarieposter med bocken `field_publik` visas för alla (node access-omskrivning avstängd i vyn - medvetet, admin väljer vad som blir publikt) och försvinner automatiskt efter sitt datum. Designskissen `web/designforslag.html` är borttagen.
- Deploy-rutin (`deploy.sh` efter noters mönster) byggs inför driftsättning.

## Deploylista: lokala INNEHÅLLSÄNDRINGAR (följer inte med config/git)

Produktionens databas behålls vid driftsättning; dessa lokala databasändringar måste göras om eller migreras dit:

- Menylänken Hem: `internal:#` ändrad till `internal:/`.
- Menylänken "Kören Gott och Blandat" (dubblett av startsidan) borttagen ur huvudmenyn.
- 20 kalendarieposter hösten 2026 (16 övningar onsdagar 18.20 med sluttid 20.35, gudstjänst 15/11, adventskör 29/11, julkonsert 16/12, seminarium 10/10 utan anmälan).
- Nya taxonomitermer i `datum_framforande` skapade via autocreate.
- Tre Pixabay-platshållarbilder i `sites/default/files/publikbild/` kopplade till höstens publika poster via `field_publik_bild` (bild + fil-entiteter är innehåll, följer inte git).
- 13 musiknoders brödtext rensad från inbäddade vue-audio-mixer-spelare (ersatta av temats mixer).
- Kyrkans namnbyte till Equmeniakyrkan Betel: brödtexten, 13 kalendarieposters information och 11 termer i `datum_framforande` omskrivna lokalt (skriptet `_import/byt-kyrknamn.php` kan köras om mot produktionsdatabasen).
- Alla lösenord nollställs inför lansering; medlemmarna sätter nya (Carina67 har lokalt testlösenord).
