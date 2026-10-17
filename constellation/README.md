# Constellation

A notes app (Linux and macOS) for a **Vault** of linked markdown Notes, like Obsidian, built for teams with many Projects made of
many microservices in separate repositories. The Vault keeps what each Repo does, its Endpoints, what they call, what is
broken and what is planned, and the app draws it as a graph of Projects, Repos, Endpoints, External APIs and Clients.
The app starts empty: people and agents fill the Vault. Agents follow an `AGENTS.md` that the app writes into the Vault.

Tauri 2: a Rust core (`core/`), a TypeScript + CodeMirror frontend (`ui/`) and the app shell (`src-tauri/`). Linux (x86_64, aarch64) and macOS (universal, ad-hoc signed).

## Install

One line, on macOS or Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/constellation/install.sh | bash
```

It downloads the latest build with curl and installs it: `/Applications/Constellation.app` on macOS (or `~/Applications`),
`~/.local/bin/constellation` plus an app-menu entry on Linux. Remove it with `... | bash -s -- --uninstall`.

Downloads from the [latest release](https://github.com/alexlol87/public_ish_projects/releases/tag/constellation-latest) by hand:

- **macOS, `Constellation.dmg`**: drag the app to Applications. The app is ad-hoc signed, not notarized, and a file
  downloaded in a browser is quarantined, so Gatekeeper refuses it. Right-click the app and choose **Open** once, or run
  `xattr -dr com.apple.quarantine /Applications/Constellation.app`. `install.sh` avoids this because curl does not set the
  quarantine flag.
- **Linux, `Constellation-linux-<x86_64|aarch64>.AppImage`**: `chmod +x` it and run it (needs FUSE 2, or set
  `APPIMAGE_EXTRACT_AND_RUN=1`).
- **Linux, `Constellation-linux-<arch>.deb`**: `sudo apt install ./Constellation-linux-<arch>.deb`.

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

Needs Rust (stable), Node 22+ and, on Debian/Ubuntu,
`sudo apt install libwebkit2gtk-4.1-dev libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev build-essential curl file`.

```sh
./build.sh                  # build from source and install locally (when downloads are blocked)
./build.sh --no-install     # only build; bundles land in target/release/bundle/ (or $CARGO_TARGET_DIR)
npm ci && npm run tauri dev # run in development
CONSTELLATION_VAULT=fixtures/vault npm run tauri dev   # open the fictional fixture Vault
```

CI (`.github/workflows/constellation.yml`) lints and tests, builds the macOS, Linux x86_64 and Linux aarch64 bundles,
launch-tests each against the fixture Vault, and on `main` replaces the `constellation-latest` release.

## Tests

```sh
npm test                                   # frontend (vitest)
npx tauri build --no-bundle && npm run e2e # end-to-end, Linux only (see below)
cargo clippy --all-targets -- -D warnings
cargo test --workspace                     # Rust core
```

### End-to-end tests (Linux only)

`npm run e2e` drives the release binary through [tauri-driver](https://v2.tauri.app/develop/tests/webdriver/) and
WebKitWebDriver, with a tiny dependency-free WebDriver client (`e2e/lib.mjs`) and `e2e/run.mjs` (about 30 checks:
first launch, tree, tabs, editing and autosave, external edits and the conflict banner, live preview, links, Tags,
search, inspector, rename and undo, task tick, themes, the graph window, flush on close, reopen at launch). Each run
uses a temporary copy of `fixtures/vault` plus extra notes it writes, and a temporary config directory.

Needs `cargo install tauri-driver --locked`, `WebKitWebDriver` (Debian: `webkit2gtk-driver`), `python3`, and `Xvfb`
(without it the current `$DISPLAY` is used, which must be awake: a locked or blanked screen stops WebKit painting).
Build first with `npx tauri build --no-bundle` (the binary is read from `$CARGO_TARGET_DIR/release/constellation`,
default `target/release/`). `npm run e2e -- <part of a test name>` runs a subset; screenshots land in `e2e/out/`
(git-ignored), failures save one too. The app has two test-only switches that do nothing unless set:
`CONSTELLATION_E2E_PICK=<dir>` answers the native folder dialog, and the graph canvas exposes `e2e()` for node positions.
