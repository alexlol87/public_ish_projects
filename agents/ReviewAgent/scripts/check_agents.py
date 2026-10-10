#!/usr/bin/env python3
"""Checks the custom agents in agents/ReviewAgent/.github/agents/ before VS Code gets to ignore a mistake silently.

    python3 scripts/check_agents.py

VS Code and Copilot skip an unknown tool name without a warning, and treat every .md file in .github/agents/ as an
agent. So this checks that each file is an .agent.md with a name and a description, that every tool is a known tool
or tool set, that no tool can edit files (a reviewer must stay read-only), and that each handoff has a label and a
target agent. Needs PyYAML.
"""
import pathlib
import sys

import yaml

AGENTS = pathlib.Path(__file__).resolve().parent.parent / ".github" / "agents"

# VS Code's tools reference (docs/agents/reference/tools-reference.md, approved 2026-09-30) plus the primary aliases
# of GitHub's custom agents configuration reference. MCP tools ("<server>/*") are allowed too.
KNOWN_TOOLS = {
    "read", "read/readFile", "read/problems", "read/getNotebookSummary", "read/readNotebookCellOutput",
    "read/terminalLastCommand", "read/terminalSelection",
    "search", "search/changes", "search/codebase", "search/fileSearch", "search/listDirectory", "search/textSearch",
    "search/usages",
    "edit", "edit/createDirectory", "edit/createFile", "edit/editFiles", "edit/editNotebook",
    "execute", "execute/createAndRunTask", "execute/getTerminalOutput", "execute/runInTerminal",
    "execute/runNotebookCell", "execute/testFailure",
    "web", "web/fetch", "browser", "githubRepo", "githubTextSearch",
    "agent", "agent/runSubagent", "todo", "todos", "vscode/askQuestions",
}
WRITE_TOOLS = {"edit", "Edit", "MultiEdit", "Write", "NotebookEdit"}


def front_matter(path):
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        raise ValueError("no front matter")
    header, sep, _ = text[4:].partition("\n---\n")
    if not sep:
        raise ValueError("front matter is not closed with ---")
    return yaml.safe_load(header) or {}


def problems(path):
    if not path.name.endswith(".agent.md"):
        yield "VS Code loads every .md file here as an agent; name agents *.agent.md and keep other files elsewhere"
        return
    try:
        meta = front_matter(path)
    except (ValueError, yaml.YAMLError) as error:
        yield f"front matter: {error}"
        return
    for key in ("name", "description"):
        if not isinstance(meta.get(key), str) or not meta[key].strip():
            yield f"missing {key}"
    tools = meta.get("tools", [])
    if not isinstance(tools, list):
        yield "tools must be a list"
        tools = []
    for tool in tools:
        if tool in WRITE_TOOLS or str(tool).startswith("edit/"):
            yield f"tool {tool!r} can edit files"
        elif tool not in KNOWN_TOOLS and not str(tool).endswith("/*"):
            yield f"unknown tool {tool!r} (VS Code would ignore it)"
    for handoff in meta.get("handoffs", []):
        if not isinstance(handoff, dict) or not handoff.get("label") or not handoff.get("agent"):
            yield f"handoff without a label or an agent: {handoff!r}"


def main():
    files = sorted(p for p in AGENTS.iterdir() if p.is_file())
    if not files:
        print(f"No agents in {AGENTS}")
        return 1
    failed = False
    for path in files:
        found = list(problems(path))
        failed |= bool(found)
        for problem in found:
            print(f"{path.relative_to(AGENTS.parent.parent)}: {problem}")
        if not found:
            print(f"{path.name}: ok")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
