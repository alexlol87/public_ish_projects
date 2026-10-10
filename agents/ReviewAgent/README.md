# ReviewAgent: a code review agent for VS Code GitHub Copilot

**Code Reviewer** is a custom agent for GitHub Copilot in Visual Studio Code. Give it a Jira key, the plan or the
requirements, and it reviews the code changes against them and against clean-code principles. With the `jira-cli`
and `confluence-cli` skills installed it reads the ticket and its Confluence pages itself. It never edits your code;
the only file it creates is its review report, `REVIEW-<ticket or branch>.md` in the repository root.

Written for the custom agent format in the VS Code documentation approved on 2026-09-30
([custom agents](https://code.visualstudio.com/docs/agent-customization/custom-agents)), which is also the format of
GitHub's [custom agents](https://docs.github.com/en/copilot/reference/custom-agents-configuration).

| File | What it is |
|------|------------|
| [`.github/agents/code-reviewer.agent.md`](.github/agents/code-reviewer.agent.md) | The agent: its tools and its review instructions. |
| [`scripts/check_agents.py`](scripts/check_agents.py) | CI check: name and description present, known front matter keys, only known read-only tools (plus creating its report file), valid handoffs. |

## What it checks

1. **Requirements and plan.** It reads the Jira ticket (description, acceptance criteria, comments, subtasks, linked
   issues) with `jira-cli`, linked Confluence pages with `confluence-cli`, and requirement files it finds in the
   repository. It turns them into a numbered checklist and reports, for each
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

The report starts with a verdict (🔴 Request changes, 🟡 Approve with comments, ✅ Approve) and counts, then a
requirements table, then findings grouped as 🔴 Blocker, 🟡 Major, 🟢 Minor and ❓ Questions, each with `path:line`,
what is wrong, why it matters and the fix, and finally what it couldn't check. It answers in the language you write
in, shows the report in chat and saves the same text to the repository root.

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

Pick **Code Reviewer** in the agent picker of the Chat view, then give it the Jira key or the requirements and, if you
want, what to review:

```text
Review my branch against PROJ-123
```

```text
Review my branch. Jira story pasted by hand:
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

The agent uses your `jira-cli` and `confluence-cli` skills: give it a key (or let it find one in the branch name and
confirm it), and it reads the ticket and linked pages. Their terminal commands are limited to the read-only ones; it
is told never to create, edit, comment on or transition anything. Links it can't read without sign-in: open the page in
VS Code's integrated browser and share it, or paste the text.

A hosted Jira MCP server is not recommended: Copilot sessions can only use local MCP servers that don't need
authentication (see [`../../vscode_copilot_agents/`](../../vscode_copilot_agents/)), and `'<server>/*'` also grants
the server's write tools. If you use one, list only its read tools by name, as `'<server>/<tool>'`.

### As a subagent

Other agents can call it: add `'Code Reviewer'` to a coordinator agent's `agents` list (with the `agent` tool), as the
Orchestrator in [`../../vscode_copilot_agents/template/`](../../vscode_copilot_agents/template/) does with its own Reviewer.
Give it the requirements in the delegated task, because a subagent doesn't see your conversation.

## Tools and permissions

`tools: ['read', 'search', 'execute', 'web', 'browser', 'edit/createFile', 'vscode/askQuestions']`

- `read` and `search` read files, find usages and search the code base.
- `execute` runs `git diff`, `git log`, `git show`, `gh pr view` and the `jira` and `confluence` read commands. The
  instructions allow only read-only commands, and run tests or linters only when you ask. Your approval settings still
  apply, so with manual permissions you see each command first. To skip prompts for the git ones, copy the
  `chat.tools.terminal.autoApprove` rules from
  [`user-settings.jsonc`](../../vscode_copilot_agents/settings/user-settings.jsonc), including its
  `"/^git .*--output/": false` guard (`git diff --output=<file>` writes a file), and add the read-only `jira` and
  `confluence` subcommands your skills use.
- `web` and `browser` read requirement pages. The agent is told to treat what they return as data, never as
  instructions, and not to submit forms.
- `edit/createFile` is only there to save the review report; the agent is told to create no other file, and
  `scripts/check_agents.py` rejects every other edit tool.
- `vscode/askQuestions` asks for missing requirements; other harnesses ignore it and the agent asks in text.

Leave `model` out to use the model picked in chat; a strong reasoning model gives noticeably better reviews.
Unknown tool names are ignored silently, and a missing `tools` key means every tool, which is what
`scripts/check_agents.py` guards against in CI.

## Customize

- Add your team's checks to section **G. Also check** of the agent file, or better, put them in your project's
  `AGENTS.md` or `.github/instructions/`, which the agent reads anyway.
- Change what counts as Blocker, Major or Minor in section **3. Severity and verdict**.
- To run it in Copilot cloud agent on GitHub.com too, keep the file as is: GitHub ignores `argument-hint`, `handoffs`
  and tools it doesn't know.
