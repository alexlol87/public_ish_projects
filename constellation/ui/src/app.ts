import { emit, listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { api, baseName, errText, type Inspect, type SearchResults, type TagNode, type VaultNode } from "./api";
import { createEditor, type Editor } from "./editor/editor";
import type { FormatAction } from "./lib/formatActions";
import { NoteTabs } from "./lib/noteTabs";
import { applyTheme, THEME_CHOICES, watchSystemTheme, type ThemeChoice } from "./lib/themes";
import { ask, contextMenu, h, modal, toast } from "./ui";

const isMac = /Mac|iPhone|iPad/.test(navigator.platform);
const mod = (e: KeyboardEvent) => (isMac ? e.metaKey : e.ctrlKey);

const tabs = new NoteTabs();
let editor: Editor;
let shown: { path: string; revision: number } | null = null;
let broken = new Set<string>();
let theme: ThemeChoice = "System";
let lastEditAt = 0;
let appActionAt = 0;
let sideTab: "files" | "tags" = "files";
let tagSort: "name" | "count" = "name";
let tagView: string | null = null;
let query = "";
const expanded = new Set<string>([""]);
let tree: VaultNode | null = null;
let rootPath = "";

const P = {} as Record<"top" | "side" | "tabbar" | "toolbar" | "banner" | "editor" | "inspector" | "undo", HTMLElement> & { search: HTMLInputElement; results: HTMLElement; list: HTMLElement };

// ---------- boot ----------

export async function boot(app: HTMLElement) {
  const stored = await api.getSettings();
  theme = (THEME_CHOICES as readonly string[]).includes(stored.theme) ? (stored.theme as ThemeChoice) : "System";
  applyTheme(theme);
  watchSystemTheme(() => theme === "System" && applyTheme(theme));
  const root = await api.startup().catch(() => null);
  if (root) await start(app, root);
  else welcome(app);
}

function welcome(app: HTMLElement) {
  const msg = h("p", { class: "muted" }, "");
  const go = async (create: boolean) => {
    const dir = await api.pickFolder();
    if (!dir) return;
    try {
      const root = create ? await api.createVault(dir) : await api.openVault(dir);
      await start(app, root);
    } catch (e) { msg.textContent = errText(e); msg.classList.add("bad"); }
  };
  app.replaceChildren(h("div", { class: "welcome" },
    h("h1", {}, "Constellation"),
    h("p", { class: "muted" }, "A vault of linked markdown notes about your projects, repos and endpoints."),
    h("div", { class: "row" },
      h("button", { class: "primary", id: "create-vault", onclick: () => go(true) }, "Create vault…"),
      h("button", { id: "open-vault", onclick: () => go(false) }, "Open vault…")),
    h("p", { class: "muted small" }, "Create needs an empty folder (the folder dialog can make a new one)."),
    msg));
}

async function start(app: HTMLElement, root: string) {
  rootPath = root;
  const s = await api.getSettings();
  theme = s.theme as ThemeChoice;
  applyTheme(theme);
  buildLayout(app);
  await refreshAll();
  await listen<{ paths: string[]; own: boolean }>("vault-changed", (e) => onVaultChanged(e.payload.paths, e.payload.own));
  await listen<string>("open-note", (e) => void openNote(e.payload));
  await listen("settings-changed", () => void reloadSettings());
  setInterval(autosave, 250);
  // Unsaved edits are written before the window goes away (the close proceeds once this resolves).
  await getCurrentWindow().onCloseRequested(async (e) => {
    await flushAll();
    if (tabs.hasPendingEdits && (await api.wasTerminated())) {
      // Killed by a signal with text that can't be saved: no time to ask, keep a copy.
      for (const p of tabs.paths.filter((p) => tabs.unsaved(p))) await api.saveRecovery(p, tabs.text(p) ?? "").catch(() => {});
      return;
    }
    if (tabs.hasConflicts || tabs.hasPendingEdits) {
      const choice = await closeChoice();
      if (choice === "cancel") return e.preventDefault();
      if (choice === "keep") {
        for (const p of tabs.paths) if (tabs.conflict(p) !== undefined) await keepMine(p);
        await flushAll();
        if (tabs.hasPendingEdits) { // still not saved (e.g. read-only): do not lose it, and say why
          toast(tabs.paths.filter((p) => tabs.unsaved(p)).map((p) => lastSaveError.get(p) ?? `${p}: not saved`).join("; "), true);
          return e.preventDefault();
        }
      }
    }
  });
  addEventListener("blur", () => void flushAll());
  document.addEventListener("visibilitychange", () => document.hidden && void flushAll());
  document.addEventListener("keydown", onKey, true);
  const readme = tree?.children.find((c) => !c.isFolder && c.name.toLowerCase() === "readme.md");
  if (readme) await openNote(readme.relativePath);
  const rec = await api.recoveryFiles();
  if (rec.length) toast(`Unsaved text from the last session was kept in ${rec.join(", ")}`, true);
}

async function reloadSettings() {
  theme = (await api.getSettings()).theme as ThemeChoice;
  applyTheme(theme);
  void refreshInspector();
}

// ---------- layout ----------

const FORMATS: [FormatAction, string, string][] = [
  ["bold", "B", "Bold"], ["italic", "I", "Italic"], ["underline", "U", "Underline"], ["strikethrough", "S", "Strikethrough"],
  ["inlineCode", "`", "Inline code"], ["codeBlock", "{ }", "Code block"], ["heading1", "H1", "Heading 1"],
  ["heading2", "H2", "Heading 2"], ["heading3", "H3", "Heading 3"], ["bulletList", "•", "Bullet list"],
  ["numberedList", "1.", "Numbered list"], ["taskList", "☑", "Task list"], ["quote", "❝", "Quote"], ["link", "[[ ]]", "Link"],
  ["table", "▦", "Table"],
];

function buildLayout(app: HTMLElement) {
  P.undo = h("button", { id: "undo", title: `Undo last rename/move/Todo item/new note (${isMac ? "⌘" : "Ctrl+"}Z outside typing)`, disabled: true, onclick: () => void undo() }, "Undo");
  P.top = h("div", { class: "topbar" }, h("strong", {}, "Constellation"), h("span", { class: "muted vault-name", title: rootPath }, baseName(rootPath) || rootPath),
    h("span", { class: "grow" }), P.undo,
    h("button", { id: "open-graph", title: `Graph (${isMac ? "⌘" : "Ctrl+"}G)`, onclick: () => void api.openGraph() }, "Graph"),
    h("button", { id: "open-help", title: "Help (F1)", onclick: () => void openHelp() }, "Help"),
    h("button", { id: "open-settings", title: "Settings", onclick: () => void settings() }, "Settings"));
  P.search = h("input", { type: "search", id: "search", placeholder: "Search folders, notes, text, #tag", class: "wide" });
  let timer: number;
  P.search.addEventListener("input", () => { clearTimeout(timer); timer = window.setTimeout(() => { query = P.search.value.trim(); void renderSide(); }, 120); });
  P.list = h("div", { class: "list" });
  P.results = h("div", { class: "list", hidden: true });
  P.side = h("div", { class: "side" },
    h("button", { id: "new-note", title: `New note (${isMac ? "⌘" : "Ctrl+"}N)`, onclick: () => void newNote() }, "New note"),
    P.search,
    h("div", { class: "seg" },
      h("button", { id: "tab-files", onclick: () => { sideTab = "files"; tagView = null; void renderSide(); } }, "Files"),
      h("button", { id: "tab-tags", onclick: () => { sideTab = "tags"; tagView = null; void renderSide(); } }, "Tags")),
    P.list, P.results);
  P.tabbar = h("div", { class: "tabbar" });
  P.toolbar = h("div", { class: "toolbar" }, ...FORMATS.map(([a, label, title]) =>
    h("button", { title, class: `fmt fmt-${a}`, onmousedown: (e: Event) => e.preventDefault(), onclick: () => { editor.applyFormat(a); editor.focus(); } }, label)));
  P.banner = h("div", { class: "banner", hidden: true });
  P.editor = h("div", { class: "editor-host", id: "editor" });
  const main = h("div", { class: "main" }, P.tabbar, P.toolbar, P.banner, P.editor);
  P.inspector = h("div", { class: "inspector", id: "inspector" });
  app.replaceChildren(P.top, h("div", { class: "panes" }, P.side, main, P.inspector));

  editor = createEditor(P.editor, {
    doc: "",
    onChange: (doc) => {
      if (!tabs.active) return;
      lastEditAt = Date.now();
      tabs.edit(tabs.active, doc);
      scheduleSoft();
    },
    onSelection: () => scheduleInspector(),
    onTickTask: (offset) => void tickTask(offset),
    onOpenLink: (t, newTab) => void openLink(t, newTab),
    onTagClick: (tag) => { sideTab = "tags"; tagView = tag; void renderSide(); },
    resolveImage: (p) => `vaultimg://localhost/?note=${encodeURIComponent(tabs.active ?? "")}&path=${encodeURIComponent(p)}`,
    linkCompletions: (typed) => api.linkCompletions(typed),
    tagCompletions: (prefix) => api.tagCompletions(prefix),
    isBrokenLink: (t) => broken.has(t.split("#")[0].trim()),
  });
}

// ---------- notes and tabs ----------

async function openNote(path: string, at?: { offset?: number; heading?: string }) {
  try {
    if (!tabs.paths.includes(path)) tabs.open(path, await api.readNote(path));
    else tabs.active = path;
  } catch (e) { toast(errText(e), true); return; }
  showActive();
  const text = tabs.text(path) ?? "";
  let offset = at?.offset;
  if (offset === undefined && at?.heading) offset = headingOffset(text, at.heading);
  if (offset !== undefined) {
    const o = Math.min(offset, text.length);
    editor.view.dispatch({ selection: { anchor: o }, scrollIntoView: true });
    editor.focus();
  }
  void refreshInspector();
}

function headingOffset(text: string, title: string): number | undefined {
  const want = title.replace(/`/g, "").trim().toLowerCase();
  let pos = 0;
  for (const line of text.split("\n")) {
    const m = /^#{1,6} +(.*?) *$/.exec(line);
    if (m && m[1].replace(/`/g, "").trim().toLowerCase() === want) return pos;
    pos += line.length + 1;
  }
}

