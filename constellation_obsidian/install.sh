#!/bin/sh
# Build the plugin and copy it into a vault: ./install.sh <vault>
set -e
[ -n "$1" ] || { echo "usage: $0 <vault>" >&2; exit 1; }
[ -d "$1" ] || { echo "not a folder: $1" >&2; exit 1; }
vault=$(CDPATH= cd -- "$1" && pwd) # absolute, before the cd below
cd "$(dirname "$0")"
npm run build
mkdir -p "$vault/.obsidian/plugins/constellation"
cp plugin/constellation/* "$vault/.obsidian/plugins/constellation/"
echo "Installed into $vault/.obsidian/plugins/constellation. Enable it in Settings > Community plugins."
