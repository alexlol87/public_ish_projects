import { history, undo, redo } from "@codemirror/commands";
import { EditorState } from "@codemirror/state";
import { describe, expect, test } from "vitest";
import { buildDecorations, type DecoOptions } from "./decorations";
import { formatKeys, formatTransaction } from "./editor";
import { applyFormat } from "../lib/formatActions";

const opts: DecoOptions = { resolveImage: (p) => "asset://" + p, isBrokenLink: (t) => t === "gone", onTickTask: () => {} };
const at = (doc: string, anchor?: number, head = anchor) =>
  EditorState.create({ doc, selection: anchor === undefined ? undefined : { anchor, head } });

/** `from-to:class` or `from-to:Widget`/`from-to:hide` for every decoration. */
function describeAll(state: EditorState, set: "all" | "atomic" = "all") {
  const out: string[] = [];
  buildDecorations(state, opts)[set].between(0, state.doc.length, (from, to, d) => {
    const s = d.spec;
    out.push(`${from}-${to}:${s.class ?? s.widget?.constructor.name ?? "hide"}`);
  });
  return out;
}

describe("decorations", () => {
  test("markers hidden off the cursor line, visible on it", () => {
    const doc = "## Title\nx **b**";
    expect(describeAll(at(doc, 12))).toEqual(["0-3:hide", "3-8:cm-h cm-h2", "13-14:cm-bold"]);
    const onHeading = describeAll(at(doc, 2));
    expect(onHeading).toContain("3-8:cm-h cm-h2");
    expect(onHeading).not.toContain("0-3:hide");
    expect(onHeading).toContain("13-14:cm-bold");
    expect(onHeading).toContain("11-13:hide");
  });

  test("multi-line selection reveals every touched line", () => {
    const hides = describeAll(at("**a**\n**b**\n**c**", 1, 8)).filter((d) => d.endsWith("hide"));
    expect(hides).toEqual(["12-14:hide", "15-17:hide"]);
  });

  test("wikilinks: alias shown, broken ones flagged", () => {
    const d = describeAll(at("[[ok|Alias]] [[gone]]\nend", 23));
    expect(d).toContain("5-10:cm-link");
    expect(d).toContain("15-19:cm-link cm-broken");
    expect(d.filter((x) => x.endsWith("hide"))).toEqual(["0-5:hide", "10-12:hide", "13-15:hide", "19-21:hide"]);
  });

  test("markdown links are never flagged broken", () => {
    expect(describeAll(at("[gone](gone)\nx", 13))).toContain("1-5:cm-link");
  });

  test("tags, code, quote, strike, underline", () => {
    const d = describeAll(at("#a `c` ~~s~~ <u>u</u>\n> q\n```\nfenced\n```\nend", 0));
    expect(d).toContain("0-2:cm-tag");
    expect(d).toContain("4-5:cm-code");
    expect(d).toContain("9-10:cm-strike");
    expect(d).toContain("16-17:cm-underline");
  });

  test("quote and code block use line decorations", () => {
    const d = describeAll(at("x\n> q\n```\nfenced\n```\nend", 0));
    expect(d).toContain("2-2:cm-quote");
    expect(d.filter((x) => x.endsWith("cm-codeblock"))).toHaveLength(1);
  });

  test("task checkbox is a widget off the cursor line and raw on it", () => {
    expect(describeAll(at("- [ ] a\nb", 8))).toContain("2-5:CheckboxWidget");
    expect(describeAll(at("- [ ] a\nb", 3)).some((d) => d.includes("Checkbox"))).toBe(false);
  });

  test("table is a block widget off the cursor, raw inside it", () => {
    const doc = "| a | b |\n|---|---|\n| 1 | 2 |\nafter";
    const d = describeAll(at(doc, doc.length));
    expect(d).toEqual(["0-31:TableWidget"].map((x) => x.replace("31", String(doc.indexOf("\nafter")))));
    expect(describeAll(at(doc, 5)).some((x) => x.includes("Table"))).toBe(false);
  });

  test("image becomes a widget, raw on the cursor line", () => {
    expect(describeAll(at("![c](p.png)\nx", 12))).toEqual(["0-11:ImageWidget"]);
    expect(describeAll(at("![c](p.png)\nx", 3))).toEqual([]);
  });

  test("atomic ranges contain only replaced text, never marks", () => {
    expect(describeAll(at("**b** #t\nx", 9), "atomic")).toEqual(["0-2:hide", "3-5:hide"]);
  });
});

describe("format actions in the editor", () => {
  const withHistory = (doc: string, from: number, to = from) =>
    EditorState.create({ doc, selection: { anchor: from, head: to }, extensions: [history()] });

  test("one transaction, minimal change, selection from the pure action", () => {
    const s = withHistory("a word b", 2, 6);
    const tr = s.update(formatTransaction(s, "bold"));
    expect(tr.state.doc.toString()).toBe("a **word** b");
    expect(tr.changes.desc.empty).toBe(false);
    expect([tr.state.selection.main.from, tr.state.selection.main.to]).toEqual([4, 8]);
  });

  test("every action matches the pure function", () => {
    for (const action of new Set(Object.values(formatKeys))) {
      const s = withHistory("one\ntwo", 1, 5);
      const expected = applyFormat(action, "one\ntwo", { from: 1, to: 5 });
      const tr = s.update(formatTransaction(s, action));
      expect(tr.state.doc.toString()).toBe(expected.text);
      expect([tr.state.selection.main.from, tr.state.selection.main.to]).toEqual([expected.selection.from, expected.selection.to]);
    }
  });

  test("undo and redo revert a format action in one step, toggling works across", () => {
    let s = withHistory("a word b", 2, 6);
    const dispatch = (tr: import("@codemirror/state").Transaction) => (s = tr.state);
    dispatch(s.update(formatTransaction(s, "bold")));
    dispatch(s.update(formatTransaction(s, "heading1")));
    expect(s.doc.toString()).toBe("# a **word** b");
    undo({ state: s, dispatch });
    expect(s.doc.toString()).toBe("a **word** b");
    undo({ state: s, dispatch });
    expect(s.doc.toString()).toBe("a word b");
    redo({ state: s, dispatch });
    expect(s.doc.toString()).toBe("a **word** b");
    dispatch(s.update(formatTransaction(s, "bold"))); // selection is the inner word: toggles off
    expect(s.doc.toString()).toBe("a word b");
  });

  test("shortcuts cover the PLAN 6.2 table", () => {
    expect(Object.keys(formatKeys)).toHaveLength(14);
    expect(formatKeys["Mod-Shift-x"]).toBe("strikethrough");
  });
});
