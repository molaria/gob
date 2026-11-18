#!/usr/bin/env bash
#
# deploy.sh - deploys one exact commit to the production checkout.
#
# Usage (from the site root on the server):
#   bash deploy.sh <commit-sha>             gate + deploy
#   bash deploy.sh <commit-sha> --dry-run   gate only, changes nothing
#
# The pipeline (.github/workflows/deploy.yml) extracts this file straight
# from the commit being deployed, so the version that runs is always the one
# under review in git, never a stale copy lying on the server.
#
# Principle: a deploy must never silently overwrite anything that exists on
# the server but not in git. When in doubt the gate stops before touching
# anything and says why. Server-side updates (drupal-uppdatera.sh) commit
# their own changes back to GitHub, so in normal operation the gate passes.
#
# Environment overrides exist only so drift/test/run-tests.sh can stub the
# tools; production uses the defaults.

set -euo pipefail

DRUSH="${DRUSH:-vendor/bin/drush}"
COMPOSER_BIN="${COMPOSER_BIN:-composer}"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/deploy-backup}"
LOCK_WAIT="${DEPLOY_LOCK_WAIT:-900}"

# Set to true once the gate starts changing the checkout, so error messages
# never claim "nothing changed" when that is no longer true.
touched=false

stop() {
  echo
  echo "STOPP: $*"
  if [[ "$touched" == false ]]; then
    echo "Inget har ändrats på servern."
  fi
  exit 1
}

has_content() {
  grep -q '[^[:space:]]' <<< "$1"
}

target="${1:-}"
dry_run=false
[[ "${2:-}" == "--dry-run" ]] && dry_run=true

[[ "$target" =~ ^[0-9a-f]{40}$ ]] || stop "Ogiltig commit: '$target' (förväntade en fullständig SHA)."
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || stop "Körs inte i en git-katalog: $(pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- Lock -----------------------------------------------------------------
# Shared with drupal-uppdatera.sh: a deploy and a server update must never
# run at the same time. The lock is released automatically when this process
# exits, however it exits.
exec 9> "$(git rev-parse --git-dir)/drift.lock"
if ! flock -w "$LOCK_WAIT" 9; then
  stop "En serveruppdatering pågår fortfarande efter $LOCK_WAIT sekunder. Kör om deployen när den är klar."
fi

git fetch --quiet origin || stop "git fetch mot GitHub misslyckades."
git cat-file -e "${target}^{commit}" 2> /dev/null || stop "Committen $target finns inte på servern efter git fetch."
if ! git merge-base --is-ancestor "$target" origin/main; then
  # A dry run never changes anything, so it may test a commit on another
  # branch (to try a new deploy.sh before it reaches main). A real deploy
  # only ever takes commits that are on main.
  if [[ "$dry_run" == true ]]; then
    echo "OBS: $target finns inte på origin/main. Torrkörningen fortsätter, men en riktig deploy skulle stoppa här."
  else
    stop "Committen $target finns inte på origin/main."
  fi
fi

head="$(git rev-parse HEAD)"
echo "Servern står på: $head"
echo "Mål:             $target"

# --- Which situation are we in? -------------------------------------------
if ! git merge-base --is-ancestor HEAD origin/main; then
  echo
  echo "Commits på servern som inte finns på GitHub:"
  git log --oneline origin/main..HEAD | sed 's/^/  /'
  stop "Servern har egna commits som inte nått GitHub. Kör ~/bin/drupal-uppdatera.sh på servern, så erbjuds en push av dem."
fi

if [[ "$head" == "$target" ]] || git merge-base --is-ancestor "$target" HEAD; then
  # Re-run after a failed composer install / drush deploy, or an old run
  # started again. The code is already in place; only the tree must be
  # clean. The config check is skipped on purpose: after a half-finished
  # deploy, config/sync legitimately differs until it has been imported.
  mode="omkörning"
  dirty="$(git status --porcelain --untracked-files=no)"
  if has_content "$dirty"; then
    echo "$dirty" | sed 's/^/  /'
    stop "Servern står redan på (eller efter) målcommiten men har ändrade spårade filer."
  fi
  echo
  echo "Omkörning: servern står redan på målcommiten. Koden är på plats, kör bara installation och drush deploy igen."
elif git merge-base --is-ancestor HEAD "$target"; then
  mode="normal"
else
  stop "Servern och målcommiten har gått isär i historiken. Kontrollera manuellt."
fi

