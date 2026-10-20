# Constellation for Obsidian

An Obsidian plugin that adds Constellation's domain features to an Obsidian vault: a panel with a Repo's staleness and
an Endpoint's Calls, Called by and Used by clients, a command that archives ticked Bugs and Todos, the agent files and
templates, and ready ingest and refresh prompts for agents. Everything else (editor, search, Tags pane, graph,
backlinks, renames) is Obsidian's.

The plugin reads and writes the same Vault format as the standalone [Constellation](../constellation/) app, so one Vault
opens in both. The format is in [../constellation/PLAN.md](../constellation/PLAN.md) §4 and the vocabulary in
[../constellation/GLOSSARY.md](../constellation/GLOSSARY.md). The plugin changes no file until you run a command.

Needs Obsidian 1.5 or later. The plugin is not desktop-only, but it has been tried on desktop only.

## Install

Copy the folder `plugin/constellation/` into `<vault>/.obsidian/plugins/`, so that you get
`<vault>/.obsidian/plugins/constellation/main.js`. Then in Obsidian open **Settings > Community plugins**, turn on
community plugins if they are off, and enable **Constellation**. No Node or build step is needed: the built plugin is
committed.

From a clone, `./install.sh <vault>` builds the plugin and copies it into the vault in one step (needs Node and npm).

## Commands

All are in the command palette under "Constellation".

- **Initialize vault**: turns the open vault into a Constellation Vault. It writes `README.md`, `AGENTS.md`,
  `repos.txt`, `tags.md`, `templates/`, `external/` and `clients/`, never overwriting a file that is already there, and
  says what it created and what it skipped. It also adds `AGENTS.md`, `repos.txt`, `tags.md` and `templates/` to
  Obsidian's Excluded files, points the core Templates plugin at `templates/`, and adds a graph colour group per Note
  type. Those three are internal Obsidian settings: if one can't be written, a notice says what to set by hand. Safe to
  run again. It runs only when you ask.
- **Open Constellation panel**: opens the panel in the right sidebar (also the sparkles icon in the ribbon).
- **Copy ingest prompt** and **Copy refresh prompt**: put the prompt for the active Note's Repo on the clipboard, for
  example `Follow AGENTS.md in this Vault and run the Ingest workflow for the repository "cart-service".` Available
  only in a Note inside a Repo.
- **Archive ticked items**: in a Repo's `bugs.md` or `todo.md`, moves every ticked item, with its indented lines, to
  `<project>/archive/fixed-bugs.md` or `<project>/archive/done-todos.md` (created when missing), in the standard entry
  format with `fix: unknown`. Unticked items stay. Ticking a box on its own only ticks it.

## The panel

The panel follows the active Note.

- **Repo**: in a Note inside a Repo (`<project>/<repo>/`), the Repo name and how long ago it was verified, from
  `verified_on` in the Repo's `README.md`: "verified today", "verified N days ago", "never verified", "date is in the
  future" or "verified date unreadable". The label is highlighted when the Repo is past the staleness threshold, never
  verified, or its date is wrong. Two buttons copy the ingest and refresh prompts.
- **Endpoint**: with the cursor in a `##` heading of an `endpoints.md` or an `external/` Note, the Endpoint's
  **Calls**, what calls it (**Called by**, across all Repos) and which Clients use it (**Used by clients**). Only the
  bullet list right after a line that is exactly `Calls:` counts. Broken targets are marked. It updates as the cursor
  moves and when any Note changes, also on disk.
- **Client**: in a Client Note (`type: client`), its **Uses**.

Click an entry to open that Note at that heading.

## Settings

- **Staleness threshold (days)**: a Repo verified longer ago than this is highlighted. Default 30.

## Agents

Run your own agent tool inside the Vault and tell it to follow `AGENTS.md`, or paste a copied prompt. The rules,
templates and archive format are the standalone app's, so a Vault an agent fills works in both apps. The plugin does
not launch agents.

## Building

```sh
npm ci
npm test          # unit tests (node --test, Node 24)
npm run check     # tsc --noEmit
npm run build     # writes plugin/constellation/
```

`plugin/constellation/` is committed. Rebuild before a push; git must show no change in it afterwards.
