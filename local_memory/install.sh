#!/usr/bin/env bash
# Installs Local Memory for GitHub Copilot. The work is done by install.py (on Windows: python install.py).
# Usage: ./install.sh [--no-hooks | --uninstall]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
command -v python3 >/dev/null || { echo "python3 is required (macOS: xcode-select --install)" >&2; exit 1; }
exec python3 "$here/install.py" "$@"
