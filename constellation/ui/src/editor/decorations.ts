import { EditorState, StateEffect, StateField, type Range, type Text, type Transaction } from "@codemirror/state";
import { Decoration, EditorView, WidgetType, type DecorationSet } from "@codemirror/view";
import { lineRangeCovering, style, type StyledRange, type StyleRole } from "../lib/styler";

export interface DecoOptions {
  resolveImage(path: string): string;
  isBrokenLink(target: string): boolean;
  onTickTask(offset: number): void;
}

/** Dispatch to rebuild decorations without a document or selection change (e.g. after link targets change). */
export const refreshEffect = StateEffect.define<null>();

class CheckboxWidget extends WidgetType {
  constructor(private checked: boolean, private onTick: (offset: number) => void) { super(); }
  eq(o: CheckboxWidget) { return o.checked === this.checked; }
  toDOM(view: EditorView) {
    const box = document.createElement("input");
    box.type = "checkbox";
    box.className = "cm-task";
    box.checked = this.checked;
    box.addEventListener("mousedown", (e) => {
      e.preventDefault();
      this.onTick(view.posAtDOM(box));
    });
    return box;
  }
  ignoreEvent() { return true; }
}

class ImageWidget extends WidgetType {
  constructor(private src: string, private alt: string) { super(); }
  eq(o: ImageWidget) { return o.src === this.src && o.alt === this.alt; }
  toDOM() {
    // The widget's root node must stay: replacing it behind CodeMirror's back makes it read the change as typed text.
    const root = document.createElement("span");
    const img = document.createElement("img");
    img.className = "cm-image";
    img.alt = this.alt;
    if (this.src) img.src = this.src;
    const missing = () => {
      const span = document.createElement("span");
      span.className = "cm-image-missing";
      span.textContent = `[image: ${this.alt || "missing"}]`;
      img.replaceWith(span);
    };
    img.addEventListener("error", missing);
    if (!this.src) queueMicrotask(missing);
    root.append(img);
    return root;
  }
}

class TableWidget extends WidgetType {
  constructor(private rendered: string) { super(); }
  eq(o: TableWidget) { return o.rendered === this.rendered; }
  toDOM() {
    const pre = document.createElement("pre");
    pre.className = "cm-table";
    pre.textContent = this.rendered;
    return pre;
  }
}

class FrontmatterWidget extends WidgetType {
  constructor(private summary: string) { super(); }
  eq(o: FrontmatterWidget) { return o.summary === this.summary; }
  toDOM(view: EditorView) {
    const div = document.createElement("div");
    div.className = "cm-frontmatter-summary";
    div.textContent = this.summary;
    div.title = "Frontmatter (click to edit)";
    div.addEventListener("mousedown", (e) => {
      e.preventDefault();
      view.dispatch({ selection: { anchor: view.posAtDOM(div) + 4 } }); // into the block: after the opening `---`
      view.focus();
    });
    return div;
  }
}

const mark = (cls: string, attrs?: Record<string, string>) => Decoration.mark({ class: cls, attributes: attrs });
const hide = Decoration.replace({});
const lineDeco = (cls: string) => Decoration.line({ class: cls });

function roleDecoration(role: StyleRole, o: DecoOptions): Decoration | null {
  switch (role.kind) {
    case "heading": return mark(`cm-h cm-h${role.level}`);
    case "bold": return mark("cm-bold");
    case "italic": return mark("cm-italic");
    case "strike": return mark("cm-strike");
    case "underline": return mark("cm-underline");
    case "inlineCode": return mark("cm-code");
    case "link":
      return mark(role.wiki && o.isBrokenLink(role.target) ? "cm-link cm-broken" : "cm-link", { "data-link": role.target });
    case "tag": return mark("cm-tag", { "data-tag": role.name });
    default: return null;
  }
}

export interface Built { all: DecorationSet; atomic: DecorationSet }

