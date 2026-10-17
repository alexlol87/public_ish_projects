# Constellation: implementation plan

Status: **rewritten from Swift/macOS to Tauri 2 (Linux + macOS); stack, architecture, distribution and tests below are updated, the other sections still describe the original Swift design and apply as product spec**. Written 2026-10-17 from a design interview. Vocabulary is defined in
[GLOSSARY.md](GLOSSARY.md); hard-to-reverse decisions are in [docs/adr/](docs/adr/).

## 1. Purpose

Teams with many Projects, each made of many microservices in separate GitHub repositories, keep losing time and money
re-reading code (by hand or by sending agents) to answer the same questions: what endpoints a service has, what they
call, whether they are complete, what is broken, what is planned, who uses them. Constellation keeps those answers in a
Vault of linked markdown Notes, like Obsidian, with a graph of Projects, Repos, Endpoints, External APIs and Clients.

- The app starts empty. People and agents fill the Vault.
- Agents fill most of it by inspecting the repositories, following an `AGENTS.md` the app writes into the Vault.
- Clients and decisions are written by people.
- Questions are answered from the Vault first, and from code only when the Vault can't answer.

## 2. Decisions (from the interview)

| # | Topic | Decision |
|---|-------|----------|
| 1 | Stack | Tauri 2 app for Linux and macOS. Rust core (`core/`), TypeScript frontend with CodeMirror 6 for the editor (`ui/`), app shell in `src-tauri/`. Cargo workspace plus npm (Vite). Third-party dependencies are allowed but kept small. |
| 2 | Name | **Constellation**, in `public_ish_projects/constellation/`. Public repo, so no personal data in code, docs or samples. |
| 3 | Vault | One Vault holds many Projects, plus `external/` and `clients/` at its root. |
| 4 | Git | Plain files. No git integration in the app. |
| 5 | Nodes | Every Note is a Node, and so is every folder (Project, Repo, `external/`, `clients/`). Containment edges are drawn differently from Links. *May be revisited after seeing it.* |
| 6, 16 | Endpoints | One `endpoints.md` per Repo, with one `##` heading per Endpoint. Calls are a `Calls:` bullet list of Links under the heading, in the body. See ADR 0001. |
| 7 | Links | Obsidian `[[wikilinks]]`, with `[[path#Heading]]` and `[[path\|alias]]`. Targets resolve by vault-relative path, or by unique file name when that is unambiguous. |
| 8 | Frontmatter | Small YAML frontmatter. `type` is required, everything else is optional. See §4.3. |
| 9, 21 | Editor | Live preview at Obsidian level: markdown markers are hidden except on the line the cursor is on. |
| 22 | Toolbar | Fixed formatting toolbar above the editor, with keyboard shortcuts. See §6.2. |
| 23 | Rendering | Headings, emphasis, lists, task items, quotes, inline and fenced code, links, tables (monospace-aligned) and inline images. Mermaid stays a code block until after v1. |
| 10, 39 | Live updates | File watcher (the `notify` crate: FSEvents on macOS, inotify on Linux) updates the tree, graph, search and backlinks. Autosave runs 1 s after the last keystroke. A file changed on disk while open is reloaded silently if clean; if it has unsaved edits, a banner offers *Reload from disk* or *Keep mine*. |
| 11 | Search | Case- and diacritic-insensitive **substring** search over folder names, Note names and Note text. Results are grouped as Folders / Notes / Text matches, and each text match shows its sentence with the hit highlighted. In-memory index. |
| 12 | Scale | Up to ~5,000 Notes. |
| 13, 28 | Agents | The app writes a harness-agnostic `AGENTS.md` and `templates/` into each new Vault. It covers three workflows: Ingest, Refresh and Answer. See §7. |
| 14, 27 | Themes | Light, Dark, Dracula and One Dark, plus System (which picks Light or Dark). A theme colours the editor, the graph and the accent. Window chrome follows the theme's light or dark appearance. |
| 15 | Distribution | `build.sh` builds from source and installs locally. A CI workflow builds, tests and publishes a `constellation-latest` release (macOS universal `.dmg` and zipped `.app`, Linux x86_64 and aarch64 `.AppImage` and `.deb`) plus `install.sh`, a curl one-liner that avoids the macOS quarantine flag (the app is ad-hoc signed, not notarized). The repo README gets a table row. |
| 17 | Repo Notes | The fixed set listed in §4.2. Only `README.md` is required. Clicking a folder's Node opens that folder's `README.md`. |
| 18 | Endpoint fields | Uses the template in §4.4, including Status (`implemented`, `last_changed`, missing features) and known Bugs. |
| 19 | Up to date | Each Repo `README.md` records `verified_commit` and `verified_on`. The app shows "verified N days ago" and highlights it after N days (setting, default 30). |
| 20 | Bugs and Todos | Markdown task items in `bugs.md` and `todo.md`, with checkboxes you can click. A vault-wide Tasks panel waits until after v1. |
| 29, 30 | Archive | `<project>/archive/fixed-bugs.md` and `done-todos.md`. Ticking a box in the app **moves** the item there, adding the date and a source Link, and ⌘Z undoes it. Agents follow the same rule. See ADR 0002. |
| 31 | Archive visibility | Hidden in the graph by default (a filter shows it). Shown in search, labelled "archived". |
| 32, 33 | Clients | `clients/` at the Vault root, one Note per Client (type `client`): who they are, what they do, a `Uses:` list of Endpoint Links (a third edge style in the graph), plus SLAs, auth and the docs they rely on. |
| 34 | Agents and Clients | Agents may read Client Notes but never create or edit them unless explicitly asked. |
| 35 | Running agents | You run your own agent tool in the Vault. The app only offers **Copy ingest prompt** and **Copy refresh prompt** on a Repo. |
| 36, 42, 44 | Source location | The Vault sits in your workspace next to the cloned repositories. A **Repo list** file at the Vault root (`repos.txt`, one repository name per line) names the only sibling folders agents may read. It can include non-service repos (e.g. infrastructure), which become Repos without an `endpoints.md`. Notes never store local paths. |
| 37 | First launch | *Create vault* or *Open vault*. Create writes `README.md`, `AGENTS.md`, `repos.txt`, `tags.md`, `templates/`, `external/` and `clients/`, with no sample data. One Vault is open at a time, and the last one is remembered. |
| 38 | Hidden files | `AGENTS.md`, `repos.txt`, `tags.md`, `templates/` and `.constellation/` (app settings) show in the file tree but are left out of the graph and search. |
| 24 | Layout | Three panes. Left: search plus Files and Tags tabs. Middle: editor with tabs. Right: inspector with backlinks, outline, and Calls/Uses in and out. The graph opens in its own window (⌘G). |
| 25, 40 | Renames | Renaming or moving a Note in the app rewrites every Link to it. Renaming a heading in the app rewrites Links to that heading. Links broken from outside the app show red in the editor and as ghost Nodes in the graph, and clicking one creates the Note. |
| 26 | External APIs | One Note per API, `external/<name>.md` (type `external-api`), with one heading per Endpoint that we use. |
| 41 | Graph | Force-directed layout with drag, zoom and pan. Click opens a Note, and hover highlights its neighbours. Filters: Project, Note type, edge type (Containment / Link / Call / Uses), archive, Tag. Local graph of depth 1–3 around the current Note. Positions are not saved in v1. |
| 45 | Tag syntax | `#tag` only. It must start with a letter right after `#`, so `# Heading`, `#123` and `#fff` are not Tags. Nesting is allowed (`#team/payments`). A frontmatter `tags: [a, b]` list also counts. Nothing inside code spans, code blocks or URLs counts. Tags match case-insensitively. `@` stays plain text. |
| 46 | Tags pane | A **Tags** tab in the left sidebar next to Files. It lists every Tag with its Note count, nested Tags fold out as a tree, and it sorts by name or count. Clicking a Tag lists its Notes, each with the line where the Tag appears, and clicking a Note opens it. |
| 47 | Tags in search and graph | A search for `#payments` filters to Notes with that Tag, and can be combined with text (`#payments refund`). The graph has a Tag filter that shows the tagged Notes and their neighbours. Tags are not graph Nodes. |
| 48 | Tag click | ⌘-click on a Tag in the editor opens the Tags tab filtered to it. |
| 49 | Tag list | `tags.md` at the Vault root lists one Tag per line with its meaning. Agents use only Tags already in the Vault or in this list, and propose new ones to the user instead of creating them. The editor autocompletes Tags after `#`. |
| 50 | Tag rename | Right-click → Rename in the Tags pane rewrites the Tag in every Note, as one undoable step. |

