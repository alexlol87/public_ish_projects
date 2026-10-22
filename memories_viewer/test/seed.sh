#!/bin/sh
# Throwaway HOME with mem.py and four memories, for test/suite.js and trying the extension by hand.
set -e
T=${1:-/tmp/memtest}
rm -rf "$T" && mkdir -p "$T/home/.local_memory_sqlite"
cp "$(dirname "$0")/../../local_memory_sqlite/mem.py" "$T/home/.local_memory_sqlite/"
m() { HOME="$T/home" python3 "$T/home/.local_memory_sqlite/mem.py" "$@" >/dev/null; }
m add --title "Prefer stdlib over new dependencies" --content "$(printf '# Stdlib first\n\nReach for the standard library before adding a package.\n\n- fewer installs\n- fewer CVEs')" --scope global --load always --expires never
m add --title "Answer in short bullets" --content "Keep replies short." --scope global --load on_demand --expires 2026-12-01
m add --title "Build in ~/build worktrees" --content "Native modules crash on network mounts." --scope repo --repo alexlol87/public_ish_projects --load always --expires never
m add --title "Use Bruno for API tests" --content "Collections live in bruno/." --scope repo --repo acme/payments --load on_demand --expires never
