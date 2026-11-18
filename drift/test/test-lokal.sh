#!/bin/bash
#
# test-lokal.sh - scenarios for the Mac side: lokal-synk.sh and the git
# hooks (pre-push, post-merge, post-rewrite).
#
# Runs on the Mac with the system bash 3.2 on purpose, since that is what
# the hooks get:   /bin/bash drift/test/test-lokal.sh
# DDEV is replaced by a stub; every scenario builds its own throwaway git
# world in a temp directory. Nothing in the project is touched.

set -u
source "$(dirname "$0")/lib-test.sh"

export DDEV="$STUBS/ddev"

# The production server commits an update and pushes it to GitHub.
server_pushes_update() {
  (
    cd "$T/server" || exit 1
    write_lock "11.4.13"
    echo "b: 2" > config/sync/b.yml
    git commit -qam "Serveruppdatering [skip ci]"
    git push -q origin HEAD:main
  )
}

run_in_dev() {
  (cd "$T/dev" && "$@") > "$T/out" 2>&1
  rc=$?
}

dev_db_in_step() {
  cmp -s "$T/dev/config/sync/b.yml" "$STUB_STATE/db/b.yml" \
    && cmp -s "$T/dev/composer.lock" "$STUB_STATE/vendor.lock"
}

use_hooks() {
  git -C "$T/dev" config core.hooksPath drift/hooks
}

scenario "L1 DDEV startar: serverns uppdatering hämtas och körs lokalt"
make_fixture
server_pushes_update
run_in_dev drift/lokal-synk.sh --efter-start
check "exit 0" test "$rc" -eq 0
check "Macen står på GitHubs main" test "$(git -C "$T/dev" rev-parse HEAD)" = "$(origin_head)"
check "vendor och databas i fas" dev_db_in_step
check "ögonblicksbild tagen före drush deploy" grep -q "ddev snapshot --name fore-synk-" "$STUB_STATE/calls.log"
check "hookarna aktiverade" test "$(git -C "$T/dev" config core.hooksPath)" = "drift/hooks"
check "ingen kvarvarande markering" test ! -e "$T/dev/.git/drift-synk-fran"
cleanup_fixture

scenario "L2 DDEV startar med eget oexporterat config-arbete: det rörs inte"
make_fixture
echo "a: my-unexported-work" > "$STUB_STATE/db/a.yml"
server_pushes_update
run_in_dev drift/lokal-synk.sh --efter-start
check "exit 0" test "$rc" -eq 0
check "eget arbete kvar i databasen" grep -q "my-unexported-work" "$STUB_STATE/db/a.yml"
check "ingen drush deploy" sh -c "! grep -q 'drush deploy' '$STUB_STATE/calls.log'"
check "meddelande om eget arbete" output_has "eget oexporterade arbete"
check "markeringen kvar till nästa gång" test -s "$T/dev/.git/drift-synk-fran"
cleanup_fixture

scenario "L3 DDEV startar med osparade ändringar: ingen hämtning"
make_fixture
server_pushes_update
before="$(git -C "$T/dev" rev-parse HEAD)"
echo "edit" >> "$T/dev/web/modules/custom/x.txt"
run_in_dev drift/lokal-synk.sh --efter-start
check "exit 0" test "$rc" -eq 0
check "HEAD oförändrad" test "$(git -C "$T/dev" rev-parse HEAD)" = "$before"
check "osparade ändringen kvar" grep -q "edit" "$T/dev/web/modules/custom/x.txt"
check "meddelande" output_has "osparade ändringar"
cleanup_fixture

scenario "L4 DDEV startar när Mac och GitHub gått isär: ingen hämtning"
make_fixture
server_pushes_update
(cd "$T/dev" && echo "mine" > web/modules/custom/x.txt && git commit -qam "egen")
before="$(git -C "$T/dev" rev-parse HEAD)"
run_in_dev drift/lokal-synk.sh --efter-start
check "HEAD oförändrad" test "$(git -C "$T/dev" rev-parse HEAD)" = "$before"
check "säger git pull --rebase" output_has "git pull --rebase"
cleanup_fixture

scenario "L5 Pull när DDEV är stoppad, synk när DDEV startar"
make_fixture
use_hooks
server_pushes_update
touch "$STUB_STATE/ddev_stopped"
run_in_dev git pull -q --ff-only origin main
check "hooken säger att DDEV inte körs" output_has "DDEV körs inte"
check "markering sparad" test -s "$T/dev/.git/drift-synk-fran"
rm "$STUB_STATE/ddev_stopped"
run_in_dev drift/lokal-synk.sh --efter-start
check "vendor och databas i fas" dev_db_in_step
check "markeringen borta" test ! -e "$T/dev/.git/drift-synk-fran"
cleanup_fixture

