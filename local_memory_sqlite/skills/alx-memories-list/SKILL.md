---
name: alx-memories-list
description: List local memories when the user asks what is remembered, for this repository, another repository or all repositories.
---

# List memories

The CLI is `python3 ~/.local_memory_sqlite/mem.py`; every command prints JSON, newest first. Find the repository key as the `alx-remember` skill describes.

- **This repository** (the default): `mem.py list --repo <key>` gives global memories plus this repository's.
- **Another repository**: `mem.py list --repo <other key>`, or `mem.py list --path <its folder>`.
- **Everything**: `mem.py list --all-repos --titles`. Group the result by repository (global first). If it has more than about 30 memories, show titles only and offer to expand a group with `mem.py list --repo <key>`.
- To narrow the list, add `--scope global|repo` or `--load always|on_demand`.

Show each memory as `#id [scope, load, expires …] title`, followed by its content when you have it. Don't add commentary.
