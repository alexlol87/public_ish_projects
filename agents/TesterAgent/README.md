# TesterAgent: a story test writer for VS Code GitHub Copilot

**Story Tester** is a custom agent for GitHub Copilot in Visual Studio Code. Give it a Jira key and it reads the story
with your `jira-cli` skill, finds the test cases (positive, negative, boundary, plus important ones it finds in the
code that the story misses) and **creates the test files**. It runs nothing until you ask, never runs anything
against production, and deletes only data its own tests created.

| Mode | When | What it creates |
|------|------|-----------------|
| **A. Bruno** | Your Bruno collection is open (or you say Bruno) | A folder for the story, a subfolder per scenario, one `.bru` request per call, in run order, plus `RUN-ORDER.md` |
| **B. Other tests** | UI flows, curl without Bruno, mixed checks | `TEST-PLAN-<KEY>.md` with a table of tests and the exact curl or browser steps |

Written for the same custom agent format as [ReviewAgent](../ReviewAgent/)
([custom agents](https://code.visualstudio.com/docs/agent-customization/custom-agents)).

| File | What it is |
|------|------------|
| [`.github/agents/story-tester.agent.md`](.github/agents/story-tester.agent.md) | The agent: its tools and its instructions. |

CI checks it with ReviewAgent's [`scripts/check_agents.py`](../ReviewAgent/scripts/check_agents.py): name and
description present, known front matter keys and tools, and no tool that edits existing files.

## What it creates

```
PROJ-123 Cancel order/
  RUN-ORDER.md                                   what was created, what to set up, the order to run
  01 Positive - Cancel an unshipped order/
    01 Create order.bru
    02 Cancel order, expect 200.bru
    03 Get order, status is CANCELLED.bru
  03 Negative - Cancel a shipped order returns 409/
  04 Negative - Quantity 0, -1 and -20 are rejected with 400/
  05 Negative - No token returns 401/
  06 Beyond the story - Cancel twice returns 409/
```

- Folder names say what must happen. Positive scenarios come first, then negative, then **beyond the story**:
  scenarios the story doesn't mention but the code shows are important (validation rules, permissions, state
  checks). Delete the ones you don't want.
- Negative flows are always covered: if the story says "positive numbers" with the example `5`, it also writes
  requests with `100` (accepted) and `0`, `-1`, `-20`, `"abc"`, `null` (refused), and asserts the error.
- A scenario that needs several calls gets one request file per call, chained with `vars:post-response`. Every
  scenario sets up its own data, so any folder runs alone.
- `seq` in the requests and folders follows the numbers in the names, so the sidebar and **Run folder** use the order
  you should follow. Each request has `assert` blocks for the status code and key fields, and a `docs` block with the
  story reference, the expected result and whether it changes data.
- `RUN-ORDER.md` (also shown in the chat) lists the run order, what to set before running (environment, token,
  test data the agent couldn't create), questions it couldn't answer, and what it didn't cover.

## Conventions and secrets

Before writing (Mode A), the agent reads your collection, including `collection.bru`, `folder.bru` and environment
files, and copies its conventions: the request file format, the base URL variable, the path style, the variable names,
the naming and `seq` style, and how authentication is done.

- Authentication: only variable references, such as `Authorization: Bearer {{token}}` and, if your requests send one,
  `x-api-key: {{apiKey}}`, using your collection's own variable names. You provide the token in the environment.
- It never writes a secret value into a request, a doc, the summary or the chat; it uses variable names only.
  It writes only new files and never overwrites: if the story folder exists, it asks.
- If a request needs a variable your environment doesn't define, it declares it in the request's own
  `vars:pre-request` and lists it in `RUN-ORDER.md`.

## Running, production, deleting

- Nothing runs until you ask in your own message ("run `03 Negative - ...` on staging"). It then confirms the
  requests and the environment first. It passes no secrets on the command line and writes no reports.
- **Production is off limits**: it will not run anything against it, even if you ask, and it never writes a production
  URL into a file. Run it yourself if you need to.
- It deletes only records its own scenario created, by the id captured in that scenario, never by filter or in bulk.

These limits are instructions to the model, not tool restrictions: `execute` and `edit/createFile` are not
path-restricted. Use test tokens and keep terminal command approval on.

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

For Mode A open the Bruno collection folder in VS Code (add the API's source folder to the workspace if you want the
agent to find uncovered scenarios in the code). Pick **Story Tester** in the agent picker, then:

```text
PROJ-123
```

```text
PROJ-456, only AC2 and AC3. The API code is in the api/ folder. Put it under the "Orders" folder.
```

```text
PROJ-789: the export button must be hidden for read-only users. UI test plan, not Bruno.
```

Then, in Bruno, reload the collection, pick the environment, make sure your token is set, and run the story folder
or one scenario. To have the agent run something, say so explicitly: "run `03 Negative - ...` against staging".

## Tools and permissions

`tools: ['read', 'search', 'execute', 'edit/createFile', 'web', 'browser', 'vscode/askQuestions']`

- `read` and `search` read the collection, the code and context files.
- `edit/createFile` creates the new requests, `RUN-ORDER.md` and test plans. The agent is told never to overwrite.
- `execute` is for `jira-cli` read commands and, only when you ask, `bru` or `curl`. Keep VS Code's terminal approval
  on to see every command.
- `web` and `browser` read pages and run UI checks, only when you ask for a run.
- `vscode/askQuestions` asks for missing inputs; other harnesses ignore it and the agent asks in text.
