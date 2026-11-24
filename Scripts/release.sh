#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version'; exit 1; }
mkdir -p Releases
stage=$(mktemp -d "$PWD/build/.dmg-stage.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
mkdir "$stage/content"
ditto build/MacMaintenance.app "$stage/content/MacMaintenance.app"
ln -s /Applications "$stage/content/Applications"
cp Docs/PUBLIC_INSTALL.md "$stage/content/README.txt"
cp Docs/USER_GUIDE.md "$stage/content/USER_GUIDE.txt"
cp LICENSE "$stage/content/LICENSE.txt"
cp Docs/PRIVACY.txt "$stage/content/PRIVACY.txt"
hdiutil create -quiet -volname MacMaintenance -srcfolder "$stage/content" -format UDZO "$stage/MacMaintenance.dmg"
hdiutil verify "$stage/MacMaintenance.dmg"
output="$PWD/Releases/MacMaintenance-$version-arm64.dmg"
[[ ! -L "$output" && ! -L "$output.sha256" && ! -d "$output" && ! -d "$output.sha256" ]] || { echo 'Unexpected release path'; exit 1; }
(cd "$stage" && shasum -a 256 MacMaintenance.dmg | sed "s/  MacMaintenance.dmg$/  $(basename "$output")/" > release.sha256)
mv -f "$stage/MacMaintenance.dmg" "$output"
mv -f "$stage/release.sha256" "$output.sha256"
echo "=== RELEASE_PASS === $output"
