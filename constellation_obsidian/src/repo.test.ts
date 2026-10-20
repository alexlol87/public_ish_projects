import { test } from "node:test";
import assert from "node:assert/strict";
import { repoOf, staleness, isStale, label, prompt, frontmatterValue } from "./repo.ts";

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
  assert.equal(prompt("ingest", "orders"), 'Follow AGENTS.md in this Vault and run the Ingest workflow for the repository "orders".');
  assert.equal(prompt("refresh", "orders"), 'Follow AGENTS.md in this Vault and run the Refresh workflow for the repository "orders".');
});

test("frontmatter values are read as raw text, so loose dates stay loose and are rejected", () => {
  const readme = "---\ntype: repo\nverified_on: 2026-6-5\nrepo_url: https://x.test/a:b\n---\n# A\nverified_on: 2026-06-01\n";
  assert.equal(frontmatterValue(readme, "type"), "repo");
  assert.equal(frontmatterValue(readme, "verified_on"), "2026-6-5");
  assert.equal(frontmatterValue(readme, "repo_url"), "https://x.test/a:b");
  assert.deepEqual(staleness(frontmatterValue(readme, "verified_on"), "2026-06-30"), { kind: "malformed" });
  assert.equal(frontmatterValue("---\r\nverified_on: 2026-06-20\r\n---\r\n", "verified_on"), "2026-06-20");
  assert.equal(frontmatterValue("# no frontmatter\nverified_on: 2026-06-20\n", "verified_on"), undefined);
  assert.equal(frontmatterValue("---\nverified_on: 2026-06-20\n", "verified_on"), undefined); // never closed
});
