import { table } from "./tables";

/** UTF-16 offsets (JS string indices). */
export interface Range { from: number; to: number }

export type StyleRole =
  | { kind: "heading"; level: number }
  | { kind: "bold" | "italic" | "strike" | "underline" | "inlineCode" | "codeBlock" }
  /** A ``` fence line; `collapsed` (off the cursor) means its text is hidden and it draws as a thin edge of the block. */
  | { kind: "codeFence"; collapsed: boolean }
  /** Whole frontmatter block off the cursor (drawn as `summary`), or one of its lines (summary "") when the cursor is inside. */
  | { kind: "frontmatter"; summary: string }
  /** Content of a `> ` quote line (the marker is hidden). */
  | { kind: "quote" }
  /** `target` is `path[#heading]` for a wikilink, the URL for a markdown link. */
  | { kind: "link"; target: string; wiki: boolean }
  /** `#tag` including the `#`; never hidden. `name` has no `#`. */
  | { kind: "tag"; name: string }
  /** Whole `![alt](path)` range; the editor draws the image instead of the raw text. */
  | { kind: "image"; path: string; alt: string }
  /** Whole table block; `rendered` is the column-aligned monospace text to draw instead of the raw rows. */
  | { kind: "table"; rendered: string }
  /** The `[ ]` / `[x]` of a task item (3 chars); a clickable checkbox, raw on the cursor line. */
  | { kind: "taskBox"; checked: boolean };

export interface StyledRange extends Range { role: StyleRole }
export interface StyleResult {
  /** Markers are never inside these; code content is never styled as anything but code. */
  styled: StyledRange[];
  /** Marker ranges to hide. Empty for the cursor line. */
  hidden: Range[];
}

const taskBoxRe = /^[ \t]*[-*+] (\[([ xX])\])(?= |$)/d;
const imageRe = /!\[([^\]]*)\]\(([^)\s]+)\)/gd;
const headingRe = /^(#{1,6}) +(?=\S)/;
const codeRe = /`[^`]+`/g;
const linkUrlRe = /\]\([^)]*\)/g;
const hexRe = /^(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;
export const tagName = "\\p{L}[\\p{L}\\p{N}_-]*(?:/\\p{L}[\\p{L}\\p{N}_-]*)*";
const tagRe = new RegExp("(?<![\\p{L}\\p{N}_/&#])#(" + tagName + ")", "gu");
const typedTagRe = /(?<![\p{L}\p{N}_/&#])#([\p{L}\p{N}_/-]*)$/u;
const wikilink = String.raw`\[\[([^\[\]|]+)(?:\|([^\[\]]*))?\]\]`; // 1 target[#heading], 2 alias
const wikiRe = new RegExp(wikilink, "gd");
const spans: [RegExp, "inlineCode" | "link" | "bold" | "italic" | "strike" | "underline"][] = [
  [/`([^`]+)`/gd, "inlineCode"],
  [wikiRe, "link"],
  [/\*\*(?=\S)(.+?)(?<=\S)\*\*/gd, "bold"],
  [/~~(?=\S)(.+?)(?<=\S)~~/gd, "strike"],
  [/<u>(.+?)<\/u>/gd, "underline"],
  [/(?<![*\w])\*(?=[^\s*])([^*]+?)(?<=\S)\*(?![*\w])/gd, "italic"],
  [/(?<!\w)_(?=[^\s_])([^_]+?)(?<=\S)_(?!\w)/gd, "italic"],
  [/\[([^\]]+)\]\(([^)\s]+)\)/gd, "link"],
];

const overlap = (a: Range, b: Range) => Math.min(a.to, b.to) > Math.max(a.from, b.from);
const idx = (m: RegExpMatchArray, g: number) => (m as RegExpMatchArray & { indices: [number, number][] }).indices[g];

