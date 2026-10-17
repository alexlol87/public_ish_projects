# Constellation

A macOS notes app for a **Vault** of linked markdown Notes, like Obsidian, built for teams with many Projects made of
many microservices in separate repositories. The Vault keeps what each Repo does, its Endpoints, what they call, what is
broken and what is planned, and the app draws it as a graph of Projects, Repos, Endpoints, External APIs and Clients.
The app starts empty: people and agents fill the Vault. Agents follow an `AGENTS.md` that the app writes into the Vault.

Swift, SwiftUI with AppKit and TextKit 2, no third-party dependencies. macOS 14+, Apple Silicon.

## Install

1. Download `Constellation.dmg` (or `Constellation.zip`) from the
   [latest release](https://github.com/alexlol87/public_ish_projects/releases/tag/constellation-latest).
2. Move `Constellation.app` to /Applications.
3. The app is ad-hoc signed, not notarized. Run this once:
   `xattr -dr com.apple.quarantine /Applications/Constellation.app`

## First launch

Choose **Create vault...** (pick an empty folder) or **Open vault...** (pick an existing Vault). Creating writes
`README.md`, `AGENTS.md`, `repos.txt`, `tags.md`, `templates/`, `external/` and `clients/`, with no sample data. One
Vault is open at a time and the last one is reopened at launch. A good place for it is your workspace folder, next to
the cloned repositories.

## Vault layout

```
my-vault/
  README.md  AGENTS.md  repos.txt  tags.md  templates/  .constellation/
  external/<api>.md            one Note per External API
  clients/<client>.md          one Note per Client, written by people
  <project>/README.md
  <project>/archive/           fixed-bugs.md, done-todos.md
  <project>/<repo>/            README.md (required), endpoints.md, architecture.md, requirements.md,
                               future.md, bugs.md, todo.md, adr/NNNN-<slug>.md
```

- Notes are plain `.md` files with small YAML frontmatter (`type` is required, a Note without it is `type: note`) and
  Obsidian `[[wikilinks]]` (`[[path#Heading]]`, `[[path|alias]]`).
- `endpoints.md` has one `##` heading per Endpoint, with a `Calls:` bullet list of Links under it.
- Tags are `#tag` (nesting allowed, `#team/payments`) or a frontmatter `tags:` list; `tags.md` lists the known ones.
- `repos.txt` names (one per line) the sibling folders agents may read.
- `AGENTS.md`, `repos.txt`, `tags.md`, `templates/` and `.constellation/` show in the file tree but not in search or the graph.

The full format is in [PLAN.md](PLAN.md); vocabulary in [GLOSSARY.md](GLOSSARY.md); decisions in [docs/adr/](docs/adr/).

## Agents

Run your own agent tool inside the Vault and tell it to follow `AGENTS.md`. It describes three workflows: **Ingest**
(read a repository and write its Notes), **Refresh** (update Notes for a repository that changed) and **Answer**
(answer questions from the Vault first, from code only when the Vault can't). On a Repo, **Copy ingest prompt** and
**Copy refresh prompt** put a ready prompt on the clipboard. The app does not launch agents.

## Building

On macOS 14+ with Swift 6.2:

```sh
scripts/build-app.sh        # build/Constellation.app (ad-hoc signed), Constellation.zip and Constellation.dmg
CONSTELLATION_VAULT=fixtures/vault build/Constellation.app/Contents/MacOS/Constellation   # open the fictional fixture Vault
```

Set `SIGN_IDENTITY` to sign with a certificate instead of ad-hoc. CI (`.github/workflows/constellation.yml`) tests,
builds, launch-tests the app, and on `main` replaces the `constellation-latest` release.

## Tests

```sh
swift test -Xswiftc -warnings-as-errors
```

`ConstellationCore` (Vault, parsing, links, search, tags, graph layout, renames, archive, agent files) is
Foundation-only and tested on Linux too (e.g. in a `swift:6.2` container). The SwiftUI/AppKit app target compiles only
on macOS.
