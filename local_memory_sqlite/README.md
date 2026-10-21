# local_memory_sqlite

Memory that lasts between sessions for GitHub Copilot agents in VS Code (macOS). Memories live in one SQLite database, `~/.local_memory_sqlite/memory.db`. Hooks load the relevant ones, and six skills teach the agent to remember, recall, forget, list and reflect. Terms are defined in [GLOSSARY.md](GLOSSARY.md).

**Install:** ask your agent to follow [install.md](install.md).

## How memories work

| | |
|---|---|
| **Scope** | `global` (every session) or `repo` (only sessions in one repository) |
| **Repository key** | `landing_zone/repo_name` from the git `origin` remote, `local/<folder>` for other folders, `local/chat` when no folder is open |
| **Load mode** | `always`: the full text is given to the agent at session start. `on_demand`: only the title is shown, and the agent fetches the text when needed |
| **Expiry** | `never`, relative (`30d`, `2w`, `6m`, `1y`; a month counts as 30 days) or a date (`2027-01-01`, valid through that day, UTC). Expired memories are deleted on the next CLI call and are never shown |

At session start the agent receives a header saying how to use the CLI, then the `always` memories in full and the `on_demand` titles, newest first, capped at 40 KB:

- **One repository** (or a plain folder): global memories and that repository's.
- **A folder holding several repositories** (found up to two levels down; hidden folders, `node_modules`, `venv`, `build`, `dist` and `target` are skipped): global memories only, plus the list of repositories with their keys and memory counts.

A PostToolUse hook does the rest. The first time a tool reads or edits a file in a repository, the agent gets that repository's memories (capped at 8 KB) and its key. Each repository loads once per session, and only if the session works in it. Which repositories a session has loaded is kept in the database for 30 days.

## Skills

| Skill | Use |
|---|---|
| `alx-remember` | "Remember that…": searches first and updates an existing memory instead of adding a duplicate |
| `alx-recall` | Searches and reads memories, and changes one when you ask |
| `alx-forget` | Shows the matching memories and deletes only the ones you confirm |
| `alx-memories-list` | Lists memories for this repository, another repository or all repositories |
| `alx-reflect` | Proposes new memories, updates and deletions from the conversation; you approve any subset |
| `alx-reflect-auto` | Adds or updates this repository's memories without asking; never deletes, never touches global memories |

## CLI

`python3 ~/.local_memory_sqlite/mem.py <command>`. Every command prints JSON. Errors print `{"error": "..."}` and exit with status 1.

```sh
mem.py add --title T --content C|- --scope global|repo --load always|on_demand --expires never|30d|YYYY-MM-DD [--repo KEY | --path DIR]
mem.py get ID
mem.py update ID [--title] [--content] [--scope] [--repo | --path] [--load] [--expires]
mem.py delete ID
mem.py search TERMS... [--repo KEY | --path DIR | --all-repos] [--limit 20]   # every term must match; "exact phrase"; best match first
mem.py list [--scope] [--load] [--titles] [--repo KEY | --path DIR | --all-repos]
mem.py context    # SessionStart and PostToolUse hooks: reads the hook JSON on stdin, prints the hook JSON
```

Without `--repo`, a command uses the repository key of the current folder. `--path DIR` uses the key of the repository that contains `DIR`. `--content -` reads the content from stdin. Set `LOCAL_MEMORY_DB` to use another database file.

## Tests

```sh
python3 -m unittest -v test_mem.py
```

The tests run the real CLI against a temporary database. They cover every command, the JSON errors, expiry parsing and purging, scope and repository filtering, FTS5 search (prefixes, phrases, ranking, diacritics, special characters), repository keys for SSH, HTTPS and Azure DevOps remotes, the hook output and its 40 KB cap, workspaces with several repositories (the repository list, loading on the first tool call, once per session, path forms in tool arguments), a broken database, and parallel writers.
