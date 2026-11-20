# Driftsättning: gob.betelkyrkan.se

Referens för hur kod, config och Drupal-uppdateringar tar sig mellan din Mac, GitHub och produktionsservern, och var gränsen går mot sådant som aldrig automatiseras (databasens innehåll, uppladdade filer).

<!-- Pipeline first verified end-to-end: 2026-07-19. Safety gate and server self-commit: 2026-11-18 -->

## Grundprinciperna

1. **En deploy skriver aldrig tyst över något som bara finns på servern.** Vid minsta tvekan stoppas den innan något ändras, och meddelandet säger vad som är fel och vad du gör (se avsnitt h).
2. **Git är alltid i fas med produktionen.** När du uppdaterar Drupal på servern committar och pushar servern själv det som ändrats.
3. **Macen hålls automatiskt i fas med git.** Du behöver inte komma ihåg något: det som inte kan göras automatiskt och säkert stoppas med ett begripligt besked.

## a) Tre flöden

```
  MAC     --- kod + config (git push) ------------> GITHUB --- deploy.yml ---> SERVER
  SERVER  --- Drupal-uppdateringar ([skip ci]) ---> GITHUB --- pull / ddev start ---> MAC
  SERVER  --- innehåll + filer (manuellt, avsnitt e) ----------------------------> MAC
```

Innehåll och uppladdade filer går aldrig uppåt. Nytt innehåll som ska nå medlemmarna skapas direkt på produktionssajten.

## b) Deploy: push till main

Varje push till `main` startar `.github/workflows/deploy.yml`. Den loggar in på servern och kör `drift/deploy.sh`, **läst ur exakt den commit som pushades** (`github.sha`), så det är alltid den granskade versionen som körs. Två deploys körs aldrig samtidigt.

`drift/deploy.sh` gör, i ordning:

1. **Låset.** Väntar upp till 15 minuter om en serveruppdatering pågår (samma lås som uppdateringsskriptet).
2. **Kontrollen**, som stoppar utan att ändra något om:
   - committen inte finns på `origin/main`
   - servern har egna commits som inte nått GitHub
   - en ändrad, borttagen eller rättighetsändrad spårad fil på servern inte är byte-identisk med det som ska ut
   - en fil som deployen lägger till redan finns på servern utanför git (även gitignorerade filer)
   - `composer.json`/`composer.lock` inte klarar `composer validate` och `composer check-platform-reqs --lock --no-dev` (testas i en tillfällig katalog innan något ändras)
   - `drush config:status` visar config som ändrats på servern men inte exporterats (`block.block.*` undantas via config_ignore)
3. **Säkerhetskopia** av eventuella ändrade filer i `~/deploy-backup/<tid>-<commit>/`, sedan `git merge --ff-only <commit>`.
4. `composer install --no-dev --optimize-autoloader`, `drush deploy -y`, `drush cache:rebuild`.
5. **Efterkontroll** (`drift/post-deploy.sh`): spårade filer identiska med git, inga väntande databasuppdateringar, config i fas, startsidan svarar 200 och `/kalendarium` svarar 403 för anonyma (åtkomstskyddet lever). Rött vid fel.

**Omkörning:** misslyckas `composer install` eller `drush deploy` står koden redan på plats. Kör om jobbet i GitHub Actions ("Re-run jobs"). `deploy.sh` känner igen läget, hoppar över config-kontrollen (den nya configen är ju inte importerad än) och kör installation och `drush deploy` igen.

**Torrkörning** direkt på servern, ändrar ingenting (fungerar även för en commit på en testgren):

```sh
cd /var/www/gob.betelkyrkan.se
git fetch origin
git show <commit>:drift/deploy.sh | bash -s <commit> --dry-run
```

Efterkontrollen kan köras när som helst, den bara läser: `bash drift/post-deploy.sh`.

`drush deploy` kör i sin tur (se `vendor/drush/drush/docs/deploycommand.md`):

```
drush updatedb          # hook_update_N() - låg nivå
drush config:import     # importerar config/sync
drush cache:rebuild
drush deploy:hook       # hook_deploy_NAME() - körs EFTER config-importen
drush cache:warm
```

**Vad deployen ALDRIG rör:**

- **Produktionsdatabasens innehåll** (noder, användare, anmälningar). `config:import` ändrar bara *struktur*. `updatedb`/`deploy:hook` skriver bara om ett hook uttryckligen gör det (avsnitt g).
- **`web/sites/default/files/`**, **`web/sites/default/settings.php`** och **`/var/www/private/`**: inte git-spårade.

