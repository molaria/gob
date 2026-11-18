#!/bin/bash
#
# kor-alla.sh - runs every drift test. Safe to run at any time: all
# scenarios use throwaway git worlds in temp directories.
#
#   drift/test/kor-alla.sh
#
# The Mac side runs with macOS' own bash 3.2 (what the git hooks get), the
# server side inside the DDEV container (Linux, bash 5, flock, php, like the
# server). To include the full-flow scenarios for ~/bin/drupal-uppdatera.sh,
# point UPDATE_SCRIPT at a local copy of it:
#
#   UPDATE_SCRIPT=~/drupal-uppdatera.sh drift/test/kor-alla.sh

cd "$(dirname "$0")/../.." || exit 1

echo "===== Mac-sidan (lokal-synk.sh och git-hookarna)"
/bin/bash drift/test/test-lokal.sh
lokal=$?

echo
echo "===== Serversidan (deploy.sh, före-/efter-uppdatering.sh)"
if [ -n "${UPDATE_SCRIPT:-}" ]; then
  ddev exec 'cat > /tmp/drupal-uppdatera.sh' < "$UPDATE_SCRIPT" || exit 1
  ddev exec 'UPDATE_SCRIPT=/tmp/drupal-uppdatera.sh bash drift/test/test-server.sh'
else
  ddev exec 'bash drift/test/test-server.sh'
fi
server=$?

echo
if [ "$lokal" -eq 0 ] && [ "$server" -eq 0 ]; then
  echo "ALLA TESTER GRÖNA."
  exit 0
fi
echo "NÅGOT TEST FALLERADE (se ovan)."
exit 1
