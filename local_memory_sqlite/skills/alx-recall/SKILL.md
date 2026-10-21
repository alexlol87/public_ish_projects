---
name: alx-recall
description: Look up local memories. Use when an on_demand memory title in the "Local memory" session context looks relevant to the task, when the user asks what you remember about something, or when the user asks to change a memory.
---

# Recall

The CLI is `python3 ~/.local_memory_sqlite/mem.py`; every command prints JSON. Find the repository key as the `alx-remember` skill describes, and pass it with `--repo <key>`.

- **Read one memory**: `mem.py get <id>`. Use this for an on_demand title shown at session start.
- **Search**: `mem.py search <terms> --repo <key>` returns global memories plus this repository's memories that contain every term, best match first. Words match as prefixes (`deploy` finds "deployment"); `"exact phrase"` matches the phrase. If nothing comes back, try fewer or other words. Add `--all-repos` to search every repository, or `--repo <other key>` to search another one.
- Before starting a task, search for its main topic if any on_demand title might apply. Follow what you find; if a memory contradicts what the user says now, the user wins, so mention it and offer to update the memory.

## Changing a memory

Only when the user asks. Find it, show the user its current title, content, scope, load mode and expiry, and the change you will make. Then wait for their yes:

```sh
python3 ~/.local_memory_sqlite/mem.py update <id> [--title ...] [--content - <<'EOF' ... EOF] [--scope ...] [--repo ...] [--load ...] [--expires ...]
```

Only the flags you pass change. `--expires never` removes the expiry.
