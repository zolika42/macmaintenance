#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]]
keydir="$HOME/Library/Application Support/MacMaintenance Publisher"
umask 077
if [[ ! -e "$keydir" && ! -L "$keydir" ]]; then mkdir -m 700 "$keydir"; fi
[[ -d "$keydir" && ! -L "$keydir" && $(/usr/bin/stat -f '%u:%Lp' "$keydir") == "$(id -u):700" ]] || { echo 'Unsafe publisher key directory'; exit 1; }
key="$keydir/ed25519.key"
[[ -f "$key" && ! -L "$key" ]] || { echo 'Publisher key missing; do not generate a replacement for a published key'; exit 1; }
public=$(mktemp -t macmaintenance-public-key)
trap 'rm -f -- "$public"' EXIT
swift Scripts/release-sign.swift keygen "$key" "$public"
cmp "$public" Resources/UpdatePublicKey.txt
bash Scripts/verify-release.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
[[ ! -L Releases/release.json && ! -d Releases/release.json ]]
swift Scripts/release-sign.swift sign "$key" "Releases/MacMaintenance-$version-arm64.dmg" Releases/release.json
echo '=== SIGNED_PUBLICATION_ARTIFACTS_PREPARED ==='
echo 'Not uploaded; see Docs/PUBLICATION.md for outstanding public release gates.'
