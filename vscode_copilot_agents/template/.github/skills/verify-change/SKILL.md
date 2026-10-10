---
name: verify-change
description: Verify a code change before calling it done. Use after editing code, before committing, or when asked to check that something works.
---
# Verify a change

1. List what changed: `git status --short` and `git diff --stat`.
2. Run the checks for the changed area only, using the commands in AGENTS.md:
   tests for the touched package, then lint and typecheck.
3. If a check fails, read the first error, fix the cause, and rerun that check. Don't skip or disable a test.
4. Re-read the diff once as a reviewer would: leftover debug code, unused imports, TODOs, unrelated edits.
5. Report what you ran and the result of each command. If you couldn't run something, say so and why.
