import { EditorState, StateEffect, StateField, type Range } from "@codemirror/state";
import { Decoration, EditorView, WidgetType, type DecorationSet } from "@codemirror/view";
import { lineRangeCovering, style, type StyleRole } from "../lib/styler";

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

/** Live-preview decorations: the styler's ranges, with markers hidden except on lines touched by the selection. */
export function buildDecorations(state: EditorState, o: DecoOptions): Built {
  const text = state.doc.toString();
  const { styled, hidden } = style(text, lineRangeCovering(state.selection.main, text));
  const all: Range<Decoration>[] = [];
  const atomic: Range<Decoration>[] = [];
  const widgets = new Set<string>(); // ranges replaced by a widget; their `hidden` entry is redundant
  const replace = (from: number, to: number, d: Decoration) => {
    all.push(d.range(from, to));
    atomic.push(d.range(from, to));
  };
  for (const { from, to, role } of styled) {
    const lineStart = state.doc.lineAt(from).from;
    if (role.kind === "taskBox" || role.kind === "image" || role.kind === "table") widgets.add(`${from}-${to}`);
    if (role.kind === "taskBox") replace(from, to, Decoration.replace({ widget: new CheckboxWidget(role.checked, o.onTickTask) }));
    else if (role.kind === "image") replace(from, to, Decoration.replace({ widget: new ImageWidget(o.resolveImage(role.path), role.alt) }));
    else if (role.kind === "table") replace(from, to, Decoration.replace({ widget: new TableWidget(role.rendered), block: true }));
    else if (role.kind === "codeBlock") all.push(lineDeco("cm-codeblock").range(lineStart));
    else if (role.kind === "quote") all.push(lineDeco("cm-quote").range(lineStart));
    else {
      const d = roleDecoration(role, o);
      if (d && to > from) all.push(d.range(from, to));
    }
  }
  for (const { from, to } of hidden) if (to > from && !widgets.has(`${from}-${to}`)) replace(from, to, hide);
  return { all: Decoration.set(all, true), atomic: Decoration.set(atomic, true) };
}

export function livePreview(o: DecoOptions) {
  const field = StateField.define<Built>({
    create: (state) => buildDecorations(state, o),
    update: (v, tr) =>
      tr.docChanged || tr.selection || tr.effects.some((e) => e.is(refreshEffect)) ? buildDecorations(tr.state, o) : v,
    provide: (f) => [
      EditorView.decorations.from(f, (v) => v.all),
      EditorView.atomicRanges.of((view) => view.state.field(f).atomic),
    ],
  });
  return field;
}
