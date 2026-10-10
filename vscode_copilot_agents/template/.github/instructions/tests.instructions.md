---
name: 'Tests'
description: 'Use when writing or changing tests.'
applyTo: '**/*.{test,spec}.{ts,tsx,js,jsx}'
---
# Tests

- Reuse the fixtures in `test/fixtures/` instead of writing new setup helpers.
- Name tests after the behavior: `returns 404 when the user does not exist`.
- One behavior per test. No snapshot tests for logic.
