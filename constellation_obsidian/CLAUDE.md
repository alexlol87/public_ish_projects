# Constellation for Obsidian

An Obsidian plugin that adds Constellation's domain features (Calls/Uses panel, staleness, Archive, agent files) to an
Obsidian vault. Start with `PLAN.md`. This folder is public: no personal data in code, docs or samples.

## Domain docs

Shared with the standalone app: `../constellation/GLOSSARY.md`, the Vault format in `../constellation/PLAN.md` §4 and
`../constellation/docs/adr/`. This folder's own decisions are in `docs/adr/`. Do not change the Vault format here.

## Issue tracker

Local markdown under `.scratch/<feature>/` (git-ignored), same conventions as `../constellation/docs/agents/issue-tracker.md`.

## Build

`npm run build` writes `plugin/constellation/`, which is committed. Rebuild before every push; git must show no
change in that folder afterwards. `npm test` runs `node --test`.
