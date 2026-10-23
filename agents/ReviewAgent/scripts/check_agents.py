#!/usr/bin/env python3
"""Checks the custom agents in agents/ReviewAgent/.github/agents/ before VS Code gets to ignore a mistake silently.

    python3 scripts/check_agents.py [path/to/.github/agents] [--may-edit]

VS Code and Copilot skip an unknown tool name without a warning, and treat every .md file in .github/agents/ as an
agent. So this checks that each file is an .agent.md with a name and a description, that every tool is a known tool
or tool set, that no tool can edit existing files or delegate (a reviewer stays read-only; it may only create its
report file; --may-edit also allows edit/editFiles, for an agent that keeps its own docs up to date), that the front matter has no unknown keys and the body fits GitHub's 30,000 characters, and that each
handoff has a label and a target agent. Needs PyYAML.
"""
import pathlib
import sys

import yaml

# Another agent folder's .github/agents can be passed as the first argument (TesterAgent's CI does).
ARGS = [a for a in sys.argv[1:] if a != "--may-edit"]
MAY_EDIT = "--may-edit" in sys.argv[1:]
AGENTS = pathlib.Path(ARGS[0]).resolve() if ARGS else (
    pathlib.Path(__file__).resolve().parent.parent / ".github" / "agents")

# VS Code's tools reference (docs/agents/reference/tools-reference.md, approved 2026-09-30) plus the primary aliases
# of GitHub's custom agents configuration reference. MCP tools ("<server>/<tool>") are allowed too.
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
# Tools that edit files, run arbitrary commands or hand the work to an agent that can. "edit/createFile" is the one
# write the reviewer and the tester need (the report file, the new Bruno requests), so it is not listed.
WRITE_TOOLS = {
    "edit", "Edit", "MultiEdit", "Write", "NotebookEdit", "*", "agent", "agent/runSubagent", "Task",
    "execute/createAndRunTask", "execute/runNotebookCell", "newWorkspace",
}
KNOWN_KEYS = {
    "name", "description", "argument-hint", "tools", "agents", "model", "user-invocable", "disable-model-invocation",
    "target", "mcp-servers", "handoffs", "hooks",
}
MAX_BODY = 30000


def front_matter(path):
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
    if not text.startswith("---\n"):
        raise ValueError("no front matter")
    header, sep, body = text[4:].partition("\n---\n")
    if not sep:
        raise ValueError("front matter is not closed with ---")
    return yaml.safe_load(header) or {}, body


def problems(path):
    if not path.name.endswith(".agent.md"):
        yield "VS Code loads every .md file here as an agent; name agents *.agent.md and keep other files elsewhere"
        return
    try:
        meta, body = front_matter(path)
    except (ValueError, yaml.YAMLError) as error:
        yield f"front matter: {error}"
        return
    for key in ("name", "description"):
        if not isinstance(meta.get(key), str) or not meta[key].strip():
            yield f"missing {key}"
    for key in sorted(meta.keys() - KNOWN_KEYS):
        yield f"unknown front matter key {key!r} (ignored silently)"
    if len(body) > MAX_BODY:
        yield f"body is {len(body)} characters; GitHub allows {MAX_BODY}"
    # A missing tools key means every tool, edit included.
    if "tools" not in meta:
        yield "no tools list: the agent would get every tool, including edit"
    tools = meta.get("tools") or []
    if not isinstance(tools, list):
        yield "tools must be a list"
        tools = []
    known = {t.lower() for t in KNOWN_TOOLS}
    for tool in tools:
        name = str(tool)
        allowed = {"edit/createFile", "edit/editFiles"} if MAY_EDIT else {"edit/createFile"}
        if name in WRITE_TOOLS or (name.startswith("edit/") and name not in allowed):
            yield f"tool {tool!r} can edit files or delegate"
        elif name.lower() not in known and "/" not in name:
            yield f"unknown tool {tool!r} (VS Code would ignore it)"
    if {"edit/createFile", "edit/editFiles"} & set(tools) and not any(
            marker in body for marker in ("REVIEW-", "RUN-ORDER", "service-map/data/")):
        yield "edit tools are only for the agent's own output files; the body must describe them (REVIEW-..., RUN-ORDER.md, service-map/data/)"
    for handoff in meta.get("handoffs") or []:
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
