# Constellation

Native macOS app (Swift, Apple frameworks only) for a Vault of linked markdown Notes about Projects, Repos and
Endpoints. Start with `PLAN.md`. This folder is public: no personal data in code, docs, fixtures or samples.

## Agent skills

### Issue tracker

Local markdown files under `.scratch/<feature>/` (git-ignored). See `docs/agents/issue-tracker.md`.

`.scratch/` is git-ignored and exists only in the main checkout: never run `git clean -x`, and read it from the main
checkout when working in a worktree.

### Triage labels

The five default labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), written as a
`Status:` line in each issue. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` in this folder. See `docs/agents/domain.md`.