/** `#tag` ranges (with the `#`) in one line, outside inline code and `](url)` parts. */
export function inlineTags(s: string): (Range & { name: string })[] {
  const skip = [...s.matchAll(codeRe), ...s.matchAll(linkUrlRe)].map((m) => ({ from: m.index, to: m.index + m[0].length }));
  return [...s.matchAll(tagRe)]
    .map((m) => ({ from: m.index, to: m.index + m[0].length, name: m[1] }))
    .filter((t) => !skip.some((k) => overlap(k, t)) && !hexRe.test(t.name));
}

/** The Tag text typed after a `#` at the end of `line` (a `#` that would start a Tag), else null. */
export function typedTagPrefix(lineBeforeCursor: string): string | null {
  return typedTagRe.exec(lineBeforeCursor)?.[1] ?? null;
}

function styleInline(s: string, offset: number, out: StyleResult, hidden: Range[]) {
  const R = (from: number, to: number): Range => ({ from: from + offset, to: to + offset });
  const taken: Range[] = [];
  const free = (r: Range) => !taken.some((t) => overlap(t, r));
  const push = (r: Range, role: StyleRole) => out.styled.push({ ...R(r.from, r.to), role });

  for (const m of s.matchAll(imageRe)) {
    const r = { from: m.index, to: m.index + m[0].length };
    taken.push(r);
    push(r, { kind: "image", path: m[2], alt: m[1] });
    hidden.push(R(r.from, r.to));
  }
  const h = headingRe.exec(s);
  if (h && s.length > h[0].length) {
    push({ from: h[0].length, to: s.length }, { kind: "heading", level: h[1].length });
    hidden.push(R(0, h[0].length));
  }
  const q = /^> ?/.exec(s);
  if (q && s.length > q[0].length) {
    push({ from: q[0].length, to: s.length }, { kind: "quote" });
    hidden.push(R(0, q[0].length));
  }
  for (const [re, kind] of spans) {
    for (const m of s.matchAll(re)) {
      const whole = { from: m.index, to: m.index + m[0].length };
      if (!free(whole)) continue;
      taken.push(whole);
      // Visible part: group 1, or for a wikilink the alias if given. Everything else is a marker.
      const wiki = re === wikiRe;
      const [from, to] = (wiki && idx(m, 2)) || idx(m, 1);
      push({ from, to }, kind === "link" ? { kind, wiki, target: (wiki ? m[1].trim() : m[2]) } : { kind });
      hidden.push(R(whole.from, from), R(to, whole.to));
    }
  }
  for (const t of inlineTags(s)) if (free(t)) push(t, { kind: "tag", name: t.name });
}

/**
 * Pure markdown-to-ranges mapper, line based. `cursorLine` is the range of the line(s) holding the
 * selection (see `lineRange`); markers there are not hidden. null means no line is active.
 */
