---
name: alx-reflect
description: Learn from this session and the prompts and tool failures the hooks logged, by turning repeated corrections, error fixes and workflows into instincts with confidence scores, and suggesting which stable ones belong in AGENTS.md or a skill. Use when the user says "reflect", "/alx-reflect", "learn from this", or at the end of a long session.
---

# Reflect

Instincts are small learned habits: one trigger, one action, a confidence between 0.2 and 0.9, scoped to this repository
or global. Those at 70% or more are loaded into every new session; unused ones lose 10% every 30 days. This skill is
the learning step: nothing runs in the background, so it costs nothing until the user runs it.

Run every command from the repository you're working in, exactly as written.

## 1. Gather evidence

```bash
__CMD__ observations
__CMD__ instincts
```

`observations` lists the prompts and tool failures logged since the last reflection; prompts that look like a
correction are marked `[correction?]`. `turn ended` lines name a transcript file you may read when a prompt needs its
context. Also use the current conversation.

## 2. Find patterns

Look for, in this order:

1. **Corrections**: the user rejected or redid something ("no, use X", "don't…", "I said…"). Instinct: when doing that,
   do X.
2. **Error fixes**: a tool failed and a later step fixed it the same way more than once. Instinct: when error E, do F.
3. **Repeated workflows**: the same sequence of steps for the same kind of task. Instinct: when asked for T, do the
   steps.
4. **Preferences**: tools, libraries, formats or wording the user keeps choosing.

Ignore one-offs that won't recur, anything only true for one task, and anything containing secrets.

## 3. Record them

For each pattern, reuse an existing instinct id when one covers it, otherwise make a short kebab-case id.

```bash
# new (starts at 50%) or seen again (+10%, max 90%); stdin: first line is the trigger, the rest the action
__CMD__ instinct use-repository-pattern --repo --evidence 'user moved a query out of a route twice' --stdin <<'EOF'
when adding a data access function
Add it to the repository class in src/data/, never query from route handlers
EOF
# the user contradicted an instinct (-20%, deleted below 20%)
__CMD__ weaken prefer-classes --repo --evidence 'user asked for functions instead'
```

Always send the trigger and action on stdin with the quoted `<<'EOF'` heredoc, never as arguments, so user words are
never run by the shell. Keep `--evidence` a short paraphrase without quote marks.

Scope: `--repo` for language, framework, structure and style conventions of this codebase; `--user` for habits that hold
everywhere (security, git, how the user likes answers). Record a pattern at most once per reflection, even if it
appeared several times; confidence should grow across sessions, not inside one.

## 4. Promote and graduate

- `instincts` ends with ids that are ready to promote (in 2+ repositories, average 80%+). Promote each with
  `__CMD__ promote <id>` from one of those repositories, then weaken or ignore the copies in the others.
- Instincts at 80% or more about this repository are reviewed knowledge waiting to be shared. Suggest adding them to the
  repository's `AGENTS.md` or an instructions file, or a skill when several form a procedure. Don't edit those files
  unless the user agrees.
- Plain facts you learned (not habits) go through the alx-remember skill.

## 5. Finish

```bash
__CMD__ mark-reflected
```

Report in a few lines: instincts created, reinforced, weakened or promoted, and what you suggest moving into AGENTS.md.
