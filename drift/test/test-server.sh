#!/usr/bin/env bash
#
# test-server.sh - scenarios for the server side: deploy.sh, post-deploy.sh,
# fore-uppdatering.sh, efter-uppdatering.sh and the patched
# drupal-uppdatera.sh flow.
#
# Needs a Linux environment like the server (flock, php, bash 5). Run it in
# the DDEV container:   ddev exec bash drift/test/test-server.sh
# Every scenario builds its own throwaway git world in /tmp; nothing in the
# project or on any server is touched.

set -u
source "$(dirname "$0")/lib-test.sh"

export COMPOSER_BIN="$STUBS/composer"
export CURL_BIN="$STUBS/curl"
export DEPLOY_LOCK_WAIT=1

# Runs deploy.sh the way the pipeline does: extracted from the target commit.
run_deploy() {
  export BACKUP_ROOT="$T/backup"
  (
    cd "$T/server" || exit 1
    git fetch -q origin
    git show "$1:drift/deploy.sh" > "$T/deploy-run.sh"
    bash "$T/deploy-run.sh" "$@"
  ) > "$T/out" 2>&1
  rc=$?
}

run_in_server() {
  # run_in_server <stdin-text> <command...>
  local input="$1"
  shift
  (cd "$T/server" && printf '%s' "$input" | "$@") > "$T/out" 2>&1
  rc=$?
}

change_lock_to_11_4_13() { write_lock "11.4.13"; }
change_b() { echo "b: 2" > config/sync/b.yml; }
change_custom() { echo "custom code v2" > web/modules/custom/x.txt; }
add_new_file() { echo "new" > web/modules/custom/new.txt; }
remove_custom() { git rm -q web/modules/custom/x.txt; }
chmod_custom() { chmod +x web/modules/custom/x.txt; }

# ---------------------------------------------------------------- deploy.sh

scenario "D1 Rent träd, ny commit: deploy går igenom"
make_fixture
target="$(dev_commit "change b" change_b)"
run_deploy "$target"
check "exit 0" test "$rc" -eq 0
check "servern står på målet" test "$(server_head)" = "$target"
check "composer install kördes" grep -q "composer install --no-dev" "$STUB_STATE/calls.log"
check "drush deploy kördes" grep -q "drush deploy -y" "$STUB_STATE/calls.log"
check "config importerad" cmp -s "$T/server/config/sync/b.yml" "$STUB_STATE/db/b.yml"
check "efterkontrollen grön" output_has "Efterkontrollen är grön."
cleanup_fixture

scenario "D2 Servern har en egen commit: stopp"
make_fixture
(cd "$T/server" && echo x >> web/modules/custom/x.txt && git commit -qam "egen")
before="$(server_head)"
target="$(dev_commit "change b" change_b)"
run_deploy "$target"
check "exit 1" test "$rc" -eq 1
check "HEAD oförändrad" test "$(server_head)" = "$before"
check "meddelandet nämner egna commits" output_has "egna commits"
check "inget installerat" sh -c "! grep -q 'composer install' '$STUB_STATE/calls.log'"
cleanup_fixture

scenario "D3 Ändrad fil som skiljer sig från målet: stopp"
make_fixture
echo "server-only edit" > "$T/server/web/modules/custom/x.txt"
before="$(server_head)"
target="$(dev_commit "change b" change_b)"
run_deploy "$target"
check "exit 1" test "$rc" -eq 1
check "HEAD oförändrad" test "$(server_head)" = "$before"
check "filen orörd" grep -q "server-only edit" "$T/server/web/modules/custom/x.txt"
check "filen listas" output_has "web/modules/custom/x.txt (innehållet skiljer sig"
cleanup_fixture

scenario "D4 Ändrad fil identisk med målet: deploy med säkerhetskopia"
make_fixture
(cd "$T/server" && write_lock "11.4.13")
target="$(dev_commit "lock" change_lock_to_11_4_13)"
run_deploy "$target"
check "exit 0" test "$rc" -eq 0
check "servern står på målet" test "$(server_head)" = "$target"
check "trädet rent" test -z "$(git -C "$T/server" status --porcelain --untracked-files=no)"
check "säkerhetskopia finns" sh -c "ls '$T'/backup/*/composer.lock"
cleanup_fixture

