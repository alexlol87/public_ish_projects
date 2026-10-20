import { MarkdownView, type App, type TFile } from "obsidian";
import type ConstellationPlugin from "./main.ts";
import { endpointAt, endpointRelations, parseNote, resolveLinks, type ParsedNote, type Ref, type Target } from "./relations.ts";

type Entry = { text: string; link: string | null; broken?: boolean };

/** Endpoint/Client section of the panel (ticket 04). Leave `el` empty when there is nothing to show. */
export function renderEndpointSection(el: HTMLElement, plugin: ConstellationPlugin, file: TFile) {
  void render(el, plugin.app, file);
}

async function render(el: HTMLElement, app: App, file: TFile) {
  const isEndpoints = file.name === "endpoints.md" || file.path.startsWith("external/");
  const isClient = app.metadataCache.getFileCache(file)?.frontmatter?.type === "client";
  if (file.extension !== "md" || (!isEndpoints && !isClient)) return;
  const line = isEndpoints ? cursorLine(app, file) : null;
  if (isEndpoints && line === null) return;

  // ponytail: re-parses every Note per render (cachedRead is in memory); cache by mtime if big Vaults lag.
  const files = app.vault.getMarkdownFiles();
  const notes = new Map<string, ParsedNote>(
    await Promise.all(files.map(async (f) => [f.path, parseNote(await app.vault.cachedRead(f))] as [string, ParsedNote])),
  );
  const note = notes.get(file.path);
  if (!note) return;
  const resolve = (target: string, from: string) => app.metadataCache.getFirstLinkpathDest(target, from)?.path ?? null;
  const open = (link: string) => void app.workspace.openLinkText(link, file.path);

  // A heading as written in its Note (backticks kept), so the click lands on it.
  const raw = (path: string, heading: string) =>
    notes.get(path)?.headings.find((h) => h.title.replaceAll("`", "").toLowerCase() === heading.toLowerCase())?.title ?? heading;
  const target = (t: Target): Entry => {
    const text = t.heading ? `${t.target}#${t.heading}` : t.target;
    const link = t.path === null ? null : t.heading ? `${t.path}#${raw(t.path, t.heading)}` : t.path;
    return { text, link, broken: t.broken };
  };
  const ref = (r: Ref): Entry => {
    const name = r.path.replace(/\.md$/, "");
    return r.heading ? { text: `${name}#${r.heading}`, link: `${r.path}#${raw(r.path, r.heading)}` } : { text: name, link: r.path };
  };

  if (isEndpoints) {
    const heading = endpointAt(note, line!);
    if (!heading) return;
    const r = endpointRelations(notes, resolve, file.path, heading);
    el.createEl("h4", { text: heading });
    list(el, "Calls", r.calls.map(target), open);
    list(el, "Called by", r.calledBy.map(ref), open);
    list(el, "Used by clients", r.usedBy.map(ref), open);
  } else {
    list(el, "Uses", resolveLinks(notes, resolve, file.path, note.uses).map(target), open);
  }
}

/** Cursor line in the editor showing `file`; the panel itself may hold focus, so fall back to any leaf with it open. */
function cursorLine(app: App, file: TFile): number | null {
  const active = app.workspace.getActiveViewOfType(MarkdownView);
  const view =
    active?.file?.path === file.path
      ? active
      : app.workspace
          .getLeavesOfType("markdown")
          .map((l) => l.view)
          .find((v): v is MarkdownView => v instanceof MarkdownView && v.file?.path === file.path);
  return view ? view.editor.getCursor().line : null;
}

function list(el: HTMLElement, title: string, entries: Entry[], open: (link: string) => void) {
  el.createEl("h5", { text: title });
  if (!entries.length) {
    el.createEl("p", { text: "none", cls: "constellation-none" });
    return;
  }
  const ul = el.createEl("ul");
  for (const e of entries) {
    const li = ul.createEl("li");
    const a = li.createEl("a", { text: e.text, cls: e.broken ? "internal-link is-unresolved" : "internal-link" });
    if (e.broken) li.createSpan({ text: " (broken)", cls: "constellation-broken-label" });
    const link = e.link;
    if (link) a.addEventListener("click", (ev) => (ev.preventDefault(), open(link)));
  }
}