## 3. Out of scope for v1

These were deliberately left out:
- git integration
- launching agents from the app
- the vault-wide Tasks panel
- Mermaid and other diagrams
- saved graph positions
- several open Vaults
- sync or collaboration
- plugins
- one Note per Endpoint
- a quick-open palette (search covers it)

## 4. Vault format

### 4.1 Layout

```
<workspace>/
├── constellation-vault/            ← the Vault (any name)
│   ├── README.md                   type: note, what this vault covers
│   ├── AGENTS.md                   rules for agents (§7)
│   ├── repos.txt                   Repo list, one repository name per line, `#` comments allowed
│   ├── tags.md                     Tag list: `- #payments: payment flows`, one per line
│   ├── templates/                  one template per Note type
│   ├── .constellation/             app settings (graph filters, staleness days)
│   ├── external/
│   │   └── stripe.md               type: external-api
│   ├── clients/
│   │   └── billing-portal.md       type: client
│   └── shop/                       a Project
│       ├── README.md               type: project
│       ├── archive/
│       │   ├── fixed-bugs.md       type: archive
│       │   └── done-todos.md       type: archive
│       ├── orders-service/         a Repo
│       │   ├── README.md           type: repo
│       │   ├── endpoints.md
│       │   ├── architecture.md
│       │   ├── requirements.md
│       │   ├── future.md
│       │   ├── bugs.md
│       │   ├── todo.md
│       │   └── adr/0001-<slug>.md
│       └── infra/                  a non-service Repo: no endpoints.md
├── orders-service/                 the cloned source repositories, siblings of the Vault
└── infra/
```

The Repo folder name must equal the repository name in `repos.txt`, which is also the last part of `repo_url`.

### 4.2 Notes in each Repo

| Note | `type` | Content |
|------|--------|---------|
| `README.md` (required) | `repo` | Purpose, tech stack, owning team, `repo_url`, `verified_commit`, `verified_on` |
| `endpoints.md` | `endpoint` | One `##` per Endpoint (§4.4) |
| `architecture.md` | `architecture` | Components, data stores, messaging, deployment |
| `adr/NNNN-<slug>.md` | `adr` | One decision that cannot be changed lightly: context, decision, why |
| `requirements.md` | `requirements` | Service-wide requirements (endpoint-specific ones go under that Endpoint) |
| `future.md` | `future` | Planned or considered work, e.g. new Endpoints |
| `bugs.md` | `bugs` | Open Bugs as task items |
| `todo.md` | `todo` | Open Todos (refactorings and other work) as task items |

