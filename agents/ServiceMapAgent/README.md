# ServiceMapAgent: an offline HTML map of your microservices

**Service Mapper** is a custom agent for GitHub Copilot in Visual Studio Code. It reads a system made of many
microservices in many repositories (plus Terraform and GitHub Actions repositories), one repository per session, and
fills an HTML service map that opens from disk with a double-click, with no server and no internet:

- **every endpoint of every service in one searchable table**, each with **when to use it**, what not to confuse it
  with, who calls it today and its auth, instead of one Swagger page per service;
- **who calls whom**: an interactive graph (click a service for its endpoints, calls and callers; filter by layer) and
  a table of which endpoint calls which endpoint of which service, with what happens when the call fails;
- **what one call touches**: for every endpoint, a graph of the endpoints it calls in other services, the tables it
  reads and writes, the events it sends and the listeners that receive them, and the external systems it reaches. By
  default it stops at the next service (click one to open its endpoint's own graph); **Show the whole chain** follows
  every call and event to the end. The page stitches this from each repository's data, so no second agent pass;
- **what each endpoint does, step by step**: for every endpoint that does more than read or save one record, a sequence diagram from
  the controller through the services and repositories down to the database tables, other services and topics, with
  the business branches, errors and transaction boundary, a step list linking to the code, the error table and what
  changes afterwards;
- **business journeys** across services, **things to know** (risks shown first), data ownership, entity lifecycles,
  where each service runs (Terraform), how it ships (GitHub Actions), a glossary and the open questions.

It never changes code, never builds or runs anything, and writes only the map's data files. Every fact links to the
`path:line` it came from (click it to open the file in VS Code), and what it couldn't prove becomes an open question.

**Demo:** [`viewer/`](viewer/) is the map of a made-up shop. Open `viewer/index.html` in a browser.

| Path | What it is |
|------|------------|
| [`.github/agents/service-mapper.agent.md`](.github/agents/service-mapper.agent.md) | The agent: its tools and its instructions. |
| [`viewer/index.html`](viewer/index.html), `app.js`, `app.css` | The viewer, styled after the Kami Parchment skill (warm paper, one ink-blue accent, one serif): start page, system graph, all endpoints, service and endpoint pages, journeys, calls and events, data, infrastructure and CI/CD, glossary, open questions, progress. Fixed; the agent never edits it. |
| [`viewer/vendor/`](viewer/vendor/) | Mermaid 11.17.2 and Cytoscape.js 3.30.2 (MIT), bundled so the map works offline. |
| [`scripts/scan_repo.py`](scripts/scan_repo.py) | The scanner (Python 3, standard library): pulls endpoints, clients and where they're called, listeners, producers, jobs, entities, URL config, workflows and Terraform out of one repository as JSON, with `path:line` for each. Tested by `scripts/test_scan_repo.py`. |
| [`viewer/data/`](viewer/data/) | What the agent writes: `repos.js` (system, layers, repository order), one `<repo>.js` per repository, `journeys.js`. Here: the shop's data. |

## How it works

| Step | You say | It does |
|------|---------|---------|
| 1. Plan | `start` | Asks for the repository list, the system's summary and your layer names, and writes `repos.js` in the mapping order: Terraform first (real names, URLs, queues, databases), then CI/CD, then core services, gateways last. |
| 2. Map | `map <repo>` | In a new chat per repository: reads endpoints (OpenAPI, Spring `@*Mapping`, FastAPI/Flask, gateway routes), calls (Feign, `@HttpExchange`, `RestClient`/`RestTemplate`/`WebClient`, generated clients, resolved to a service and endpoint through config, service DNS and the Terraform already mapped), events, JPA entities and queries, deployment and workflows, then writes `data/<repo>.js`. |
| 3. Journeys | `journey a customer places an order` | Follows one business flow through the mapped services and adds it to `journeys.js`. |
| 3a. Link | `link` | Resolves calls whose target endpoint didn't match yet (the caller was mapped before the callee), from the data files first and the client code only when needed. The viewer lists them under **Open questions → Unresolved links**. |
| 4. Update | `update <repo>` | When you decide to: `git diff` since the commit stored in the repository's data file, re-maps only what changed. |
| 5. Check | `check <repo>` | Compares the map with the code and reports what drifted, changing nothing. |

Start with a pilot of two or three repositories, look at the result, then do the rest. One repository per chat keeps
the agent's context small and the result accurate; the data files carry everything between chats.

## Scanner first, agent second

Most of what the agent would otherwise search for is mechanical: annotations, client interfaces, listener topics,
entity tables. `scan_repo.py` finds those in a second without spending tokens, and also lists, for every Feign or
`@HttpExchange` client method, the class and method that call it, which is the expensive part of linking endpoint to
endpoint. The agent reads that facts file first and spends its reading on what needs judgement: which endpoint
triggers each call, when to use each endpoint, the step-by-step flows, the risks. On `update`, re-running the scanner
and comparing with the data file shows added and removed endpoints, clients and tables before any code is read.

The scanner is regex-based, so it is a checklist rather than the truth: the agent confirms what it uses in the code and
still searches for what the scanner can't see (URLs built at runtime, multi-line annotations, `RouterFunction`
routes). Without Python the agent skips it and reads everything itself.

