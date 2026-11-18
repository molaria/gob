#!/usr/bin/env bash
#
# lib-test.sh - fixture and assertion helpers for the drift tests.
# Sourced by test-server.sh and test-lokal.sh. Portable to bash 3.2.
#
# A fixture is a throwaway world in a temp directory:
#   origin.git   bare repo standing in for GitHub
#   dev/         the Mac's checkout
#   server/      the production checkout (with stubbed vendor/bin/drush)
#   state/       the stubs' "database", "vendor" and call log

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STUBS="$REPO_ROOT/drift/test/stubs"

passed=0
failed=0
current=""

scenario() {
  current="$1"
  echo
  echo "--- $current"
}

pass() {
  passed=$((passed + 1))
  echo "  ok    $1"
}

fail() {
  failed=$((failed + 1))
  echo "  FEL   $1"
  # Show what the script under test printed, once per scenario.
  if [ "${shown_for:-}" != "$current" ] && [ -s "${T:-/nonexistent}/out" ]; then
    shown_for="$current"
    echo "        --- utskrift från körningen:"
    sed 's/^/        | /' "$T/out" | tail -40
  fi
}

check() {
  # check "description" command...
  local description="$1"
  shift
  if "$@" > /dev/null 2>&1; then pass "$description"; else fail "$description"; fi
}

output_has() {
  grep -qF -- "$1" "$T/out"
}

finish() {
  echo
  echo "Resultat: $passed godkända, $failed fel."
  [ "$failed" -eq 0 ]
}

git_quiet() {
  git -c init.defaultBranch=main -c advice.detachedHead=false "$@"
}

setup_identity() {
  git config user.name "Test"
  git config user.email "test@example.invalid"
}

write_lock() {
  # write_lock <core-version>
  cat > composer.lock << EOF
{
    "content-hash": "stub",
    "packages": [
        {"name": "drupal/core", "version": "$1"},
        {"name": "drupal/flag", "version": "5.2.2"}
    ],
    "packages-dev": []
}
EOF
}

make_fixture() {
  T="$(mktemp -d)"
  export STUB_STATE="$T/state"
  mkdir -p "$STUB_STATE/db"

  git_quiet init -q --bare "$T/origin.git"
  git_quiet init -q "$T/dev"
  (
    cd "$T/dev" || exit 1
    setup_identity
    git remote add origin "$T/origin.git"
    printf '/vendor/\n/web/core/\n' > .gitignore
    cat > composer.json << 'EOF'
{
    "name": "test/site",
    "extra": {"drupal-scaffold": {"locations": {"web-root": "web/"}}}
}
EOF
    write_lock "11.4.12"
    mkdir -p config/sync web/modules/custom drift/hooks
    echo "a: 1" > config/sync/a.yml
    echo "b: 1" > config/sync/b.yml
    echo "# htaccess v1" > web/.htaccess
    echo "root = true" > .editorconfig
    echo "custom code" > web/modules/custom/x.txt
    cp "$REPO_ROOT"/drift/*.sh drift/
    cp "$REPO_ROOT"/drift/hooks/* drift/hooks/
    chmod +x drift/*.sh drift/hooks/*
    git add -A
    git commit -q -m "init"
    git push -q origin main
  )
  git --git-dir="$T/origin.git" symbolic-ref HEAD refs/heads/main

  git_quiet clone -q "$T/origin.git" "$T/server"
  (
    cd "$T/server" || exit 1
    setup_identity
    mkdir -p web/core vendor/bin
    cat > web/core/composer.json << 'EOF'
{
    "extra": {"drupal-scaffold": {"file-mapping": {
        "[project-root]/.editorconfig": "assets/scaffold/files/editorconfig",
        "[web-root]/.htaccess": "assets/scaffold/files/htaccess"
    }}}
}
EOF
    ln -s "$STUBS/drush" vendor/bin/drush
    cp config/sync/*.yml "$STUB_STATE/db/"
    cp composer.lock "$STUB_STATE/vendor.lock"
  )
}

cleanup_fixture() {
  [ -n "${T:-}" ] && rm -rf "$T"
}

# dev_commit "message" -- then the commands to run in dev/ before committing.
dev_commit() {
  local message="$1"
  shift
  (
    cd "$T/dev" || exit 1
    "$@" > /dev/null
    git add -A
    git commit -q -m "$message"
    git push -q origin main
  )
  git -C "$T/dev" rev-parse HEAD
}

server_head() {
  git -C "$T/server" rev-parse HEAD
}

origin_head() {
  git --git-dir="$T/origin.git" rev-parse main
}