/** Decoration ranges for styler output; `offset` is where the styled text starts in `doc`. */
function toRanges(doc: Text, styled: StyledRange[], hidden: { from: number; to: number }[], offset: number, o: DecoOptions) {
  const all: Range<Decoration>[] = [];
  const atomic: Range<Decoration>[] = [];
  const widgets = new Set<string>(); // ranges replaced by a widget; their `hidden` entry is redundant
  const replace = (from: number, to: number, d: Decoration) => {
    all.push(d.range(from, to));
    atomic.push(d.range(from, to));
  };
  for (const s of styled) {
    const { role } = s, from = s.from + offset, to = s.to + offset;
    const lineStart = doc.lineAt(from).from;
    if (role.kind === "taskBox" || role.kind === "image" || role.kind === "table" || role.kind === "frontmatter") widgets.add(`${from}-${to}`);
    if (role.kind === "taskBox") replace(from, to, Decoration.replace({ widget: new CheckboxWidget(role.checked, o.onTickTask) }));
    else if (role.kind === "image") replace(from, to, Decoration.replace({ widget: new ImageWidget(o.resolveImage(role.path), role.alt) }));
    else if (role.kind === "table") replace(from, to, Decoration.replace({ widget: new TableWidget(role.rendered), block: true }));
    else if (role.kind === "frontmatter") {
      if (role.summary) replace(from, to, Decoration.replace({ widget: new FrontmatterWidget(role.summary), block: true }));
      else all.push(lineDeco("cm-frontmatter").range(lineStart));
    } else if (role.kind === "codeFence") all.push(lineDeco(role.collapsed ? "cm-codeblock cm-fence cm-fence-collapsed" : "cm-codeblock cm-fence").range(lineStart));
    else if (role.kind === "codeBlock") all.push(lineDeco("cm-codeblock").range(lineStart));
    else if (role.kind === "quote") all.push(lineDeco("cm-quote").range(lineStart));
    else {
      const d = roleDecoration(role, o);
      if (d && to > from) all.push(d.range(from, to));
    }
  }
  for (const h of hidden) {
    const from = h.from + offset, to = h.to + offset;
    if (to > from && !widgets.has(`${from}-${to}`)) replace(from, to, hide);
  }
  return { all, atomic };
}

/** Live-preview decorations: the styler's ranges, with markers hidden except on lines touched by the selection. */
export function buildDecorations(state: EditorState, o: DecoOptions): Built {
  const text = state.doc.toString();
  const { styled, hidden } = style(text, lineRangeCovering(state.selection.main, text));
  const { all, atomic } = toRanges(state.doc, styled, hidden, 0, o);
  return { all: Decoration.set(all, true), atomic: Decoration.set(atomic, true) };
}

/** Fence lines (```) starting before `pos`, outside frontmatter. */
function fencesBefore(doc: Text, pos: number): number {
  let n = 0;
  const first = frontmatterEnd(doc) + 1;
  if (pos <= 0 || first > doc.lineAt(pos - 1).number) return 0;
  for (const l of doc.iterLines(first, doc.lineAt(pos - 1).number + 1)) if (l.startsWith("```")) n++;
  return n;
}

/** Line number of the line closing a frontmatter block opened on line 1, else 0. */
function frontmatterEnd(doc: Text): number {
  if (doc.line(1).text !== "---") return 0;
  let n = 1;
  for (const l of doc.iterLines(2)) { n++; if (/^(---|\.\.\.)\r?$/.test(l)) return n; }
  return 0;
}

/**
 * The same result as `buildDecorations`, but only the lines the transaction touched (the edit, the old and new
 * cursor lines, whole tables) are restyled; the rest is mapped through the change. null: do a full rebuild
 * (several edits, fences or frontmatter involved).
 */
