# Driftsättning: gob.betelkyrkan.se

Referens för hur kod och konfiguration tar sig från din Mac till produktionsservern, och var gränsen går mot sådant som aldrig ska automatiseras (databasen, uppladdade filer).

<!-- Pipeline first verified end-to-end: 2026-07-19 -->

## a) Deploy-flödet

Pipelinen (`.github/workflows/deploy.yml`) triggas av varje push till `main` på GitHub. Den loggar in på servern över SSH och kör, i denna ordning:

```
git pull origin main
composer install --no-dev --optimize-autoloader --no-interaction
vendor/bin/drush deploy -y
vendor/bin/drush cache:rebuild
```

`drush deploy` i sin tur kör (i denna ordning, se `vendor/drush/drush/docs/deploycommand.md`):

```
drush updatedb          # hook_update_N() - låg nivå
drush config:import     # importerar config/sync
drush cache:rebuild
drush deploy:hook       # hook_deploy_NAME() - körs EFTER config-importen
drush cache:warm
```

**Vad pipelinen ALDRIG rör:**

- **Produktionsdatabasens innehåll** (noder, användare, anmälningar). `config:import` skapar och ändrar bara *struktur* (innehållstyper, fält, vyer, block) - aldrig innehållet i befintliga noder. `updatedb`/`deploy:hook` kan skriva till databasen, men bara om ett update- eller deploy-hook uttryckligen skriver kod för det (se avsnitt d).
- **`web/sites/default/files/`** - inte git-spårat, `git pull` ser den aldrig.
- **`web/sites/default/settings.php`** - inte git-spårat av samma anledning. Bara `web/sites/default/default.settings.php` (Drupals oskyldiga mall) är spårad.
- **`/var/www/private/`** - ligger helt utanför webroot och utanför repot.

`config_ignore`-modulen är ett extra skyddsnät för det fåtal config-typer som kan tänkas ändras snabbt via admin-UI:t utan att gå via git - se `config/sync/config_ignore.settings.yml` för aktuell lista och motiveringen i commit-historiken.

## b) Daglig utvecklingscykel

**Innan ett utvecklingspass** - spegla produktionens data till dev (databas + uppladdade filer, aldrig kod åt det hållet):

```sh
# på servern
vendor/bin/drush sql:dump --gzip --result-file=$HOME/gob-prod.sql

# på Mac
scp -P 1369 mol@e-pro.se:~/gob-prod.sql.gz ~/Web/gob/
cd ~/Web/gob && ddev import-db --file=gob-prod.sql.gz
rsync -avz -e "ssh -p 1369" mol@e-pro.se:/var/www/gob.betelkyrkan.se/web/sites/default/files/ ~/Web/gob/web/sites/default/files/
ddev drush cache:rebuild
```

**Under utveckling** - exportera config efter varje strukturändring (nya fält, vyer, block):

```sh
ddev drush config:export -y
git add -A && git commit -m "..." && git push
```

**Deploy sker automatiskt** via pipelinen vid push till `main`. Inget manuellt steg på servern behövs längre.

## c) Regeln om flödesriktning

Två flöden, åt varsitt håll, som aldrig får mötas destruktivt:

```
  DEV  --- kod + config --->  GIT  --- pipeline --->  SERVER
  DEV  <--- innehåll + filer ---------------------    SERVER   (manuellt, se b)
```

- **Kod och config går uppåt**, via git och pipelinen. `drush deploy` rör bara struktur, aldrig nodinnehåll.
- **Innehåll och filer går nedåt**, manuellt, separat från pipelinen (`sql:dump` + `rsync`, se b).
- Undantaget är engångsmigreringen som redan är gjord (den ursprungliga cutovern till `web/`-docroot och det nuvarande temat) - normalt sker det aldrig i andra riktningen.

## d) Deploy hooks - att avsiktligt och säkert röra befintlig produktionsdata

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

De en gångsskript som redan finns i `_import/` (körs manuellt via `ddev drush php:script` mot en specifik databas) är ett annat, mer ad hoc-verktyg för just engångsmigreringar - deploy hooks är för sådant som ska köras automatiskt vid *varje* framtida deploy där det behövs.

## e) Felsökning

- **Filrättigheter efter deploy**: `git pull` som körs som `mol` skapar/uppdaterar filer ägda av `mol` - ingen `chown`-städning behövs längre (till skillnad från det gamla rsync-baserade `deploy.sh`, som rörde ägarskap eftersom filer kom in utifrån). Om något ändå hamnar fel: `chown mol:www-data`, kataloger `755`, filer `644`, `settings.php` alltid `440`.
- **`settings.php` får ALDRIG committas.** Den är gitignorerad (`web/sites/*/settings.php`) - kontrollera med `git status` om den någonsin dyker upp som "modified" eller "untracked men borde spåras", det är ett tecken på att något är fel i `.gitignore` eller att filen råkat läggas fel.
- **Privata filer** (noter, feeds-import) ligger i `/var/www/private/`, helt utanför webroot och utanför repot. DDEV kan inte hantera den katalogen lokalt - motsvarande lokala plats är `../private/` (utanför `web/`), redan gitignorerad.
- **`php vendor/bin/drush ...` fungerar INTE** - `vendor/bin/drush` är ett skalskript (från Drush 13), inte en PHP-fil. Kör det direkt: `vendor/bin/drush ...`. Det gamla `deploy.sh` hade detta fel; pipelinen har det inte.
- **`git pull` vägrar därför att lokala ändringar finns**: någon har ändrat en git-spårad fil direkt på servern (ska aldrig hända - all kodändring går via git). Kör `git status` på servern, granska diffen med `git diff`, och antingen `git stash` eller committa avsiktligt innan nästa deploy kan gå igenom. Aldrig `git checkout .`/`git reset --hard` utan att först ha läst diffen.
- **Grenen heter `master` lokalt på servern**: hände en gång vid den inledande cutovern (en fristående `git init` push:ad till en egen gren istället för att kopplas till den befintliga `main`-historiken). Löst genom `git checkout -b main origin/main` - ren växling, rör aldrig gitignorerade filer. Om det händer igen: kontrollera med `git diff <lokal-gren> origin/main --stat` innan bytet, för säkerhets skull.
