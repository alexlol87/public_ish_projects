# public_ish_projects

Things that others can use.

| Project | What it is | Download |
|---------|------------|----------|
| [`window_borders/`](window_borders/) | **Window Borders**: a macOS menu bar app that draws a differently colored border around every window, so same-app windows are easy to tell apart, including in Mission Control (Swift/AppKit, macOS 14+, Apple Silicon). | [Latest build](https://github.com/alexlol87/public_ish_projects/releases/tag/window-borders-latest) |
| [`skills_updated/`](skills_updated/) | **Agent skills** at their latest versions: Matt Pocock's skills (engineering, productivity, misc, beta), obra's Superpowers, plus `caveman` (terse replies, fewer tokens), `ponytail` (simplest, least-code solutions), shadcn's `improve` (read-only advisor that writes implementation plans) and Cursor's `thermo-nuclear-code-quality-review` (very strict maintainability review). New: `popular/` adds 38 of the most installed and most starred skills (Vercel's `find-skills` and `agent-browser`, Anthropic's `frontend-design` and `skill-creator`, Karpathy guidelines, Addy Osmani's agent skills, UI UX Pro Max, Taste Skill, Impeccable). The folder's README lists every skill with its description and what's new. | Copy a skill folder into `~/.claude/skills/` |
| [`postit_app/`](postit_app/) | **PostIt**: a menu-bar post-it note for macOS, borderless and resizable, can float over every app and Space, several colored markdown notes with live rendering and clickable task lists (Swift/AppKit/WebKit, macOS 14+). | `./build.sh` |
| [`window_colors/`](window_colors/) | **Window Colors**: a VS Code extension that gives every window its own color, on the window border, title bar, activity bar and status bar like Peacock, also windows with no folder or workspace open (where Peacock can't) (plain JavaScript, VS Code 1.75+). | `window-colors-vsix` artifact of the [latest workflow run](https://github.com/alexlol87/public_ish_projects/actions/workflows/window-colors.yml) |
| [`vscode_copilot_agents/`](vscode_copilot_agents/) | **VS Code + GitHub Copilot for agents**: how to configure VS Code and the Copilot extension for agents, subagents and skills (harness choice, settings, instructions, custom agents, skills, MCP, hooks, cost and approvals), with recommended settings, a copy-into-your-repo starter kit (`AGENTS.md`, orchestrator/researcher/reviewer/planner agents, a skill) and a script that installs the skills from `skills_updated/` so VS Code loads them. Checked against the VS Code docs of 2026-09-30. | Copy `template/` into your repo |
| [`agents/`](agents/) | **Custom agents for GitHub Copilot in VS Code**: [`ReviewAgent`](agents/ReviewAgent/) (**Code Reviewer**, an agent that never edits code and reviews changes against a Jira ticket (read with your `jira-cli` and `confluence-cli` skills), plan or requirements, and for unintended logic or endpoint changes, missed reuse, duplicated logic, KISS, YAGNI, DRY, SOLID, clean code, tests, security and performance) and [`TesterAgent`](agents/TesterAgent/) (**Story Tester**, turns a Jira story into test files: ordered Bruno requests grouped by positive and negative scenario in your open collection, or a curl/browser test plan; runs nothing unless you ask and never against production). | Copy `agents/ReviewAgent/.github/agents/code-reviewer.agent.md` into your repo's `.github/agents/` |
| [`springboot_java_utilities/`](springboot_java_utilities/) | **Java linters demo**: a small Spring Boot 4.1 / H2 app (REST, service, JPA repository, tests with WireMock and JSON stubs) wired to **Spotless, Checkstyle, SpotBugs + Find Security Bugs, PMD + CPD and SonarQube**, plus deliberately bad code (`-Pdemo`) and a script that shows what each tool catches. | `mvn verify`; `scripts/run-demo.sh` |
| [`local_memory_sqlite/`](local_memory_sqlite/) | **Local memory (SQLite)**: memory that lasts between sessions for GitHub Copilot agents in VS Code. One SQLite database with full-text search, global and per-repository memories, a SessionStart hook, and a PostToolUse hook that loads a repository's memories the first time the agent touches it, so a workspace with many repositories keeps them apart. Six `alx-*` skills to remember, recall, forget, list and reflect (Python stdlib only). | Ask your agent to follow [`install.md`](local_memory_sqlite/install.md) |
| [`local_memory/`](local_memory/) | **Local Memory** (older, file-based): memory and learned habits ("instincts") for GitHub Copilot in VS Code when Copilot Memory is turned off, as plain files managed by one Python script, two skills and four hooks. | `./install.sh` |
| [`claude_statusline/`](claude_statusline/) | **Claude Code status line**: Victor Rentea's [victor-statusline](https://github.com/victorrentea/victor-statusline) with a Dracula colour theme and calendar days for the weekly reset, self-contained (script, `install.sh` that merges only the `statusLine` setting, my previous bar to switch back). | `./install.sh` |

## Window Borders

Five VS Code windows might be green, red, blue, purple and orange. Each window keeps its color for its whole life, and
can get the same color back after an app restart.

- **Download:** `WindowBorders.zip` from the
  [latest release](https://github.com/alexlol87/public_ish_projects/releases/tag/window-borders-latest).
- **Install:** unzip it, move `Window Borders.app` to /Applications, run
  `xattr -dr com.apple.quarantine "/Applications/Window Borders.app"` once (the app is ad-hoc signed), then open it and
  grant Accessibility.
- **Details:** settings, permissions, limitations, architecture and how to build it yourself are in
  [window_borders/README.md](window_borders/README.md).

## CI

Each project has its own GitHub Actions workflow in `.github/workflows/`, which runs only when that project changes.

`window-borders.yml` runs on a macOS (Apple Silicon) runner:

- unit tests;
- a build that fails on any compiler warning;
- a launch test of the `.app`, with the zipped `.app` attached to the run.

On `main`, a green build also replaces the `window-borders-latest` release.

`window-colors.yml` runs the unit tests, then the extension inside a real VS Code (an empty window and a folder
window, on VS Code 1.75 and current stable), and attaches the `.vsix` to the run.

`skills.yml` checks that every skill in `skills_updated/` has a name and a description, and that the folder's
README lists them all.

`agents.yml` checks that ReviewAgent's and TesterAgent's custom agents have a name and a description, use only
known tools that can't edit existing files, and have valid handoffs.
