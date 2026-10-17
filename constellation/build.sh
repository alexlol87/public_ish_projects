#!/usr/bin/env bash
# Builds Constellation from source and installs it locally (use when downloads are blocked).
#   ./build.sh               build and install
#   ./build.sh --no-install  build only
set -euo pipefail
cd "$(dirname "$0")"

install=1
case "${1:-}" in
  "") ;;
  --no-install) install=0 ;;
  *) echo "usage: build.sh [--no-install]" >&2; exit 1 ;;
esac

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
os=$(uname -s)

command -v cargo >/dev/null || die "cargo not found (install Rust: https://rustup.rs)"
command -v npm >/dev/null || die "npm not found (install Node 22+)"
if [ "$os" = Linux ] && ! pkg-config --exists webkit2gtk-4.1 2>/dev/null; then
  die "webkit2gtk-4.1 not found. Install the build dependencies:
  sudo apt install libwebkit2gtk-4.1-dev libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev build-essential curl file"
fi

npm ci
npm run tauri build

bundle="${CARGO_TARGET_DIR:-target}/release/bundle"
[ -d "$bundle" ] || die "no bundles found in $bundle"
echo "==> Built: $bundle"
[ "$install" = 1 ] || exit 0

case "$os" in
  Darwin)
    app="$bundle/macos/Constellation.app"
    [ -d "$app" ] || die "$app not found"
    mkdir -p build
    cp "$bundle"/dmg/*.dmg build/Constellation.dmg 2>/dev/null || echo "no .dmg produced"
    dest=/Applications
    [ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
    rm -rf "$dest/Constellation.app"
    cp -R "$app" "$dest/"
    xattr -dr com.apple.quarantine "$dest/Constellation.app" 2>/dev/null || true
    codesign --force --deep -s - "$dest/Constellation.app"
    echo "==> Installed $dest/Constellation.app (dmg in build/)"
    ;;
  Linux)
    bin="$HOME/.local/bin/constellation"
    desktop="$HOME/.local/share/applications/constellation.desktop"
    mkdir -p "$(dirname "$bin")" "$(dirname "$desktop")"
    appimage=$(find "$bundle/appimage" -name '*.AppImage' 2>/dev/null | head -n1)
    [ -n "$appimage" ] || die "no AppImage in $bundle/appimage"
    install -m 755 "$appimage" "$bin"
    cat > "$desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Constellation
Exec=$bin
Categories=Office;Utility;
Terminal=false
DESK
    echo "==> Installed $bin and $desktop (a .deb is in $bundle/deb)"
    ;;
  *) die "unsupported OS: $os" ;;
esac
