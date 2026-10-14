#!/usr/bin/env bash
# Installs this status line for Claude Code. Safe to re-run. Usage: ./install.sh [--previous]
#   --previous  restore the older token bar in previous/ instead
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$claude_dir/settings.json"
mkdir -p "$claude_dir"
[ -f "$settings" ] || echo '{}' > "$settings"
cp "$settings" "$settings.bak-statusline"

if [ "${1:-}" = "--previous" ]; then
  install -m 755 "$here/previous/status_line_tokens.sh" "$claude_dir/status_line_tokens.sh"
  block="$here/previous/statusLine.json"
else
  install -m 755 "$here/statusline-command.sh" "$claude_dir/statusline-command.sh"
  block='{"type":"command","command":"~/.claude/statusline-command.sh","refreshInterval":1}'
fi

# merge only the statusLine key, leave the rest of settings.json untouched
python3 - "$settings" "$block" <<'PY'
import json, sys, os
path, block = sys.argv[1], sys.argv[2]
new = json.load(open(block)) if os.path.isfile(block) else json.loads(block)
d = json.load(open(path))
d["statusLine"] = new
json.dump(d, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
echo "statusLine set in $settings (backup: $settings.bak-statusline). Restart Claude Code or wait for the next refresh."
