---
name: reverse-grill-me
description: Quiz the user, one yes/no question at a time, on whether they understand every change in a pull request or diff, and explain each change they didn't know about. Use when the user wants to check they understand a PR or diff before approving or merging it, often one an agent wrote.
disable-model-invocation: true
---

The reverse of grilling: here the user answers questions about changes that already happened. The goal is that by
the end, the user understands everything the diff does, including what an agent changed without telling them.

## 1. Get the diff

Use what the user names:

- a PR number or URL: `gh pr view <pr>` for the title and description, `gh pr diff <pr>` for the changes;
- a branch, commit or range: `git diff <base>...<branch>` and `git log <base>..<branch>`;
- nothing: the current branch against its base (`git diff $(git merge-base HEAD origin/main)`, or the repository's
  default branch), plus uncommitted and untracked files.

Say in one line what you are reviewing (for example "PR #42, 9 files, +310/-85") before the first question.

## 2. Work out what changed

Read the diff, and the surrounding code wherever the diff alone doesn't show what a change does: the callers of a
changed function, the config a new flag reads, the tests that pin the behavior. Finding facts is your job, never the
user's.

Turn the diff into a list of **changes in behavior**, not files. A file can hold several changes; one change can span
several files. Look for:

- **new scenarios**: what can now happen that couldn't before (a new endpoint, input, branch, retry, error path);
- **removed scenarios**: what used to happen and no longer does (a deleted check, a dropped fallback, a narrowed
  type, a removed feature);
- **changed behavior**: same entry point, different result (defaults, ordering, validation, error messages, timeouts);
- **side effects**: things around the code (new dependencies, migrations, config or environment variables,
  permissions, CI, public API or contract changes, data that is now written or no longer written);
- **tests**: tests added, deleted or loosened, and behavior the diff changes that no test covers.

Leave out changes with no behavior in them (formatting, renames that change nothing, comment typos), or fold them
into one question at the end.

Order the list from the most impactful change to the least, and keep the count: you will show "3/11".

## 3. Ask one question at a time

Ask about one change, then stop and wait for the answer. Use this format:

```
❓ **3/11** - **<short title>** (`path/to/file.ts:42`)

Did you know that <the concrete behavior, as it now works>?

Answer yes or no.
```

Make each question about something specific the user could know or not know, in terms of what happens at run time:
"Did you know that a request with an expired token is now retried once, and only fails after the second 401?",
not "Did you know `auth.ts` changed?". Never give the answer away in the question beyond what is needed to ask it,
and never ask the user to look anything up.

- **Yes**: go to the next change. Don't explain it.
- **No**: explain the change (section 4), then go to the next change.
- **Anything else** (a follow-up question, "partly", "why?"): answer it, then continue from the same change.

## 4. Explain a change the user didn't know

Keep it short and concrete:

1. **What changed**: before versus after, with the file and line.
2. **What it impacts**: who or what calls it, which users, data or systems now see a different result.
3. **Scenarios**: the scenarios that are now possible and the ones that are no longer possible, each as one
   concrete case (input → result).
4. **Worth checking**, only if it is true: the change looks unintended, unrelated to the PR's stated goal, untested,
   or risky. Say so plainly; it is a finding, not a verdict.

Illustrate it the way the `show-me` skill does: a before/after `diff` of the call tree or control flow, a Mermaid
sequence diagram, or pseudocode, whichever is the smallest view that makes the point. If the `show-me` skill is
installed, you may call it for this change. One visual per explanation is usually enough.

Then ask the next question in the same message, so the user can keep going.

## 5. Finish

After the last change, write a short summary:

- how many changes the user already knew about, out of the total;
- each change they didn't know about, as one line with its file;
- everything you flagged as worth checking.

Don't change any code. If the user wants something fixed, that is a separate task after the quiz.
