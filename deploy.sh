#!/bin/sh
# Deploy gob.betelkyrkan.se to production (routine deploy AFTER the
# initial cutover to the web/-docroot layout is done).
# Usage: ./deploy.sh
# Requires: ssh key access to mol@e-pro.se -p 1369, mol in www-data group.
#
# Files under web/sites/default/files/ live on the server and are never
# synced. Config changes are imported; the database is not touched here.

set -e

REMOTE="mol@e-pro.se"
REMOTE_PORT="1369"
REMOTE_PATH="/var/www/gob.betelkyrkan.se"
SSH="ssh -p $REMOTE_PORT"
# GNU rsync (Homebrew) - macOS openrsync lacks the --chmod flags.
RSYNC="/opt/homebrew/bin/rsync"

echo "==> Syncing files..."
$RSYNC -rltz --delete --progress \
  -e "$SSH" \
  --exclude='.git/' \
  --exclude='.ddev/' \
  --exclude='.claude/' \
  --exclude='/_import/' \
  --exclude='/private/' \
  --exclude='/CLAUDE.md' \
  --exclude='/deploy.sh' \
  --exclude='*.sql' \
  --exclude='*.sql.gz' \
  --exclude='web/sites/default/settings.ddev.php' \
  --exclude='web/sites/default/files/' \
  /Users/mol/Web/gob/ \
  "$REMOTE:$REMOTE_PATH"

echo "==> Fixing ownership and permissions..."
$SSH $REMOTE "
  cd $REMOTE_PATH
  find . -not -path './web/sites/default/files*' -user mol -exec chown mol:www-data {} \;
  find . -not -path './web/sites/default/files*' -type d -exec chmod 755 {} \;
  find . -not -path './web/sites/default/files*' -type f -exec chmod 644 {} \;
  chmod 440 web/sites/default/settings.php
  find vendor/bin -type f -exec chmod 755 {} \;
"

echo "==> Importing config and rebuilding..."
$SSH $REMOTE "cd $REMOTE_PATH && php vendor/bin/drush config:import -y && php vendor/bin/drush cr"

echo "==> Done. Site: https://gob.betelkyrkan.se"