scenario "D5 Fil borttagen på servern men kvar i målet: stopp"
make_fixture
rm "$T/server/web/modules/custom/x.txt"
target="$(dev_commit "change b" change_b)"
run_deploy "$target"
check "exit 1" test "$rc" -eq 1
check "listas som borttagen" output_has "borttagen på servern men finns i målcommiten"
cleanup_fixture

scenario "D5b Fil borttagen både på servern och i målet: går igenom"
make_fixture
rm "$T/server/web/modules/custom/x.txt"
target="$(dev_commit "remove x" remove_custom)"
run_deploy "$target"
check "exit 0" test "$rc" -eq 0
check "servern står på målet" test "$(server_head)" = "$target"
check "trädet rent" test -z "$(git -C "$T/server" status --porcelain --untracked-files=no)"
cleanup_fixture

scenario "D6 Ospårad fil krockar med ny fil i målet: stopp"
make_fixture
echo "server copy" > "$T/server/web/modules/custom/new.txt"
target="$(dev_commit "add new" add_new_file)"
run_deploy "$target"
check "exit 1" test "$rc" -eq 1
check "krocken listas" output_has "web/modules/custom/new.txt"
check "serverns fil orörd" grep -q "server copy" "$T/server/web/modules/custom/new.txt"
cleanup_fixture

scenario "D6b Ignorerad fil krockar med ny fil i målet: stopp"
make_fixture
add_vendor_file() { mkdir -p vendor && echo "tracked now" > vendor/forced.txt && git add -f vendor/forced.txt; }
mkdir -p "$T/server/vendor" && echo "local" > "$T/server/vendor/forced.txt"
target="$(dev_commit "force-add ignored path" add_vendor_file)"
run_deploy "$target"
check "exit 1" test "$rc" -eq 1
check "ignorerade filen orörd" grep -q "local" "$T/server/vendor/forced.txt"
cleanup_fixture

scenario "D7 composer validate underkänner: stopp"
make_fixture
echo 2 > "$STUB_STATE/validate_rc"
before="$(server_head)"
target="$(dev_commit "lock" change_lock_to_11_4_13)"
run_deploy "$target"
check "exit 1" test "$rc" -eq 1
check "HEAD oförändrad" test "$(server_head)" = "$before"
check "meddelande om validate" output_has "composer validate underkände"
cleanup_fixture

scenario "D7b Låset passar inte serverns PHP: stopp"
make_fixture
echo 2 > "$STUB_STATE/platform_rc"
target="$(dev_commit "lock" change_lock_to_11_4_13)"
run_deploy "$target"
check "exit 1" test "$rc" -eq 1
check "meddelande om PHP-miljö" output_has "passar inte serverns PHP-miljö"
cleanup_fixture

scenario "D8 Config ändrad i admin på servern: stopp"
make_fixture
echo "a: admin-change" > "$STUB_STATE/db/a.yml"
before="$(server_head)"
target="$(dev_commit "change b" change_b)"
run_deploy "$target"
check "exit 1" test "$rc" -eq 1
check "HEAD oförändrad" test "$(server_head)" = "$before"
check "configen listas" output_has "  a"
check "admin-ändringen kvar i databasen" grep -q "admin-change" "$STUB_STATE/db/a.yml"
cleanup_fixture

scenario "D8b drush config:status fallerar: stopp"
make_fixture
touch "$STUB_STATE/drush_fail"
target="$(dev_commit "change b" change_b)"
run_deploy "$target"
check "exit 1" test "$rc" -eq 1
check "meddelande om drush" output_has "drush config:status misslyckades"
cleanup_fixture

