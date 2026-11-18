#!/usr/bin/env bash
#
# lokal-synk.sh - keeps the local DDEV environment in step with git, so
# development always happens on the same versions as production.
#
# Runs automatically, never by hand:
#   --efter-start   DDEV post-start hook (.ddev/config.yaml): fetch from
#                   GitHub, fast-forward main when it is safe, then align.
#   --efter-pull    git hooks post-merge / post-rewrite: align after a pull,
#                   merge or rebase.
#
# "Align" means: composer install, and if the database lags behind the code,
# a ddev snapshot followed by drush deploy (updatedb + config:import).
#
# It never blocks anything and always exits 0. When it cannot act safely
# (unsaved work, config that may be your own unexported work) it says so and
# leaves things alone; the pre-push hook then stops any push that would be
# wrong.
#
# Written for the bash 3.2 that ships with macOS.

set -o pipefail

DDEV="${DDEV:-ddev}"
mode="${1:-}"

cd "$(git rev-parse --show-toplevel)" || exit 0
git_dir="$(git rev-parse --git-dir)"
# Commit the database was last known to match, kept while an align is owed.
pending_file="$git_dir/drift-synk-fran"

note() {
  echo "[lokal-synk] $*"
}

has_content() {
  grep -q '[^[:space:]]' <<< "$1"
}

ddev_running() {
  [ "$("$DDEV" describe -j 2> /dev/null | jq -r '.raw.status' 2> /dev/null)" = "running" ]
}

# Names of config items where the database differs from config/sync.
# Returns non-zero if drush fails.
config_differences() {
  local output
  output="$("$DDEV" drush config:status --format=list 2> /dev/null)" || return 1
  sed '/^[[:space:]]*$/d' <<< "$output"
}

# Make sure the versioned hooks in drift/hooks are the active ones.
if [ "$(git config --get core.hooksPath)" != "drift/hooks" ]; then
  git config core.hooksPath drift/hooks
  note "Git-hookarna i drift/hooks är nu aktiva."
fi

# Remembers that the database must be brought up to date from <commit>.
# An older marker wins, so the range always covers every change not yet
# applied.
remember_base() {
  if [ ! -s "$pending_file" ] && [ -n "$1" ]; then
    echo "$1" > "$pending_file"
  fi
}

align() {
  local base cfg updb name unsafe snapshot
  base="$(cat "$pending_file" 2> /dev/null)"

  if ! ddev_running; then
    note "DDEV körs inte. Den lokala miljön synkas automatiskt nästa gång du startar DDEV."
    return 0
  fi

  if ! "$DDEV" composer install --no-interaction > /dev/null 2>&1; then
    note "ddev composer install misslyckades. Kör det för hand och läs felet."
    return 0
  fi

  if ! cfg="$(config_differences)"; then
    note "ddev drush config:status misslyckades. Ingen databassynk gjord."
    return 0
  fi
  if ! updb="$("$DDEV" drush updatedb:status --format=json 2> /dev/null)"; then
    note "ddev drush updatedb:status misslyckades. Ingen databassynk gjord."
    return 0
  fi

  if ! has_content "$cfg" && ! has_content "$updb"; then
    rm -f "$pending_file"
    note "Lokal miljö i fas med git ($(git rev-parse --short HEAD))."
    return 0
  fi

  # A config:import overwrites the database with config/sync. That is only
  # safe for items git itself changed since the database was last in step;
  # anything else may be your own unexported work in the admin UI.
  unsafe=""
  if has_content "$cfg"; then
    if [ -z "$base" ] || ! git cat-file -e "$base^{commit}" 2> /dev/null; then
      unsafe="$cfg"
    else
      changed_config="$(git diff --name-only "$base" HEAD -- config/sync)"
      while IFS= read -r name; do
        [ -z "$name" ] && continue
        if ! grep -qxF "config/sync/$name.yml" <<< "$changed_config"; then
          unsafe="$unsafe$name"$'\n'
        fi
      done <<< "$cfg"
    fi
  fi

  if has_content "$unsafe"; then
    note "Config i din lokala databas skiljer sig från config/sync utan att git har ändrat den:"
    sed '/^$/d; s/^/    /' <<< "$unsafe"
    note "Det kan vara ditt eget oexporterade arbete, så inget importeras automatiskt."
    note "Är det ditt arbete: ddev drush config:export -y och committa."
    note "Är det inte ditt: ddev drush deploy -y"
    return 0
  fi

  snapshot="fore-synk-$(date +%Y%m%d-%H%M%S)"
  if ! "$DDEV" snapshot --name "$snapshot" > /dev/null 2>&1; then
    note "ddev snapshot misslyckades. Ingen databassynk gjord."
    return 0
  fi
  note "Databasen ligger efter koden. Ögonblicksbild tagen ($snapshot), kör drush deploy ..."
  if ! "$DDEV" drush deploy -y; then
    note "drush deploy misslyckades. Återställ vid behov: ddev snapshot restore $snapshot"
    return 0
  fi
  rm -f "$pending_file"
  note "Lokal miljö i fas med git ($(git rev-parse --short HEAD))."
}

case "$mode" in
  --efter-pull)
    remember_base "$(git rev-parse -q --verify ORIG_HEAD)"
    align
    ;;

  --efter-start)
    branch="$(git symbolic-ref --short -q HEAD)"
    if [ "$branch" = "main" ] && git fetch --quiet origin; then
      behind="$(git rev-list --count HEAD..origin/main)"
      ahead="$(git rev-list --count origin/main..HEAD)"
      if [ "$behind" -gt 0 ]; then
        dirty="$(git status --porcelain --untracked-files=no)"
        if [ "$ahead" -gt 0 ]; then
          note "GitHub har $behind nya commits och du har $ahead egna. Kör: git pull --rebase (miljön synkas sedan automatiskt)."
        elif has_content "$dirty"; then
          note "GitHub har $behind nya commits, men du har osparade ändringar. Committa dem och kör git pull (miljön synkas sedan automatiskt)."
        else
          old_head="$(git rev-parse HEAD)"
          # Hooks are switched off for this merge; align runs right below.
          if git -c core.hooksPath=/dev/null merge --ff-only --quiet origin/main; then
            remember_base "$old_head"
            note "Hämtade $behind nya commits från GitHub."
          else
            note "Kunde inte hämta från GitHub automatiskt (git merge --ff-only misslyckades)."
          fi
        fi
      fi
    elif [ "$branch" = "main" ]; then
      note "Kunde inte nå GitHub. Hämtning hoppas över."
    fi
    align
    ;;

  *)
    note "Okänt läge '$mode'. Används av DDEV och git-hookarna."
    ;;
esac
exit 0
