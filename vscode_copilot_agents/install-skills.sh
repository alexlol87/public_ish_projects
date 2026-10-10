#!/usr/bin/env bash
# Install skills from ../skills_updated (or any folder) as personal skills for GitHub Copilot in VS Code.
#
# VS Code loads a skill only if its folder name equals the `name:` in its SKILL.md, and the docs show skills as
# <skills folder>/<name>/SKILL.md. This script copies each skill flat into the target, named after its `name:` field.
# If two skills share a name, the first one found wins, even with FORCE=1.
#
# Usage:
#   ./install-skills.sh                                   # every skill in ../skills_updated -> ~/.copilot/skills
#   ./install-skills.sh ../skills_updated/superpowers     # only the skills under that folder
#   TARGET=/path/to/repo/.github/skills ./install-skills.sh <folder>   # into a repository (shared with the team)
#   FORCE=1 ./install-skills.sh <folder>                  # replace skills that are already installed
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
source_dir="${1:-$here/../skills_updated}"
target="${TARGET:-$HOME/.copilot/skills}"   # a relative TARGET is relative to the current directory

[ -d "$source_dir" ] || { echo "no such folder: $source_dir" >&2; exit 1; }
mkdir -p "$target"
installed=0
skipped=0
seen=$'\n'   # names installed by this run, one per line (bash 3.2 has no associative arrays)

while IFS= read -r -d '' skill_md; do
  dir="$(dirname "$skill_md")"
  # The `name:` field of the first front matter block, without quotes.
  name="$(awk '/^---[[:space:]]*$/ { n++; next } n == 1 && /^name:/ { sub(/^name:[[:space:]]*/, ""); gsub(/["\047[:space:]]/, ""); print; exit }' "$skill_md")"

  if [[ ! "$name" =~ ^[a-z0-9-]{1,64}$ ]]; then
    echo "skip  $dir: invalid or missing name '$name'" >&2
    skipped=$((skipped + 1))
    continue
  fi
  case "$seen" in
    *$'\n'"$name"$'\n'*)
      echo "skip  $dir: another skill named '$name' was already installed by this run" >&2
      skipped=$((skipped + 1))
      continue
      ;;
  esac
  if [[ -e "$target/$name" && -z "${FORCE:-}" ]]; then
    echo "skip  $name: already in $target (FORCE=1 replaces it)" >&2
    skipped=$((skipped + 1))
    continue
  fi

  rm -rf "${target:?}/$name"
  cp -R "$dir" "$target/$name"
  echo "ok    $name"
  seen="$seen$name"$'\n'
  installed=$((installed + 1))
done < <(find "$source_dir" -name SKILL.md -not -path '*/node_modules/*' -print0 | sort -z)

echo "Installed $installed skill(s) into $target, skipped $skipped."
