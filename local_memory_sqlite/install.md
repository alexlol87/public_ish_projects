# Install (instructions for the agent)

You are installing local_memory_sqlite for GitHub Copilot in VS Code on macOS, for the current user. Run each step from this folder (the folder that contains `mem.py`), check its result, and stop and report if a step fails.

1. **Check prerequisites.** `python3 --version` must be 3.9 or newer, and FTS5 must be available:
   `python3 -c "import sqlite3; sqlite3.connect(':memory:').execute('create virtual table t using fts5(a)')"`
   If FTS5 is missing, stop and tell the user.

2. **Run the tests.** `python3 -m unittest test_mem.py` must end with `OK`.

3. **Install the CLI.** If `~/.local_memory_sqlite/memory.db` already exists, keep it; only replace `mem.py`.
   ```sh
   mkdir -p ~/.local_memory_sqlite && chmod 700 ~/.local_memory_sqlite
   cp mem.py ~/.local_memory_sqlite/mem.py
   ```

4. **Install the skills** as personal skills (VS Code reads `~/.copilot/skills/`). If a skill folder with the same name already exists, show the user the difference and ask before replacing it.
   ```sh
   mkdir -p ~/.copilot/skills
   cp -R skills/alx-remember skills/alx-recall skills/alx-forget skills/alx-memories-list skills/alx-reflect skills/alx-reflect-auto ~/.copilot/skills/
   ```

5. **Install the hooks** (SessionStart and PostToolUse; VS Code reads `~/.copilot/hooks/*.json`). If `~/.copilot/hooks/local-memory.json` already exists with different content, ask before replacing it.
   ```sh
   mkdir -p ~/.copilot/hooks
   cp hooks/local-memory.json ~/.copilot/hooks/local-memory.json
   ```

6. **Smoke test** against the real database. Run these from inside a git repository, then check that each prints JSON without an `"error"` key:
   ```sh
   M="python3 $HOME/.local_memory_sqlite/mem.py"
   ID=$($M add --title "install smoke test" --content "temporary" --scope global --load always --expires 1d | python3 -c "import json,sys; print(json.load(sys.stdin)['memory']['id'])")
   $M search smoke
   echo "{\"cwd\": \"$PWD\"}" | $M context     # additionalContext must contain "install smoke test"
   $M delete "$ID"
   ```

7. **Tell the user:**
   - The SessionStart hook runs at the start of each new agent session; the PostToolUse hook adds a repository's memories the first time the agent touches a file in it. They need the VS Code setting `chat.useHooks`, which is on by default. If memories don't show up, check that setting and run step 6's `context` command by hand.
   - Skills need `chat.useAgentSkills`, which is on by default. Type `/skills` in chat to confirm the six `alx-*` skills are listed.
   - The database is `~/.local_memory_sqlite/memory.db`. To back it up, copy the file while VS Code is closed.

## Uninstall

Follow [uninstall.md](uninstall.md).
