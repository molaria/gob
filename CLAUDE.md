# Gott och Blandat (gob.betelkyrkan.se)

Sajt för kören Gott och Blandat vid Betelkyrkan i Örebro. Drupal 11, Composer-hanterad. Publik presentationssida plus intranät för ca 40 körmedlemmar: kalendarium med anmälan, notregister med lyssning, medlemsmatrikel, fikalista.

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
- Modulen `sticky` varnar om saknad `libraries/sticky/jquery.sticky.js` (saknas även på produktion) - städkandidat.

## Pågående och planerat

- Anmälan har tre lägen: anmäld, avanmäld, ej svarat. Idag löst med fyra flaggor i par (`deltar`/`deltar_andrad`, `deltar_ej`/`delta_ej_andrad`) där ändrad-flaggan inverterar förstasvaret. Systemet ska ersättas med en riktig trelägesmodell (egen tabell: uid, nid, status, tidpunkt; ingen rad = ej svarat) med migrering av befintliga flaggningar.
- Notregistret (`/musik`) väntar på omdesign (bort från jQuery UI-dragspel, mot katalogmönster som noter).
- Publika startsidan ska få hero enligt designskissen (`web/designforslag.html`, tas bort när klar).
- Deploy-rutin (`deploy.sh` efter noters mönster) byggs inför driftsättning.
