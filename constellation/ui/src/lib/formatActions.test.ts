import { describe, expect, test } from "vitest";
import { applyFormat, type FormatAction } from "./formatActions";

const r = (loc: number, len: number) => ({ from: loc, to: loc + len });
const ap = (a: FormatAction, t: string, s: { from: number; to: number }) => {
  const e = applyFormat(a, t, s);
  return [e.text, e.selection] as const;
};

const inline: [FormatAction, string, string][] = [
  ["bold", "**", "**"], ["italic", "*", "*"], ["underline", "<u>", "</u>"], ["strikethrough", "~~", "~~"],
  ["inlineCode", "`", "`"], ["link", "[[", "]]"],
];

describe("formatActions", () => {
  test.each(inline)("%s: wrap, empty pair and toggle off", (a, o, c) => {
    let [t, s] = ap(a, "a word b", r(2, 4));
    expect(t).toBe(`a ${o}word${c} b`);
    expect(s).toEqual(r(2 + o.length, 4));
    [t, s] = ap(a, t, s); // inner selected: surrounding markers removed
    expect([t, s]).toEqual(["a word b", r(2, 4)]);

    [t, s] = ap(a, "ab", r(1, 0));
    expect(t).toBe(`a${o}${c}b`);
    expect(s).toEqual(r(1 + o.length, 0));
    [t, s] = ap(a, t, s); // cursor inside empty pair: removed
    expect([t, s]).toEqual(["ab", r(1, 0)]);

    [t, s] = ap(a, `${o}x${c}`, r(0, o.length + 1 + c.length)); // markers inside selection
    expect([t, s]).toEqual(["x", r(0, 1)]);
  });

  test("italic is not toggled off by bold markers", () => {
    expect(ap("italic", "**x**", r(2, 1))[0]).toBe("***x***");
  });

  test("code block wrap, empty and toggle", () => {
    let [t, s] = ap("codeBlock", "let x", r(0, 5));
    expect([t, s]).toEqual(["```\nlet x\n```", r(4, 5)]);
    [t, s] = ap("codeBlock", t, s);
    expect(t).toBe("let x");
    [t, s] = ap("codeBlock", "", r(0, 0));
    expect([t, s]).toEqual(["```\n\n```", r(4, 0)]);
  });

  const lineFormats: [FormatAction, string[]][] = [
    ["heading1", ["# ", "# "]], ["heading2", ["## ", "## "]], ["heading3", ["### ", "### "]],
    ["bulletList", ["- ", "- "]], ["numberedList", ["1. ", "2. "]], ["taskList", ["- [ ] ", "- [ ] "]], ["quote", ["> ", "> "]],
  ];
  test.each(lineFormats)("%s: multi-line, toggle and cursor", (a, p) => {
    let [t, s] = ap(a, "one\ntwo\nthree", r(1, 5)); // touches lines 1 and 2 only
    expect(t).toBe(`${p[0]}one\n${p[1]}two\nthree`);
    expect(s).toEqual(r(0, t.length - "\nthree".length));
    [t, s] = ap(a, t, s);
    expect(t).toBe("one\ntwo\nthree");

    [t, s] = ap(a, "one", r(3, 0));
    expect(t).toBe(`${p[0]}one`);
    expect(s).toEqual(r(3 + p[0].length, 0));
  });

  test("line format switches within family", () => {
    expect(ap("heading2", "# Title", r(0, 0))[0]).toBe("## Title");
    expect(ap("numberedList", "- a\n- b", r(0, 7))[0]).toBe("1. a\n2. b");
    expect(ap("quote", "- a", r(0, 0))[0]).toBe("> - a"); // quote nests; not same family
  });

  test("selection ending at line start excludes that line", () => {
    expect(ap("bulletList", "a\nb", r(0, 2))[0]).toBe("- a\nb");
  });

  test("table inserts skeleton and selects first header", () => {
    const [t, s] = ap("table", "ab", r(1, 0));
    expect(t).toBe("a| Column | Column |\n| --- | --- |\n|  |  |\nb");
    expect(s).toEqual(r(3, 6));
  });

  test("emoji uses UTF-16", () => {
    expect(ap("bold", "😀 hi", r(3, 2))).toEqual(["😀 **hi**", r(5, 2)]);
  });

  test("line format on a later line and at text start", () => {
    expect(ap("quote", "a\nb", r(2, 0))).toEqual(["a\n> b", r(4, 0)]);
    expect(ap("heading1", "\nb", r(0, 0))[0]).toBe("# \nb");
  });
});