scenario "D9 Omkörning efter misslyckad installation: går igenom"
make_fixture
target="$(dev_commit "change b" change_b)"
touch "$STUB_STATE/install_fail"
run_deploy "$target"
check "första körningen fallerar" test "$rc" -ne 0
check "koden är redan på plats" test "$(server_head)" = "$target"
rm "$STUB_STATE/install_fail"
run_deploy "$target"
check "omkörningen: exit 0" test "$rc" -eq 0
check "omkörningsläge" output_has "Omkörning"
check "config importerad till slut" cmp -s "$T/server/config/sync/b.yml" "$STUB_STATE/db/b.yml"
cleanup_fixture

scenario "D9b Omkörning med ändrade filer: stopp"
make_fixture
target="$(dev_commit "change b" change_b)"
touch "$STUB_STATE/install_fail"
run_deploy "$target"
rm "$STUB_STATE/install_fail"
echo "edit" >> "$T/server/web/modules/custom/x.txt"
run_deploy "$target"
check "exit 1" test "$rc" -eq 1
check "meddelande om ändrade filer" output_has "har ändrade spårade filer"
cleanup_fixture

scenario "D10 Commit som inte finns på origin/main: stopp"
make_fixture
side="$( cd "$T/dev" && git checkout -q -b sidogren && echo s > side.txt && git add side.txt && git commit -qm side && git push -q origin sidogren && git rev-parse HEAD )"
run_deploy "$side"
check "exit 1" test "$rc" -eq 1
check "meddelande om origin/main" output_has "finns inte på origin/main"
cleanup_fixture

scenario "D10b Torrkörning av commit på testgren: varnar, kör kontrollen, ändrar inget"
make_fixture
before="$(server_head)"
side="$( cd "$T/dev" && git checkout -q -b testgren && echo "b: 2" > config/sync/b.yml && git commit -qam test && git push -q origin testgren && git rev-parse HEAD )"
run_deploy "$side" --dry-run
check "exit 0" test "$rc" -eq 0
check "varnar om origin/main" output_has "en riktig deploy skulle stoppa här"
check "kontrollen kördes" output_has "Kontrollen är grön"
check "HEAD oförändrad" test "$(server_head)" = "$before"
check "ingen installation" sh -c "! grep -q 'composer install' '$STUB_STATE/calls.log'"
cleanup_fixture

scenario "D10c Torrkörning på testgren när servern har drift: stoppar ändå"
make_fixture
echo "a: admin-change" > "$STUB_STATE/db/a.yml"
side="$( cd "$T/dev" && git checkout -q -b testgren && echo "b: 2" > config/sync/b.yml && git commit -qam test && git push -q origin testgren && git rev-parse HEAD )"
run_deploy "$side" --dry-run
check "exit 1" test "$rc" -eq 1
check "configen listas" output_has "  a"
cleanup_fixture

scenario "D11 Torrkörning ändrar ingenting"
make_fixture
(cd "$T/server" && write_lock "11.4.13")
before="$(server_head)"
target="$(dev_commit "lock" change_lock_to_11_4_13)"
index_before="$(git -C "$T/server" diff --cached --stat)"
run_deploy "$target" --dry-run
check "exit 0" test "$rc" -eq 0
check "HEAD oförändrad" test "$(server_head)" = "$before"
check "index oförändrat" test "$(git -C "$T/server" diff --cached --stat)" = "$index_before"
check "ingen säkerhetskopia" test ! -e "$T/backup"
check "ingen installation" sh -c "! grep -q 'composer install' '$STUB_STATE/calls.log'"
check "säger torrkörning" output_has "TORRKÖRNING"
cleanup_fixture

scenario "D12 Låset hålls av en serveruppdatering: stopp"
make_fixture
target="$(dev_commit "change b" change_b)"
lockfile="$T/server/.git/drift.lock"
flock "$lockfile" sleep 5 &
holder=$!
sleep 0.5
run_deploy "$target"
check "exit 1" test "$rc" -eq 1
check "meddelande om pågående uppdatering" output_has "serveruppdatering pågår"
wait "$holder"
cleanup_fixture

scenario "D13 Ändrad filrättighet som skiljer sig från målet: stopp"
make_fixture
chmod +x "$T/server/web/modules/custom/x.txt"
target="$(dev_commit "change b" change_b)"
run_deploy "$target"
check "exit 1" test "$rc" -eq 1
check "meddelande om filrättighet" output_has "filrättigheten skiljer sig"
cleanup_fixture

