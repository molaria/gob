#!/usr/bin/env bash
#
# efter-uppdatering.sh - run by ~/bin/drupal-uppdatera.sh on the server
# AFTER a successful composer update + drush updb + drush cr.
#
# Exports any config the update changed, checks that only files an update
# may touch have changed, then commits and pushes them to GitHub with
# [skip ci] (the server already runs this code, so no deploy is needed).
# Git is thereby always in step with production, and the Mac picks the
# update up automatically.
#
# Can also be run by hand from the site root to commit a finished update.
#
# Exit 0: committed and pushed (or nothing to commit). Exit 1: stopped.

set -euo pipefail
cd "$(dirname "$0")/.."
source drift/lib-server.sh

COMPOSER_BIN="${COMPOSER_BIN:-composer}"

take_lock_unless_held

# The commit must describe a finished update: everything in composer.lock
# installed, every database update run. No --no-dev here, to match the
# plain `composer update` that drupal-uppdatera.sh runs.
install_check="$("$COMPOSER_BIN" install --dry-run --no-interaction 2>&1)" \
  || stop "composer install --dry-run misslyckades. Inget committat."
grep -q "Nothing to install, update or remove" <<< "$install_check" \
  || stop "vendor matchar inte composer.lock, uppdateringen verkar inte ha gått klart. Inget committat."
updb="$("$DRUSH" updatedb:status --format=json 2> /dev/null)" \
  || stop "drush updatedb:status misslyckades. Inget committat."
if has_content "$updb"; then
  stop "Det finns databasuppdateringar som inte körts. Inget committat."
fi

config_list="$(config_differences)" || stop "drush config:status misslyckades. Inget committat."
if has_content "$config_list"; then
  say "Uppdateringen ändrade config, exporterar:"
  sed 's/^/    /' <<< "$config_list"
  "$DRUSH" config:export -y > /dev/null
  remaining="$(config_differences)" || stop "drush config:status misslyckades. Inget committat."
  if has_content "$remaining"; then
    stop "Config skiljer sig fortfarande efter export. Inget committat."
  fi
fi

collect_changed_paths
if (( ${#CHANGED[@]} == 0 )); then
  say "Inga spårade filer ändrades. Inget att committa."
  exit 0
fi

find_not_allowed
if (( ${#NOT_ALLOWED[@]} > 0 )); then
  say "Filer som en uppdatering inte ska ändra:"
  printf '    %s\n' "${NOT_ALLOWED[@]}"
  stop "Inget committat. Nästa deploy stoppas tills detta är utrett."
fi

# Package changes, read from the lock files before and after.
package_changes="$(git show HEAD:composer.lock | "$PHP_BIN" -r '
  $versions = function ($lock) {
    $packages = array_merge($lock["packages"] ?? [], $lock["packages-dev"] ?? []);
    return array_column($packages, "version", "name");
  };
  $old = $versions(json_decode(stream_get_contents(STDIN), true) ?? []);
  $new = $versions(json_decode(file_get_contents("composer.lock"), true) ?? []);
  ksort($new);
  foreach ($new as $name => $version) {
    if (!isset($old[$name])) {
      echo "$name: ny, $version\n";
    }
    elseif ($old[$name] !== $version) {
      echo "$name: {$old[$name]} -> $version\n";
    }
  }
  foreach ($old as $name => $version) {
    if (!isset($new[$name])) {
      echo "$name: borttagen ($version)\n";
    }
  }
')"

core_line="$(grep '^drupal/core: ' <<< "$package_changes" || true)"
package_count="$(grep -c . <<< "$package_changes" || true)"
if [[ -n "$core_line" ]]; then
  subject="Serveruppdatering: ${core_line#drupal/core: } (drupal/core)"
  (( package_count > 1 )) && subject="$subject + $((package_count - 1)) paket"
elif (( package_count > 0 )); then
  subject="Serveruppdatering: $package_count paket"
else
  subject="Serveruppdatering: config"
fi

message="$(mktemp)"
trap 'rm -f "$message"' EXIT
{
  echo "$subject [skip ci]"
  echo
  echo "Gjord på servern med ~/bin/drupal-uppdatera.sh och committad"
  echo "automatiskt av drift/efter-uppdatering.sh."
  if [[ -n "$package_changes" ]]; then
    echo
    echo "Paket:"
    sed 's/^/- /' <<< "$package_changes"
  fi
  if has_content "$config_list"; then
    echo
    echo "Config:"
    sed 's/^/- /' <<< "$config_list"
  fi
} > "$message"

git add -A -- "${CHANGED[@]}"
git commit --quiet -F "$message"
say "Committat: $(git log -1 --format='%h %s')"

push_to_github || stop "Committen är gjord på servern men pushen till GitHub misslyckades. Inget är förlorat: kör uppdateringsskriptet igen, så erbjuds en ny push."
say "Pushat till GitHub."