function showActive() {
  const p = tabs.active;
  renderTabs();
  void api.setCurrent(p);
  P.editor.style.visibility = p ? "visible" : "hidden";
  P.toolbar.classList.toggle("off", !p);
  if (!p) { shown = null; renderBanner(); return; }
  const rev = tabs.revision(p);
  if (!shown || shown.path !== p || shown.revision !== rev) {
    editor.setDoc(tabs.text(p) ?? "", p);
    shown = { path: p, revision: rev };
  }
  renderBanner();
  void refreshBroken();
}

function renderTabs() {
  const names = tabs.paths.map(baseName);
  const label = (p: string) => (names.filter((n) => n === baseName(p)).length > 1 ? p.split("/").slice(-2).join("/").replace(/\.md$/i, "") : baseName(p));
  P.tabbar.replaceChildren(...tabs.paths.map((p) =>
    h("div", { class: "tab" + (p === tabs.active ? " active" : "") + (tabs.conflict(p) !== undefined ? " conflict" : ""), title: p, onclick: () => { tabs.active = p; showActive(); void refreshInspector(); } },
      h("span", {}, label(p) + (tabs.conflict(p) !== undefined ? " !" : tabs.pending().includes(p) ? " •" : "")),
      h("span", { class: "x", onclick: (e: Event) => { e.stopPropagation(); void closeTab(p); } }, "×"))));
  P.tabbar.querySelector(".tab.active")?.scrollIntoView({ block: "nearest", inline: "nearest" });
}