### 4.3 Frontmatter

```yaml
---
type: repo            # required: project | repo | endpoint | architecture | adr | requirements | future |
                      #           external-api | client | bugs | todo | archive | note
repo_url: https://github.com/<org>/orders-service   # repo only
verified_commit: abc1234                              # repo only
verified_on: 2026-10-01                               # repo only
tags: [payments, pci]                                 # any type, same as writing #payments #pci in the body
---
```

Unknown keys are kept as they are and ignored. A Note without frontmatter is treated as `type: note`.

### 4.4 Endpoint template (a heading in `endpoints.md`)

```md
## POST /orders

Summary: Creates an order from a cart.

Request: `{ cartId, customerId }`. Response: `201 { orderId }`.

Calls:
- [[shop/payments-service/endpoints#POST /charges]]
- [[external/stripe#POST /v1/payment_intents]]

Requirements:
- Must be idempotent on `Idempotency-Key`.

Status:
- implemented: partial          # complete | partial | planned | deprecated
- last_changed: 2026-09-30 (abc1234)
- missing: discount codes

Known bugs:
- [[bugs#Order total ignores discounts]]
```

Parsing rule: inside an Endpoint heading, the bullet list right after a line that is exactly `Calls:` holds that
Endpoint's Calls. The same applies to `Uses:` in Client Notes. Every other `[[...]]` is a plain Link.

