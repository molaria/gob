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
- Avinstallation av en modul RADERAR config som beror på den. En vy kan ha ett stalt `views_accordion` kvar i `dependencies.module` fastän ingen display använder stilen - rensa beroendet i config/sync innan modulen tas bort, annars försvinner vyn.
- **VAPN (behörighet för musik/kalendarium/internt) implementerar bara `hook_node_access`, inte `hook_node_access_records`.** Det skyddar enskilda nodsidor, filnedladdningar (mp3/pdf) och Views-listningssidor korrekt (alla verifierade 2026-07-17: anonym nekas, inloggad medlem släpps in). Men `node_access`-databastabellen är aldrig ifylld av VAPN - den innehåller bara Drupals standardrad "alla ser allt". Varje NY funktion som filtrerar bulklistor via den tabellen (kärnans sökmodul gjorde det - fixat genom att ta bort `search content`/`access content overview` från anonym 2026-07-17) kommer läcka skyddat innehåll. Kontrollera detta INNAN du lägger till: JSON:API, RSS/sitemap, eller en Views-vy med tillägget "Access: node access checked" på musik/kalendarium/internt-innehåll.

## Klart (hösten 2026-arbetet)

- Eget tema `gob` med designsystem enligt godkänd skiss, Nunito självhostad.
- Kalendariet: händelsekort med accordion, trelägesanmälan i hopfällt läge ("Kommer du? Ja/Nej", statuschip + Ändra), fika- och programlistor, sluttidsfält (time_field).
- Apple-lik navigering: tunn blur-list, rullgardiner utan symboler som öppnas vid hover/fokus, hamburgarmeny på mobil, välkomstrad för inloggade.
- Admin-menyn dold och åtkomstskyddad för vanliga medlemmar (epost/telefon-vyerna kräver administrator eller kalendarium_admin).
- Matrikeln: klientsökning, sortering, kombinerat löpnummer (13:1).
- Städat 2026-07-17: Drupal-kärnan säkerhetsuppdaterad 11.3.13 -> 11.4.4. Avinstallerade och borttagna ur composer: webform-sviten (oanvänd), asset_injector, countdown, counter, menu_bootstrap_icon, twbstools, views_bulk_operations, views_field_view, samt aldrig-aktiverade registration, css_editor, block_field, field_permissions, user_display_name, htmlmail, upgrade_status. Gamla Bootstrap-temana (bootstrap5, bootstrap5_admin, custom gobsubtheme + b5subtheme) borttagna - bara `gob` + admin `claro` kvar. Contrib-moduler: 41 -> 26. jQuery UI-stacken (views_accordion, jquery_ui_accordion, jquery_ui) borttagen - lattips och utskick omgjorda till nativt/sökbart, skräpvyn dubblett_av_taxonomiterm raderad. Kvar att städa: flag-stacken (se nedan) när trelägesmodellen bevisats i drift.
- Statusrapporten rensad 2026-07-17: `gob.info.yml` bytte `base theme` från det avvecklade `stable9` till `false` (temat har redan alla egna mallar/CSS sedan starterkit-genereringen - matchar hur `starterkit_theme` själv är byggd) och `stable9` avinstallerades. `enable_html5_validation` satt explicit till `TRUE` i settings.php (nuvarande beteende, Drupal 12 kommer defaulta till `FALSE`). Kvarvarande varningar i statusrapporten som INTE är buggar: "Deprecated modules" (Contact/History) är i aktiv bruk (kontaktformulär + kommentarmodulen) och ska inte avinstalleras; "Protection disabled" på settings.php är en känd DDEV/Docker Desktop-begränsning (host-chmod 444 speglas inte fullt ut i containern) - produktionens `deploy.sh` sätter redan korrekt `chmod 440` på den riktiga servern.

## Anmälan: trelägesmodellen (klar 2026-07-16)

- Modulen `gob_attendance`: tabellen `gob_attendance` (uid, nid, status attending/declined, changed; ingen rad = ej svarat), service `gob_attendance.manager`, rutt `/anmalan/{node}/{ja|nej}` (inloggning + CSRF-token, kräver anmälningsbar kalendariumnod) med bekräftelsemeddelanden.
- Vyn kalendarium är rensad från flaggfält/relationer och kör cache none (raderna varierar per användare); status och svarslänkar injiceras i preprocess från modulen.
- Närvarosidan (`gob_attending`) portad till nya tabellen; `FlagStatusResolver` borttagen.
- 939 flaggningar migrerade till 853 besked (583 anmälda, 270 avanmälda) med samma resolverlogik, stickprovsverifierat inklusive ändringspar.
- Flaggdata och flag-modulen ligger KVAR orörda som säkerhetsnät. Städkandidater när modellen bevisat sig i drift: modulerna flag och kalendarium_deltagande, de fyra flaggorna, flaggningstabellens data.

## Pågående och planerat

