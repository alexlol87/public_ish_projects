#!/usr/bin/env bash
# Runs this checkout's install.sh against the published constellation-latest release (Linux), in a throwaway HOME:
# installs, checks the binary, desktop entry and icon, launches the app on the fixture Vault for 10 s, then uninstalls.
set -euo pipefail
cd "$(dirname "$0")/.."
home=$(mktemp -d)
pid=
# Stop the app (it writes under HOME until it is gone) before removing HOME.
trap '[ -z "$pid" ] || { kill -- "-$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }; rm -rf "$home"' EXIT
export HOME="$home"
export TMPDIR="$home/tmp"; mkdir "$TMPDIR" # the AppImage extracts itself under TMPDIR: keep it inside the throwaway HOME

bash install.sh > "$home/install.log" 2>&1 || { cat "$home/install.log"; exit 1; }
for f in .local/bin/constellation .local/share/applications/constellation.desktop .local/share/icons/constellation.png; do
  [ -s "$home/$f" ] || { echo "FAIL: missing $f"; cat "$home/install.log"; exit 1; }
done
grep -q "^Icon=$home/.local/share/icons/constellation.png" "$home/.local/share/applications/constellation.desktop" ||
  { echo "FAIL: desktop entry has no icon"; exit 1; }

vault="$home/vault"; cp -r fixtures/vault "$vault"
CONSTELLATION_VAULT="$vault" APPIMAGE_EXTRACT_AND_RUN=1 setsid xvfb-run -a "$home/.local/bin/constellation" > "$home/run.log" 2>&1 &
pid=$!
sleep 10
kill -0 "$pid" 2>/dev/null || { echo "FAIL: the app quit at launch"; cat "$home/run.log"; exit 1; }
kill -- "-$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; pid=

bash install.sh --uninstall > /dev/null
[ ! -e "$home/.local/bin/constellation" ] || { echo "FAIL: uninstall left the binary"; exit 1; }
echo "install check passed"