scenario "L6 git pull (snabbspolning) kör post-merge-hooken"
make_fixture
use_hooks
server_pushes_update
run_in_dev git pull -q --ff-only origin main
check "exit 0" test "$rc" -eq 0
check "hooken körde" output_has "[lokal-synk]"
check "vendor och databas i fas" dev_db_in_step
cleanup_fixture

scenario "L7 git pull --rebase med egen commit kör post-rewrite-hooken"
make_fixture
use_hooks
server_pushes_update
(cd "$T/dev" && echo "mine" > web/modules/custom/x.txt && git commit -qam "egen")
run_in_dev git pull -q --rebase origin main
check "exit 0" test "$rc" -eq 0
check "hooken körde" output_has "[lokal-synk]"
check "vendor och databas i fas" dev_db_in_step
cleanup_fixture

scenario "L8 Push när GitHub har nyare commits: stoppas"
make_fixture
use_hooks
server_pushes_update
before="$(origin_head)"
(cd "$T/dev" && echo "mine" > web/modules/custom/x.txt && git commit -qam "egen")
run_in_dev git push -q origin main
check "pushen nekad" test "$rc" -ne 0
check "GitHub orörd" test "$(origin_head)" = "$before"
check "säger git pull --rebase" output_has "git pull --rebase"
cleanup_fixture

scenario "L9 Push när vendor inte matchar låset: stoppas"
make_fixture
use_hooks
(cd "$T/dev" && write_lock "11.4.13" && git commit -qam "lås")
before="$(origin_head)"
run_in_dev git push -q origin main
check "pushen nekad" test "$rc" -ne 0
check "GitHub orörd" test "$(origin_head)" = "$before"
check "meddelande" output_has "ddev composer install"
cleanup_fixture

scenario "L10 Push med databasuppdateringar som inte körts: stoppas"
make_fixture
use_hooks
touch "$STUB_STATE/updb_pending"
(cd "$T/dev" && echo "mine" > web/modules/custom/x.txt && git commit -qam "egen")
run_in_dev git push -q origin main
check "pushen nekad" test "$rc" -ne 0
check "meddelande" output_has "ddev drush deploy -y"
cleanup_fixture

scenario "L11 Push när databasens config skiljer sig från config/sync: stoppas"
make_fixture
use_hooks
echo "a: not exported" > "$STUB_STATE/db/a.yml"
(cd "$T/dev" && echo "mine" > web/modules/custom/x.txt && git commit -qam "egen")
run_in_dev git push -q origin main
check "pushen nekad" test "$rc" -ne 0
check "configen listas" output_has "    a"
cleanup_fixture

scenario "L12 Push med ocommittad ändring i config/sync: stoppas"
make_fixture
use_hooks
(cd "$T/dev" && echo "mine" > web/modules/custom/x.txt && git commit -qam "egen")
echo "a: 2" > "$T/dev/config/sync/a.yml"
cp "$T/dev/config/sync/a.yml" "$STUB_STATE/db/a.yml"
run_in_dev git push -q origin main
check "pushen nekad" test "$rc" -ne 0
check "meddelande" output_has "inte är committade"
cleanup_fixture

scenario "L13 Push när allt är i fas: går igenom"
make_fixture
use_hooks
(cd "$T/dev" && echo "mine" > web/modules/custom/x.txt && git commit -qam "egen")
run_in_dev git push -q origin main
check "exit 0" test "$rc" -eq 0
check "GitHub har commiten" test "$(origin_head)" = "$(git -C "$T/dev" rev-parse HEAD)"
check "kontrollen grön" output_has "Kontrollen är grön"
cleanup_fixture

scenario "L14 Push till annan gren: kontrolleras inte"
make_fixture
use_hooks
echo "a: not exported" > "$STUB_STATE/db/a.yml"
(cd "$T/dev" && git checkout -q -b testgren && echo "t" > t.txt && git add t.txt && git commit -qm test)
run_in_dev git push -q origin testgren
check "exit 0" test "$rc" -eq 0
check "ingen kontroll kördes" sh -c "! grep -q 'Kontroll före push' '$T/out'"
cleanup_fixture

scenario "L15 Push när DDEV är stoppad: stoppas"
make_fixture
use_hooks
touch "$STUB_STATE/ddev_stopped"
(cd "$T/dev" && echo "mine" > web/modules/custom/x.txt && git commit -qam "egen")
run_in_dev git push -q origin main
check "pushen nekad" test "$rc" -ne 0
check "meddelande" output_has "ddev start"
cleanup_fixture

finish