### 4.5 Bugs, Todos and the Archive

Open item in `bugs.md` or `todo.md`:

```md
- [ ] Order total ignores discounts → [[endpoints#POST /orders]]
  Discounts are applied after tax instead of before.
```

Archived entry, which the app writes when the box is ticked:

```md
### Order total ignores discounts
- closed: 2026-10-17
- source: [[shop/orders-service/endpoints#POST /orders]]
- what: Discounts are applied after tax instead of before.
- fix: unknown
```

`fix` is left as `unknown` for the person or agent to fill in. If the item has no Link, `source` is the Repo
(`[[shop/orders-service/README]]`).

### 4.6 Client Note

```md
---
type: client
---
# Billing portal
Who: internal billing team (team or system name, no personal data needed).
What they do: show invoices to customers.

Uses:
- [[shop/orders-service/endpoints#GET /orders/{id}]]

SLA, auth method, docs they rely on: …
```

## 5. Architecture

```
constellation/
├── Cargo.toml               workspace: core, src-tauri
├── package.json             Vite, vitest, @tauri-apps/cli
├── build.sh, install.sh     build from source / install a release
├── core/                    Rust library, no UI or Tauri dependency; embeds AGENTS.md and templates/
├── src-tauri/               Tauri shell: commands exposing core, file watcher, windows, bundling config
├── ui/                      TypeScript frontend: CodeMirror editor, panes, graph
└── fixtures/vault/          fictional Vault for tests and launch checks
```

**Core has no UI dependency**, so `cargo test` runs the same on Linux and macOS. The frontend talks to it only through
Tauri commands and events.

Core modules (each a small surface with the logic behind it):

| Module | Interface (sketch) | Notes |
|--------|--------------------|-------|
| `NoteParser` | `parse(text) -> ParsedNote` (frontmatter, headings with ranges, links with ranges, Calls/Uses per heading, task items, Tags with ranges) | Hand-written line parser. No markdown library (zero dependencies). The editor's styling uses the same ranges. |
| `Vault` | `load(root)`, `apply(change)`, notes, folders | Treats the file system as the source of truth and holds the index in memory. Applies the hidden-file rules from §2 #38. |
| `LinkResolver` | `resolve(link, from:) -> Target?` | Resolves by path, then by unique name, then marks the link broken. |
| `Graph` | `nodes`, `edges(kind)`, `local(around:depth:)` | Edge kinds: Containment, Link, Call, Uses. Folds Calls into one edge per Note pair, with the list of Endpoint pairs. |
| `SearchIndex` | `search(query) -> Results(folders, notes, matches)` | Lowercased, diacritic-folded copy of every Note. Text is split into sentences on load so a match returns its sentence. Updated per changed file. Target: <50 ms for 5,000 Notes. |
| `TagIndex` | `tags -> [(tag, count)]`, `notes(tag) -> [(note, line)]` | Built from the parser output and updated per changed file. Nested Tags roll up into their parent. |
| `Refactor` | `rename(note, to:)`, `renameHeading(in:from:to:)`, `renameTag(from:to:) -> [FileEdit]` | Returns edits and the app applies them, so undo is one step. |
| `Archiver` | `archive(item, in: note) -> [FileEdit]` | Removes the item and appends the entry from §4.5 to the Project's archive Note. |
| `VaultScaffold` | `create(at:)` | Writes the starter files from §2 #37. |

