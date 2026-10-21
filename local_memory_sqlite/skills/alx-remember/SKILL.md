---
name: alx-remember
description: Store something in local memory because the user asked you to remember it ("remember that…", "from now on…", "don't forget…"). Updates an existing memory instead of adding a duplicate.
---

# Remember

The CLI is `python3 ~/.local_memory_sqlite/mem.py`; every command prints JSON. Always pass the repository key with `--repo <key>`, because the terminal's folder may not match the session's. Find it in the "Local memory" context:
- A session in one repository names its key at the top (for example `landing_zone/repo_name`, `local/<folder>` or `local/chat`).
- A workspace with several repositories lists them as `folder: key`. When you read or edit a file in a repository, a "you are now working in repository key …" note names that key too.
- When the user names a repository ("for the scripts repo"), use that repository's key, not the one of the folder you happen to be in. If it is not listed, pass `--path <its folder>` instead of `--repo`. If you can't tell which repository the user means, ask. Never store it as global just because the repository is not the session's.

1. Search first, with two or three distinctive words from what the user said:
   `mem.py search <words> --repo <key>`
2. If a memory already covers it, update that memory: `mem.py update <id> --content - ...` (put the full new content on stdin, merged with the old content). Otherwise add a new one:

   ```sh
   python3 ~/.local_memory_sqlite/mem.py add --title "<one line>" --scope <global|repo> --repo <key> \
     --load <always|on_demand> --expires <never|30d|6m|1y|YYYY-MM-DD> --content - <<'EOF'
   <the memory, self-contained, written so a future session understands it without this conversation>
   EOF
   ```
   For `--scope global`, leave out `--repo`.

Choose each field:
- **scope**: `global` if it applies wherever the user works (personal preferences, how they like answers). `repo` if it is about one repository's code, tools or conventions, or if the user names a repository. If unsure, ask.
- **load**: `always` for rules that change how you work in every session (keep these few and short). `on_demand` for reference facts needed only for some tasks; the title must contain the words you would search for later.
- **expires**: `never` for lasting preferences and conventions. A short time for facts about current state ("the staging server is down": `7d`; "we are migrating to X": `3m`). If the user gives a date or duration, use it.

3. Tell the user in one line what you stored or updated: id, title, scope, load mode and expiry.