export function style(text: string, cursorLine: Range | null = null, ctx: { inFence?: boolean; atStart?: boolean } = {}): StyleResult {
  const out: StyleResult = { styled: [], hidden: [] };
  const lines = text.split("\n");
  const touches = (r: Range, c: Range | null) => !!c && (overlap(c, r) || c.from === r.from);
  let inFence = ctx.inFence ?? false;
  const atStart = ctx.atStart ?? true; // false: `text` is a slice from mid-document, so line 0 cannot open frontmatter
  let loc = 0;
  let t: ReturnType<typeof table>;
  let fm: number;
  for (let li = 0; li < lines.length; li++) {
    const raw = lines[li];
    const full: Range = { from: loc, to: Math.min(loc + raw.length + 1, text.length) };
    if (full.from >= text.length) break; // a trailing newline does not open another line
    const line: Range = { from: loc, to: loc + raw.replace(/\r$/, "").length };
    const content = text.slice(line.from, line.to);
    const active = touches(full, cursorLine);
    const hidden: Range[] = [];
    loc = full.to;

    if (atStart && li === 0 && content === "---" && (fm = frontmatterEnd(lines)) > 0) {
      const end = lines.slice(0, fm + 1).reduce((n, l) => n + l.length + 1, 0);
      const block = { from: 0, to: Math.min(end - 1, text.length) };
      if (touches({ from: 0, to: end }, cursorLine)) {
        for (let i = 0, at = 0; i <= fm; at += lines[i].length + 1, i++) out.styled.push({ from: at, to: at + lines[i].length, role: { kind: "frontmatter", summary: "" } });
      } else {
        out.styled.push({ ...block, role: { kind: "frontmatter", summary: frontmatterSummary(lines.slice(1, fm)) || "properties" } });
        out.hidden.push(block);
      }
      loc = end;
      li = fm;
      continue;
    } else if (content.startsWith("```")) {
      inFence = !inFence;
      out.styled.push({ ...line, role: { kind: "codeFence", collapsed: !active } });
      hidden.push(line);
    } else if (inFence) {
      if (line.to > line.from) out.styled.push({ ...line, role: { kind: "codeBlock" } });
    } else if (content.trim().startsWith("|") && (t = table(lines, li))) {
      const last = lines.slice(li, li + t.count);
      const end = full.from + last.reduce((n, l) => n + l.length + 1, 0);
      const block = { from: full.from, to: Math.min(end - 1, text.length) };
      if (!touches({ from: block.from, to: end }, cursorLine)) {
        out.styled.push({ ...block, role: { kind: "table", rendered: t.rendered } });
        out.hidden.push(block);
      }
      loc = end;
      li += t.count - 1;
      continue;
    } else {
      const before = out.styled.length;
      styleInline(content, line.from, out, hidden);
      const m = active ? null : taskBoxRe.exec(content);
      if (m) {
        const [from] = idx(m, 1);
        out.styled.push({ from: line.from + from, to: line.from + from + 3, role: { kind: "taskBox", checked: m[2] !== " " } });
        hidden.push({ from: line.from + from, to: line.from + from + 3 });
      }
      // Raw markdown comes back on the cursor line: no image widget there.
      if (active) out.styled = [...out.styled.slice(0, before), ...out.styled.slice(before).filter((r) => r.role.kind !== "image")];
    }
    if (!active) out.hidden.push(...hidden);
  }
  return out;
}

/** Index of the line closing a frontmatter block opened by `---` on line 0, or -1. */
function frontmatterEnd(lines: string[]): number {
  for (let i = 1; i < lines.length; i++) if (/^(---|\.\.\.)\r?$/.test(lines[i])) return i;
  return -1;
}

/** One-line summary of YAML frontmatter lines: `type: repo · tags: a, b`. List items join their key. */
export function frontmatterSummary(lines: string[]): string {
  const parts: string[] = [];
  for (const l of lines) {
    const item = /^\s+-\s*(.*)$/.exec(l);
    if (item && parts.length) parts[parts.length - 1] += (parts[parts.length - 1].endsWith(":") ? " " : ", ") + item[1].trim();
    else if (l.trim()) parts.push(l.trim());
  }
  return parts.join(" · ");
}

/** The line (including newline) containing a UTF-16 cursor offset. */
export function lineRange(cursor: number, text: string): Range {
  const c = Math.min(Math.max(cursor, 0), text.length);
  const from = c === 0 ? 0 : text.lastIndexOf("\n", c - 1) + 1;
  const nl = text.indexOf("\n", c);
  return { from, to: nl < 0 ? text.length : nl + 1 };
}

/** The whole lines touched by a selection, so markers stay visible across a multi-line selection.
 *  A selection ending exactly at a line start does not include that next line. */
export function lineRangeCovering(sel: Range, text: string): Range {
  const from = Math.min(Math.max(sel.from, 0), text.length);
  const end = Math.min(Math.max(sel.to - (sel.to > sel.from ? 1 : 0), from), text.length);
  return { from: lineRange(from, text).from, to: lineRange(end, text).to };
}
