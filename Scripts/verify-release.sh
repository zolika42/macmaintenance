#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || { echo 'macOS ARM64 required'; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version'; exit 1; }
name="MacMaintenance-$version-arm64.dmg"
image="$PWD/Releases/$name"
sidecar="$image.sha256"
[[ -f $image && ! -L $image && -f $sidecar && ! -L $sidecar ]] || { echo 'Missing or unsafe release files'; exit 1; }
# Never pass arbitrary paths from a checksum sidecar to shasum -c.
expected=$(shasum -a 256 "$image" | awk '{print $1}')
[[ $(wc -c < "$sidecar" | tr -d ' ') == $((${#expected}+2+${#name}+1)) ]] || { echo 'Unexpected checksum format'; exit 1; }
[[ $(cat "$sidecar") == "$expected  $name" ]] || { echo 'Checksum mismatch'; exit 1; }
hdiutil verify "$image"
mount=$(mktemp -d "${TMPDIR:-/tmp}/macmaintenance-verify.XXXXXX")
mount=$(cd "$mount" && pwd -P)
attached=0
cleanup() {
    if [[ $attached == 1 ]]; then
        if ! hdiutil detach "$mount" >/dev/null; then echo "ERROR: detach manually: $mount" >&2; return 1; fi
    fi
    if [[ -d "$mount" ]]; then rmdir "$mount"; fi
}
trap 'cleanup || true' EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$image" >/dev/null
attached=1
app="$mount/MacMaintenance.app"
plist="$app/Contents/Info.plist"
[[ -d $app && ! -L $app && -f $plist && ! -L $plist ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist") == local.macmaintenance.toolkit ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist") == "$version" ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist") == MacMaintenance ]]
[[ -f "$app/Contents/MacOS/MacMaintenance" && ! -L "$app/Contents/MacOS/MacMaintenance" ]]
[[ -f "$app/Contents/Resources/AppIcon.icns" && ! -L "$app/Contents/Resources/AppIcon.icns" ]]
xcrun lipo -verify_arch arm64 "$app/Contents/MacOS/MacMaintenance"
codesign --verify --deep --strict --verbose=2 "$app"
[[ -L "$mount/Applications" && $(readlink "$mount/Applications") == /Applications ]]
[[ -f "$mount/README.txt" && ! -L "$mount/README.txt" ]]
[[ -f "$mount/LICENSE.txt" && -f "$mount/PRIVACY.txt" ]]
cmp LICENSE "$mount/LICENSE.txt"
cmp LICENSE "$app/Contents/Resources/LICENSE.txt"
if [[ -f Resources/UpdatePublicKey.txt ]]; then cmp Resources/UpdatePublicKey.txt "$app/Contents/Resources/UpdatePublicKey.txt"; fi
hdiutil detach "$mount" >/dev/null
attached=0
if [[ -d "$mount" ]]; then rmdir "$mount"; fi
trap - EXIT
printf '=== RELEASE_CONTENT_PASS === %s\n' "$image"