# --- Gate (normal mode) ---------------------------------------------------
changed=()
if [[ "$mode" == "normal" ]]; then
  # Refresh stat info so files that were only touched (not changed) do not
  # show up as modified.
  git update-index -q --refresh > /dev/null 2>&1 || true

  # 1. Tracked files that differ from HEAD on the server (content, mode or
  #    deletion) must be byte-identical to the target, otherwise the deploy
  #    would overwrite something that only exists on the server.
  while IFS= read -r -d '' path; do
    changed+=("$path")
  done < <(git diff --name-only -z HEAD --)

  mismatches=()
  for path in "${changed[@]}"; do
    entry="$(git ls-tree "$target" -- "$path")"
    if [[ -L "$path" ]]; then
      mismatches+=("$path (symbolisk länk, kontrolleras inte automatiskt)")
    elif [[ -f "$path" ]]; then
      if [[ -z "$entry" ]]; then
        mismatches+=("$path (finns på servern men är borttagen i målcommiten)")
        continue
      fi
      target_mode="${entry%% *}"
      target_hash="$(awk '{print $3}' <<< "$entry")"
      if [[ -x "$path" ]]; then local_mode="100755"; else local_mode="100644"; fi
      local_hash="$(git hash-object -- "$path")"
      if [[ "$local_hash" != "$target_hash" ]]; then
        mismatches+=("$path (innehållet skiljer sig från målcommiten)")
      elif [[ "$local_mode" != "$target_mode" ]]; then
        mismatches+=("$path (filrättigheten skiljer sig från målcommiten)")
      fi
    elif [[ -e "$path" ]]; then
      mismatches+=("$path (är inte en vanlig fil)")
    elif [[ -n "$entry" ]]; then
      mismatches+=("$path (borttagen på servern men finns i målcommiten)")
    fi
  done
  if (( ${#mismatches[@]} > 0 )); then
    echo
    echo "Ändrade filer på servern som skiljer sig från det som ska deployas:"
    printf '  %s\n' "${mismatches[@]}"
    stop "Servern har ändringar som en deploy skulle skriva över."
  fi

  # 2. Files the target adds must not already exist on the server as
  #    untracked or ignored files (git would refuse, or silently overwrite
  #    ignored ones).
  collisions=()
  while IFS= read -r -d '' path; do
    if [[ -e "$path" || -L "$path" ]]; then
      collisions+=("$path")
    fi
  done < <(git diff --name-only -z --diff-filter=A HEAD "$target" --)
  if (( ${#collisions[@]} > 0 )); then
    echo
    echo "Filer som målcommiten lägger till men som redan finns på servern utanför git:"
    printf '  %s\n' "${collisions[@]}"
    stop "En deploy skulle skriva över filer som bara finns på servern."
  fi

  # 3. Incoming composer files must be consistent and installable on this
  #    server's PHP. Checked in a scratch directory, before anything changes.
  git show "$target:composer.json" > "$tmp/composer.json"
  git show "$target:composer.lock" > "$tmp/composer.lock"
  if ! (cd "$tmp" && "$COMPOSER_BIN" validate --no-check-publish --no-interaction > "$tmp/validate.log" 2>&1); then
    sed 's/^/  /' "$tmp/validate.log"
    stop "composer validate underkände målcommitens composer.json/composer.lock."
  fi
  if ! (cd "$tmp" && "$COMPOSER_BIN" check-platform-reqs --lock --no-dev --no-interaction > "$tmp/platform.log" 2>&1); then
    sed 's/^/  /' "$tmp/platform.log"
    stop "Målcommitens composer.lock passar inte serverns PHP-miljö."
  fi

  # 4. Active config on the server must equal config/sync, otherwise the
  #    config:import in drush deploy would overwrite it.
  if ! config_diff="$("$DRUSH" config:status --format=list 2> "$tmp/drush.err")"; then
    sed 's/^/  /' "$tmp/drush.err"
    stop "drush config:status misslyckades."
  fi
  if has_content "$config_diff"; then
    echo
    echo "Config på servern som skiljer sig från config/sync:"
    sed '/^[[:space:]]*$/d; s/^/  /' <<< "$config_diff"
    stop "Config har ändrats på servern (troligen i admin) utan att exporteras. Kör ~/bin/drupal-uppdatera.sh på servern, så erbjuds en export och commit."
  fi

  echo
  if (( ${#changed[@]} > 0 )); then
    echo "Kontrollen är grön. Ändrade filer på servern är identiska med målcommiten:"
    printf '  %s\n' "${changed[@]}"
  else
    echo "Kontrollen är grön. Servern har inga lokala ändringar."
  fi
fi

if [[ "$dry_run" == true ]]; then
  echo
  echo "TORRKÖRNING ($mode): skulle nu deploya $target. Inget har ändrats."
  exit 0
fi

# --- Apply ----------------------------------------------------------------
if [[ "$mode" == "normal" ]]; then
  touched=true
  if (( ${#changed[@]} > 0 )); then
    backup="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-${head:0:8}"
    mkdir -p "$backup"
    for path in "${changed[@]}"; do
      if [[ -f "$path" ]]; then
        mkdir -p "$backup/$(dirname "$path")"
        cp -p -- "$path" "$backup/$path"
      fi
      echo "$path" >> "$backup/FILER.txt"
    done
    echo "Säkerhetskopia av ändrade filer: $backup"

    # The files are already identical to the target; this only brings the
    # index in line so the fast-forward is not refused. Content never goes
    # backwards at any point.
    for path in "${changed[@]}"; do
      if [[ -n "$(git ls-tree "$target" -- "$path")" ]]; then
        git checkout --quiet "$target" -- "$path"
      else
        git rm --cached --quiet --ignore-unmatch -- "$path"
      fi
    done
  fi

  if ! git merge --ff-only --quiet "$target"; then
    # Put the index back; the working tree content is unchanged.
    if (( ${#changed[@]} > 0 )); then
      git reset --quiet HEAD -- "${changed[@]}" || true
    fi
    stop "git merge --ff-only misslyckades. Indexet är återställt, filernas innehåll är oförändrat."
  fi
  echo "Koden är uppdaterad: $head -> $(git rev-parse HEAD)"
fi

touched=true
echo
echo "== composer install"
"$COMPOSER_BIN" install --no-dev --optimize-autoloader --no-interaction
echo
echo "== drush deploy"
"$DRUSH" deploy -y
"$DRUSH" cache:rebuild
echo
echo "== Efterkontroll"
bash drift/post-deploy.sh
echo
echo "Deploy klar: $(git rev-parse HEAD)"
