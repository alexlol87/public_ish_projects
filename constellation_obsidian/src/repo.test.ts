import { test } from "node:test";
import assert from "node:assert/strict";
import { repoOf, staleness, isStale, label, ingestPrompt, refreshPrompt } from "./repo.ts";

test("a Note two folders down belongs to the Repo project/repo", () => {
  assert.deepEqual(repoOf("shop/orders/README.md"), { folder: "shop/orders", project: "shop", name: "orders" });
  assert.deepEqual(repoOf("shop/orders/sub/deep.md"), { folder: "shop/orders", project: "shop", name: "orders" });
});

test("Notes outside a Repo, archives and app folders have no Repo", () => {
  for (const p of ["README.md", "shop/README.md", "shop/archive/fixed-bugs.md", "external/x/a.md", "clients/x/a.md",
    "archive/x/a.md", "templates/x/a.md", "Templates/x/a.md", ".constellation/x/a.md", ""]) {
    assert.equal(repoOf(p), null, p);
  }
});

test("staleness from verified_on: days, never, malformed", () => {
  const now = "2026-06-30";
  assert.deepEqual(staleness("2026-06-20", now), { kind: "verified", days: 10 });
  assert.deepEqual(staleness("2026-05-01", now), { kind: "verified", days: 60 });
  assert.deepEqual(staleness("2026-06-30", now), { kind: "verified", days: 0 });
  assert.deepEqual(staleness("2026-06-29", now), { kind: "verified", days: 1 });
  assert.deepEqual(staleness("2025-01-01", now), { kind: "verified", days: 545 });
  assert.deepEqual(staleness("2026-07-03", now), { kind: "verified", days: -3 });
  assert.deepEqual(staleness(undefined, now), { kind: "never" });
  assert.deepEqual(staleness("  ", now), { kind: "never" });
  for (const bad of ["last tuesday", "soon", "2026-13-45", "2026-02-30", "2026-6-5"]) {
    assert.deepEqual(staleness(bad, now), { kind: "malformed" }, bad);
  }
  assert.deepEqual(staleness('"2026-06-20"', now), { kind: "verified", days: 10 });
  assert.deepEqual(staleness("'2026-06-20'", now), { kind: "verified", days: 10 });
});

test("stale past the threshold, never verified, unreadable or in the future", () => {
  assert.equal(isStale({ kind: "verified", days: 30 }, 30), false);
  assert.equal(isStale({ kind: "verified", days: 0 }, 30), false);
  assert.equal(isStale({ kind: "verified", days: 31 }, 30), true);
  assert.equal(isStale({ kind: "verified", days: -3 }, 30), true);
  assert.equal(isStale({ kind: "never" }, 30), true);
  assert.equal(isStale({ kind: "malformed" }, 30), true);
});

test("labels match the standalone app", () => {
  assert.equal(label({ kind: "verified", days: 10 }), "verified 10 days ago");
  assert.equal(label({ kind: "verified", days: 1 }), "verified 1 day ago");
  assert.equal(label({ kind: "verified", days: 0 }), "verified today");
  assert.equal(label({ kind: "verified", days: -3 }), "date is in the future");
  assert.equal(label({ kind: "never" }), "never verified");
  assert.equal(label({ kind: "malformed" }), "verified date unreadable");
});

test("copy prompts match the standalone app", () => {
  assert.equal(ingestPrompt("orders"), 'Follow AGENTS.md in this Vault and run the Ingest workflow for the repository "orders".');
  assert.equal(refreshPrompt("orders"), 'Follow AGENTS.md in this Vault and run the Refresh workflow for the repository "orders".');
});
