#!/usr/bin/env bash
#
# post-deploy.sh - read-only health check of the production checkout.
#
# Run from the site root. Called by deploy.sh after every deploy, and safe to
# run by hand at any time: it only reads.
#
# Exit 0 when everything is in order, 1 otherwise (each problem is listed).

set -uo pipefail

DRUSH="${DRUSH:-vendor/bin/drush}"
CURL_BIN="${CURL_BIN:-curl}"
SITE_URL="${SITE_URL:-https://gob.betelkyrkan.se}"

problems=0
ok()   { echo "  OK   $*"; }
fail() { echo "  FEL  $*"; problems=$((problems + 1)); }

has_content() {
  grep -q '[^[:space:]]' <<< "$1"
}

# The working tree must match the deployed commit exactly.
dirty="$(git status --porcelain --untracked-files=no)"
if has_content "$dirty"; then
  fail "Spårade filer skiljer sig från git:"
  echo "$dirty" | sed 's/^/         /'
else
  ok "Spårade filer är identiska med $(git rev-parse --short HEAD)"
fi

# All database updates must have run.
if updb="$("$DRUSH" updatedb:status --format=json 2> /dev/null)"; then
  if has_content "$updb"; then
    fail "Det finns databasuppdateringar som inte körts (drush updatedb:status)"
  else
    ok "Inga väntande databasuppdateringar"
  fi
else
  fail "drush updatedb:status misslyckades"
fi

# Active config must equal config/sync.
if config_diff="$("$DRUSH" config:status --format=list 2> /dev/null)"; then
  if has_content "$config_diff"; then
    fail "Config skiljer sig från config/sync:"
    sed '/^[[:space:]]*$/d; s/^/         /' <<< "$config_diff"
  else
    ok "Config är identisk med config/sync"
  fi
else
  fail "drush config:status misslyckades"
fi

# The public front page answers, and member-only pages still refuse
# anonymous visitors (proves the access control survived the deploy).
check_http() {
  local path="$1" expected="$2" code
  code="$("$CURL_BIN" -s -o /dev/null -w '%{http_code}' --max-time 30 "$SITE_URL$path")"
  if [[ "$code" == "$expected" ]]; then
    ok "$path svarar $code"
  else
    fail "$path svarar $code, förväntade $expected"
  fi
}
check_http "/" 200
check_http "/kalendarium" 403

if (( problems > 0 )); then
  echo "Efterkontrollen hittade $problems problem."
  exit 1
fi
echo "Efterkontrollen är grön."
