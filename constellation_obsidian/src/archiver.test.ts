import { test } from "node:test";
import assert from "node:assert/strict";
import { archiveTicked, appendToArchive, clampPos, mapCursor } from "./archiver.ts";
import { AGENTS_MD } from "./scaffold.ts";

const day = new Date("2026-10-17T12:00:00Z");
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
  assert.equal(r.text, "# Todo\n\n- [ ] keep 1\n  keep detail\n    - [ ] nested open child\n\n- [ ] keep 2\n");
  assert.equal(
    r.entries,
    "### Done A\n- closed: 2026-10-17\n- source: [[shop/r/README]]\n- what: line one\n- fix: unknown\n" +
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

test("closed is the UTC date, like staleness and the standalone app", () => {
  const late = new Date("2026-10-17T23:30:00Z"); // already the 18th east of UTC
  const early = new Date("2026-10-17T00:30:00Z"); // still the 16th west of UTC
  for (const on of [late, early]) assert.ok(archiveTicked("shop/r/todo.md", "- [x] A\n", on)!.entries.includes("- closed: 2026-10-17\n"));
});

test("a Link inside inline code is not the source", () => {
  const r = archiveTicked("shop/r/bugs.md", "- [x] Docs show `[[nope]]` wrongly → [[endpoints#GET /a]]\n", day);
  assert.ok(r!.entries.includes("- source: [[endpoints#GET /a]]\n"));
  const none = archiveTicked("shop/r/bugs.md", "- [x] Docs show `[[nope]]`\n", day);
  assert.ok(none!.entries.includes("- source: [[shop/r/README]]\n"));
});

test("the archive entry example in AGENTS.md round-trips through the archiver", () => {
  const r = archiveTicked("shop/orders/bugs.md", "# Bugs\n- [x] Total ignores discounts → [[endpoints#POST /orders]]\n  Discounts are applied after tax.\n", day, (t) => `shop/orders/${t}`);
  const example = AGENTS_MD.split("```markdown\n").find((s) => s.startsWith("### Total"))!.split("```")[0];
  const norm = (t: string) => t.split("\n").filter((l) => l && !l.startsWith("- fix:")).map((l) => (l.startsWith("- closed:") ? "- closed: DATE" : l));
  assert.deepEqual(norm(example), norm(r!.entries));
  assert.ok(example.includes("- fix: "));
});

const at = (name: string) => `shop/orders-service/${name}`;

test("03: an unticked child task stays in the Note with its detail lines; a ticked child moves", () => {
  const r = archiveTicked(at("bugs.md"), "- [x] Parent ticked\n  - [ ] open child task\n    child detail\n  continuation\n  - [x] ticked child\n- [ ] last open\n", day)!;
  assert.equal(r.text, "  - [ ] open child task\n    child detail\n- [ ] last open\n");
  assert.ok(r.entries.includes("- what: continuation - [x] ticked child\n"));
});

test("04: ticked boxes inside fenced code blocks are left alone", () => {
  const t = "Example:\n```md\n- [x] example\n```\n~~~\n- [x] tilde\n~~~\n- [ ] real\n";
  assert.equal(archiveTicked(at("bugs.md"), t, day), null);
  const r = archiveTicked(at("bugs.md"), t + "- [x] real done\n", day)!;
  assert.equal(r.count, 1);
  assert.equal(r.text, t);
});

test("05: only a Repo's bugs.md / todo.md counts; source falls back to the Repo README", () => {
  for (const p of ["external/vendor/bugs.md", "shop/archive/bugs.md", "shop/bugs.md", "clients/x/todo.md"]) assert.equal(archiveTicked(p, "- [x] a\n", day), null, p);
  const r = archiveTicked("shop/orders-service/docs/bugs.md", "- [x] a\n", day)!;
  assert.equal(r.archivePath, "shop/archive/fixed-bugs.md");
  assert.ok(r.entries.includes("- source: [[shop/orders-service/README]]\n"));
});

test("06: an item with no text gets a placeholder title", () => {
  const r = archiveTicked(at("bugs.md"), "- [x]\n- [ ] open\n", day)!;
  assert.ok(r.entries.startsWith("### (no text)\n"));
  assert.ok(r.entries.includes("- what: (no text)\n"));
});

test("07: entries appended to a CRLF archive note use CRLF", () => {
  const r = archiveTicked(at("todo.md"), "- [x] A\n  more\n", day)!;
  assert.equal(appendToArchive("# Done todos\r\n", r), "# Done todos\r\n\r\n### A\r\n- closed: 2026-10-17\r\n- source: [[shop/orders-service/README]]\r\n- what: more\r\n- fix: unknown\r\n");
});

test("16: numbered ticked tasks are archived", () => {
  const r = archiveTicked(at("bugs.md"), "1. [x] numbered done\n2) [ ] open\n", day)!;
  assert.equal(r.count, 1);
  assert.equal(r.text, "2) [ ] open\n");
});

test("clampPos keeps a cursor inside shortened text", () => {
  assert.deepEqual(clampPos("a\nb", { line: 6, ch: 5 }), { line: 1, ch: 1 });
  assert.deepEqual(clampPos("abc\nde\n", { line: 0, ch: 2 }), { line: 0, ch: 2 });
  assert.deepEqual(clampPos("", { line: 3, ch: 3 }), { line: 0, ch: 0 });
});

test("19: the cursor follows its text through the removed items", () => {
  const r = archiveTicked(at("bugs.md"), "---\ntype: bugs\n---\n# Bugs\n\n- [ ] A open\n- [x] B fixed\n  more B\n- [ ] C open\n", day)!;
  assert.deepEqual(mapCursor(r.keep, { line: 8, ch: 3 }), { line: 6, ch: 3 }); // C moves up two lines
  assert.deepEqual(mapCursor(r.keep, { line: 5, ch: 4 }), { line: 5, ch: 4 }); // above B: unchanged
  assert.deepEqual(mapCursor(r.keep, { line: 7, ch: 2 }), { line: 6, ch: 0 }); // inside B: where B was
  assert.deepEqual(mapCursor(r.keep, { line: 9, ch: 0 }), { line: 7, ch: 0 }); // the empty last line
});
