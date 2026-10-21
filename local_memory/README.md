# Local Memory for GitHub Copilot

Memory and learned habits ("instincts") for GitHub Copilot in VS Code, for when your organization has turned off
Copilot Memory and VS Code's memory tool. Everything is plain files on your machine, managed by one Python script with no
dependencies, two skills and four hooks.

The design follows the memory and continuous-learning parts of
[ECC](https://github.com/affaan-m/ECC) (`skills/continuous-learning-v2`), adapted to Copilot's hooks and without ECC's
background model, so it costs no AI credits until you ask it to learn.

## What it does

| Piece | What happens | When |
|-------|--------------|------|
| **User memory** | Your preferences, loaded into every session through a personal instructions file. | Always (no hooks needed) |
| **Repository memory** | Facts about one repository (commands, conventions, gotchas), added at the start of each session in that repository. | Session start hook |
| **Instincts** | Small learned habits ("when installing packages: use pnpm") with a confidence from 20% to 90%. Those at 70% or more are loaded like memory; unused ones lose 10% every 30 days. | Session start hook, instructions file |
| **Observation log** | Your prompts (marked when they look like a correction), failed tool calls and transcript paths, with secrets redacted. Only `/alx-reflect` reads it. | Prompt, tool-failure and stop hooks |
| **`alx-remember` skill** | The agent saves or forgets a fact when you say "remember…", "from now on…", "forget…", or correct it. | When relevant, or `/alx-remember` |
| **`alx-reflect` skill** | The agent reviews the log and the session, creates or reinforces instincts, weakens contradicted ones, promotes habits seen in 2+ repositories to global, and suggests which ones belong in `AGENTS.md`. | When you type `/alx-reflect` (after 20 logged prompts and failures, the agent reminds you) |

```
~/.copilot/
├── local-memory/                      created by the installer (usually 0755); the data inside is private
│   ├── mem.py                         the tool
│   ├── user.md                        your memory (one fact per line; you can edit it)
│   ├── instincts/*.md                 global instincts
│   ├── no-repo/                       logs of hooks run outside a git repository (same files as a repository)
│   ├── hook-errors.log                errors from the hooks; hook-errors.1.log is the previous copy
│   ├── .pruned_at                     date of the last daily prune of expired instincts
│   ├── .lock                          lock file that serialises writes from hooks and commands
│   └── repos/<name>-<hash>/
│       ├── repo.json                  the repository's id and source (remote URL or path)
│       ├── memory.md                  repository memory
│       ├── instincts/*.md             repository instincts
│       ├── observations.jsonl         the log /alx-reflect reads
│       ├── observations.1.jsonl ...   older parts of the log (.1 to .3), each rotated at 1 MB
│       ├── observations.count         unreviewed prompts and tool failures, so session start does not parse the log
│       └── reflected_at               when mark-reflected last ran
├── instructions/local-memory.instructions.md   generated from user.md and global instincts
├── hooks/local-memory.json
└── skills/alx-remember/, skills/alx-reflect/
```

A repository is identified by its `origin` remote, so every clone and worktree of it shares one memory. A repository
without a remote is identified by its path. A folder that is not itself a repository but directly contains some (a
multi-repository workspace opened at its parent folder) gets one shared memory, identified by its path.

## Install

Requires Python 3.9+ and the **Copilot** session target in VS Code (the Copilot harness, which also covers Copilot CLI).
On macOS and Linux that is `python3` (on macOS run `xcode-select --install` if it's missing); on Windows it is `py` or `python`.

```bash
git clone https://github.com/alexlol87/public_ish_projects
cd public_ish_projects/local_memory
./install.sh
```

On Windows, from the same folder, run the installer directly (`install.sh` needs bash):

```powershell
py install.py
```

The installer runs under the Python that starts it and writes that interpreter's full path, and the path to `mem.py`, into
the hooks and skills, quoted for the shell that runs them. Paths with spaces, apostrophes or `#` are fine. It honors
`COPILOT_HOME` (default `~/.copilot` or `%USERPROFILE%\.copilot`). If you move Python or this folder, run the installer again.

Then start a new chat and open **Chat: Open Customizations**: `alx-remember` and `alx-reflect` should be under skills,
`local-memory.instructions.md` under instructions and `local-memory.json` under hooks.

- `./install.sh` (or `py install.py`) again updates the tool, skills and hooks; your saved memory is never overwritten.
- `--no-hooks` installs without hooks. User memory still loads through the instructions file, and the
  agent runs `mem.py recall` to read repository memory.
- `./install.sh --uninstall` (or `py install.py --uninstall`) removes the tool, the skills, the hooks and the instructions
  file. It never deletes saved memory: the rest of `~/.copilot/local-memory/` (memory, instincts, repositories, logs)
  stays, and a reinstall picks it up. To delete that too, run `clear --all --yes` first (see Status, cleanup and backup).

### Pause and resume

Type `/alx-disable-memory` to switch Local Memory off for a while: the hooks and the instructions file move to
`~/.copilot/local-memory/paused/`, and `alx-remember` and `alx-reflect` get `disable-model-invocation: true`, so nothing
loads and the agent never calls them. Saved memory stays. `/alx-enable-memory` moves everything back and sets the flag
to `false`. Both take effect in a new session. Running the installer also switches memory back on.

### Fewer approval prompts

The skills run `mem.py` in the terminal, which asks for approval each time. To allow the common calls without asking, add
this rule to `chat.tools.terminal.autoApprove` in your user settings. Its limits:

- **Interpreter and path:** an absolute interpreter path with no spaces or quotes (such as `/usr/bin/python3` or
  `/opt/homebrew/bin/python3`), and `mem.py` at `/Users/<name>/.copilot/local-memory/mem.py` or
  `/home/<name>/.copilot/local-memory/mem.py`.
- **Commands:** `recall`, `instincts`, `observations`, `remember`, `forget`, `instinct`, `weaken`, `promote` and
  `mark-reflected`. The others (`sync`, `status`, `clear`, `export`, `import`, `forget-instinct`, `where`) still ask.
- **Arguments:** flags, lowercase ids, single-quoted text, or text on stdin through a quoted heredoc (`<<'EOF'`), which
  is the form the skills use for user text. Double-quoted text, other arguments such as `--cwd`, and chained commands
  (`&&`, `;`, pipes) still ask.
- **Not covered:** a custom `COPILOT_HOME`, Windows paths, and any path with a space or apostrophe. These still ask. To
  approve them, write your own rule for your exact paths, following the same pattern.

The rule:

```jsonc
"chat.tools.terminal.autoApprove": {
  "/^(?:/[\\w.+-]+)+ /(?:Users|home)/[\\w-][\\w.-]*/\\.copilot/local-memory/mem\\.py (?:recall|instincts|observations|remember|forget|instinct|weaken|promote|mark-reflected)(?: '[^']*'| --?[a-z-]+| [a-z0-9-]+)*(?: <<'EOF'\\n(?:(?!EOF(?:\\n|$))[^\\n]*\\n)*EOF)?$/": true
}
```

## Use

You mostly don't need to do anything:

- Say "remember that…" or "from now on…" and the agent saves it; say "forget…" to remove it.
- Correct the agent as usual. Every few sessions, or at the end of a long one, type `/alx-reflect`.
- Look at what it knows: ask "what do you remember?", or run `python3 ~/.copilot/local-memory/mem.py recall` and
  `… instincts` yourself.
- Edit `~/.copilot/local-memory/user.md` or a repository's `memory.md` by hand whenever you like. Changes to `user.md`
  reach the instructions file at the next session start (or run `mem.py sync`).

When an instinct or fact has proved itself, move it into the repository's `AGENTS.md` (reflect suggests which), so it is
reviewed and shared with your team instead of living only on your machine.

Settings, as environment variables for VS Code: `LOCAL_MEMORY_MIN_CONFIDENCE` (default `0.7`: instincts at or above it
are loaded) and `LOCAL_MEMORY_MAX_INSTINCTS` (default `10` per scope: how many are loaded).

Limits:

- A fact is one line of at most 300 characters; `remember` and `import` reject longer ones.
- The facts loaded into a session are the newest that fit in 200 lines and about 4,000 characters per scope. Older ones
  are left out, and the context says how many (`mem.py recall` shows all). Loaded instinct triggers and actions are
  clipped to 300 characters.
- An instinct starts at 50%, rises 10 points each time it is seen again (capped at 90%), and falls 20 points when
  weakened. Unused instincts fade continuously, 0.1 for every 30 days since they were last seen, worked out when read.
  Below 20% an instinct is deleted.
- Session start deletes such instincts at most once a day. `sync` and other writes to user memory do it every time.
- Each scope holds at most 100 instincts. Creating one more drops the one with the lowest current confidence.

### Changing the limits

Every number above lives in an optional `~/.copilot/local-memory/config.json`. List only what you want to change; the
rest keeps its default. Reading it adds well under a millisecond to a hook. `mem.py where` prints its path.

```json
{"max_memory_lines": 300, "max_memory_chars": 6000, "max_fact_chars": 500, "active_max_instincts": 15}
```

| Setting | Default | Meaning |
|---|---|---|
| `max_memory_lines`, `max_memory_chars` | 200, 4000 | facts loaded into a session, per scope |
| `max_fact_chars` | 300 | longest fact, and the clip for loaded instinct text |
| `min_forget_chars` | 4 | shortest text `forget` accepts |
| `active_min_confidence`, `active_max_instincts` | 0.7, 10 | instincts loaded into a session: threshold and count per scope |
| `start_confidence`, `step_up`, `step_down`, `max_confidence` | 0.5, 0.1, 0.2, 0.9 | how confidence moves |
| `decay_per_30_days`, `min_confidence` | 0.1, 0.2 | fading, and the level below which an instinct is deleted |
| `max_instincts_per_scope`, `max_evidence` | 100, 5 | instincts kept per scope, evidence lines kept per instinct |
| `max_prompt_chars` | 1000 | longest prompt logged |
| `max_observation_bytes`, `keep_rotated` | 1000000, 3 | log size that triggers rotation, rotated copies kept |
| `max_hook_log_bytes` | 100000 | size at which `hook-errors.log` rotates |
| `git_timeout_seconds` | 2 | wait for each `git` call |

Counts must be whole numbers of at least 1 (`active_max_instincts` may be 0); confidences and steps are between 0 and 1.
The two environment variables above still win over the file. A missing or unreadable file, an unknown name or a bad value
never stops a hook: the default is used, and `mem.py status` lists what was ignored. `clear --all` keeps the file.

## Differences from ECC

| ECC | Here | Why |
|-----|------|-----|
| A background Haiku agent analyses every ~5 minutes | `/alx-reflect` runs on your normal model when you ask | A background model on Copilot spends AI credits every session |
| Logs every tool call before and after | Logs prompts, failed tool calls and transcript paths | Corrections and error fixes are where the habits are; less to redact and store |
| Instincts injected by a session start hook only | User memory and global instincts also go into a personal instructions file | Still works if your organization blocks hooks |
| `/evolve` into skills, agents and commands | Promote to global, and suggestions to move into `AGENTS.md` or a skill | Keeps it small; the reviewed home for stable knowledge is the repository |

## Status, cleanup and backup

```bash
python3 ~/.copilot/local-memory/mem.py status                        # counts, log sizes, estimated tokens, last hook errors
python3 ~/.copilot/local-memory/mem.py forget --dry-run 'pnpm'       # print the lines that would go; change nothing
python3 ~/.copilot/local-memory/mem.py forget-instinct ID            # delete one instinct outright (add --user for a global one)
python3 ~/.copilot/local-memory/mem.py export backup.json            # user memory, global instincts and every repository
python3 ~/.copilot/local-memory/mem.py import backup.json            # merge a backup back in (duplicates are skipped)
```

`forget` removes every line that contains the text (case-insensitive, at least 4 characters; the scope defaults to
`--repo`). If several lines match, it refuses and lists them: repeat with a longer text, or pass `--all`.
`remember --stdin` reads the text from standard input instead of the arguments, which is how the skills pass text with quotes:
`mem.py remember --user --stdin <<'EOF'`, then the text, then `EOF`.

`export` writes one JSON file with user memory, global instincts, and each repository's memory and instincts. For a
repository without a remote it records the folder path. `import` checks the whole file before writing anything, keeps
existing facts, skips duplicate facts and instincts whose id already exists, and redacts secrets again.

To delete data, pick the narrowest flag and always add `--yes`; without it `clear` refuses to run:

| Command | Deletes |
|---------|---------|
| `clear --obs --yes` | the observation log of the current repository, its rotated parts and its unreviewed count |
| `clear --instincts --yes` | the instincts of the current repository |
| `clear --repo --yes` | all memory and instincts of the current repository |
| `clear --all --yes` | all saved data under `~/.copilot/local-memory/`: user memory, global instincts, all repositories, `no-repo` and every log. `mem.py`, `.lock` and `.pruned_at` are kept, and the instructions file is regenerated with empty user memory, so the hooks keep working |

The first three need a git repository (or `LOCAL_MEMORY_REPO` set); `--all` works anywhere. Export first if you might want
the data back. `./install.sh --uninstall` does not touch saved data.

`hook-errors.log` is renamed to `hook-errors.1.log` once it passes 100,000 bytes, replacing the previous copy. The
observation log is rotated the same way once it passes 1,000,000 bytes: `observations.jsonl` becomes `.1`, the older parts
move up one, and the oldest of the three is dropped.

## Privacy and safety

- Nothing leaves your machine except what Copilot reads as context: user memory, this repository's memory and the active
  instincts, which are sent with your requests like any instructions file.
- `mem.py` redacts common secret formats (GitHub, OpenAI and AWS keys, Slack tokens, JWTs, bearer tokens, private keys,
  `password=`/`token=` values) before writing anything.
- The observation log keeps the first 1,000 characters of each prompt, the first 500 characters of a failed tool's error,
  the first 300 of its arguments (for terminal tools, only the first word of the command) and the transcript path at the
  end of each turn. A prompt that looks like a correction is marked.
- Memory is loaded as instructions, so treat `user.md` like your personal instructions file: only the agent (through the
  skills) and you write to it.
- Files that `mem.py` writes (memory, instincts, logs, counters, exports, the instructions file) are readable only by you
  (mode `0600`), and the folders it creates are `0700`. Two exceptions use your umask instead, usually `0644`:
  `hook-errors.log` and `.lock`. The installer creates `local-memory/` the same way (usually `0755`), so others can see
  its file names but not read the data.
- `LOCAL_MEMORY_LOG=off` (an environment variable) stops the prompt, tool-failure and turn-end hooks from logging. They
  write nothing and create no `repos/` folder or `repo.json`. Session start still loads memory and instincts, and
  `remember`, `instinct` and the other commands still work. Existing logs are kept; `clear --obs --yes` or
  `clear --all --yes` removes them.
- Hooks never block or fail a session: any error goes to `~/.copilot/local-memory/hook-errors.log`.

## Tests

```bash
python3 -m unittest discover -s tests
```

`.github/workflows/local-memory.yml` runs them on Linux and macOS with Python 3.9 and 3.13. They cover the hook payloads
in both the Copilot CLI (camelCase) and VS Code compatible (snake_case) shapes from the
[GitHub Copilot hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference), and the installer.
They don't drive a real VS Code session.