App layer:
- Three panes in the main window, plus a separate graph window.
- The editor is CodeMirror 6 with decorations for live preview.
- The graph is drawn on a canvas, using a simple force simulation of Barnes–Hut type when node count makes plain n² too
  slow.
- A `notify` watcher in `src-tauri` feeds `Vault.apply`.
- Settings: theme and staleness days.

## 6. Editor

### 6.1 Live preview, built in steps (target: §2 #21)

1. **Styled in place.** Use the parser's ranges to apply attributes: bold and italic fonts, heading sizes, code
   background, link colour, dimmed markers.
2. **Hide markers off the cursor line.** Collapse marker ranges (`**`, `#`, `[[`, `]]`, `|alias` target) on every line
   except the selected ones, and restyle on selection change.
3. **Widgets.** Checkboxes you can click (and the archive move from §4.5), inline images, aligned tables, links you
   can click (⌘-click when on the cursor line).

Step 1 already gives a usable app. Step 2 is the riskiest part of the project, so prototype it early (milestone M2).

### 6.2 Toolbar and shortcuts

Each button wraps the selection, or inserts an empty pair with the cursor in the middle when nothing is selected.
Pressing it again on text that already has the format removes it. Line formats (headings, lists, quote) apply to every
selected line.

| Button | Markdown | Shortcut |
|--------|----------|----------|
| Bold | `**x**` | ⌘B |
| Italic | `*x*` | ⌘I |
| Underline | `<u>x</u>` | ⌘U |
| Strikethrough | `~~x~~` | ⇧⌘X |
| Inline code | `` `x` `` | ⌘E |
| Code block | ```` ``` ```` fence | ⌥⌘C |
| H1 / H2 / H3 | `#` / `##` / `###` | ⌘1 / ⌘2 / ⌘3 |
| Bullet list | `- ` | ⇧⌘8 |
| Numbered list | `1. ` | ⇧⌘7 |
| Task list | `- [ ] ` | ⇧⌘9 |
| Quote | `> ` | ⇧⌘. |
| Link | `[[x]]`, with autocomplete of Note and heading names | ⌘K |
| Table | 2×2 skeleton | none |

## 7. `AGENTS.md` (shipped in `Resources/`, written into every new Vault)

The outline is below. Write it with the `writing-for-agents` skill. It must be short, imperative and testable.

1. **What this Vault is.** The purpose (§1), and that it is the first place to look.
2. **Hard rules.**
   - Read and write only the repositories named in `repos.txt`, found as sibling folders of the Vault. Ask when a
     folder is missing.
   - Never read `*/archive/` unless the user asks about history.
   - Never create or edit `clients/` Notes unless explicitly asked.
   - Never invent facts. Write `unknown` instead.
   - Use only Tags already in the Vault or in `tags.md`. Propose new Tags to the user instead of creating them.
   - Never store local paths, secrets, tokens or personal data.
   - Keep the layout, templates and syntax from §4 exactly (Calls, Uses, Status keys, task items).
3. **Ingest a Repo.**
   - Create `<project>/<repo>/` from `templates/`.
   - Fill `README.md`, then `endpoints.md` (every Endpoint, its Calls including External APIs, its Status with
     `last_changed` from `git log` on the handler), then `architecture.md`, ADRs, `requirements.md`, `future.md`,
     `bugs.md` and `todo.md`. The last two come from code TODOs, issue trackers if available, and what the user says.
   - Set `verified_commit` to `HEAD` and `verified_on` to today.
   - Create missing `external/<api>.md` Notes for any External API that is called.
