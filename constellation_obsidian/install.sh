#!/bin/sh
# Build the plugin and copy it into a vault: ./install.sh <vault>
set -e
[ -n "$1" ] || { echo "usage: $0 <vault>" >&2; exit 1; }
cd "$(dirname "$0")"
npm run build
mkdir -p "$1/.obsidian/plugins/constellation"
cp plugin/constellation/* "$1/.obsidian/plugins/constellation/"
echo "Installed into $1/.obsidian/plugins/constellation. Enable it in Settings > Community plugins."