```bash
python3 service-map/tools/scan_repo.py ../orders-service --out service-map/facts/orders-service.json
python3 -m unittest discover -s agents/ServiceMapAgent/scripts   # the scanner's tests, from this repository
```

## Set up

1. Create a folder (or a small repository) for the map and copy [`viewer/`](viewer/) into it as `service-map/`.
   Delete the shop's files in `service-map/data/` (the agent writes `repos.js` on `start`), and copy
   [`scripts/scan_repo.py`](scripts/scan_repo.py) to `service-map/tools/scan_repo.py`. Add `service-map/facts/` to
   `.gitignore` if the map is a repository: those are scratch files.
2. Install the agent, from that folder:

   ```bash
   mkdir -p .github/agents
   curl -fsSL https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/ServiceMapAgent/.github/agents/service-mapper.agent.md \
     -o .github/agents/service-mapper.agent.md
   ```

   Or save it to `~/.copilot/agents/service-mapper.agent.md` to have it everywhere. In VS Code user settings, turn on
   `github.copilot.chat.cli.customAgents.enabled` and check that **Service Mapper** is listed under Command Palette →
   **Chat: Open Customizations** → **Agents** (see [`../../vscode_copilot_agents/`](../../vscode_copilot_agents/)).
3. For each session, open a multi-root workspace with the map folder and the one repository to map
   (**File → Add Folder to Workspace**), pick **Service Mapper** in the agent picker, and say `map <repo>`.
4. Open `service-map/index.html` in your browser. Reload it after each session.

The optional `codeLink` in `repos.js` turns every `path:line` into a link that opens the file in VS Code
(`vscode://file/<folder with all repositories>/{path}:{line}`); for IntelliJ on macOS try
`idea://open?file=<folder>/{path}&line={line}`.

## Tools and permissions

`tools: ['read', 'search', 'execute', 'edit/createFile', 'edit/editFiles', 'todo', 'vscode/askQuestions']`

- `read` and `search` read the code, specs, config, Terraform and workflows.
- `execute` is limited by its instructions to the scanner and read-only git (`rev-parse`, `log`, `diff --name-only`,
  `ls-files`), for the facts, the commit stamps and `update`. Keep terminal approvals on to see each command.
- `edit/createFile` and `edit/editFiles` write the data files. The instructions limit them to `service-map/data/`;
  tool lists can't restrict paths, so keep edit approvals on or review the diff before you commit.
- No web, no MCP servers, no subagents: everything comes from the code on your machine.

CI checks the agent with ReviewAgent's [`scripts/check_agents.py`](../ReviewAgent/scripts/check_agents.py)
`--may-edit`: name and description present, known front matter keys and tools, and its edit tools tied to its own
data folder in the instructions.