## c) Uppdatera Drupal på servern

Kör som vanligt, från vilken dator som helst:

```sh
~/bin/drupal-uppdatera.sh
```

Skriptet gäller alla Drupal-sajter i `/var/www`. För sajter som har en `drift/`-katalog i sitt förråd (gob) gör det dessutom detta:

- **Vid skanningen** listas sajten även när den saknar nya paket men har ändringar som inte nått GitHub (en tidigare push som misslyckats, config ändrad i admin).
- **Före uppdateringen** tas låset och `drift/fore-uppdatering.sh` körs. Den kontrollerar att servern är i fas med GitHub. Den kan fråga:
  - *"Pusha dem till GitHub nu?"* om servern har en commit som aldrig nått GitHub.
  - *"Ta med allt detta i den här uppdateringens commit?"* om en tidigare uppdatering lämnat ocommittade composer-, scaffold- eller config-filer.
  - *"Exportera och committa den först, som en egen commit?"* om config ändrats i admin på produktionen.
  Svarar du nej hoppas sajten över och inget ändras.
- **Efter lyckad `composer update` + `drush updb` + `drush cr`** körs `drift/efter-uppdatering.sh`. Den kontrollerar att allt är installerat, exporterar config som uppdateringen ändrat, släpper bara igenom `composer.json`, `composer.lock`, `config/sync/` och Drupals scaffold-filer, och committar och pushar med `[skip ci]` (ingen deploy behövs, servern kör redan koden). Commit-meddelandet listar paketändringarna, till exempel *"Serveruppdatering: 11.4.12 -> 11.4.13 (drupal/core) + 3 paket [skip ci]"*.

Om composer inte kan kontrollera en sajt (nätfel, låsproblem, fel PHP-version) visas den som *"✗ ... composer kunde inte kontrollera uppdateringar"* med composers felmeddelande, aldrig som uppdaterad, och skriptet avslutas med felkod.

Uppdateringsskriptet ligger utanför git. Versionen före drift-stödet är sparad som `~/bin/drupal-uppdatera.sh.bak-20261118`, versionen före rättelsen av torrkörningen som `~/bin/drupal-uppdatera.sh.bak-20261118b`.

**Behörigheter på servern:** förrådet pushar med deploy-nyckeln `~/.ssh/id_gob_betelkyrkan` ("Server gob" i GitHub, skrivrätt), vald via `core.sshCommand` i förrådets `.git/config`. Commits görs som *Servern (gob)*.

## d) På Macen: allt sker automatiskt

| När | Vad som händer | Var |
|---|---|---|
| Ny Claude Code-session i projektet | Samma som vid `ddev start` nedan. Fångar serveruppdateringar som kommit medan DDEV redan kört i flera dagar | `.claude/settings.json` (SessionStart-krok) → `drift/lokal-synk.sh` |
| `ddev start` | Hämtar nya commits från GitHub (om du står på `main` utan osparade ändringar), kör `composer install` och vid behov `ddev snapshot` + `drush deploy` | `.ddev/config.drift.yaml` → `drift/lokal-synk.sh` |
| `git pull` / `git pull --rebase` | Samma synk av den lokala miljön | `drift/hooks/post-merge`, `post-rewrite` |
| `git push` till `main` | Stoppas om GitHub har nyare commits, om composer-filer eller config/sync har ocommittade ändringar, om DDEV inte körs, om `vendor` inte matchar låset, om databasuppdateringar inte körts eller om databasens config skiljer sig från `config/sync` | `drift/hooks/pre-push` |

Synken importerar aldrig config som git inte har ändrat: det kan vara ditt eget oexporterade arbete i admin. Då säger den till i stället. Före varje `drush deploy` tar den en ögonblicksbild som heter `fore-synk-<tid>`, återställs med `ddev snapshot restore fore-synk-<tid>`.

Hookarna aktiveras av `core.hooksPath=drift/hooks`, som `lokal-synk.sh` sätter automatiskt vid `ddev start`. På en ny dator eller klon: kör `ddev start` en gång. I ett verkligt nödläge kan kontrollen före push hoppas över med `git push --no-verify`.

## e) Daglig utvecklingscykel

**Innan ett utvecklingspass**, om du vill ha produktionens innehåll lokalt (databas + uppladdade filer, aldrig kod åt det hållet):