- Notregistret omdesignat 2026-07-16: katalograder med snabbsök (`notes-filter.js`). Titeln länkar till redigeringsformuläret för behöriga (edit_node-fältet måste vara exclude: false - exkluderade vyfält når inte mallen). Ljudfiler är dolda bakom Lyssna-knappen som öppnar stämmixern (`player.js` + `player.css`): dialog-popup med Web Audio, samtidig uppspelning, volym/Tyst/Solo per stämma, spellista som JSON i knappen i nodens fältordning, fullskärm på mobil. Gamla vue-audio-mixer-snuttarna (unpkg-CDN) är rensade ur 13 musiknoders brödtext. Låttipsen (58 st) ligger på /tips (vyn lattips), nu omgjord till sökbar katalog i samma stil (`views-view-fields--lattips.html.twig` + `lattips.css`, delar snabbsöket `notes-filter.js`). Låttipsen avdubblade (56 kvar). Utskickssidan (/utskick, interna nyheter typ internt) omgjord till nativt <details>-dragspel (`views-view-fields--utskick.html.twig` + `news.css`). jQuery UI-stacken därmed helt borttagen.
- Konsertprogram 2026-07-17: dragbart fält `field_program` (referens till musiknoder, obegränsat) på `datum_framforande`-termer - allt sköts på termen: välj noter, dra ordning, skriv fri info i beskrivningen. Termsidan (`taxonomy-term--datum-framforande.html.twig` + `program.css`) visar programmet som accordion (hopfällt: titel + Noter/Lyssna, utfällt: full notinfo), inloggat-bara via `gob_form_taxonomy_term_access`. Sångernas `field_hepp` (Framförd-listan) synkas automatiskt från programmet i `gob_form` (`_gob_form_sync_hepp`). 24 termer migrerade från befintliga field_hepp-kopplingar (bokstavsordning som start).
- Publika startsidan är egen innehållstyp `startsida` (nod 899, ersatte page-nod 770 som avpublicerades): motto, ingress, körledare-foto + text redigeras på noden, fälten dolda i standardvisningen och ritas av `page--front.html.twig`. Körledarsektion (foto + bakgrund, länk till /historik) efter konserterna. Dirigenthistorik: innehållstyp `dirigent` (från/till-år, porträtt, text), vyn `historik` på publika `/historik` som tidslinje (`views-view-fields--historik.html.twig` + `timeline.css`), nutid överst via counter, prickar ur logopaletten. Tre dirigenter inlagda (Caroline Ericson Welin från 1997, Emila Kiland 2010-2012, Mats-Olof 2012-nu).
- Konserter på framsidan hämtas ur vyn `konserter`: kalendarieposter med bocken `field_publik` (+ ev. `field_publik_bild`) visas för alla (node access-omskrivning avstängd i vyn - medvetet, admin väljer vad som blir publikt) och försvinner automatiskt efter sitt datum (tidscache 6 h). Korten i Apple-stil (`hero.css`).
- Deploy-rutin (`deploy.sh` efter noters mönster) byggs inför driftsättning.

## Deploylista: lokala INNEHÅLLSÄNDRINGAR (följer inte med config/git)

Produktionens databas behålls vid driftsättning; dessa lokala databasändringar måste göras om eller migreras dit:

- Menylänken Hem: `internal:#` ändrad till `internal:/`.
- Menylänken "Kören Gott och Blandat" (dubblett av startsidan) borttagen ur huvudmenyn.
- Menylänken Låttips (-> /tips) tillagd som barn under Noter; musik-vyns Noter (page_1) satt expanderad, page_2:s Noter2-menylänk avstängd.
- 20 kalendarieposter hösten 2026 (16 övningar onsdagar 18.20 med sluttid 20.35, gudstjänst 15/11, adventskör 29/11, julkonsert 16/12, seminarium 10/10 utan anmälan).
- Nya taxonomitermer i `datum_framforande` skapade via autocreate.
- Tre Pixabay-platshållarbilder i `sites/default/files/publikbild/` kopplade till höstens publika poster via `field_publik_bild` (bild + fil-entiteter är innehåll, följer inte git).
- 13 musiknoders brödtext rensad från inbäddade vue-audio-mixer-spelare (ersatta av temats mixer).
- 24 datum_framforande-termer fick migrerat program (field_program) ur field_hepp; ordning satt lokalt genom dragning per term.
- Kyrkans namnbyte till Equmeniakyrkan Betel: brödtexten, 13 kalendarieposters information och 11 termer i `datum_framforande` omskrivna lokalt (skriptet `_import/byt-kyrknamn.php` kan köras om mot produktionsdatabasen).
- Ny startsida-nod (899) och tre dirigent-noder, förstasidan pekad om från 770 till 899 (gamla 770 avpublicerad). Porträttet FotoMO_1.jpg synkat från servern till sites/default/files/2024-01/.
- Alla lösenord nollställs inför lansering; medlemmarna sätter nya (Carina67 har lokalt testlösenord).
- Dirigenthistoriken (2026-07-18) utökad från tre till nio poster (alla sex verkliga ledare 1997-2011 plus två viloperioder) baserat på ett detaljerat underlag - årtal rättade, notiser med Vt/Ht-detaljer tillagda. Skripten `_import/dirigent-nya-falt.php` (fälten body + field_viloperiod, redan i config/sync) och `_import/dirigent-historik-uppdatering.php` + `_import/dirigent-mer-detalj.php` (själva innehållet, körs i den ordningen) kan köras om mot produktionsdatabasen.
- Info-sidans sex kort (2026-07-18) migrerade från internt-noder (taggade "Info") till egen typ `infokort` (fält + vy redan i config/sync). Skriptet `_import/info-innehallstyp.php` skapar typen/fälten och migrerar innehållet - kan köras om mot produktionsdatabasen. De sex gamla internt-noderna avpublicerades (inte raderade); de åtta andra internt-noderna (konsertutskick, nyhetsbrev) rörda inte.
- Info-korten (2026-07-18): field_icon utökat till alla 1748 Lucide-ikoner (fältkonfig i config/sync, spriten i `web/themes/custom/gob/icons/lucide-sprite.svg`). De sex kortens ikonvärden rättade till riktiga Lucide-namn - skriptet `_import/info-alla-ikoner.php` kan köras om mot produktionsdatabasen. Modulen `drupal/draggableviews` tillagd (composer + config, följer med vid nästa deploy) för dragbar kortordning på `/admin/content/infokort-ordning` - ingen sparad ordning ännu, bara publicerad via config.
