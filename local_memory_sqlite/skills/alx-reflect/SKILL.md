---
name: alx-reflect
description: Review the conversation and propose what to remember for future sessions, and which existing memories to update or delete. The user approves each proposal; nothing is stored without approval.
---

# Reflect (proposals only)

The CLI is `python3 ~/.local_memory_sqlite/mem.py`; every command prints JSON. Find the repository key as the `alx-remember` skill describes, and pass it with `--repo <key>`.

1. Go through the conversation for things a future session would need and could not easily rediscover:
   - corrections the user made to your work, and preferences they stated;
   - project conventions, commands and gotchas that took effort to find;
   - decisions together with their reasons.

   Skip anything already in the code, the docs or git history, and one-off details of this task.
2. For each candidate, search the existing memories (`mem.py search <words> --repo <key>`). Also look for existing memories this conversation proved wrong or outdated.
3. Show one numbered list:
   - **New**: title, content, scope (global or repo), load (always or on_demand), expiry, and one line on why.
   - **Update #id**: what changes, and why.
   - **Delete #id**: why it is wrong or stale.
4. Wait. The user approves any subset in one reply ("1, 3, 4", "all", "2 but make it global"). Apply exactly that, following the field rules in the `alx-remember` skill, and use `delete` for approved deletions.
5. Report what you stored, updated and deleted (ids and titles).