async function closeTab(p: string) {
  if (tabs.conflict(p) !== undefined) { toast("Resolve the conflict first (Reload from disk or Keep mine)", true); return; }
  if (tabs.unsaved(p)) await save(p);
  if (tabs.unsaved(p)) { // the write failed (e.g. read-only): never drop the text silently
    const choice = await closeChoice();
    if (choice === "cancel") return;
    if (choice === "keep") {
      await save(p);
      if (tabs.unsaved(p)) { toast(lastSaveError.get(p) ?? "Could not save", true); return; }
    } else tabs.discard(p);
  }
  tabs.close(p);
  showActive();
  editor.forget(p);
  void refreshInspector();
}

function renderBanner() {
  const p = tabs.active;
  const disk = p ? tabs.conflict(p) : undefined;
  P.banner.hidden = disk === undefined;
  if (disk === undefined || !p) return;
  if (disk === null) {
    P.banner.replaceChildren(h("span", {}, "This note was deleted or moved on disk while you had unsaved edits. "),
      h("button", { id: "keep-mine", onclick: () => void keepMine(p) }, "Re-create here"),
      h("button", { id: "reload-disk", onclick: () => { tabs.discard(p); showActive(); editor.forget(p); } }, "Discard"));
    return;
  }
  P.banner.replaceChildren(h("span", {}, "This note changed on disk while you had unsaved edits. "),
    h("button", { id: "reload-disk", onclick: () => { tabs.resolveConflict(p, true); showActive(); } }, "Reload from disk"),
    h("button", { id: "keep-mine", onclick: () => void keepMine(p) }, "Keep mine"));
}

