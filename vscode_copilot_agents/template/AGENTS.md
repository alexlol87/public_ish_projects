# Project instructions

<!-- Loaded into every agent request. Keep it short: only what the agent can't infer from the code.
     Replace every line below with your project's facts, and delete what doesn't apply. -->

## Commands

- Install: `npm ci`
- Test one package: `npm test -- <package>`
- Lint and typecheck: `npm run lint && npm run typecheck`

## Architecture

- HTTP handlers live in `src/api/routes`; database access only in `src/repositories`, so handlers stay testable.

## Rules

- Add or update a test for every behavior change, and run it before saying the work is done.
- Use `date-fns`, not `moment` (moment is deprecated and bloats the bundle).
- Don't edit generated files under `src/generated/`; change the schema and run `npm run codegen`.
