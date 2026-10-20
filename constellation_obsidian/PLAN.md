# Constellation for Obsidian: plan

Status: **planned**. Written 2026-10-20 from a design interview. Vocabulary and the Vault format come from the
standalone app: [../constellation/GLOSSARY.md](../constellation/GLOSSARY.md),
[../constellation/PLAN.md](../constellation/PLAN.md) §4 and [../constellation/docs/adr/](../constellation/docs/adr/).
This folder's own decision is [docs/adr/0001-obsidian-plugin-over-the-same-vault-format.md](docs/adr/0001-obsidian-plugin-over-the-same-vault-format.md).

## 1. Purpose

Constellation's value is the Vault format and the agent workflows, not the editor. Obsidian already is the editor, so
this plugin adds only what Constellation has and Obsidian lacks. The standalone app stays; one Vault opens in both.

## 2. Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Split | Obsidian keeps: editor, live preview, search, Tags pane, themes, backlinks, outline, Note rename/move with Link rewrites, new Note, file watching, graph. The plugin owns: Initialize vault, the Constellation panel, Archive ticked items, Copy ingest/refresh prompt. Dropped: Tag rename (use the Tag Wrangler plugin), heading rename, the cheat sheet. |
| 2 | Format | Identical to Constellation (its PLAN §4, ADR 0001, ADR 0002). Agents keep following the same `AGENTS.md`. |
| 3 | Publishing | Plaintext in the public repo, no personal information (names, emails, local paths). |
| 4 | Archive | A command, **Archive ticked items**, moves every `[x]` item of the current `bugs.md` or `todo.md` to `<project>/archive/fixed-bugs.md` or `done-todos.md` in the Constellation §4.5 entry format. Ticking a box alone does nothing. |
| 5 | Graph | Obsidian's graph, with colour groups per Note type set by Initialize. Edge kinds (Call, Uses, Containment) are not drawn; the panel lists Calls and Uses. A custom graph view only if this falls short. |
| 6 | Code | TypeScript only. The few pieces needed are rewritten from `constellation/core`; `AGENTS.md` and templates are copied as text. Obsidian's metadata cache supplies Links, headings and frontmatter. |
| 7 | Install | `plugin/constellation/` holds the built `main.js`, `manifest.json`, `styles.css`, committed. Copy that folder into `<vault>/.obsidian/plugins/` and enable it, or run `./install.sh <vault>`. Not in the community store (it needs a repo of its own). |
| 8 | Panel | A right-sidebar view. **Repo** section when the active Note is inside a Repo: "verified N days ago" (highlighted after the staleness setting, default 30 days), Copy ingest prompt, Copy refresh prompt. **Endpoint** section when the cursor is in a `##` of an `endpoints.md` or `external/*.md`: Calls, Called by, Used by clients. **Client** Notes: their Uses. Entries open on click. Prompts and archiving are also commands. |
| 9 | Initialize | Command only, never automatic, never overwrites. Writes `README.md`, `AGENTS.md`, `repos.txt`, `tags.md`, `templates/`, `external/`, `clients/`. Also sets Obsidian's Excluded files (`AGENTS.md`, `repos.txt`, `tags.md`, `templates/`), the core Templates folder (`templates/`) and graph colour groups per Note type. Those three use undocumented settings; each failure shows a notice saying what to set by hand. |
| 10 | Freshness of the build | `npm run build` writes into `plugin/constellation/`. Before a push: rebuild, and git must show no change there. No CI. |
| 11 | Tests | `node --test` (Node 24 runs TypeScript directly) on pure functions: Calls/Uses extraction, the archive edit, the staleness label, Repo detection. Everything else by hand in Obsidian against a copy of `../constellation/fixtures/vault`. |

Prompt text, as in Constellation: `Follow AGENTS.md in this Vault and run the Ingest workflow for the repository "<repo>".`
(and `Refresh`). A Repo is a folder at `project/repo` depth outside `external/`, `clients/`, `archive/` and the
app-only files.

## 3. Layout

```
constellation_obsidian/
├── manifest.json  package.json  package-lock.json  tsconfig.json  styles.css  install.sh
├── docs/adr/       this folder's decisions
├── src/
│   ├── main.ts             plugin: commands, settings tab, Archive ticked items
│   ├── panel.ts            right-sidebar view; renders the two sections below
│   ├── panel-repo.ts       Repo section: staleness, copy prompts
│   ├── panel-endpoint.ts   Endpoint/Client section: Calls, Called by, Used by, Uses
│   ├── initialize.ts       Initialize vault command (starter files, Obsidian settings)
│   └── pure, with *.test.ts beside them: settings.ts, repo.ts, relations.ts, archiver.ts, scaffold.ts
└── plugin/constellation/   built output, committed
```
