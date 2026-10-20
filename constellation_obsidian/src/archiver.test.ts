import { test } from "node:test";
import assert from "node:assert/strict";
import { archiveTicked, appendToArchive } from "./archiver.ts";

const day = new Date(2026, 9, 17);
const BUGS =
  "# Bugs\n- [x] Order total ignores discounts → [[endpoints#POST /orders]]\n  Discounts are applied after tax.\n- [ ] Other\n";

test("a ticked bug moves to a new fixed-bugs archive note", () => {
  const r = archiveTicked("shop/orders-service/bugs.md", BUGS, day, (t) => `shop/orders-service/${t}`);
  assert.ok(r);
  assert.equal(r.text, "# Bugs\n- [ ] Other\n");
  assert.equal(r.count, 1);
  assert.equal(r.archivePath, "shop/archive/fixed-bugs.md");
  assert.equal(
    appendToArchive(null, r),
    "---\ntype: archive\n---\n# Fixed bugs\n\n### Order total ignores discounts\n- closed: 2026-10-17\n- source: [[shop/orders-service/endpoints#POST /orders]]\n- what: Discounts are applied after tax.\n- fix: unknown\n",
  );
});

test("a todo without a link goes to done-todos with the Repo README as source, appended to the existing note", () => {
  const r = archiveTicked("shop/orders-service/todo.md", "- [X] Split the handler\n", day);
  assert.ok(r);
  assert.equal(r.text, "");
  assert.equal(r.archivePath, "shop/archive/done-todos.md");
  assert.equal(
    appendToArchive("# Done todos\n", r),
    "# Done todos\n\n### Split the handler\n- closed: 2026-10-17\n- source: [[shop/orders-service/README]]\n- what: Split the handler\n- fix: unknown\n",
  );
  assert.equal(appendToArchive("# Done todos", r).split("\n### ")[0], "# Done todos\n");
  assert.ok(appendToArchive("", r).startsWith("### Split"));
});

test("every ticked item moves with its continuation lines; unticked items stay exactly", () => {
  const text = "# Todo\n\n- [ ] keep 1\n  keep detail\n- [x] Done A\n  line one\n    - [ ] nested open child\n\n- [ ] keep 2\n* [x] Done B → [[orders#GET /x|alias]]\n";
  const r = archiveTicked("shop/r/todo.md", text, day);
  assert.ok(r);
  assert.equal(r.count, 2);
  assert.equal(r.text, "# Todo\n\n- [ ] keep 1\n  keep detail\n\n- [ ] keep 2\n");
  assert.equal(
    r.entries,
    "### Done A\n- closed: 2026-10-17\n- source: [[shop/r/README]]\n- what: line one - [ ] nested open child\n- fix: unknown\n" +
      "\n### Done B\n- closed: 2026-10-17\n- source: [[orders#GET /x]]\n- what: Done B\n- fix: unknown\n",
  );
});

test("nothing ticked, or not a Repo's bugs.md / todo.md, gives no edit", () => {
  assert.equal(archiveTicked("shop/r/bugs.md", "- [ ] open\n", day), null);
  assert.equal(archiveTicked("shop/r/notes.md", "- [x] done\n", day), null);
  assert.equal(archiveTicked("bugs.md", "- [x] done\n", day), null);
  assert.equal(archiveTicked("shop/bugs.md", "- [x] done\n", day), null);
  assert.equal(archiveTicked("shop/r/bugs.md", "plain [x] text\n", day), null);
});

test("accented and emoji text, and CRLF notes", () => {
  const text = "# Bugs ééé 😀\r\n- [x] Crash on 😀 input → [[endpoints#POST /orders]]\r\n  Détail ünï.\r\n- [ ] Other\r\n";
  const r = archiveTicked("shop/orders-service/bugs.md", text, day);
  assert.ok(r);
  assert.equal(r.text, "# Bugs ééé 😀\r\n- [ ] Other\r\n");
  assert.ok(r.entries.startsWith("### Crash on 😀 input\n"));
  assert.ok(r.entries.includes("- what: Détail ünï.\n"));
  assert.ok(r.entries.includes("- source: [[endpoints#POST /orders]]\n"));
});
