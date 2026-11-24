#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || exit 1
if pgrep -x MacMaintenance >/dev/null 2>&1; then echo 'Quit MacMaintenance first.'; exit 1; fi
# Use an isolated home, never the user's actual Applications directory.
fixture=$(mktemp -d "${TMPDIR:-/tmp}/mm-install-test.XXXXXX")
fixture=$(cd "$fixture" && pwd -P)
trap 'rm -rf -- "$fixture"' EXIT
mkdir "$fixture/Applications"
app="$fixture/Applications/MacMaintenance.app"
run() { HOME="$fixture" INSTALL_DIR="$fixture/Applications" bash Scripts/install.sh "$@"; }
check() { codesign --verify --deep --strict "$app"; }
# A foreign destination must never be replaced.
mkdir "$app"; echo sentinel > "$app/keep"
if run install; then echo 'Unexpected foreign bundle acceptance'; exit 1; fi
[[ $(cat "$app/keep") == sentinel ]]
rm "$app/keep"; rmdir "$app"
# First install, replacement, list previous versions, explicit rollback and uninstall.
run install; check
run install; check
listing=$(run backups)
id=$(printf '%s\n' "$listing" | awk 'NR==1 {print $1}')
[[ $id =~ ^backup\.[a-zA-Z0-9]+$ ]]
backup="$fixture/Applications/.MacMaintenance-backups/$id/MacMaintenance.app"
[[ -d $backup ]]
if run rollback '../invalid'; then echo 'Unexpected invalid backup acceptance'; exit 1; fi
check
run rollback "$id"; check
[[ -d $backup ]]
run uninstall
[[ ! -e $app && ! -L $app ]]
run rollback "$id"; check
# The source backup is retained, and no real user directories are touched by installation.
[[ -d $backup ]]
echo '=== INSTALL_SMOKE_PASS ==='