```sh
# på servern
vendor/bin/drush sql:dump --gzip --result-file=$HOME/gob-prod.sql

# på Mac
scp -P 1369 mol@e-pro.se:~/gob-prod.sql.gz ~/Web/gob/
cd ~/Web/gob && ddev import-db --file=gob-prod.sql.gz
rsync -avz -e "ssh -p 1369" mol@e-pro.se:/var/www/gob.betelkyrkan.se/web/sites/default/files/ ~/Web/gob/web/sites/default/files/
ddev drush cache:rebuild
```

**Under utveckling**, exportera config efter varje strukturändring (nya fält, vyer, block):

```sh
ddev drush config:export -y
git add -A && git commit -m "..." && git push
```

Deployen sker automatiskt vid push till `main`.

## f) Regeln om flödesriktning

- **Kod och config går uppåt** via git och pipelinen.
- **Det enda undantaget är Drupal-uppdateringar gjorda på servern**: de går från servern till GitHub, och därifrån till Macen. Det är bara `composer.json`, `composer.lock`, scaffold-filer och config som uppdateringen själv ändrat, och servern committar dem automatiskt (avsnitt c).
- **Innehåll och filer går nedåt**, manuellt (avsnitt e).
- Ingen ändrar kod direkt på servern. Gör någon det ändå stoppas nästa deploy.

## g) Deploy hooks: att avsiktligt och säkert röra befintlig produktionsdata

`config:import` skapar bara *tom fältstruktur*. Ett nytt fält på en befintlig innehållstyp har inget värde på de noder som redan finns - de måste fyllas i explicit. Gör det med ett `hook_deploy_NAME()` i valfri egen modul (t.ex. `gob_form.module`) - det körs automatiskt av `drush deploy`, EFTER att config importerats, så fältet garanterat redan finns när koden nedan kör:

```php
/**
 * Sätter startvärde 0 på field_weight för infokort som saknar det.
 *
 * hook_deploy_NAME() körs en gång per unikt funktionsnamn (namnet sparas
 * i key-value-lagret, precis som hook_update_N()) - säkert att lämna kvar
 * i koden permanent, det körs aldrig två gånger på samma server.
 */
function gob_form_deploy_infokort_field_weight_default(): string {
  $storage = \Drupal::entityTypeManager()->getStorage('node');
  $nids = \Drupal::entityQuery('node')
    ->condition('type', 'infokort')
    ->notExists('field_weight')
    ->accessCheck(FALSE)
    ->execute();

  $weight = 0;
  foreach ($storage->loadMultiple($nids) as $node) {
    $node->set('field_weight', $weight);
    $node->save();
    $weight += 10;
  }

  return count($nids) . ' infokort-noder fick ett startvärde.';
}
```

Skillnaden mot `hook_update_N()`: deploy-hooks körs *efter* `config:import`, så du kan lita på att nya fält/innehållstyper redan är på plats. `hook_update_N()` körs *före* - använd det bara för lågnivåändringar som inte beror på config som importeras i samma deploy.

Observera att även den lokala synken (avsnitt d) kör `drush deploy`, så ett nytt deploy-hook körs också mot din lokala databas första gången den synkas.

De engångsskript som redan finns i `_import/` (körs manuellt via `ddev drush php:script` mot en specifik databas) är ett annat, mer ad hoc-verktyg för just engångsmigreringar.

## h) När något stoppas: meddelande och åtgärd

**Deployen (GitHub Actions, mejl från GitHub):**

| Meddelandet säger | Gör så här |
|---|---|
| *Servern har egna commits som inte nått GitHub* | Kör `~/bin/drupal-uppdatera.sh` på servern och svara ja på pushen. Kör sedan om deployen. Har GitHub också fått nya commits: se avsnitt i. |
| *Config har ändrats på servern ... utan att exporteras* | Kör `~/bin/drupal-uppdatera.sh`, svara ja på exporten. Kör om deployen. |
| *Servern har ändringar som en deploy skulle skriva över* | Någon har ändrat filer direkt på servern. Läs `git status` och `git diff` på servern. Aldrig `git checkout .` eller `git reset --hard` utan att först ha förstått diffen. |
| *En serveruppdatering pågår fortfarande* | Vänta tills uppdateringen är klar, kör om deployen. |
| *composer validate underkände* / *passar inte serverns PHP-miljö* | Rätta låsfilen lokalt (`ddev composer update --lock` eller motsvarande), committa, pusha. |
| Fel i `composer install` eller `drush deploy` | Kör om jobbet. Upprepas felet: läs loggen, rätta, pusha. |
| *Efterkontrollen hittade N problem* | Koden är driftsatt men något stämmer inte. Läs listan. `/kalendarium svarar 200` betyder att åtkomstskyddet är borta: utred direkt. |

