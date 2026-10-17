#!/usr/bin/env bash
# Builds "build/Constellation.app" (release) from the Swift package, ad-hoc signs it, and packs
# build/Constellation.zip and build/Constellation.dmg (app plus an /Applications link).
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

rm -f build/Constellation.zip build/Constellation.dmg
ditto -c -k --keepParent "$app" build/Constellation.zip
stage="$(mktemp -d)"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname Constellation -srcfolder "$stage" -ov -format UDZO build/Constellation.dmg >/dev/null
rm -rf "$stage"
echo "$PWD/$app"
