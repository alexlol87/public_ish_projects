import { beforeEach, describe, expect, test } from "vitest";
import { NoteTabs } from "./noteTabs";

let tabs: NoteTabs;
beforeEach(() => (tabs = new NoteTabs()));

describe("noteTabs", () => {
  test("several notes open and focusing", () => {
    tabs.open("a.md", "A"); tabs.open("b.md", "B"); tabs.open("a.md", "ignored");
    expect(tabs.paths).toEqual(["a.md", "b.md"]);
    expect(tabs.active).toBe("a.md");
    expect(tabs.text("b.md")).toBe("B");
    expect(tabs.text("a.md")).toBe("A");
  });

  test("reload replaces an edited buffer with the given text", () => {
    tabs.open("a.md", "A"); tabs.edit("a.md", "mine", 0);
    const rev = tabs.revision("a.md");
    tabs.reload("a.md", "fresh");
    expect(tabs.text("a.md")).toBe("fresh");
    expect(tabs.hasPendingEdits).toBe(false);
    expect(tabs.revision("a.md")).toBe(rev + 1);
    tabs.reload("zzz.md", "x");
    expect(tabs.text("zzz.md")).toBeUndefined();
  });

  test("closing active tab focuses neighbour and returns pending edits", () => {
    tabs.open("a.md", "A"); tabs.open("b.md", "B");
    tabs.edit("b.md", "B2", 0);
    expect(tabs.close("b.md")).toEqual({ closed: true, flush: "B2" });
    expect(tabs.paths).toEqual(["a.md"]);
    expect(tabs.active).toBe("a.md");
    expect(tabs.hasPendingEdits).toBe(false);
    expect(tabs.close("a.md")).toEqual({ closed: true, flush: undefined });
    expect(tabs.active).toBeNull();
    expect(tabs.close("zzz").closed).toBe(false);
  });

  test("autosave only one second after last edit", () => {
    tabs.open("a.md", "A");
    tabs.edit("a.md", "A1", 0);
    tabs.edit("a.md", "A12", 800);
    expect(tabs.due(1500)).toEqual([]); // 0.7 s since last keystroke
    expect(tabs.due(1800)).toEqual(["a.md"]);
    tabs.saved("a.md", "A12");
    expect(tabs.hasPendingEdits).toBe(false);
  });

  test("typing during an in-flight save stays unsaved", () => {
    tabs.open("a.md", "A");
    tabs.edit("a.md", "A1", 0);
    tabs.edit("a.md", "A12", 10);
    tabs.saved("a.md", "A1");
    expect(tabs.hasPendingEdits).toBe(true);
    expect(tabs.pending()).toEqual(["a.md"]);
  });

  test("unchanged text is not an edit", () => {
    tabs.open("a.md", "A");
    tabs.edit("a.md", "A", 0);
    tabs.edit("nope.md", "x", 0);
    expect(tabs.hasPendingEdits).toBe(false);
  });

  test("clean note reloads silently on external change", () => {
    tabs.open("a.md", "one");
    tabs.diskChanged("a.md", "two");
    expect(tabs.text("a.md")).toBe("two");
    expect(tabs.conflict("a.md")).toBeUndefined();
    expect(tabs.revision("a.md")).toBe(1);
  });

  test("own save echo is not a conflict", () => {
    tabs.open("a.md", "one");
    tabs.edit("a.md", "mine", 0);
    tabs.saved("a.md", "mine");
    tabs.edit("a.md", "mine!", 3000); // typed before the watcher event for the save arrives
    tabs.diskChanged("a.md", "mine");
    expect(tabs.conflict("a.md")).toBeUndefined();
    expect(tabs.text("a.md")).toBe("mine!");
    expect(tabs.revision("a.md")).toBe(0);
  });

  test("dirty note raises conflict and reload takes disk", () => {
    tabs.open("a.md", "one");
    tabs.edit("a.md", "mine", 0);
    tabs.diskChanged("a.md", "theirs");
    expect(tabs.text("a.md")).toBe("mine");
    expect(tabs.conflict("a.md")).toBe("theirs");
    expect(tabs.hasConflicts).toBe(true);
    expect(tabs.resolveConflict("a.md", true)).toBeUndefined();
    expect(tabs.text("a.md")).toBe("theirs");
    expect(tabs.conflict("a.md")).toBeUndefined();
    expect(tabs.hasPendingEdits).toBe(false);
    expect(tabs.revision("a.md")).toBe(1);
  });

  test("keep mine returns my text to write over disk", () => {
    tabs.open("a.md", "one");
    tabs.edit("a.md", "mine", 0);
    tabs.diskChanged("a.md", "theirs");
    expect(tabs.resolveConflict("a.md", false)).toBe("mine");
    expect(tabs.conflict("a.md")).toBeUndefined();
    expect(tabs.text("a.md")).toBe("mine");
    tabs.saved("a.md", "mine");
    expect(tabs.hasPendingEdits).toBe(false);
    tabs.diskChanged("a.md", "mine"); // echo of the overwrite
    expect(tabs.conflict("a.md")).toBeUndefined();
  });

  test("changes to files that are not open are ignored", () => {
    tabs.diskChanged("other.md", "x");
    expect(tabs.text("other.md")).toBeUndefined();
  });

  test("autosave and pending never include a conflicted note, and close refuses", () => {
    tabs.open("a.md", "one");
    tabs.edit("a.md", "mine", 0);
    tabs.diskChanged("a.md", "theirs");
    expect(tabs.due(60_000)).toEqual([]);
    expect(tabs.pending()).toEqual([]);
    expect(tabs.close("a.md").closed).toBe(false);
    expect(tabs.paths).toEqual(["a.md"]);
    expect(tabs.text("a.md")).toBe("mine");
  });
});

describe("noteTabs external delete and CRLF", () => {
  test("a dirty Note whose file vanished is a conflict (not re-created); discard drops it", () => {
    tabs.open("a.md", "A"); tabs.edit("a.md", "mine", 0);
    tabs.diskGone("a.md");
    expect(tabs.conflict("a.md")).toBeNull();
    expect(tabs.pending()).toEqual([]);
    tabs.discard("a.md");
    expect(tabs.paths).toEqual([]);
  });

  test("re-create keeps my text for the app to write", () => {
    tabs.open("a.md", "A"); tabs.edit("a.md", "mine", 0);
    tabs.diskGone("a.md");
    expect(tabs.resolveConflict("a.md", false)).toBe("mine");
    expect(tabs.conflict("a.md")).toBeUndefined();
  });

  test("a clean Note whose file vanished just closes", () => {
    tabs.open("a.md", "A"); tabs.diskGone("a.md");
    expect(tabs.paths).toEqual([]);
  });

  test("line endings alone are not an outside change", () => {
    tabs.open("a.md", "x\r\ny"); tabs.edit("a.md", "x\ny!", 0); tabs.saved("a.md", "x\ny!");
    tabs.diskChanged("a.md", "x\r\ny!");
    expect(tabs.conflict("a.md")).toBeUndefined();
  });

  test("unsaved is true from the first edit until the write succeeds", () => {
    tabs.open("a.md", "A"); expect(tabs.unsaved("a.md")).toBe(false);
    tabs.edit("a.md", "B", 0); expect(tabs.unsaved("a.md")).toBe(true);
    tabs.saved("a.md", "B"); expect(tabs.unsaved("a.md")).toBe(false);
  });
});
