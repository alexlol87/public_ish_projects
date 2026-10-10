# ReviewAgent: a code review agent for VS Code GitHub Copilot

**Code Reviewer** is a custom agent for GitHub Copilot in Visual Studio Code. Give it the Jira story, the plan or the
requirements, and it reviews the code changes against them and against clean-code principles. It only reads; it never
edits your files.

Written for the custom agent format in the VS Code documentation approved on 2026-09-30
([custom agents](https://code.visualstudio.com/docs/agent-customization/custom-agents)), which is also the format of
GitHub's [custom agents](https://docs.github.com/en/copilot/reference/custom-agents-configuration).

| File | What it is |
|------|------------|
| [`.github/agents/code-reviewer.agent.md`](.github/agents/code-reviewer.agent.md) | The agent: its tools and its review instructions. |
| [`scripts/check_agents.py`](scripts/check_agents.py) | CI check: name and description present, only known and read-only tools, valid handoffs. |

## What it checks

1. **Requirements and plan.** It turns the story, plan or requirements into a numbered checklist and reports, for each
   item, whether it is met, partly met or missing, where it is implemented and which test proves it. It flags
   requirements implemented differently from what they say, deviations from the plan, and scope creep (changes nobody
   asked for).
2. **Unintended changes to logic and endpoints.** It compares the old and new behavior of every changed hunk: business
   conditions, defaults and side effects; routes, HTTP methods, status codes, request and response fields, auth and
   validation; database schema and queries; configuration; every caller of a changed function; and tests that were
   loosened or deleted to make the change pass. Any behavior change that no requirement asks for is a blocker.
3. **Reuse.** For every new function, constant, type, regex or helper it searches the code base and the existing
   dependencies for something that already does the job, and points to it.
4. **Duplicated logic**, inside the change and between the change and existing code, treating DRY as duplicated
   knowledge rather than similar-looking text.
5. **Design principles**: KISS, YAGNI, DRY, SOLID, separation of concerns, least astonishment, fail fast, Law of
   Demeter, composition over inheritance, and consistency with how the code base already does things. Each finding
   names the code and what it costs, not just the principle.
6. **Clean code**: names, function size and nesting, magic values, dead or commented-out code, debug leftovers,
   comments, error handling, type suppressions, and clean tests.
7. **Also**: missing tests, security (secrets, injection, authorization, sensitive data in logs), performance (N+1
   queries, unbounded loading), concurrency and resource leaks, new dependencies, outdated API docs or migrations, and
   backward compatibility.

It also reads your project's own rules (`AGENTS.md`, `.github/copilot-instructions.md`, `CLAUDE.md`, matching
`.github/instructions/*.instructions.md`, `CONTRIBUTING.md`), which take precedence over the general principles.

The report starts with a verdict (Request changes, Approve with comments, Approve), then a requirements table, then
findings grouped as Blocker, Major, Minor and Questions, each with `path:line`, what is wrong, why it matters and the
fix, and finally what it couldn't check. It answers in the language you write in.

## Install

The agent is one self-contained file, meant to be downloaded into your own projects; nothing in it refers to this
repository. Download it straight from GitHub, no clone needed.

**Into a project** (shared with your team through git), from the project's root folder:

```bash
mkdir -p .github/agents
curl -fsSL https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/ReviewAgent/.github/agents/code-reviewer.agent.md \
  -o .github/agents/code-reviewer.agent.md
```

On Windows (PowerShell):

```powershell
New-Item -ItemType Directory -Force .github/agents | Out-Null
Invoke-WebRequest https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/ReviewAgent/.github/agents/code-reviewer.agent.md `
  -OutFile .github/agents/code-reviewer.agent.md
```

**For yourself, in every project**: save it to `~/.copilot/agents/code-reviewer.agent.md` instead (same commands,
with `~/.copilot/agents` as the folder).

Run the same command again to update to the latest version.

Then:

1. In VS Code user settings, turn on `github.copilot.chat.cli.customAgents.enabled` (it is off by default, and
   without it Copilot sessions ignore custom agents). See [`../../vscode_copilot_agents/`](../../vscode_copilot_agents/) for
   the rest of the recommended setup.
2. Check that it loaded: Command Palette → **Chat: Open Customizations** → **Agents** should list **Code Reviewer**
   with no warnings.

VS Code treats every `.md` file in `.github/agents/` as an agent, so don't put a README or notes in that folder.

## Use

Pick **Code Reviewer** in the agent picker of the Chat view, then give it the requirements and, if you want, what to
review:

```text
Review my branch. Jira story:
PROJ-123 As a customer I can cancel an order while it is not shipped yet.
Acceptance criteria:
- Cancelling a shipped order returns 409 and changes nothing.
- A cancelled order sends one cancellation email.
```

```text
Review the last 3 commits against the plan in #file:docs/plans/order-cancellation.md
```

```text
Review the uncommitted changes. No requirements, just code quality.
```

Without a scope it reviews everything on your branch that isn't on the default branch yet, uncommitted changes
included. Without requirements it asks for them once, then reviews everything else if you tell it to go on.

After the review, the **Fix the findings** button hands the review to the built-in agent to fix the blockers and major
findings. Ask for a re-review afterwards: it marks each earlier finding Fixed or Not fixed, then reviews only what
changed.

### Jira

The agent fetches links it can read, but Jira usually needs sign-in, so pasting the story is the simplest. To let it
read Jira itself, add your Jira MCP server's tools to the agent's `tools` list as `'<server name>/*'` (for example
`'atlassian/*'`, using the name from your `.mcp.json` or `~/.copilot/mcp-config.json`).

### As a subagent

Other agents can call it: add `'Code Reviewer'` to a coordinator agent's `agents` list (with the `agent` tool), as the
Orchestrator in [`../../vscode_copilot_agents/template/`](../../vscode_copilot_agents/template/) does with its own Reviewer.
Give it the requirements in the delegated task, because a subagent doesn't see your conversation.

## Tools and permissions

`tools: ['read', 'search', 'execute', 'web', 'vscode/askQuestions']`

- `read` and `search` read files, find usages and search the code base.
- `execute` runs `git diff`, `git log` and `git show`, which the review needs for branches and commits. The
  instructions allow only read-only commands, and run tests or linters only when you ask. Your approval settings still
  apply, so with manual permissions you see each command first. Allow `git diff`, `git log`, `git show` and
  `git status` in `chat.tools.terminal.autoApprove` to skip those prompts.
- `web` fetches a requirements link.
- `vscode/askQuestions` asks for missing requirements; other harnesses ignore it and the agent asks in text.

Leave `model` out to use the model picked in chat; a strong reasoning model gives noticeably better reviews.
Unknown tool names are ignored silently, which is what `scripts/check_agents.py` guards against in CI.

## Customize

- Add your team's checks to section **G. Also check** of the agent file, or better, put them in your project's
  `AGENTS.md` or `.github/instructions/`, which the agent reads anyway.
- Change what counts as Blocker, Major or Minor in section **3. Severity and verdict**.
- To run it in Copilot cloud agent on GitHub.com too, keep the file as is: GitHub ignores `argument-hint`, `handoffs`
  and tools it doesn't know.
