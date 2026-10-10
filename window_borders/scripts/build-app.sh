#!/usr/bin/env bash
# Builds "build/Window Borders.app" (Apple Silicon, release) from the Swift package and code-signs it.
# Signs ad hoc by default; set SIGN_IDENTITY to a "Developer ID Application: ..." identity for a stable signature.
# With ad-hoc signing every rebuild is a "new" app to macOS, so Accessibility must be granted again after rebuilding.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release --arch arm64
bin_dir="$(swift build -c release --arch arm64 --show-bin-path)"

app="build/Window Borders.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/WindowBorders" "$app/Contents/MacOS/WindowBorders"
cp Resources/Info.plist "$app/Contents/Info.plist"

# App icon: Resources/AppIcon.png (rendered from AppIcon.svg) -> every size macOS wants -> AppIcon.icns.
iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" > /dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$iconset")"
printf 'APPL????' > "$app/Contents/PkgInfo"

# Hardened runtime needs no entitlements here: the app uses Accessibility (a TCC permission, not an entitlement)
# and is deliberately not sandboxed, because sandboxed apps cannot use the Accessibility API on other apps' windows.
codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"

echo "$PWD/$app"