scenario "D13b Ändrad filrättighet identisk med målet: går igenom"
make_fixture
chmod +x "$T/server/web/modules/custom/x.txt"
target="$(dev_commit "chmod" chmod_custom)"
run_deploy "$target"
check "exit 0" test "$rc" -eq 0
check "trädet rent" test -z "$(git -C "$T/server" status --porcelain --untracked-files=no)"
cleanup_fixture

scenario "D14 Efterkontrollen hittar fel (startsidan svarar 500): rött"
make_fixture
echo -n 500 > "$STUB_STATE/http_"
target="$(dev_commit "change b" change_b)"
run_deploy "$target"
check "exit skild från 0" test "$rc" -ne 0
check "felet rapporteras" output_has "/ svarar 500"
cleanup_fixture

scenario "D14b Åtkomstskyddet borta (/kalendarium svarar 200): rött"
make_fixture
echo -n 200 > "$STUB_STATE/http_kalendarium"
target="$(dev_commit "change b" change_b)"
run_deploy "$target"
check "exit skild från 0" test "$rc" -ne 0
check "felet rapporteras" output_has "/kalendarium svarar 200, förväntade 403"
cleanup_fixture

scenario "D15 Ogiltigt argument: stopp"
make_fixture
run_deploy "main"
check "exit 1" test "$rc" -eq 1
check "meddelande" output_has "Ogiltig commit"
cleanup_fixture

scenario "D16 Gammal commit (servern redan förbi): ingen tillbakagång"
make_fixture
old="$(git -C "$T/dev" rev-parse HEAD)"
new="$(dev_commit "change b" change_b)"
run_deploy "$new"
run_deploy "$old"
check "exit 0" test "$rc" -eq 0
check "servern står kvar på den nyare" test "$(server_head)" = "$new"
cleanup_fixture

scenario "D17 Isär-fallet löst enligt DEPLOY.md: servercommit via gren, Macen slår ihop, deploy grön"
make_fixture
# The server committed an update but its push was refused, because the Mac
# pushed meanwhile.
(cd "$T/server" && write_lock "11.4.13" && cp composer.lock "$STUB_STATE/vendor.lock" && git commit -qam "Serveruppdatering [skip ci]")
mac_commit="$(dev_commit "mac work" change_custom)"
run_deploy "$mac_commit"
check "deployen av Macens commit stoppas först" test "$rc" -eq 1
# 1. Server: push its commit to a side branch (changes nothing on the server).
git -C "$T/server" push -q origin HEAD:refs/heads/serveruppdatering
# 2. Mac: merge that branch and push main.
git -C "$T/dev" pull -q --no-rebase --no-edit origin serveruppdatering
git -C "$T/dev" push -q origin main
merged="$(git -C "$T/dev" rev-parse HEAD)"
run_deploy "$merged"
check "deployen av sammanslagningen går igenom" test "$rc" -eq 0
check "servern står på sammanslagningen" test "$(server_head)" = "$merged"
check "trädet rent" test -z "$(git -C "$T/server" status --porcelain --untracked-files=no)"
cleanup_fixture

# ------------------------------------------------- fore-/efter-uppdatering.sh

scenario "F1 I fas med GitHub: uppdateringen får köras"
make_fixture
run_in_server "" drift/fore-uppdatering.sh
check "exit 0" test "$rc" -eq 0
check "säger klart" output_has "Uppdateringen kan köras"
cleanup_fixture

scenario "F2 GitHub har odeployade commits: hoppar över"
make_fixture
dev_commit "change b" change_b > /dev/null
run_in_server "" drift/fore-uppdatering.sh
check "exit 1" test "$rc" -eq 1
check "meddelande" output_has "inte deployats"
cleanup_fixture

scenario "F3 Opushad servercommit, svar ja: pushas"
make_fixture
(cd "$T/server" && write_lock "11.4.13" && git commit -qam "server [skip ci]")
run_in_server "j"$'\n' drift/fore-uppdatering.sh
check "exit 0" test "$rc" -eq 0
check "GitHub har servercommiten" test "$(origin_head)" = "$(server_head)"
cleanup_fixture

