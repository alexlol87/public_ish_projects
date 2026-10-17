import { describe, expect, test } from "vitest";
import { inlineTags, lineRange, lineRangeCovering, style, typedTagPrefix } from "./styler";

const r = (loc: number, len: number) => ({ from: loc, to: loc + len });
const s = (loc: number, len: number, role: object) => ({ ...r(loc, len), role });
const roles = (t: string) => style(t).styled.map((x) => x.role.kind);

describe("styler", () => {
  test("heading off cursor styles title and hides marker", () => {
    const out = style("## Hello");
    expect(out.styled).toEqual([s(3, 5, { kind: "heading", level: 2 })]);
    expect(out.hidden).toEqual([r(0, 3)]);
  });
  test("heading on cursor line keeps marker", () => {
    const out = style("## Hello", r(0, 8));
    expect(out.styled).toEqual([s(3, 5, { kind: "heading", level: 2 })]);
    expect(out.hidden).toEqual([]);
  });
  test("bold", () => {
    const out = style("a **b** c");
    expect(out.styled).toEqual([s(4, 1, { kind: "bold" })]);
    expect(out.hidden).toEqual([r(2, 2), r(5, 2)]);
  });
  test("italic star and underscore", () => {
    const out = style("*a* and _b_");
    expect(out.styled.map(({ from, to }) => ({ from, to }))).toEqual([r(1, 1), r(9, 1)]);
    expect(roles("*a* and _b_")).toEqual(["italic", "italic"]);
    expect(out.hidden).toEqual([r(0, 1), r(2, 1), r(8, 1), r(10, 1)]);
  });
  test("inline code contents are not styled", () => {
    const out = style("`**x** [a](b)`");
    expect(out.styled).toEqual([s(1, 12, { kind: "inlineCode" })]);
    expect(out.hidden).toEqual([r(0, 1), r(13, 1)]);
  });
  test("link", () => {
    const out = style("see [docs](a/b.md)");
    expect(out.styled).toEqual([s(5, 4, { kind: "link", wiki: false, target: "a/b.md" })]);
    expect(out.hidden).toEqual([r(4, 1), r(9, 9)]);
  });
  test("fenced code is not styled inside", () => {
    const out = style("```swift\n**not bold**\n```\nafter");
    expect(out.styled).toEqual([s(0, 8, { kind: "codeFence", collapsed: true }), s(9, 12, { kind: "codeBlock" }), s(22, 3, { kind: "codeFence", collapsed: true })]);
    expect(out.hidden).toEqual([r(0, 8), r(22, 3)]);
  });
  test("cursor line keeps its markers only", () => {
    const text = "**a**\n**b**";
    const out = style(text, lineRange(8, text));
    expect(out.hidden).toEqual([r(0, 2), r(3, 2)]);
    expect(out.styled.length).toBe(2);
  });
  test("cursor at end of text on trailing newline line", () => {
    expect(style("**a**\n", lineRange(3, "**a**\n")).hidden).toEqual([]);
  });
  test("selection spanning lines keeps markers on every touched line", () => {
    const text = "**a**\n**b**\n**c**";
    const sel = lineRangeCovering(r(3, 5), text);
    expect(sel).toEqual(r(0, 12));
    expect(style(text, sel).hidden).toEqual([r(12, 2), r(15, 2)]);
  });
  test("selection ending at line start does not touch next line", () => {
    expect(lineRangeCovering(r(0, 6), "**a**\n**b**")).toEqual(r(0, 6));
  });
  test("lineRange edges", () => {
    expect(lineRange(0, "\nab")).toEqual(r(0, 1));
    expect(lineRange(99, "ab\ncd")).toEqual(r(3, 2));
  });
  test("wikilink hides brackets off cursor line", () => {
    const out = style("a [[api]] b");
    expect(out.styled).toEqual([s(4, 3, { kind: "link", wiki: true, target: "api" })]);
    expect(out.hidden).toEqual([r(2, 2), r(7, 2)]);
  });
  test("wikilink alias shows only alias", () => {
    const out = style("[[notes#H|the notes]]");
    expect(out.styled).toEqual([s(10, 9, { kind: "link", wiki: true, target: "notes#H" })]);
    expect(out.hidden).toEqual([r(0, 10), r(19, 2)]);
  });
  test("wikilink markers visible on cursor line, ignored in code", () => {
    expect(style("[[a]]", r(0, 5)).hidden).toEqual([]);
    expect(roles("`[[a]]`")).toEqual(["inlineCode"]);
  });

  // widgets
  test("image is a widget range hidden off cursor line", () => {
    const out = style("a\n![cat](pics/cat.png)\nb");
    expect(out.styled).toEqual([s(2, 20, { kind: "image", path: "pics/cat.png", alt: "cat" })]);
    expect(out.hidden).toEqual([r(2, 20)]);
  });
  test("image on cursor line shows raw markdown", () => {
    const out = style("![cat](c.png)", r(0, 13));
    expect(out.styled).toEqual([]);
    expect(out.hidden).toEqual([]);
  });
  test("table aligns columns and hides raw block", () => {
    const out = style("| a | bb |\n|---|:--:|\n| ccc | d |\nafter");
    const rendered = "| a   | bb |\n| --- | -- |\n| ccc | d  |";
    expect(out.styled).toEqual([s(0, 33, { kind: "table", rendered })]);
    expect(out.hidden).toEqual([r(0, 33)]);
  });
  test("cursor anywhere in table shows raw", () => {
    const text = "| a | b |\n|---|---|\n| 1 | 2 |\n";
    const out = style(text, lineRange(15, text));
    expect(out.styled).toEqual([]);
    expect(out.hidden).toEqual([]);
  });
  test("strike, underline and quote", () => {
    const st = style("~~a~~ <u>b</u>");
    expect(st.styled.map((x) => x.role.kind)).toEqual(["strike", "underline"]);
    expect(st.hidden).toEqual([r(0, 2), r(3, 2), r(6, 3), r(10, 4)]);
    expect(style("> quoted")).toEqual({ styled: [s(2, 6, { kind: "quote" })], hidden: [r(0, 2)] });
    expect(style("> quoted", r(0, 8)).hidden).toEqual([]);
    expect(roles(">")).toEqual([]);
  });
  test("pipes without delimiter row are not a table", () => {
    expect(style("| a | b |\n| c | d |").styled).toEqual([]);
  });
  test("fences stay code blocks", () => {
    expect(roles("```mermaid\n| a | b |\n|---|---|\n![x](y.png)\n```")).toEqual(["codeFence", "codeBlock", "codeBlock", "codeBlock", "codeFence"]);
  });
  test("fence on the cursor line is shown, not collapsed", () => {
    const text = "```\nx\n```";
    const out = style(text, lineRange(1, text));
    expect(out.styled[0]).toEqual(s(0, 3, { kind: "codeFence", collapsed: false }));
    expect(out.hidden).toEqual([r(6, 3)]);
  });
  test("frontmatter collapses to a summary off the cursor", () => {
    const text = "---\ntype: endpoint\ntags:\n  - a\n  - b\n---\n# T";
    const out = style(text, lineRange(text.length, text));
    expect(out.styled[0]).toEqual(s(0, 40, { kind: "frontmatter", summary: "type: endpoint · tags: a, b" }));
    expect(out.hidden).toEqual([r(0, 40)]);
    expect(roles("---\n---\nx")).toEqual(["frontmatter"]);
    expect(style("---\n---\nx").styled[0].role).toEqual({ kind: "frontmatter", summary: "properties" });
  });
  test("frontmatter is raw but dimmed when the cursor is inside", () => {
    const text = "---\na: 1\n---\nx";
    const out = style(text, lineRange(5, text));
    expect(out.styled).toEqual([0, 4, 9].map((at, i) => s(at, [3, 4, 3][i], { kind: "frontmatter", summary: "" })));
    expect(out.hidden).toEqual([]);
  });
  test("--- without a closing line, or not on line 1, is not frontmatter", () => {
    expect(roles("---\na: 1")).toEqual([]);
    expect(roles("x\n---\na\n---")).toEqual([]);
  });

  // tasks and tags
  test("task box is a widget hidden on cursor line", () => {
    const out = style("- [x] done\n- [ ] todo");
    expect(out.styled.filter((x) => x.role.kind === "taskBox")).toEqual([
      s(2, 3, { kind: "taskBox", checked: true }), s(13, 3, { kind: "taskBox", checked: false }),
    ]);
    expect(style("- [ ] a", r(0, 7)).styled).toEqual([]);
  });
  test("tags", () => {
    expect(inlineTags("a #team/pay and #fff and #123 `#code` [x](#frag) # H").map((t) => t.name)).toEqual(["team/pay"]);
    expect(style("hi #tag").styled).toEqual([s(3, 4, { kind: "tag", name: "tag" })]);
    expect(style("hi #tag").hidden).toEqual([]);
  });
  test("typedTagPrefix", () => {
    expect(typedTagPrefix("see #pay")).toBe("pay");
    expect(typedTagPrefix("see #")).toBe("");
    expect(typedTagPrefix("a#b")).toBeNull();
    expect(typedTagPrefix("# ")).toBeNull();
    expect(typedTagPrefix("no tag")).toBeNull();
  });
});
