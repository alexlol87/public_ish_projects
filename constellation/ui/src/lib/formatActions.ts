import type { Range } from "./styler";

export type FormatAction =
  | "bold" | "italic" | "underline" | "strikethrough" | "inlineCode" | "codeBlock"
  | "heading1" | "heading2" | "heading3" | "bulletList" | "numberedList" | "taskList" | "quote" | "link" | "table";

export interface TextEdit { text: string; selection: Range }

const inline: Partial<Record<FormatAction, [string, string]>> = {
  bold: ["**", "**"], italic: ["*", "*"], underline: ["<u>", "</u>"], strikethrough: ["~~", "~~"],
  inlineCode: ["`", "`"], link: ["[[", "]]"],
  codeBlock: ["```\n", "\n```"], // ponytail: assumes the selection starts at a line start
};
const headingRe = /^#{1,6} /;
const listRe = /^(- \[[ xX]\] |- |\d+\. )/;

/** Pure (text, selection, action) -> (text, selection). Applying a format that is already present removes it. */
export function applyFormat(action: FormatAction, text: string, sel: Range): TextEdit {
  const pair = inline[action];
  if (pair) return wrap(text, sel, pair[0], pair[1]);
  switch (action) {
    case "heading1": case "heading2": case "heading3": {
      const p = "#".repeat(Number(action.slice(-1))) + " ";
      return lines(text, sel, headingRe, () => p);
    }
    case "bulletList": return lines(text, sel, listRe, () => "- ");
    case "numberedList": return lines(text, sel, listRe, (i) => `${i + 1}. `);
    case "taskList": return lines(text, sel, listRe, () => "- [ ] ");
    case "quote": return lines(text, sel, null, () => "> ");
    default: // table
      return {
        text: text.slice(0, sel.from) + "| Column | Column |\n| --- | --- |\n|  |  |\n" + text.slice(sel.to),
        selection: { from: sel.from + 2, to: sel.from + 8 },
      };
  }
}

function wrap(text: string, sel: Range, open: string, close: string): TextEdit {
  const o = open.length, c = close.length;
  const unwrapped = (start: number, inner: number, loc: number): TextEdit => ({
    text: text.slice(0, start) + text.slice(start + o, start + o + inner) + text.slice(start + o + inner + c),
    selection: { from: loc, to: loc + inner },
  });
  const selText = text.slice(sel.from, sel.to);
  // Markers just outside the selection (or around the cursor in an empty pair).
  // ponytail: only `*` is guarded against `**`; mixed `***x***` is treated as bold-only
  if (sel.from >= o && sel.to + c <= text.length &&
      text.slice(sel.from - o, sel.from) === open && text.slice(sel.to, sel.to + c) === close &&
      !(open === "*" && (text[sel.from - 2] === "*" || text[sel.to + 1] === "*"))) {
    return unwrapped(sel.from - o, sel.to - sel.from, sel.from - o);
  }
  // Markers inside the selection.
  if (selText.length >= o + c && selText.startsWith(open) && selText.endsWith(close)) {
    return unwrapped(sel.from, selText.length - o - c, sel.from);
  }
  return { text: text.slice(0, sel.from) + open + selText + close + text.slice(sel.to), selection: { from: sel.from + o, to: sel.to + o } };
}

/** Line formats apply to every selected line; the same prefix on all of them toggles it off. */
function lines(text: string, sel: Range, strip: RegExp | null, target: (i: number) => string): TextEdit {
  let end = sel.to;
  if (sel.to > sel.from && end > 0 && text[end - 1] === "\n") end--; // ending at a line start excludes that line
  const from = sel.from === 0 ? 0 : text.lastIndexOf("\n", sel.from - 1) + 1;
  const nl = text.indexOf("\n", end > sel.from ? end - 1 : sel.from);
  const bodyEnd = nl < 0 ? text.length : nl;
  const old = text.slice(from, bodyEnd).split("\n");
  const quote = strip === null;
  const prefix = (l: string) => (quote ? (l.startsWith("> ") ? "> " : "") : strip.exec(l)?.[0] ?? "");
  const removing = old.every((l, i) => prefix(l) === target(i));
  const next = old.map((l, i) => (removing ? "" : target(i)) + l.slice(prefix(l).length)).join("\n");
  const out = text.slice(0, from) + next + text.slice(bodyEnd);
  if (sel.from === sel.to) {
    const at = Math.max(from, sel.from + next.length - (bodyEnd - from));
    return { text: out, selection: { from: at, to: at } };
  }
  return { text: out, selection: { from, to: from + next.length } };
}