function updateDecorations(v: Built, tr: Transaction, o: DecoOptions): Built | null {
  const doc = tr.state.doc, old = tr.startState.doc;
  const edits: number[][] = [];
  tr.changes.iterChangedRanges((a, b, c, d) => edits.push([a, b, c, d]));
  if (edits.length > 1) return null;
  const sel = (from: number, to: number) => ({ from, to: to > from ? to - 1 : to });
  const m = (p: number) => tr.changes.mapPos(p);
  const s0 = tr.startState.selection.main, s1 = tr.state.selection.main;
  const spans = [sel(m(s0.from), m(s0.to)), sel(s1.from, s1.to)];
  if (edits.length) spans.push({ from: edits[0][2], to: edits[0][3] });
  const lineStartOf = (n: number) => doc.line(n).from;
  let regions = spans.map((s) => {
    let a = doc.lineAt(s.from).number, b = doc.lineAt(s.to).number;
    const pipe = (n: number) => doc.line(n).text.trim().startsWith("|");
    while (a > 1 && pipe(a - 1)) a--;
    while (b < doc.lines && pipe(b + 1)) b++;
    return [a, b];
  }).sort((x, y) => x[0] - y[0]);
  regions = regions.reduce<number[][]>((acc, r) => {
    const last = acc[acc.length - 1];
    if (last && r[0] <= last[1] + 1) last[1] = Math.max(last[1], r[1]); else acc.push(r);
    return acc;
  }, []);
  const fmNew = frontmatterEnd(doc), fmOld = edits.length ? frontmatterEnd(old) : 0;
  if (fmNew && regions[0][0] <= fmNew + 1) return null;
  if (edits.length) {
    const [a, b, c, d] = edits[0];
    if (fmOld && old.lineAt(a).number <= fmOld + 1) return null;
    const last = regions.find((r) => r[0] <= doc.lineAt(d).number && doc.lineAt(d).number <= r[1])!;
    const rTo = last[1] < doc.lines ? lineStartOf(last[1] + 1) : doc.length;
    const oldTo = Math.min(old.length, rTo - (d - c - (b - a)));
    if (fencesBefore(doc, rTo) % 2 !== fencesBefore(old, oldTo) % 2) return null; // every line below changed meaning
  }
  const cursor = { from: doc.lineAt(s1.from).from, to: Math.min(doc.length, doc.lineAt(s1.to > s1.from ? s1.to - 1 : s1.to).to + 1) };
  const added = { all: [] as Range<Decoration>[], atomic: [] as Range<Decoration>[] };
  const spansOut: [number, number][] = [];
  for (const [a, b] of regions) {
    const from = lineStartOf(a), to = b < doc.lines ? lineStartOf(b + 1) : doc.length;
    const { styled, hidden } = style(doc.sliceString(from, to), { from: cursor.from - from, to: cursor.to - from }, { inFence: fencesBefore(doc, from) % 2 === 1, atStart: from === 0 });
    const r = toRanges(doc, styled, hidden, from, o);
    added.all.push(...r.all); added.atomic.push(...r.atomic);
    spansOut.push([from, to]);
  }
  const filter = (from: number) => spansOut.every(([a, b]) => from < a || from >= b);
  const lo = spansOut[0][0], hi = spansOut[spansOut.length - 1][1];
  const upd = (set: DecorationSet, add: Range<Decoration>[]) =>
    set.map(tr.changes).update({ add, sort: true, filter, filterFrom: lo, filterTo: hi });
  return { all: upd(v.all, added.all), atomic: upd(v.atomic, added.atomic) };
}

export function livePreview(o: DecoOptions) {
  const field = StateField.define<Built>({
    create: (state) => buildDecorations(state, o),
    update: (v, tr) =>
      tr.effects.some((e) => e.is(refreshEffect)) ? buildDecorations(tr.state, o)
        : tr.docChanged || tr.selection ? updateDecorations(v, tr, o) ?? buildDecorations(tr.state, o) : v,
    provide: (f) => [
      EditorView.decorations.from(f, (v) => v.all),
      EditorView.atomicRanges.of((view) => view.state.field(f).atomic),
    ],
  });
  return field;
}
