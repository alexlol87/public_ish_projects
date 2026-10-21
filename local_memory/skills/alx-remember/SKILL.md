---
name: alx-remember
description: Save, change or forget a lasting fact or preference in the user's local memory. Use when the user says "remember", "from now on", "always", "never", "forget", or corrects you in a way that will matter in future sessions, and when you learn a non-obvious fact about the repository (a build quirk, a convention) that the next session would otherwise rediscover.
---

# Remember

Local memory replaces Copilot Memory. It is plain files on this machine, read back at the start of every session.
Run every command below from the repository you're working in, exactly as written (same interpreter and path), so the
user's terminal allow-list can match it.

## 1. Check what is already there

```bash
__CMD__ recall
```

If a line already says it, stop. If a line says something that is now wrong, forget it (step 3) before saving the new
version.

## 2. Save it

Pick the scope:

| Scope | Flag | For |
|-------|------|-----|
| Repository | `--repo` (default) | Facts about this codebase: commands, conventions, architecture decisions, gotchas |
| User | `--user` | The user's own preferences that apply in every repository: style, tone, tools, workflow |

```bash
__CMD__ remember --repo --stdin <<'EOF'
Run tests with make test, not npm test: the Makefile sets up the database
EOF
__CMD__ remember --user --stdin <<'EOF'
Prefers a one-line summary before code
EOF
```

Always pass the text on stdin through a heredoc with the quoted delimiter `<<'EOF'`, as above. The quotes make the shell
leave `$`, backticks, quotes and newlines in the text alone, so user words are never run as commands. Never write the
text as a plain argument. Write one fact per call, as a short sentence that still makes sense months later without this
conversation, with the reason when there is one. The text must not contain a line that is only `EOF`. Don't save:

- secrets, tokens, passwords or anything from `.env` files (mem.py redacts common formats, but don't rely on it);
- what the repository already says (README, AGENTS.md, instructions files);
- things only true for the current task (keep those in the conversation).

## 3. Forget or change it

```bash
__CMD__ forget --repo 'make test'
```

The text matches any part of a line. If several lines match, mem.py lists them; repeat with a longer text, or add
`--all` when the user wants them all gone.

## 4. Corrections are also habits

When the user corrected how you work (not just a fact), also record or reinforce an instinct so its confidence grows each
time it happens:

```bash
__CMD__ instinct prefer-pnpm --repo --evidence 'user corrected npm install' --stdin <<'EOF'
when installing packages
Use pnpm, not npm
EOF
```

On stdin, the first line is the trigger and the rest is the action. Keep `--evidence` a short paraphrase without quote
marks, and never copy the user's words into it verbatim.

Use the same id again to reinforce it. The alx-reflect skill explains instincts in full.

Tell the user in one line what you saved or removed, and in which scope.