async function keepMine(p: string) {
  const mine = tabs.resolveConflict(p, false);
  if (mine !== undefined) { await save(p); }
  showActive();
}

const lastSaveError = new Map<string, string>();

async function save(p: string) {
  const text = tabs.text(p);
  if (text === undefined) return;
  try { await api.writeNote(p, text); tabs.saved(p, text); lastSaveError.delete(p); } catch (e) {
    // The same failure on every autosave tick is shown once, until it changes or the save works.
    const msg = errText(e);
    if (lastSaveError.get(p) !== msg) toast(msg, true);
    lastSaveError.set(p, msg);
  }
}

async function autosave() {
  const due = tabs.due();
  for (const p of due) await save(p);
  if (due.length) renderTabs();
}

/** Unsaved or conflicted text at window close: write mine, throw it away, or stay. */
async function closeChoice(): Promise<"keep" | "discard" | "cancel"> {
  let out: "keep" | "discard" | "cancel" = "cancel";
  await modal("Unsaved changes", (close) => {
    const pick = (c: typeof out) => () => { out = c; close(); };
    return h("div", {}, h("p", {}, "Some notes have text that is not saved (a conflict with the file on disk, or the file could not be written)."),
      h("div", { class: "row end" },
        h("button", { id: "close-cancel", onclick: pick("cancel") }, "Cancel"),
        h("button", { id: "close-reload", onclick: pick("discard") }, "Reload (discard mine)"),
        h("button", { id: "close-keep", class: "primary", onclick: pick("keep") }, "Keep mine")));
  });
  return out;
}

async function flushAll() {
  for (const p of tabs.pending()) await save(p);
  renderTabs();
}