scenario "F3b Opushad servercommit, svar nej: inget pushat"
make_fixture
(cd "$T/server" && write_lock "11.4.13" && git commit -qam "server [skip ci]")
before="$(origin_head)"
run_in_server "n"$'\n' drift/fore-uppdatering.sh
check "exit 1" test "$rc" -eq 1
check "GitHub orörd" test "$(origin_head)" = "$before"
cleanup_fixture

scenario "F4 Servern och GitHub isär: stopp"
make_fixture
(cd "$T/server" && write_lock "11.4.13" && git commit -qam "server")
dev_commit "change b" change_b > /dev/null
run_in_server "j"$'\n' drift/fore-uppdatering.sh
check "exit 1" test "$rc" -eq 1
check "meddelande" output_has "gått isär"
cleanup_fixture

scenario "F5 Kvarlämnad uppdatering (tillåtna filer), svar ja: tas med"
make_fixture
(cd "$T/server" && write_lock "11.4.13" && echo "# htaccess v2" > web/.htaccess)
run_in_server "j"$'\n' drift/fore-uppdatering.sh
check "exit 0" test "$rc" -eq 0
check "filerna listas" output_has "web/.htaccess"
cleanup_fixture

scenario "F5b Kvarlämnad uppdatering, svar nej: hoppar över"
make_fixture
(cd "$T/server" && write_lock "11.4.13")
run_in_server "n"$'\n' drift/fore-uppdatering.sh
check "exit 1" test "$rc" -eq 1
cleanup_fixture

scenario "F6 Otillåten ändring på servern: stopp"
make_fixture
echo "hack" >> "$T/server/web/modules/custom/x.txt"
run_in_server "j"$'\n' drift/fore-uppdatering.sh
check "exit 1" test "$rc" -eq 1
check "filen listas" output_has "web/modules/custom/x.txt"
cleanup_fixture

scenario "F7 Config ändrad i admin, svar ja: egen commit med [skip ci] pushas"
make_fixture
echo "a: admin-change" > "$STUB_STATE/db/a.yml"
run_in_server "j"$'\n' drift/fore-uppdatering.sh
check "exit 0" test "$rc" -eq 0
check "GitHub har commiten" test "$(origin_head)" = "$(server_head)"
check "[skip ci] i meddelandet" sh -c "git --git-dir='$T/origin.git' log -1 --format=%s main | grep -qF '[skip ci]'"
check "configen exporterad" grep -q "admin-change" "$T/server/config/sync/a.yml"
check "trädet rent" test -z "$(git -C "$T/server" status --porcelain)"
cleanup_fixture

scenario "F7b Config ändrad i admin, svar nej: hoppar över, inget ändrat"
make_fixture
echo "a: admin-change" > "$STUB_STATE/db/a.yml"
run_in_server "n"$'\n' drift/fore-uppdatering.sh
check "exit 1" test "$rc" -eq 1
check "config/sync orörd" grep -q "a: 1" "$T/server/config/sync/a.yml"
cleanup_fixture

scenario "F8 git-identitet saknas på servern: stopp"
make_fixture
git -C "$T/server" config --unset user.name
HOME="$T" run_in_server "" drift/fore-uppdatering.sh
check "exit 1" test "$rc" -eq 1
check "meddelande" output_has "user.name"
cleanup_fixture

scenario "F9 --status rapporterar osynkat läge, tyst när allt stämmer"
make_fixture
run_in_server "" drift/fore-uppdatering.sh --status
check "tyst när rent" test ! -s "$T/out"
(cd "$T/server" && write_lock "11.4.13")
echo "a: admin-change" > "$STUB_STATE/db/a.yml"
run_in_server "" drift/fore-uppdatering.sh --status
check "rapporterar filer" output_has "ändrade filer på servern"
check "rapporterar config" output_has "config som skiljer sig"
cleanup_fixture