4. **Refresh a Repo.**
   - Read `git diff <verified_commit>..HEAD` and `git log` for that range only.
   - Update only the affected Endpoints and Notes, and fix any Links that the changes broke.
   - Move fixed Bugs and done Todos to the Archive using the §4.5 format.
   - Bump `verified_commit` and `verified_on`.
5. **Answer a question.**
   - Search the Vault first, and answer from it with Links to the Notes used.
   - Open the source only when the Vault can't answer. Then say so, and offer to add what was missing.
6. **Templates and examples.** The blocks from §4.4–4.6.

The app's **Copy ingest prompt** and **Copy refresh prompt** produce a prompt such as: "Follow AGENTS.md → Ingest Repo
`orders-service` into Project `shop`."

## 8. Milestones

Each milestone ends green in CI.

| M | Delivers | Done when |
|---|----------|-----------|
| M0 | Package skeleton, `build.sh`, CI workflow, empty window | The CI build and launch test pass |
| M1 | Core: `NoteParser`, `Vault`, `LinkResolver`, `VaultScaffold` + tests | Parsing and resolution tests pass on Linux and macOS |
| M2 | **Live-preview spike**: steps 6.1.1 and 6.1.2 in a throwaway window | Markers hide and reappear correctly while typing, selecting and undoing. Decide whether to continue with (a) or ship step 1 first |
| M3 | Main window: tree, tabs, editor (step 1 + toolbar + shortcuts), autosave, watcher, conflict banner | You can edit a Vault by hand and agents' changes appear live |
| M4 | `SearchIndex` + search UI, `TagIndex` + Tags tab, `#tag` search filter, Tag autocomplete, ⌘-click on Tags | The benchmark test passes: <50 ms on a generated 5,000-Note Vault |
| M5 | Graph window: layout, edge kinds, filters (including Tag), local graph, click and hover | Usable on the 5,000-Note fixture |
| M6 | Inspector (backlinks, outline, Calls/Uses), `Refactor` (rename Note, heading and Tag), broken links and ghost Nodes | Rename tests pass, and the rewrites can be undone |
| M7 | Editor steps 6.1.2 and 6.1.3, checkboxes, `Archiver` | Archive tests pass, and ticking a box then pressing ⌘Z restores the item |
| M8 | Themes (Light, Dark, Dracula, One Dark, System), staleness badge, Settings, first-launch flow, Copy prompt actions | |
| M9 | `AGENTS.md` and templates finalised, README, `.dmg`, README table row, release | Dry run: an agent ingests a sample service from a public repo into a new Vault, following only `AGENTS.md` |

## 9. Tests

Core code gets unit tests with `cargo test --workspace` (Linux and macOS in CI), the frontend gets `npm test` (vitest), and clippy runs with `-D warnings`:
- **Parser:** frontmatter, headings, links with heading and alias, Calls/Uses blocks, task items, code fences (no links
  parsed inside them).
- **Resolver:** path, unique name, ambiguous name, broken link.
- **Graph:** edge kinds, Call folding, local depth.
- **Search:** case and diacritics, folder / Note / text grouping, sentence extraction, incremental update, a 5,000-Note
  benchmark.
- **Tags:**
  - What counts as a Tag: `#tag`, nested Tags, frontmatter `tags:`.
  - What doesn't: `# Heading`, `#123`, Tags inside code or URLs.
  - Case-insensitive grouping, counts, and nested Tags rolling up into their parent.
- **Refactor:** Note, heading and Tag rename across the Vault.
- **Archiver:** the move, the entry format, and a source fallback when there is no Link.
- **Scaffold:** the file set of a new Vault.

The app shell only gets the CI launch test (10 s against `fixtures/vault`). Check the editor and graph by hand against
that fixture Vault. Fixture data must be fictional.

## 10. Open points to revisit after implementation

- Whether folders as Nodes look good, or whether folders should collapse into their `README.md` Node (§2 #5).
- Whether Endpoint-level Nodes are needed in the graph after all (ADR 0001).
- The vault-wide Tasks panel and Mermaid diagrams.
