# TesterAgent: a story testing agent for VS Code GitHub Copilot

**Story Tester** is a custom agent for GitHub Copilot in Visual Studio Code. Give it a Jira key, tell it what to test,
and it reads the story with your `jira-cli` skill, proposes a test plan for just that part, and after you approve it
tests it against the running application with `curl`, the browser and other terminal tools. Secrets come only from
environment variables you set; it never sees or shows their values. It never edits your code or files.

Written for the same custom agent format as [ReviewAgent](../ReviewAgent/)
([custom agents](https://code.visualstudio.com/docs/agent-customization/custom-agents)).

| File | What it is |
|------|------------|
| [`.github/agents/story-tester.agent.md`](.github/agents/story-tester.agent.md) | The agent: its tools and its testing instructions. |

CI checks it with ReviewAgent's [`scripts/check_agents.py`](../ReviewAgent/scripts/check_agents.py): name and
description present, known front matter keys and tools, and no tool that edits files.

## How it works

1. **Inputs.** It reads the Jira ticket (description, acceptance criteria, comments, subtasks, linked issues) with
   `jira-cli`'s read-only commands, your indications of what to test, the files you attach (OpenAPI, Postman
   collections, test data, notes) and, when useful, the code behind the tested part. Missing inputs (environment,
   accounts, variable names) it asks for in one round.
2. **Test plan.** It proposes a table of tests covering only what you asked for: which acceptance criterion, how
   (curl command, browser steps), the expected result, and whether it changes data. Nothing runs against the
   application until you approve.
3. **Run.** It runs exactly the approved tests, compares actual with expected, records failures and goes on, and asks
   before anything outside the plan: another endpoint, environment, write or tool.
4. **Report.** Pass/fail per test, reproduction steps for each failure (secrets as `$VARIABLE` names, secret values in
   responses replaced with `***`), the data the tests created or changed, and what was not tested.

## Secrets

Set them as environment variables; give the agent only their names ("the token is in `API_TOKEN`"). The agent uses them
only inside commands (`-H "Authorization: Bearer $API_TOKEN"`), checks they are set without printing them, never runs
`env`, `printenv`, `set -x` or `curl -v`/`--trace` (which print them), never puts them in URLs or files, redacts secrets
found in responses, and never types a secret in the browser: when a page needs sign-in, it asks you to sign in.

Copilot runs commands in its own terminal, which only has the variables VS Code itself started with. Either:

- export them in a terminal and start VS Code from it:

  ```bash
  read -rs API_TOKEN && export API_TOKEN   # typed without echo, kept out of shell history
  export BASE_URL=https://staging.example.com
  code .
  ```

- or keep them in a git-ignored file and tell the agent to load it in each command without reading it:
  `set -a; . ./.env.test; set +a; curl ...`.

Don't put secrets in `terminal.integrated.env.*` settings or in the chat. Instructions reduce the risk of a leak but
can't rule it out: use test accounts and short-lived tokens, and keep terminal command approval on.

## Install

One self-contained file. From the project's root folder:

```bash
mkdir -p .github/agents
curl -fsSL https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/TesterAgent/.github/agents/story-tester.agent.md \
  -o .github/agents/story-tester.agent.md
```

On Windows (PowerShell):

```powershell
New-Item -ItemType Directory -Force .github/agents | Out-Null
Invoke-WebRequest https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/TesterAgent/.github/agents/story-tester.agent.md `
  -OutFile .github/agents/story-tester.agent.md
```

For every project, save it to `~/.copilot/agents/story-tester.agent.md` instead. Then turn on
`github.copilot.chat.cli.customAgents.enabled` and check it loads, as in
[ReviewAgent's install steps](../ReviewAgent/README.md#install). Install the `jira-cli` skill too, or paste the story.

## Use

Pick **Story Tester** in the agent picker, then:

```text
Test AC2 and AC3 of PROJ-123 on https://staging.example.com.
Token in API_TOKEN, test customer password in CUSTOMER_PASSWORD. API spec: #file:docs/openapi.yaml
```

```text
PROJ-456: only check that the export button is hidden for read-only users, in the browser. I'm signed in already.
```

It answers with a test plan; reply "approved", or change it ("skip T3", "don't create orders, use order 42").

## Tools and permissions

`tools: ['read', 'search', 'execute', 'web', 'browser', 'vscode/askQuestions']`

- `read` and `search` read the context files and the code.
- `execute` runs `curl`, the `jira` read commands, and other test commands you approve. It is the risky one: it can
  run any command, so keep VS Code's terminal approval on (manual approval shows each command before it runs) and
  don't auto-approve `curl` with write methods.
- `web` and `browser` read pages and test UI flows; it submits forms only when the approved plan says so.
- `vscode/askQuestions` asks for missing inputs and plan approval; other harnesses ignore it and the agent asks in text.
- No `edit` tool: it can't change your files.
