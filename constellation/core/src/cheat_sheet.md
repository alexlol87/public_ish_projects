Constellation cheat sheet. The app rewrites this file each time Help opens, so edits are overwritten.

## Shortcuts

On macOS, read Ctrl as the Command key.

| Keys | Does |
|---|---|
| Ctrl+N | New note: asks for a folder and name, opens the Note |
| Ctrl+G | Open the graph |
| Ctrl+S | Save every open Note now |
| Ctrl+W | Close the current tab |
| Ctrl+Z | Undo the last app action (rename, move, task tick, new note), outside typing |
| Ctrl+, | Settings |
| Ctrl+Shift+F | Focus the search box |
| Ctrl-click | Open a Link in a new tab |
| F1 | Open this cheat sheet (also the Help button) |

## The Vault

- `<project>/README.md` for each Project, then one folder per Repo: `<project>/<repo>/` with `README.md`, and as they
  apply `endpoints.md`, `architecture.md`, `adr.md`, `requirements.md`, `future.md`, `bugs.md`, `todo.md`.
- `external/<name>.md` holds each External API. `clients/<name>.md` holds each Client, written by people.
- `<project>/archive/` is the Archive: fixed Bugs and done Todos.
- New note accepts any path, so typing `new-project/README.md` creates the Project folder.

## Writing Notes

- A Link is `[[folder/note]]`. Add a heading with `[[folder/note#Heading]]`, and a shown name with `[[folder/note|alias]]`.
- A broken Link, one whose Note does not exist, is red. Click it to create the Note.
- A Tag is `#label` in the text or frontmatter. Tags nest: `#team/payments`. The Tags tab lists them.
- Each Note starts with `type:` frontmatter; a Note without it is `type: note`.

## Actions that change files

- Tick a task in `bugs.md` or `todo.md` and it moves to the Project's Archive.
- Renaming or moving a Note, or renaming a heading or Tag, rewrites every Link that pointed at it.
- Undo reverses the last of these, including a new note.

## The graph

- Nodes are Notes and folders. Colours show the Note type.
- Edge kinds: containment (folder to what it holds), link (a Link), call (a Call between Endpoints), uses (a Client
  calls an Endpoint).
- A ghost Node is a Link target that does not exist yet. Click it to create the Note.
- Filters: Projects, Note types, Edges, Show archive (off by default), a Tag, and the local-graph Depth.

## The inspector

The right panel shows, for the current Note or Endpoint: Calls, Called by, Used by Clients, Backlinks, and how stale
the Repo is (days since its Verified commit date; set the limit in Settings).

## App-only files

`AGENTS.md`, `repos.txt`, `tags.md`, `templates/` and `.constellation/` (including this file) belong to the app. They
stay out of search, the graph and agents' reading of Notes.

## Agents

`AGENTS.md` holds the rules agents follow. On a Repo's page, Copy ingest prompt and Copy refresh prompt put a
ready-made instruction on the clipboard to paste into an agent. Agents write Notes; they leave `clients/` alone.
