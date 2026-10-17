#!/usr/bin/env bash
# Installs the latest Constellation build (macOS or Linux). Uninstall with --uninstall.
#   curl -fsSL https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/constellation/install.sh | bash
set -euo pipefail

BASE="https://github.com/alexlol87/public_ish_projects/releases/download/constellation-latest"
BIN="$HOME/.local/bin/constellation"
DESKTOP="$HOME/.local/share/applications/constellation.desktop"
ICON="$HOME/.local/share/icons/constellation.png"

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

os=$(uname -s)

if [ "${1:-}" = "--uninstall" ]; then
  case "$os" in
    Darwin) rm -rf /Applications/Constellation.app "$HOME/Applications/Constellation.app" ;;
    Linux)  rm -f "$BIN" "$DESKTOP" "$ICON" ;;
  esac
  say "Constellation removed (your Vaults are untouched)."
  exit 0
fi
[ $# -eq 0 ] || die "usage: install.sh [--uninstall]"

command -v curl >/dev/null || die "curl is required"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch() { say "Downloading $1"; curl -fSL --progress-bar "$BASE/$1" -o "$tmp/$1" || die "download failed: $BASE/$1"; }

case "$os" in
  Darwin)
    fetch Constellation-macos.zip
    command -v ditto >/dev/null || die "ditto not found"
    ditto -x -k "$tmp/Constellation-macos.zip" "$tmp/out"
    dest=/Applications
    [ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
    rm -rf "$dest/Constellation.app"
    mv "$tmp/out/Constellation.app" "$dest/"
    xattr -dr com.apple.quarantine "$dest/Constellation.app" 2>/dev/null || true
    say "Installed $dest/Constellation.app"
    echo "Open it from Launchpad/Spotlight, or: open '$dest/Constellation.app'"
    ;;
  Linux)
    case "$(uname -m)" in
      x86_64|amd64)  arch=x86_64 ;;
      aarch64|arm64) arch=aarch64 ;;
      *) die "unsupported architecture: $(uname -m)" ;;
    esac
    fetch "Constellation-linux-$arch.AppImage"
    mkdir -p "$(dirname "$BIN")" "$(dirname "$DESKTOP")"
    install -m 755 "$tmp/Constellation-linux-$arch.AppImage" "$BIN"
    # Icon: pull it out of the AppImage if possible, otherwise the entry just has no icon.
    icon=""
    if (cd "$tmp" && APPIMAGE_EXTRACT_AND_RUN=1 "$BIN" --appimage-extract 'usr/share/icons/hicolor/128x128/apps/*.png' >/dev/null 2>&1); then
      png=$(find "$tmp/squashfs-root" -name '*.png' -type f 2>/dev/null | head -n1)
      if [ -n "$png" ]; then
        mkdir -p "$(dirname "$ICON")"; cp "$png" "$ICON"; icon="$ICON"
      fi
    fi
    cat > "$DESKTOP" <<DESK
[Desktop Entry]
Type=Application
Name=Constellation
Comment=Notes for a Vault of linked markdown Notes
Exec=$BIN
${icon:+Icon=$icon}
Categories=Office;Utility;
Terminal=false
DESK
    say "Installed $BIN and $DESKTOP"
    echo "Run 'constellation' (make sure ~/.local/bin is on your PATH) or find it in your app menu."
    echo "AppImages need FUSE 2; without it run: APPIMAGE_EXTRACT_AND_RUN=1 constellation"
    echo "Prefer a package? Download Constellation-linux-$arch.deb from $BASE/ and run: sudo apt install ./Constellation-linux-$arch.deb"
    ;;
  *) die "unsupported OS: $os" ;;
esac
