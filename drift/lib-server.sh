#!/usr/bin/env bash
#
# lib-server.sh - helpers shared by fore-uppdatering.sh and
# efter-uppdatering.sh. Sourced, never run directly.
#
# Environment overrides exist only so drift/test/run-tests.sh can stub the
# tools; production uses the defaults.

DRUSH="${DRUSH:-vendor/bin/drush}"
PHP_BIN="${PHP_BIN:-php}"

say() {
  echo "  $*"
}

stop() {
  echo
  echo "STOPP: $*"
  exit 1
}

has_content() {
  grep -q '[^[:space:]]' <<< "$1"
}

# Asks a yes/no question on the terminal. Anything but an explicit yes is a
# no, including end of input when nobody is there to answer.
ask_yes() {
  local answer=""
  read -r -p "  $1 [j/N] " answer || true
  [[ "$answer" =~ ^[jJyY]$ ]]
}

# The lock is shared with deploy.sh. drupal-uppdatera.sh takes it before
# calling these scripts and sets DRIFT_LOCK_HELD=1; when they are run by hand
# they take it themselves. It is released automatically when the holding
# process exits.
take_lock_unless_held() {
  if [[ "${DRIFT_LOCK_HELD:-}" == "1" ]]; then
    return 0
  fi
  exec 9> "$(git rev-parse --git-dir)/drift.lock"
  flock -n 9 || stop "En deploy eller en annan uppdatering pågår just nu. Försök igen om en stund."
  export DRIFT_LOCK_HELD=1
}

# Prints the names of config items where the database differs from
# config/sync, one per line. Returns non-zero if drush itself fails.
config_differences() {
  local output
  output="$("$DRUSH" config:status --format=list)" || return 1
  sed '/^[[:space:]]*$/d' <<< "$output"
}

# Fills the global array CHANGED with every path git sees as changed:
# modified, deleted and new (untracked, not ignored) files.
collect_changed_paths() {
  CHANGED=()
  local entry status original
  while IFS= read -r -d '' entry; do
    status="${entry:0:2}"
    CHANGED+=("${entry:3}")
    # Renames and copies carry the original path as an extra field.
    if [[ "$status" == R* || "$status" == C* ]]; then
      IFS= read -r -d '' original || true
    fi
  done < <(git status --porcelain=v1 -z --untracked-files=all)
}

# Prints the files Drupal's composer scaffold writes, as repo-relative paths.
# Read from the installed core package, so the list follows the version
# that is actually installed.
scaffold_paths() {
  "$PHP_BIN" -r '
    $root = json_decode(file_get_contents("composer.json"), true);
    $webRoot = rtrim($root["extra"]["drupal-scaffold"]["locations"]["web-root"] ?? "web/", "/");
    $core = json_decode(file_get_contents($webRoot . "/core/composer.json"), true);
    $mapping = $core["extra"]["drupal-scaffold"]["file-mapping"] ?? [];
    foreach (array_keys($mapping) as $key) {
      echo strtr($key, ["[project-root]/" => "", "[web-root]/" => $webRoot . "/"]), "\n";
    }
  '
}

# Fills the global array NOT_ALLOWED with the paths in CHANGED that a server
# update must never commit automatically. Allowed: composer.json,
# composer.lock, config/sync/ and Drupal's scaffold files.
find_not_allowed() {
  NOT_ALLOWED=()
  local scaffold path
  scaffold="$(scaffold_paths)" || stop "Kunde inte läsa scaffold-listan ur web/core/composer.json."
  for path in "${CHANGED[@]}"; do
    case "$path" in
      composer.json | composer.lock | config/sync/*) continue ;;
    esac
    if grep -qxF -- "$path" <<< "$scaffold"; then
      continue
    fi
    NOT_ALLOWED+=("$path")
  done
}

push_to_github() {
  git push --quiet origin HEAD:main
}
