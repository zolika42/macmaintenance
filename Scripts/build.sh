#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || { echo 'ERROR: macOS ARM64 required.'; exit 1; }
configuration=${1:-release}
[[ $configuration == release || $configuration == debug ]] || exit 2
swift build -c "$configuration" --arch arm64
bin=$(swift build -c "$configuration" --arch arm64 --show-bin-path)
mkdir -p build
stage=$(mktemp -d "$PWD/build/.app-stage.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
app="$stage/MacMaintenance.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/MacMaintenance" "$app/Contents/MacOS/MacMaintenance"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [[ -f Resources/UpdatePublicKey.txt && ! -L Resources/UpdatePublicKey.txt ]]; then cp Resources/UpdatePublicKey.txt "$app/Contents/Resources/UpdatePublicKey.txt"; fi
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
plutil -lint "$app/Contents/Info.plist"
xcrun lipo -verify_arch arm64 "$app/Contents/MacOS/MacMaintenance"
codesign --force --sign - "$app"
codesign --verify --strict --verbose=2 "$app"
# Replace only a generated bundle with the expected identifier, and never a symlink.
output="$PWD/build/MacMaintenance.app"
if [[ -e "$output" || -L "$output" ]]; then
    [[ -d "$output" && ! -L "$output" && $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$output/Contents/Info.plist") == local.macmaintenance.toolkit ]] || { echo 'Unexpected existing build app; refusing replacement.'; exit 1; }
    rm -rf -- "$output"
fi
mv "$app" "$output"
echo "=== BUILD_PASS === $output"
