import { test } from "node:test";
import assert from "node:assert/strict";
import { withDefaults, parseDays } from "./settings.ts";

test("staleness threshold defaults to 30 days", () => {
  assert.deepEqual(withDefaults(null), { stalenessDays: 30 });
  assert.deepEqual(withDefaults({}), { stalenessDays: 30 });
});

test("a saved threshold is kept", () => {
  assert.deepEqual(withDefaults({ stalenessDays: 7 }), { stalenessDays: 7 });
});

test("days input accepts a whole number of days >= 1, rejects anything else", () => {
  assert.equal(parseDays("14"), 14);
  assert.equal(parseDays(" 1 "), 1);
  for (const bad of ["", "abc", "-3", "2.5", "1e3", "0", " 0 "]) assert.equal(parseDays(bad), null, bad);
});
