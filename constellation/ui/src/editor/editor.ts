import { autocompletion, type Completion, type CompletionContext } from "@codemirror/autocomplete";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { EditorState, Prec, type TransactionSpec } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { applyFormat, type FormatAction } from "../lib/formatActions";
import { typedTagPrefix } from "../lib/styler";
import { livePreview, refreshEffect } from "./decorations";
import "./editor.css";

export interface EditorOptions {
  doc: string;
  /** Called with the full text after every user edit (typing, format actions), not after `setDoc`. */
  onChange?(doc: string): void;
  /** A task checkbox was clicked; `offset` is where its `[ ]` starts. The backend moves the item to the archive. */
  onTickTask?(offset: number): void;
  /** Mod-click on a link (Mod-Shift-click: `newTab`). `target` is `path[#heading]` or a URL. */
  onOpenLink?(target: string, newTab: boolean): void;
  /** Mod-click on a `#tag`; `tag` has no `#`. */
  onTagClick?(tag: string): void;
  resolveImage?(path: string): string;
  /** Candidates for `[[typed`. */
  linkCompletions?(typed: string): Promise<string[]>;
  /** Tag names (no `#`) for `#prefix`. */
  tagCompletions?(prefix: string): Promise<string[]>;
  isBrokenLink?(target: string): boolean;
}

export interface Editor {
  view: EditorView;
  /** Replaces the document and resets undo history (opening a Note, reloading from disk). Keeps the cursor if possible. */
  setDoc(doc: string): void;
  getDoc(): string;
  applyFormat(action: FormatAction): void;
  focus(): void;
  destroy(): void;
  /** Re-evaluates broken links etc. after the Vault changed. */
  refreshDecorations(): void;
}

/** Shortcuts from PLAN §6.2; Mod is ⌘ on macOS, Ctrl elsewhere. */
export const formatKeys: Record<string, FormatAction> = {
  "Mod-b": "bold", "Mod-i": "italic", "Mod-u": "underline", "Mod-Shift-x": "strikethrough", "Mod-e": "inlineCode",
  "Mod-Alt-c": "codeBlock", "Mod-1": "heading1", "Mod-2": "heading2", "Mod-3": "heading3",
  "Mod-Shift-8": "bulletList", "Mod-Shift-7": "numberedList", "Mod-Shift-9": "taskList", "Mod-Shift-.": "quote", "Mod-k": "link",
};

/** The format as one transaction with a minimal change, so a single undo reverts it and the cursor stays put. */
export function formatTransaction(state: EditorState, action: FormatAction): TransactionSpec {
  const old = state.doc.toString();
  const { from, to } = state.selection.main;
  const next = applyFormat(action, old, { from, to });
  let a = 0;
  while (a < old.length && a < next.text.length && old[a] === next.text[a]) a++;
  let b = 0;
  while (b < old.length - a && b < next.text.length - a && old[old.length - 1 - b] === next.text[next.text.length - 1 - b]) b++;
  return {
    changes: { from: a, to: old.length - b, insert: next.text.slice(a, next.text.length - b) },
    selection: { anchor: next.selection.from, head: next.selection.to },
    userEvent: "input.format",
    scrollIntoView: true,
  };
}

export function createEditor(parent: HTMLElement, opts: EditorOptions): Editor {
  const isMac = /Mac|iPhone|iPad/.test(navigator.platform);

  const linkSource = async (ctx: CompletionContext) => {
    const m = ctx.matchBefore(/\[\[[^\]\n]*/);
    if (!m || !opts.linkCompletions) return null;
    const from = m.from + 2;
    const items = await opts.linkCompletions(m.text.slice(2));
    return {
      from,
      filter: false,
      options: items.map((label): Completion => ({
        label,
        apply: (view, _c, f, t) => {
          const close = view.state.sliceDoc(t, t + 2) === "]]";
          view.dispatch({ changes: { from: f, to: t, insert: close ? label : label + "]]" }, selection: { anchor: f + label.length + 2 }, userEvent: "input.complete" });
        },
      })),
    };
  };
  const tagSource = async (ctx: CompletionContext) => {
    const line = ctx.state.doc.lineAt(ctx.pos);
    const prefix = typedTagPrefix(line.text.slice(0, ctx.pos - line.from));
    if (prefix === null || !opts.tagCompletions) return null;
    return { from: ctx.pos - prefix.length, filter: false, options: (await opts.tagCompletions(prefix)).map((label) => ({ label })) };
  };

  const extensions = [
    history(),
    EditorView.lineWrapping,
    livePreview({
      resolveImage: opts.resolveImage ?? ((p) => p),
      isBrokenLink: opts.isBrokenLink ?? (() => false),
      onTickTask: opts.onTickTask ?? (() => {}),
    }),
    autocompletion({ override: [linkSource, tagSource], icons: false }),
    Prec.high(keymap.of(Object.entries(formatKeys).map(([key, action]) => ({
      key, preventDefault: true, run: (v: EditorView) => (v.dispatch(formatTransaction(v.state, action)), true),
    })))),
    keymap.of([...defaultKeymap, ...historyKeymap]),
    EditorView.domEventHandlers({
      mousedown(e) {
        if (!(isMac ? e.metaKey : e.ctrlKey) || !(e.target instanceof Element)) return false;
        const link = e.target.closest("[data-link]"), tag = e.target.closest("[data-tag]");
        if (link) opts.onOpenLink?.(link.getAttribute("data-link")!, e.shiftKey);
        else if (tag) opts.onTagClick?.(tag.getAttribute("data-tag")!);
        else return false;
        e.preventDefault();
        return true;
      },
    }),
    EditorView.updateListener.of((u) => u.docChanged && opts.onChange?.(u.state.doc.toString())),
  ];

  const view = new EditorView({ parent, state: EditorState.create({ doc: opts.doc, extensions }) });
  return {
    view,
    setDoc(doc) {
      const anchor = Math.min(view.state.selection.main.anchor, doc.length);
      view.setState(EditorState.create({ doc, selection: { anchor }, extensions }));
    },
    getDoc: () => view.state.doc.toString(),
    applyFormat: (action) => view.dispatch(formatTransaction(view.state, action)),
    focus: () => view.focus(),
    destroy: () => view.destroy(),
    refreshDecorations: () => view.dispatch({ effects: refreshEffect.of(null) }),
  };
}