scenario "F10 Låset hålls av en deploy: stopp"
make_fixture
flock "$T/server/.git/drift.lock" sleep 3 &
holder=$!
sleep 0.5
run_in_server "" drift/fore-uppdatering.sh
check "exit 1" test "$rc" -eq 1
check "meddelande" output_has "En deploy eller en annan uppdatering pågår"
wait "$holder"
cleanup_fixture

scenario "E1 Efter uppdatering: config exporteras, commit med [skip ci] pushas"
make_fixture
(cd "$T/server" && write_lock "11.4.13" && echo "# htaccess v2" > web/.htaccess && cp composer.lock "$STUB_STATE/vendor.lock")
echo "b: set-by-update-hook" > "$STUB_STATE/db/b.yml"
run_in_server "" drift/efter-uppdatering.sh
check "exit 0" test "$rc" -eq 0
check "GitHub har commiten" test "$(origin_head)" = "$(server_head)"
subject="$(git --git-dir="$T/origin.git" log -1 --format=%s main)"
check "ämnesraden nämner kärnversionen" sh -c "echo '$subject' | grep -qF '11.4.12 -> 11.4.13'"
check "ämnesraden har [skip ci]" sh -c "echo '$subject' | grep -qF '[skip ci]'"
check "configen med i commiten" sh -c "git -C '$T/server' show --stat HEAD | grep -q 'config/sync/b.yml'"
check "scaffoldfilen med i commiten" sh -c "git -C '$T/server' show --stat HEAD | grep -q 'web/.htaccess'"
check "trädet rent" test -z "$(git -C "$T/server" status --porcelain)"
cleanup_fixture

scenario "E2 Efter uppdatering: otillåten fil ändrad, inget committat"
make_fixture
(cd "$T/server" && write_lock "11.4.13" && cp composer.lock "$STUB_STATE/vendor.lock" && echo "x" >> web/modules/custom/x.txt)
before="$(server_head)"
run_in_server "" drift/efter-uppdatering.sh
check "exit 1" test "$rc" -eq 1
check "ingen commit" test "$(server_head)" = "$before"
check "filen listas" output_has "web/modules/custom/x.txt"
cleanup_fixture

scenario "E3 Efter uppdatering: vendor matchar inte låset, inget committat"
make_fixture
(cd "$T/server" && write_lock "11.4.13")
before="$(server_head)"
run_in_server "" drift/efter-uppdatering.sh
check "exit 1" test "$rc" -eq 1
check "ingen commit" test "$(server_head)" = "$before"
cleanup_fixture

scenario "E4 Efter uppdatering: databasuppdateringar ej körda, inget committat"
make_fixture
(cd "$T/server" && write_lock "11.4.13" && cp composer.lock "$STUB_STATE/vendor.lock")
touch "$STUB_STATE/updb_pending"
before="$(server_head)"
run_in_server "" drift/efter-uppdatering.sh
check "exit 1" test "$rc" -eq 1
check "ingen commit" test "$(server_head)" = "$before"
cleanup_fixture

scenario "E5 Efter uppdatering: inget ändrat, ingen commit"
make_fixture
before="$(server_head)"
run_in_server "" drift/efter-uppdatering.sh
check "exit 0" test "$rc" -eq 0
check "ingen commit" test "$(server_head)" = "$before"
cleanup_fixture

scenario "E6 Efter uppdatering: GitHub har fått nya commits, push nekas"
make_fixture
(cd "$T/server" && write_lock "11.4.13" && cp composer.lock "$STUB_STATE/vendor.lock")
dev_commit "change b" change_b > /dev/null
run_in_server "" drift/efter-uppdatering.sh
check "exit 1" test "$rc" -eq 1
check "commiten finns kvar på servern" sh -c "git -C '$T/server' log -1 --format=%s | grep -q Serveruppdatering"
check "meddelande om pushen" output_has "pushen till GitHub misslyckades"
cleanup_fixture

# --------------------------------------- the patched drupal-uppdatera.sh flow

