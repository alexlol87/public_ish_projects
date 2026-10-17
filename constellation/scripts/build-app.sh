#!/usr/bin/env bash
# Builds "build/Constellation.app" (release) from the Swift package and ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
app="build/Constellation.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Constellation" "$app/Contents/MacOS/Constellation"
cp Resources/Info.plist "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"
codesign --force --sign "${SIGN_IDENTITY:--}" "$app"
codesign --verify --strict "$app"
echo "$PWD/$app"
