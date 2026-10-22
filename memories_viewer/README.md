# Memories

A VS Code sidebar for the memories of [`local_memory_sqlite`](../local_memory_sqlite/). Click the journal icon in the
activity bar to see them, like the Explorer shows files. Read-only: adding, changing and deleting stay with the agent
and its `alx-*` skills.

## What you see

- **Global** first, then the repositories of the folders you have open, then every other repository, each with its
  number of memories. Global and the open repositories start expanded.
- Each memory shows its title, its load mode (`always` or `on_demand`) and its expiry, if it has one. Hovering shows
  the start of the content; newest first.
- Click a memory to open its content in a read-only Markdown tab.
- **Search** (magnifier) finds memories containing every word you type, in any repository, best match first. The
  clear button next to it goes back to the full list.
- **Refresh** reloads the list; it also reloads every time you open the view, so memories the agent just stored show up.

## Requirements

`local_memory_sqlite` installed (`~/.local_memory_sqlite/mem.py`) and `python3` on the `PATH`. The extension only runs
`mem.py list` and `mem.py search`, so it sees the same database the agent does, including `LOCAL_MEMORY_DB` if VS Code
was started with it.

## Install

Download `memories-viewer-0.1.0.vsix` from the [latest release](https://github.com/alexlol87/public_ish_projects/releases/tag/memories-viewer-latest), then run

```sh
code --install-extension memories-viewer-0.1.0.vsix
```

or in VS Code: Extensions view → `…` menu → **Install from VSIX…**.

To build it yourself: `cd memories_viewer && npm run package`.

## Test

```sh
npm test                 # unit tests, plain node
test/seed.sh             # throwaway HOME in /tmp/memtest with four memories
HOME=/tmp/memtest/home code --user-data-dir /tmp/memtest/vsc --extensionDevelopmentPath="$PWD" \
  --extensionTestsPath="$PWD/test/suite.js" "$PWD/.."
```

The last command runs `test/suite.js` inside VS Code against the seeded memories and prints
`memories-viewer: integration test passed`. Drop `--extensionTestsPath` to try the extension by hand.