async function openLink(target: string, _newTab: boolean) {
  if (/^[a-z]+:\/\//i.test(target)) return;
  const [path, heading] = [target.split("#")[0].trim(), target.includes("#") ? target.slice(target.indexOf("#") + 1) : undefined];
  try {
    const r = await api.resolve(path);
    if (r.kind === "note") return void (await openNote(r.path, { heading }));
    const created = await api.createNote(path);
    appActionAt = Date.now();
    await openNote(created);
  } catch (e) { toast(errText(e), true); }
}

let ticking = false;
async function tickTask(offset: number) {
  const p = tabs.active;
  if (!p || ticking) return;
  ticking = true;
  try {
    await flushAll();
    await api.tick(p, tabs.text(p) ?? "", offset);
    appActionAt = Date.now();
  } catch (e) { toast(errText(e), true); }
  finally { setTimeout(() => (ticking = false), 400); } // the next item slides under the cursor: swallow a double-click
}

// ---------- vault changes ----------

let inspectTimer: number;
function scheduleInspector() {
  clearTimeout(inspectTimer);
  inspectTimer = window.setTimeout(() => void refreshInspector(), 120);
}

let softTimer: number;
function scheduleSoft() {
  clearTimeout(softTimer);
  softTimer = window.setTimeout(() => { void refreshBroken(); void refreshInspector(); }, 300);
}

let changeTimer: number;
const pendingPaths = new Set<string>();
let pendingOwn = true;
function onVaultChanged(paths: string[], own: boolean) {
  paths.forEach((p) => pendingPaths.add(p));
  pendingOwn &&= own;
  clearTimeout(changeTimer);
  changeTimer = window.setTimeout(async () => {
    const touched = [...pendingPaths], wasOwn = pendingOwn;
    pendingPaths.clear(); pendingOwn = true;
    if (!wasOwn) await syncTabs(touched);
    await refreshAll();
    showActive();
  }, 80);
}

/** Open Notes touched by something other than our autosave: reload silently if clean, conflict if dirty. */
async function syncTabs(touched: string[]) {
  for (const p of tabs.paths.slice()) {
    if (!touched.some((t) => t === p || p.startsWith(t + "/"))) continue;
    try { tabs.diskChanged(p, await api.readNote(p)); }
    catch { tabs.diskGone(p); } // deleted or moved away
  }
}

async function refreshAll() {
  tree = await api.tree();
  await renderSide();
  renderTabs();
  void refreshInspector();
  void refreshBroken();
  void api.undoDepth().then((n) => (P.undo as HTMLButtonElement).disabled = n === 0);
}

async function refreshBroken() {
  const p = tabs.active;
  if (!p) return;
  const t = tabs.text(p) ?? "";
  const next = new Set(await api.brokenTargets(t).catch(() => []));
  const same = next.size === broken.size && [...next].every((x) => broken.has(x)); // a full restyle of a big Note is slow
  broken = next;
  if (tabs.active === p && !same) editor.refreshDecorations();
}

async function undo() {
  await flushAll();
  try {
    if (await api.undo()) { appActionAt = Date.now(); toast("Undone"); }
  } catch (e) {
    toast(errText(e), true);
    void api.undoDepth().then((n) => (P.undo as HTMLButtonElement).disabled = n === 0); // the refused step was dropped
  }
}

// ---------- sidebar ----------

async function renderSide() {
  byId("tab-files").classList.toggle("on", sideTab === "files");
  byId("tab-tags").classList.toggle("on", sideTab === "tags");
  const searching = query !== "";
  P.results.hidden = !searching;
  P.list.hidden = searching;
  if (searching) return renderResults(await api.search(query));
  if (sideTab === "files") P.list.replaceChildren(...(tree ? renderTree(tree, 0) : []));
  else if (tagView) await renderTagHits(tagView);
  else await renderTags();
}

const byId = (id: string) => document.getElementById(id)!;

function renderTree(n: VaultNode, depth: number): HTMLElement[] {
  const out: HTMLElement[] = [];
  for (const c of n.children) {
    const open = expanded.has(c.relativePath);
    const row = h("div", {
      class: "row-item" + (c.isFolder ? " folder" : "") + (c.appOnly ? " dim" : "") + (c.relativePath === tabs.active ? " active" : ""), style: `padding-left:${8 + depth * 14}px`, title: c.relativePath,
      onclick: () => {
        if (!c.isFolder) return void openNote(c.relativePath);
        if (expanded.has(c.relativePath)) expanded.delete(c.relativePath); else expanded.add(c.relativePath);
        const readme = c.children.find((k) => !k.isFolder && k.name.toLowerCase() === "readme.md");
        if (readme && !c.appOnly) void openNote(readme.relativePath);
        void renderSide();
      },
      oncontextmenu: (e: MouseEvent) => !c.appOnly && contextMenu(e, [c.isFolder ? ["New note here…", () => void newNote(c.relativePath)] : ["Rename / move…", () => void renameNote(c.relativePath)]]),
    }, h("span", { class: "chev" }, c.isFolder ? (open ? "▾" : "▸") : ""), c.name);
    out.push(row);
    if (c.isFolder && open) out.push(...renderTree(c, depth + 1));
  }
  return out;
}

const isAppOnly = (p: string) => p.startsWith(".") || !!tree?.children.find((c) => c.name === p.split("/")[0])?.appOnly;
const dirName = (p: string) => p.split("/").slice(0, -1).join("/");

/** Opens every folder above `path` in the tree. */
function expandAncestors(path: string) {
  for (let d = dirName(path); d; d = dirName(d)) expanded.add(d);
}

/** Prompts for a path pre-filled with `folder` (else the active Note's folder, or the Vault root for app-only ones), creates the empty Note and opens it. */
async function newNote(folder = tabs.active && !isAppOnly(tabs.active) ? dirName(tabs.active) : "") {
  let typed = folder ? `${folder}/` : "";
  for (;;) {
    const path = await ask("New note", typed, "Folder and name. Folders are created as needed; .md is added.");
    if (!path) return;
    await flushAll();
    try {
      const np = await api.newNote(path);
      appActionAt = Date.now();
      expandAncestors(np);
      await openNote(np);
      editor.focus();
      return;
    } catch (e) {
      const msg = errText(e);
      toast(msg.includes("File name too long") ? "That name is too long for the file system. Shorten it." : msg, true);
      typed = path; // ask again with what was typed
    }
  }
}

async function openHelp() {
  try {
    const p = await api.openCheatSheet();
    await refreshAll(); // first Help creates .constellation/
    tabs.reload(p, await api.readNote(p)); // an open tab may hold stale or edited text
    await openNote(p);
  } catch (e) { toast(errText(e), true); }
}

async function renameNote(path: string) {
  const to = await ask("Rename or move note", path, "Change the file name, or the folder (not both). Links are rewritten.");
  if (!to || to === path) return;
  await flushAll();
  if (tabs.unsaved(path)) { toast(`${path} has text that could not be saved. Save or discard it first (close the tab), then rename.`, true); return; }
  try {
    const np = await api.renameNote(path, to);
    appActionAt = Date.now();
    if (tabs.paths.includes(path)) { tabs.close(path); }
    await openNote(np);
  } catch (e) { toast(errText(e), true); }
}

function renderResults(r: SearchResults) {
  const arch = new Set(r.archived);
  const label = (p: string) => (arch.has(p) ? [h("span", { class: "badge" }, "archived")] : []);
  const sec = (title: string, n: number, rows: HTMLElement[]) => n ? [h("div", { class: "sec" }, `${title} (${n})`), ...rows] : [];
  const readme = (f: string) => `${f}/README.md`;
  P.results.replaceChildren(
    ...sec("Folders", r.folders.length, r.folders.map((f) => h("div", { class: "row-item folder", onclick: () => void openNote(readme(f)) }, f))),
    ...sec("Notes", r.notes.length, r.notes.map((p) => h("div", { class: "row-item", onclick: () => void openNote(p) }, p, ...label(p)))),
    ...sec("Text matches", r.matches.length, r.matches.map((m) => {
      const { location: a, length: l } = m.hit, s = m.sentence;
      return h("div", { class: "row-item match", onclick: () => void openNote(m.path, { offset: m.offset }) },
        h("div", { class: "muted small" }, m.path, ...label(m.path)),
        h("div", {}, s.slice(0, a), h("mark", {}, s.slice(a, a + l)), s.slice(a + l)));
    })));
  if (!r.folders.length && !r.notes.length && !r.matches.length) P.results.replaceChildren(h("div", { class: "muted pad" }, "No results"));
}

async function renderTags() {
  const nodes = await api.tagTree(tagSort);
  const row = (n: TagNode, d: number): HTMLElement[] => [
    h("div", {
      class: "row-item", style: `padding-left:${8 + d * 14}px`, onclick: () => { tagView = n.tag; void renderSide(); },
      oncontextmenu: (e: MouseEvent) => contextMenu(e, [["Rename tag…", () => void renameTag(n.tag)]]),
    }, h("span", {}, "#" + n.name), h("span", { class: "count" }, String(n.count))),
    ...n.children.flatMap((c) => row(c, d + 1)),
  ];
  const sel = h("select", { id: "tag-sort", onchange: (e: Event) => { tagSort = (e.target as HTMLSelectElement).value as "name" | "count"; void renderSide(); } },
    h("option", { value: "name", selected: tagSort === "name" }, "Sort by name"), h("option", { value: "count", selected: tagSort === "count" }, "Sort by count"));
  P.list.replaceChildren(h("div", { class: "pad" }, sel), ...nodes.flatMap((n) => row(n, 0)),
    ...(nodes.length ? [] : [h("div", { class: "muted pad" }, "No tags yet. Write #tag in a note.")]));
}

async function renderTagHits(tag: string) {
  const hits = await api.tagHits(tag);
  P.list.replaceChildren(h("div", { class: "pad" }, h("button", { onclick: () => { tagView = null; void renderSide(); } }, "← Tags"), " ", h("strong", {}, "#" + tag)),
    ...hits.map((x) => h("div", { class: "row-item match", onclick: () => void openNote(x.path, { offset: x.offset }) },
      h("div", { class: "muted small" }, x.path), h("div", {}, x.line.trim()))));
}

async function renameTag(tag: string) {
  const to = await ask(`Rename tag #${tag}`, tag, "Rewrites the tag (and its children) in every note.");
  if (!to || to === tag) return;
  await flushAll();
  try { await api.renameTag(tag, to.replace(/^#/, "")); appActionAt = Date.now(); } catch (e) { toast(errText(e), true); }
}

// ---------- inspector ----------

let inspectSeq = 0;
async function refreshInspector() {
  const p = tabs.active, seq = ++inspectSeq;
  if (!p) return void P.inspector.replaceChildren(h("div", { class: "muted pad" }, "Open a note"));
  const text = tabs.text(p) ?? "";
  let r: Inspect;
  try { r = await api.inspect(p, text, editor.view.state.selection.main.head); } catch { return; }
  if (seq !== inspectSeq) return;
  const sec = (t: string, ...k: (HTMLElement | false)[]) => h("div", { class: "isec" }, h("div", { class: "sec" }, t), ...(k.filter(Boolean) as HTMLElement[]));
  const ref = (path: string, heading?: string) => h("div", { class: "row-item", title: path, onclick: () => void openNote(path, { heading }) }, baseName(path) + (heading ? " › " + heading : ""));
  const parts: HTMLElement[] = [];
  if (r.repo) {
    const repo = r.repo;
    parts.push(sec("Repo " + repo.name,
      h("div", { class: "staleness" + (repo.stale ? " stale" : ""), id: "staleness" }, repo.label),
      h("div", { class: "row pad" },
        h("button", { id: "copy-ingest", onclick: () => void copyPrompt("ingest", repo.name) }, "Copy ingest prompt"),
        h("button", { id: "copy-refresh", onclick: () => void copyPrompt("refresh", repo.name) }, "Copy refresh prompt"))));
  }
  if (r.endpoint && r.relations) {
    const q = r.relations;
    const list = (title: string, items: { path: string; heading?: string }[]) => sec(title, ...(items.length ? items.map((i) => ref(i.path, i.heading)) : [h("div", { class: "muted pad small" }, "none")]));
    parts.push(h("div", { class: "isec" }, h("div", { class: "sec" }, "Endpoint"), h("div", { class: "pad endpoint" }, r.endpoint.replace(/`/g, ""))),
      list("Calls", q.callsOut), list("Called by", q.callsIn), list("Used by clients", q.usesIn));
  }
  parts.push(sec(`Backlinks (${r.backlinks.length})`, ...(r.backlinks.length ? r.backlinks.map((b) =>
    h("div", { class: "row-item", title: b.path, onclick: () => void openNote(b.path, { offset: b.link.range.location }) }, baseName(b.path),
      b.path.includes("/") && h("span", { class: "muted small" }, "  " + b.path.slice(0, b.path.lastIndexOf("/"))))) : [h("div", { class: "muted pad small" }, "none")])));
  parts.push(sec("Outline", ...(r.headings.length ? r.headings.map((hd) =>
    h("div", {
      class: "row-item", style: `padding-left:${8 + (hd.level - 1) * 12}px`,
      onclick: () => { editor.view.dispatch({ selection: { anchor: Math.min(hd.range.location, editor.view.state.doc.length) }, scrollIntoView: true }); editor.focus(); },
      oncontextmenu: (e: MouseEvent) => contextMenu(e, [["Rename heading…", () => void renameHeading(p, hd.title)]]),
    }, hd.title)) : [h("div", { class: "muted pad small" }, "no headings")])));
  P.inspector.replaceChildren(...parts);
}

async function copyPrompt(kind: "ingest" | "refresh", repo: string) {
  try { await api.copyText(await api.prompt(kind, repo)); toast(`Copied ${kind} prompt`); } catch (e) { toast(errText(e), true); }
}

async function renameHeading(path: string, title: string) {
  const to = await ask("Rename heading", title, "Links to this heading are rewritten.");
  if (!to || to === title) return;
  await flushAll();
  try { await api.renameHeading(path, title, to); appActionAt = Date.now(); } catch (e) { toast(errText(e), true); }
}

// ---------- settings and keys ----------

async function settings() {
  const s = await api.getSettings();
  await modal("Settings", (close) => {
    const sel = h("select", { id: "set-theme" }, ...THEME_CHOICES.map((t) => h("option", { value: t, selected: t === s.theme }, t)));
    const days = h("input", { type: "number", id: "set-days", min: 1, value: String(s.stalenessDays) });
    const err = h("div", { class: "bad small", id: "set-error" }, "");
    const switchVault = async (create: boolean) => {
      const dir = await api.pickFolder();
      if (!dir) return;
      await flushAll();
      if (tabs.hasPendingEdits) return void toast("Resolve the conflict first (Reload from disk or Keep mine)", true);
      try { await (create ? api.createVault(dir) : api.openVault(dir)); } catch (e) { return void toast(errText(e), true); }
      location.reload(); // fresh tabs, undo and listeners for the new Vault
    };
    return h("div", {}, h("label", {}, "Theme ", sel), h("br", {}), h("br", {}),
      h("label", {}, "Highlight repos not verified for ", days, " days"), err,
      h("div", { class: "row pad" },
        h("button", { id: "switch-open", onclick: () => void switchVault(false) }, "Open another vault…"),
        h("button", { id: "switch-create", onclick: () => void switchVault(true) }, "Create vault…")),
      h("div", { class: "row end" }, h("button", { onclick: close }, "Cancel"),
        h("button", { class: "primary", id: "set-save", onclick: async () => {
          const n = Number(days.value);
          if (!days.value.trim() || !Number.isInteger(n) || n < 1 || n > 36500) { err.textContent = "Days must be a whole number from 1 to 36500."; return; }
          try {
            await api.setSettings({ theme: sel.value, stalenessDays: n });
            theme = sel.value as ThemeChoice; applyTheme(theme);
            await emit("settings-changed");
            void refreshInspector();
          } catch (e) { err.textContent = errText(e); return; } // stay open to fix it
          close();
        } }, "Save")));
  });
}

function onKey(e: KeyboardEvent) {
  if (document.querySelector(".modal-back")) return; // a prompt is open: the app shortcuts wait
  const k = e.key.toLowerCase();
  if (e.key === "F1") { e.preventDefault(); void openHelp(); return; }
  if (!mod(e)) return;
  const t = e.target as HTMLElement;
  const inEditor = !!t.closest?.(".cm-editor");
  const inField = t instanceof HTMLInputElement || t instanceof HTMLTextAreaElement || t instanceof HTMLSelectElement;
  if (k === "g" && !e.shiftKey) { e.preventDefault(); void api.openGraph(); }
  else if (k === "n" && !e.shiftKey) { e.preventDefault(); void newNote(); }
  else if (k === "," ) { e.preventDefault(); void settings(); }
  else if (k === "s") { e.preventDefault(); void flushAll(); }
  else if (k === "w") { e.preventDefault(); if (tabs.active) void closeTab(tabs.active); }
  else if (k === "f" && e.shiftKey) { e.preventDefault(); P.search.focus(); }
  else if (k === "z" && !e.shiftKey && !inField && (!inEditor || appActionAt > lastEditAt) && !(P.undo as HTMLButtonElement).disabled) {
    e.preventDefault(); e.stopPropagation(); void undo();
  }
}