**Uppdateringsskriptet på servern:**

| Meddelandet säger | Gör så här |
|---|---|
| *GitHub har N commit(s) som inte deployats ännu* | En deploy väntar, pågår eller har misslyckats. Se GitHub Actions, låt den bli klar eller kör om den. Kör sedan uppdateringen igen. |
| *Committen är gjord på servern men pushen till GitHub misslyckades* | Kör uppdateringsskriptet igen, så erbjuds pushen på nytt. |
| *Servern och GitHub har gått isär* | Se avsnitt i. |
| *Ändrade filer på servern som inte hör till en Drupal-uppdatering* | Någon har ändrat kod på servern. Utred för hand. |
| *En deploy pågår för gob.betelkyrkan.se – hoppar över* | Kör skriptet igen om en stund. |

**På Macen:**

| Meddelandet säger | Gör så här |
|---|---|
| *GitHub har nyare commits* (vid push) | `git pull --rebase`, sedan push igen. Miljön synkas automatiskt. |
| *DDEV körs inte* (vid push) | `ddev start`, sedan push igen. |
| *Paketen i vendor matchar inte composer.lock* | `ddev composer install` |
| *Din lokala databas har uppdateringar som inte körts* | `ddev drush deploy -y` |
| *Config i din lokala databas skiljer sig från config/sync* | Är det ditt arbete: `ddev drush config:export -y` och committa. Annars: `ddev drush deploy -y`. |

## i) Servern och GitHub har gått isär (sällsynt)

Händer bara om du pushar från Macen just under de minuter en serveruppdatering pågår. Servern har då en commit (uppdateringen) som inte nått GitHub, och GitHub har din commit som inte kan deployas. Ingenting är förstört; deployen av din commit har stoppats. Så här löser du det utan att skriva om någon historik:

```sh
# 1. På servern: skicka serverns commit till en egen gren (ändrar inget på servern)
cd /var/www/gob.betelkyrkan.se
git push origin HEAD:refs/heads/serveruppdatering

# 2. På Macen: slå ihop den och pusha (miljön synkas automatiskt av hookarna)
git pull --no-rebase --no-edit origin serveruppdatering
git push

# 3. När deployen gått igenom: ta bort grenen
git push origin --delete serveruppdatering
```

Deployen går igenom eftersom serverns commit nu finns i historiken för det som deployas. Vägen är provad i testsviten (scenario D17). Har både din commit och servern ändrat `composer.lock` blir det en konflikt i steg 2: lös den med `ddev composer update --lock`.

## j) Felsökning

- **Filrättigheter efter deploy**: deployen körs som `mol` och filer ägs av `mol`. Om något ändå hamnar fel: `chown mol:www-data`, kataloger `755`, filer `644`, `settings.php` alltid `440`.
- **`settings.php` får ALDRIG committas.** Den är gitignorerad (`web/sites/*/settings.php`).
- **Privata filer** (noter, feeds-import) ligger i `/var/www/private/`, utanför webroot och repot. Lokalt motsvaras det av `../private/`.
- **`php vendor/bin/drush ...` fungerar INTE**: `vendor/bin/drush` är ett skalskript (från Drush 13). Kör det direkt.
- **Uppladdning gör ingenting på produktionen men fungerar lokalt**: se nginx-fallgropen i `CLAUDE.md`.
- **Grenen `master` på GitHub** är en rest från den första flytten till servern i juli 2026. Servern spårar `main`.

## k) Tester

Allt i `drift/` har en testsvit som bygger egna tillfälliga git-världar i temp-kataloger och aldrig rör projektet eller servern:

```sh
drift/test/kor-alla.sh
```

Mac-delen körs med macOS egen bash 3.2 (som hookarna får), serverdelen i DDEV-containern (Linux, bash 5, flock, php som servern). För att även testa hela flödet med uppdateringsskriptet:

```sh
scp -P 1369 mol@e-pro.se:bin/drupal-uppdatera.sh /tmp/drupal-uppdatera.sh
UPDATE_SCRIPT=/tmp/drupal-uppdatera.sh drift/test/kor-alla.sh
```

Kör testerna efter varje ändring i `drift/` eller i uppdateringsskriptet.
