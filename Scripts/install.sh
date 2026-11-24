#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || { echo 'macOS ARM64 required'; exit 1; }
action=${1:-install}
[[ $action == install || $action == uninstall || $action == rollback || $action == backups ]] || exit 2
dest=${INSTALL_DIR:-/Applications}
[[ $dest == /Applications || $dest == "$HOME/Applications" ]] || { echo 'Invalid INSTALL_DIR'; exit 2; }
if [[ $dest == "$HOME/Applications" && ! -e $dest && ! -L $dest ]]; then mkdir "$dest"; fi
[[ -d $dest && ! -L $dest && $(cd "$dest" && pwd -P) == "$dest" ]] || { echo 'Unsafe installation directory'; exit 2; }
app="$dest/MacMaintenance.app"
store="$dest/.MacMaintenance-backups"
exists() { [[ -e $1 || -L $1 ]]; }
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }
verify_app() {
    local bundle=$1 version
    [[ -d $bundle && ! -L $bundle && -d $bundle/Contents && ! -L $bundle/Contents && -f $bundle/Contents/Info.plist && ! -L $bundle/Contents/Info.plist ]] || return 1
    [[ $(plist_value "$bundle" CFBundleIdentifier) == local.macmaintenance.toolkit ]] || return 1
    [[ $(plist_value "$bundle" CFBundleExecutable) == MacMaintenance ]] || return 1
    version=$(plist_value "$bundle" CFBundleShortVersionString) || return 1
    [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    [[ -d $bundle/Contents/MacOS && ! -L $bundle/Contents/MacOS && -f $bundle/Contents/MacOS/MacMaintenance && ! -L $bundle/Contents/MacOS/MacMaintenance ]] || return 1
    xcrun lipo -verify_arch arm64 "$bundle/Contents/MacOS/MacMaintenance" || return 1
    codesign --verify --deep --strict "$bundle" || return 1
}
if ! exists "$store"; then (umask 077; mkdir "$store") || exit 1; fi
[[ -d $store && ! -L $store && -O $store && $(stat -f '%Lp' "$store") == 700 ]] || { echo 'Unsafe backup directory (must be owned by you, mode 700)'; exit 1; }
if [[ $action == backups ]]; then
    for item in "$store"/backup.*; do
        [[ -d $item && ! -L $item && -d $item/MacMaintenance.app && ! -L $item/MacMaintenance.app ]] || continue
        printf '%s  version %s\n' "${item##*/}" "$(plist_value "$item/MacMaintenance.app" CFBundleShortVersionString || echo unknown)"
    done
    exit 0
fi
if pgrep -x MacMaintenance >/dev/null 2>&1; then echo 'Quit MacMaintenance first.'; exit 1; fi
lock="$store/.install-lock"
mkdir "$lock" || { echo "Installer busy or stale lock: $lock"; exit 1; }
stage=''; backup=''; moved=0; placed=0; committed=0
move_exclusive() { "$stage/exclusive-move" "$1" "$2"; }
cleanup() {
    local rc=$?
    trap - EXIT HUP INT TERM
    if [[ $committed == 0 && $placed == 1 ]]; then
        if ! move_exclusive "$app" "$stage/failed.app"; then echo "Failed installation remains at: $app" >&2; fi
    fi
    if [[ $committed == 0 && $moved == 1 ]]; then
        if ! exists "$app"; then
            if move_exclusive "$backup/MacMaintenance.app" "$app"; then echo 'Previous app restored.' >&2; else echo "Restore failed; backup retained: $backup" >&2; fi
        else echo "Destination occupied; backup retained: $backup" >&2; fi
    fi
    if [[ -n $stage && -d $stage && ! -L $stage ]]; then rm -rf -- "$stage"; fi
    rmdir "$lock" || true
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
if exists "$app"; then verify_app "$app" || { echo 'Existing app is not a valid MacMaintenance bundle; refusing replacement.'; exit 1; }; fi
if [[ $action == uninstall && ! -d $app ]]; then echo 'App not installed'; committed=1; exit 0; fi
stage=$(mktemp -d "$store/stage.XXXXXX")
xcrun swiftc Scripts/exclusive-move.swift -o "$stage/exclusive-move"
if [[ $action != uninstall ]]; then
    if [[ $action == rollback ]]; then
        id=${2:-}
        [[ $id =~ ^backup\.[a-zA-Z0-9]+$ && -d $store/$id && ! -L $store/$id ]] || { echo 'Choose a backup ID from make install-backups'; exit 2; }
        source="$store/$id/MacMaintenance.app"
    else
        source="$PWD/build/MacMaintenance.app"
        expected=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
        [[ $(plist_value "$source" CFBundleShortVersionString) == "$expected" ]] || { echo 'Build version mismatch'; exit 1; }
    fi
    verify_app "$source" || { echo 'Invalid source bundle'; exit 1; }
    ditto "$source" "$stage/MacMaintenance.app"
    verify_app "$stage/MacMaintenance.app"
    if [[ $action == install && -d $app ]]; then
        # Do not silently downgrade through the normal installation command.
        old=$(plist_value "$app" CFBundleShortVersionString)
        new=$(plist_value "$stage/MacMaintenance.app" CFBundleShortVersionString)
        if ! awk -v old="$old" -v new="$new" 'BEGIN { split(old,a,"."); split(new,b,"."); for(i=1;i<=3;i++) { if(b[i]+0>a[i]+0) exit 0; if(b[i]+0<a[i]+0) exit 1 }; exit 0 }'; then
            echo 'Downgrade refused; use explicit rollback.'; exit 1
        fi
    fi
fi
if pgrep -x MacMaintenance >/dev/null 2>&1; then echo 'MacMaintenance is running; aborting.'; exit 1; fi
if [[ -d $app ]]; then
    backup=$(mktemp -d "$store/backup.XXXXXX")
    move_exclusive "$app" "$backup/MacMaintenance.app"
    moved=1
    printf 'Previous app retained: %s\n' "$backup"
fi
if [[ $action == uninstall ]]; then
    committed=1
    echo '=== UNINSTALL_PASS === App retained as backup; preferences and history untouched.'
    exit 0
fi
move_exclusive "$stage/MacMaintenance.app" "$app"
placed=1
verify_app "$app"
committed=1
if [[ $action == rollback ]]; then echo "=== ROLLBACK_PASS === $app"; else echo "=== INSTALL_PASS === $app"; fi
