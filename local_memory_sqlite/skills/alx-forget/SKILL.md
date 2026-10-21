---
name: alx-forget
description: Delete local memories the user names ("forget that…", "delete the memory about…", "remove memory #12"). Always shows the memories and waits for confirmation before deleting.
---

# Forget

The CLI is `python3 ~/.local_memory_sqlite/mem.py`; every command prints JSON. Find the repository key as the `alx-remember` skill describes, and pass it with `--repo <key>`.

1. Find the memories:
   - If the user gave ids, use `mem.py get <id>` for each one.
   - Otherwise use `mem.py search <words> --repo <key>`, and add `--all-repos` if the user means any repository.
2. Show a numbered list: id, title, scope with repository, and the first line of content. Ask which ones to delete; the user may pick several at once ("1, 3" or "all"). If nothing matched, say so and stop.
3. Delete only the ones the user confirmed: `mem.py delete <id>` for each one. A deletion is permanent.
4. Report what you deleted (ids and titles).
