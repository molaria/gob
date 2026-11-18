#!/usr/bin/env bash
#
# fore-uppdatering.sh - run by ~/bin/drupal-uppdatera.sh on the server
# BEFORE this site is updated.
#
# Makes sure the server is in step with GitHub, so that what the update
# changes can be committed cleanly afterwards (efter-uppdatering.sh).
# Leftovers from an earlier update that never reached GitHub, and config
# changed in the admin UI, are offered for commit instead of blocking.
#
# Exit 0: go ahead with the update. Exit 1: skip this site (reason printed).
#
# With --status it only reads: prints one line per thing that is out of
# step with GitHub (nothing when all is well) and always exits 0. Used by
# drupal-uppdatera.sh when scanning, so such a site is offered for update
# even when no new packages are available.

set -euo pipefail
cd "$(dirname "$0")/.."
source drift/lib-server.sh

if [[ "${1:-}" == "--status" ]]; then
  if has_content "$(git status --porcelain --untracked-files=no)"; then
    echo "(ändrade filer på servern som inte nått GitHub)"
  fi
  if has_content "$(git rev-list origin/main..HEAD)"; then
    echo "(commits på servern som inte pushats till GitHub)"
  fi
  if has_content "$(config_differences 2> /dev/null || echo fel)"; then
    echo "(config som skiljer sig från config/sync)"
  fi
  exit 0
fi

take_lock_unless_held

if [[ -z "$(git config user.name)" || -z "$(git config user.email)" ]]; then
  stop "git saknar user.name/user.email i $(pwd). Servern kan inte committa sina uppdateringar."
fi

git fetch --quiet origin || stop "Kunde inte nå GitHub (git fetch misslyckades)."
ahead="$(git rev-list --count origin/main..HEAD)"
behind="$(git rev-list --count HEAD..origin/main)"

if (( behind > 0 && ahead > 0 )); then
  stop "Servern och GitHub har gått isär (servern har $ahead egna commits, GitHub $behind nya). Se DEPLOY.md, avsnittet om när servern och GitHub gått isär."
fi
if (( behind > 0 )); then
  stop "GitHub har $behind commit(s) som inte deployats ännu. En deploy väntar, pågår eller har misslyckats (se GitHub Actions). Uppdateringen hoppas över så att de inte krockar."
fi
if (( ahead > 0 )); then
  say "Servern har commits som inte nått GitHub:"
  git log --oneline origin/main..HEAD | sed 's/^/    /'
  ask_yes "Pusha dem till GitHub nu?" || stop "Inget pushat. Uppdateringen hoppas över."
  push_to_github || stop "Pushen till GitHub misslyckades."
  say "Pushat."
fi

config_list="$(config_differences)" || stop "drush config:status misslyckades."

collect_changed_paths
if (( ${#CHANGED[@]} > 0 )); then
  find_not_allowed
  if (( ${#NOT_ALLOWED[@]} > 0 )); then
    say "Ändrade filer på servern som inte hör till en Drupal-uppdatering:"
    printf '    %s\n' "${NOT_ALLOWED[@]}"
    stop "Någon har ändrat filer direkt på servern. De måste utredas för hand innan sajten kan uppdateras."
  fi
  say "Servern har ändringar från en tidigare uppdatering som aldrig committats:"
  printf '    %s\n' "${CHANGED[@]}"
  if has_content "$config_list"; then
    say "Dessutom skiljer sig denna config från config/sync:"
    sed 's/^/    /' <<< "$config_list"
  fi
  ask_yes "Ta med allt detta i den här uppdateringens commit?" || stop "Inget ändrat. Uppdateringen hoppas över."
  exit 0
fi

if has_content "$config_list"; then
  say "Config i databasen skiljer sig från config/sync (troligen ändrad i admin):"
  sed 's/^/    /' <<< "$config_list"
  ask_yes "Exportera och committa den först, som en egen commit?" || stop "Inget ändrat. Uppdateringen hoppas över."

  "$DRUSH" config:export -y > /dev/null
  collect_changed_paths
  for path in "${CHANGED[@]}"; do
    [[ "$path" == config/sync/* ]] || stop "config:export ändrade oväntat $path. Inget committat."
  done
  git add -A -- config/sync
  git commit --quiet -m "Config ändrad i admin på produktionen [skip ci]" -m "$config_list"
  push_to_github || stop "Committen är gjord på servern men pushen till GitHub misslyckades. Kör uppdateringsskriptet igen, så erbjuds en ny push."
  say "Config committad och pushad."
fi

say "Servern är i fas med GitHub. Uppdateringen kan köras."
