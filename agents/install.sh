#!/bin/sh
# Installs a skill agent (MattPocock or JesseVincent) for GitHub Copilot in VS Code: the agent file plus its skills.
#
#   curl -fsSL https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/install.sh | sh -s -- MattPocock
#   curl -fsSL https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/install.sh | sh -s -- JesseVincent --user
#
# Without --user it installs into the current project's .github/ (agents/<name>.agent.md and agent-skills/<slug>/);
# with --user into ~/.copilot/, for all your projects. Running it again updates the agent and replaces its skills.
# PUBLIC_ISH_PROJECTS_RAW overrides where the files come from (for example file:///path/to/public_ish_projects for a local
# checkout). Needs curl.
set -eu

RAW=${PUBLIC_ISH_PROJECTS_RAW:-https://raw.githubusercontent.com/alexlol87/public_ish_projects/main}
usage() {
    echo "usage: install.sh MattPocock|JesseVincent [--user]" >&2
    exit 2
}

agent= base=.github
for arg in "$@"; do
    case $arg in
        MattPocock | JesseVincent) agent=$arg ;;
        --user) base=$HOME/.copilot ;;
        *) usage ;;
    esac
done
[ -n "$agent" ] || usage

tab=$(printf '\t')
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# files.txt: <path in the repository> TAB <path under the install folder> TAB <x if executable>
curl -fsSL "$RAW/agents/$agent/files.txt" -o "$tmp/files.txt"
while IFS=$tab read -r source target executable; do
    [ -n "$source" ] || continue
    mkdir -p "$(dirname "$tmp/out/$target")"
    curl -fsSL "$RAW/$source" -o "$tmp/out/$target"
    if [ "$executable" = x ]; then chmod +x "$tmp/out/$target"; fi
done <"$tmp/files.txt"

# Every agent-skills/<slug>/ folder is replaced as a whole, so skills removed upstream don't linger.
mkdir -p "$base/agents" "$base/agent-skills"
for skills in "$tmp"/out/agent-skills/*; do
    rm -rf "$base/agent-skills/$(basename "$skills")"
    mv "$skills" "$base/agent-skills/"
done
mv -f "$tmp"/out/agents/*.agent.md "$base/agents/"

echo "Installed $agent: $base/agents/ and $base/agent-skills/"
