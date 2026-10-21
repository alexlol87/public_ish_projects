# Uninstall (instructions for the agent)

You are removing Local Memory for GitHub Copilot, for the current user. Check the result of each step, and stop and report if something is not as described. Below, `$H` is the Copilot home: `$COPILOT_HOME` if it is set, otherwise `~/.copilot`.

`./install.sh --uninstall` (Windows: `py install.py --uninstall`) removes the same files as steps 2 to 4. But it deletes them without checking who owns them, and the newer local_memory_sqlite project (`lms.zip`) uses the same names: the skills `alx-remember` and `alx-reflect` and the hook file `$H/hooks/local-memory.json`. Use the script only if step 1 finds no local_memory_sqlite files; otherwise follow the steps by hand.

1. **Find what this project owns.** A file belongs to Local Memory if it mentions `local-memory/mem.py` (the installer wrote that path into it):
   ```sh
   H="${COPILOT_HOME:-$HOME/.copilot}"
   grep -l 'local-memory/mem\.py' "$H"/hooks/local-memory.json "$H"/skills/*/SKILL.md 2>/dev/null
   grep -l '\.local_memory_sqlite' "$H"/hooks/local-memory.json "$H"/skills/*/SKILL.md 2>/dev/null
   ```
   The first command lists Local Memory's files, the second lists local_memory_sqlite's. Never delete a file from the second list. If Local Memory is paused (`/alx-disable-memory`), its hook and instructions file are in `$H/local-memory/paused/` instead, and step 5 covers them.

2. **Remove the hook and the instructions file**, if they are Local Memory's:
   ```sh
   rm "$H/hooks/local-memory.json"                        # only if the first list in step 1 contains it
   rm -f "$H/instructions/local-memory.instructions.md"
   ```

3. **Remove the skills** from the first list in step 1: `alx-remember`, `alx-reflect`, `alx-disable-memory` and `alx-enable-memory`, plus `remember` and `reflect` from installs before the `alx-` prefix:
   ```sh
   rm -rf "$H/skills/<skill name>"
   ```

4. **Remove the tool**, keeping the saved memory:
   ```sh
   rm -f "$H/local-memory/mem.py"
   ```

5. **Ask before deleting the saved memory.** `$H/local-memory/` holds user memory (`user.md`), instincts, every repository's memory and the observation logs, and the paused hook and instructions if memory was paused. Offer a backup first: `python3 local_memory/mem.py export ~/local-memory-backup.json` (the copy of `mem.py` in this repository still works after step 4), or copy the folder. Then wait for an explicit yes before running:
   ```sh
   rm -rf "$H/local-memory"
   ```

6. **Remove the auto-approve rule**, if the user added it. In VS Code's user `settings.json`, find the `chat.tools.terminal.autoApprove` entry whose pattern contains `local-memory/mem\\.py` and delete that one entry. Show the user the change and leave the other entries alone.

7. **Check.**
   - Run step 1 again: the first command must print nothing.
   - Tell the user to start a new chat. **Chat: Open Customizations** must no longer list the removed skills, `local-memory.instructions.md` or the Local Memory hooks.
