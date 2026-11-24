#!/bin/bash
set -euo pipefail
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || { echo 'ERROR: Apple Silicon macOS required for app build.'; exit 1; }
sw_vers
xcode-select -p
xcodebuild -version
swift --version
xcrun --sdk macosx --show-sdk-version
git --version
for cmd in swift xcrun codesign hdiutil ditto plutil; do command -v "$cmd" >/dev/null; done
printf '\n=== DOCTOR_PASS ===\n'