UPDATE_SCRIPT="${UPDATE_SCRIPT:-}"
if [ -n "$UPDATE_SCRIPT" ] && [ -f "$UPDATE_SCRIPT" ]; then
  # The real script hardcodes WEBROT=/var/www; point it at the fixture.
  run_update_script() {
    mkdir -p "$T/www"
    ln -sfn "$T/server" "$T/www/gob"
    sed "s|^WEBROT=.*|WEBROT=\"$T/www\"|; s|^DUMPKATALOG=.*|DUMPKATALOG=\"$T/dumps\"|" \
      "$UPDATE_SCRIPT" > "$T/update.sh"
    # BASH_ENV is unset because DDEV's container uses it to put the real
    # composer ahead of the stub in PATH.
    (printf '%s' "$1" | env -u BASH_ENV PATH="$STUBS:$PATH" bash "$T/update.sh") > "$T/out" 2>&1
    rc=$?
  }

  scenario "U1 Hela flödet: uppdatering på servern, Mac pushar, deploy grön"
  make_fixture
  echo "  - Upgrading drupal/core (11.4.12 => 11.4.13)" > "$STUB_STATE/update_dry"
  cat > "$STUB_STATE/update_apply" << 'EOF'
sed -i 's/"11.4.12"/"11.4.13"/' composer.lock
echo "# htaccess v2" > web/.htaccess
echo "b: set-by-update-hook" > "$STUB_STATE/db/b.yml"
EOF
  run_update_script "j"$'\n'
  check "exit 0" test "$rc" -eq 0
  check "GitHub har serverns commit" test "$(origin_head)" = "$(server_head)"
  check "trädet rent på servern" test -z "$(git -C "$T/server" status --porcelain)"
  check "låset släppt efteråt" flock -n "$T/server/.git/drift.lock" true
  rm -f "$STUB_STATE/update_dry" "$STUB_STATE/update_apply"
  # The Mac pulls the server's update and pushes new work on top.
  git -C "$T/dev" pull -q --ff-only origin main
  target="$(dev_commit "new work" change_custom)"
  run_deploy "$target"
  check "deployen efteråt går igenom" test "$rc" -eq 0
  check "servern står på Macens commit" test "$(server_head)" = "$target"
  cleanup_fixture

  scenario "U2 Inga nya paket men osynkat läge: sajten listas och synkas"
  make_fixture
  echo "a: admin-change" > "$STUB_STATE/db/a.yml"
  run_update_script "j"$'\n'"j"$'\n'
  check "exit 0" test "$rc" -eq 0
  check "sajten listades" output_has "config som skiljer sig"
  check "GitHub har config-commiten" test "$(origin_head)" = "$(server_head)"
  cleanup_fixture

  scenario "U3 Deploy pågår (låset hålls): sajten hoppas över"
  make_fixture
  echo "  - Upgrading drupal/core (11.4.12 => 11.4.13)" > "$STUB_STATE/update_dry"
  flock "$T/server/.git/drift.lock" sleep 4 &
  holder=$!
  sleep 0.5
  run_update_script "j"$'\n'
  check "skriptet rapporterar fel" test "$rc" -ne 0
  check "meddelande" output_has "En deploy pågår"
  check "inget uppdaterat" sh -c "! grep -q '^composer update --with-all-dependencies --no-interaction$' '$STUB_STATE/calls.log'"
  wait "$holder"
  cleanup_fixture

  scenario "U4 composer kan inte kontrollera uppdateringar: fel, inte \"uppdaterad\""
  make_fixture
  touch "$STUB_STATE/update_dry_fail"
  run_update_script "j"$'\n'
  check "skriptet rapporterar fel" test "$rc" -ne 0
  check "sajten markeras som fel" output_has "composer kunde inte kontrollera uppdateringar"
  check "composers felmeddelande visas" output_has "requires php ^9.0"
  check "säger inte uppdaterad" sh -c "! grep -qE 'är uppdaterad|Alla sajter är uppdaterade' '$T/out'"
  check "inget uppdaterat" sh -c "! grep -q '^composer update --with-all-dependencies --no-interaction$' '$STUB_STATE/calls.log'"
  cleanup_fixture
else
  echo
  echo "(U-scenarierna hoppades över: sätt UPDATE_SCRIPT till det patchade drupal-uppdatera.sh)"
fi

finish
