# Uninstall (instructions for the agent)

You are removing local_memory_sqlite for GitHub Copilot in VS Code on macOS, for the current user. Check the result of each step, and stop and report if something is not as described.

The older Local Memory project (`lm.zip`, data in `~/.copilot/local-memory/`) uses some of the same names: the skills `alx-remember` and `alx-reflect` and the hook file `~/.copilot/hooks/local-memory.json`. Delete those three only if they belong to this project (step 1).

1. **Find what this project owns.** A file belongs to local_memory_sqlite if it mentions `.local_memory_sqlite`:
   ```sh
   grep -l '\.local_memory_sqlite' ~/.copilot/hooks/local-memory.json ~/.copilot/skills/alx-*/SKILL.md 2>/dev/null
   ```
   Only the files this lists are this project's. If `alx-remember`, `alx-reflect` or `local-memory.json` exists but is not listed, it belongs to the older Local Memory: leave it and tell the user.

2. **Remove the hook**, if step 1 listed it:
   ```sh
   rm ~/.copilot/hooks/local-memory.json
   ```

3. **Remove the skills** that step 1 listed, out of `alx-remember`, `alx-recall`, `alx-forget`, `alx-memories-list`, `alx-reflect` and `alx-reflect-auto`:
   ```sh
   rm -rf ~/.copilot/skills/<skill name>
   ```

4. **Remove the tool**, keeping the memories:
   ```sh
   rm -f ~/.local_memory_sqlite/mem.py
   ```

5. **Ask before deleting the memories.** `~/.local_memory_sqlite/` holds `memory.db` (plus `memory.db-wal` and `memory.db-shm` while it is in use). Show the user how many memories there are (`sqlite3 ~/.local_memory_sqlite/memory.db 'select count(*) from memories'`). Offer to keep a backup copy first, then wait for an explicit yes before running:
   ```sh
   rm -rf ~/.local_memory_sqlite
   ```

6. **Check.**
   - `ls ~/.copilot/skills ~/.copilot/hooks` must show none of the files removed above.
   - Tell the user to start a new chat; `/skills` must no longer list the removed skills.
   - Remind the user that sessions already open keep their loaded memories until they end.
