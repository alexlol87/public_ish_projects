---
name: alx-reflect-auto
description: Review the conversation and store, without asking, what this repository's future sessions should know. Adds or updates repository memories only; never deletes and never touches global memories.
---

# Reflect automatically

The CLI is `python3 ~/.local_memory_sqlite/mem.py`; every command prints JSON. Find the repository key as the `alx-remember` skill describes, and pass it with `--repo <key>`.

Rules:
- Only `--scope repo`, with the key of the repository each memory is about (in a workspace with several repositories, that can differ per memory). Never add, update or delete global memories, and never delete anything.
- Prefer updating to adding: before every add, search (`mem.py search <words> --repo <key>`). If a memory of this repository covers the topic, update it with merged content and an expiry that fits.

Steps:
1. Go through the conversation for things a future session in this repository would need and could not easily rediscover: corrections from the user, conventions, commands, gotchas, and decisions with their reasons. Skip what the code, docs or git history already say, and one-off details.
2. For each one, add or update a memory, following the field rules in the `alx-remember` skill. Choose the load mode and expiry yourself: `on_demand` unless it must shape every session, and short expiries for facts about current state.
3. Report in a short list what you added and updated (ids and titles), so the user can undo something with `alx-forget`.
