"use strict";
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);

// src/main.ts
var main_exports = {};
__export(main_exports, {
  default: () => ConstellationPlugin
});
module.exports = __toCommonJS(main_exports);
var import_obsidian4 = require("obsidian");

// src/archiver.ts
var TASK = /^([ \t]*)[-*+] \[([ xX])\] ?(.*?)\r?\n?$/;
var LINK = /\[\[([^\]|#]*)(?:#([^\]|]*))?(?:\|[^\]]*)?\]\]/;
var indent = (s) => s.length - s.trimStart().length;
function archiveTicked(path, text, on, resolve = (t) => t) {
  const parts = path.split("/");
  const file = parts[parts.length - 1];
  if (parts.length < 3 || file !== "bugs.md" && file !== "todo.md") return null;
  const repo = parts.slice(0, -1).join("/");
  const closed = `${on.getFullYear()}-${String(on.getMonth() + 1).padStart(2, "0")}-${String(on.getDate()).padStart(2, "0")}`;
  const lines = text.split(/(?<=\n)/);
  let kept = "";
  const entries = [];
  for (let i = 0; i < lines.length; i++) {
    const m = TASK.exec(lines[i]);
    if (!m || m[2] === " ") {
      kept += lines[i];
      continue;
    }
    let end = i + 1;
    while (end < lines.length && lines[end].trim() !== "" && indent(lines[end]) > m[1].length) end++;
    const body = m[3].trim();
    const title = body.split(" \u2192 ")[0].trim();
    const rest = lines.slice(i + 1, end).map((l) => l.trim()).filter(Boolean).join(" ");
    const link = LINK.exec(lines.slice(i, end).join(""));
    const source = link ? `[[${resolve(link[1].trim())}${link[2] ? `#${link[2]}` : ""}]]` : `[[${repo}/README]]`;
    entries.push(`### ${title}
- closed: ${closed}
- source: ${source}
- what: ${rest || title}
- fix: unknown
`);
    i = end - 1;
  }
  if (!entries.length) return null;
  const bug = file === "bugs.md";
  return {
    text: kept,
    count: entries.length,
    archivePath: `${parts[0]}/archive/${bug ? "fixed-bugs.md" : "done-todos.md"}`,
    entries: entries.join("\n"),
    heading: bug ? "Fixed bugs" : "Done todos"
  };
}
function appendToArchive(old, a) {
  if (old === null) return `---
type: archive
---
# ${a.heading}

${a.entries}`;
  return old + (old === "" ? "" : old.endsWith("\n") ? "\n" : "\n\n") + a.entries;
}

// src/panel.ts
var import_obsidian3 = require("obsidian");

// src/panel-repo.ts
var import_obsidian = require("obsidian");

// src/repo.ts
var APP_ONLY_TOP = ["agents.md", "repos.txt", "tags.md", "templates", ".constellation"];
function repoOf(path) {
  const c = path.split("/").filter((s) => s);
  if (c.length < 3) return null;
  const [project, name] = c;
  if (APP_ONLY_TOP.includes(project.toLowerCase()) || ["external", "clients", "archive"].includes(project) || name === "archive") return null;
  return { folder: `${project}/${name}`, project, name };
}
function utcDays(s) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const t = Date.parse(s + "T00:00:00Z");
  return Number.isNaN(t) || new Date(t).toISOString().slice(0, 10) !== s ? null : t / 864e5;
}
function staleness(verifiedOn, today) {
  const s = (verifiedOn ?? "").trim().replace(/^["']+|["']+$/g, "");
  if (!s) return { kind: "never" };
  const d = utcDays(s);
  const now = utcDays(today);
  return d === null || now === null ? { kind: "malformed" } : { kind: "verified", days: now - d };
}
function isStale(s, threshold) {
  return !(s.kind === "verified" && s.days >= 0 && s.days <= threshold);
}
function label(s) {
  if (s.kind === "never") return "never verified";
  if (s.kind === "malformed") return "verified date unreadable";
  if (s.days < 0) return "date is in the future";
  if (s.days === 0) return "verified today";
  return `verified ${s.days} day${s.days === 1 ? "" : "s"} ago`;
}
function ingestPrompt(repo) {
  return `Follow AGENTS.md in this Vault and run the Ingest workflow for the repository "${repo}".`;
}
function refreshPrompt(repo) {
  return `Follow AGENTS.md in this Vault and run the Refresh workflow for the repository "${repo}".`;
}

// src/panel-repo.ts
function repoInfo(plugin, file) {
  const repo = repoOf(file.path);
  if (!repo) return null;
  const folder = plugin.app.vault.getAbstractFileByPath(repo.folder);
  const readme = folder instanceof import_obsidian.TFolder ? folder.children.find((f) => f instanceof import_obsidian.TFile && f.name.toLowerCase() === "readme.md") : void 0;
  const fm = readme && plugin.app.metadataCache.getFileCache(readme)?.frontmatter;
  if (fm?.type !== "repo") return { ...repo, label: "no repo README", stale: true };
  const v = fm.verified_on;
  const s = staleness(
    v instanceof Date ? v.toISOString().slice(0, 10) : v == null ? void 0 : String(v),
    (/* @__PURE__ */ new Date()).toISOString().slice(0, 10)
  );
  return { ...repo, label: label(s), stale: isStale(s, plugin.settings.stalenessDays) };
}
function copyPrompt(file, kind, copy = true) {
  const repo = file && repoOf(file.path);
  if (!repo) return false;
  if (copy) {
    const text = kind === "ingest" ? ingestPrompt(repo.name) : refreshPrompt(repo.name);
    navigator.clipboard.writeText(text).then(
      () => new import_obsidian.Notice(`Copied ${kind} prompt`),
      () => new import_obsidian.Notice(`Could not copy the ${kind} prompt`)
    );
  }
  return true;
}
function renderRepoSection(el, plugin, file) {
  const info = repoInfo(plugin, file);
  if (!info) return;
  el.createEl("h4", { text: `Repo ${info.name}` });
  el.createDiv({ text: info.label, cls: info.stale ? "constellation-staleness mod-warning" : "constellation-staleness" });
  const row = el.createDiv({ cls: "constellation-buttons" });
  row.createEl("button", { text: "Copy ingest prompt" }).onclick = () => copyPrompt(file, "ingest");
  row.createEl("button", { text: "Copy refresh prompt" }).onclick = () => copyPrompt(file, "refresh");
}

// src/panel-endpoint.ts
var import_obsidian2 = require("obsidian");

// src/relations.ts
var HEADING = /^(#{1,6}) +(\S.*?) *$/;
var CODE = /`[^`]+`/g;
var LINK2 = /\[\[([^\[\]|#]+)(?:#([^\[\]|]*))?(?:\|([^\[\]]*))?\]\]/g;
var ENDPOINT = /^`?(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) \//;
var plain = (title) => title.replaceAll("`", "");
function lineLinks(s) {
  const code = [...s.matchAll(CODE)].map((m) => [m.index, m.index + m[0].length]);
  return [...s.matchAll(LINK2)].filter((m) => !code.some(([a, b]) => m.index < b && a < m.index + m[0].length)).map((m) => ({ target: m[1].trim(), heading: m[2] || null }));
}
function endpointHeading(headings, line) {
  let shallowest = Infinity;
  for (const h of [...headings].reverse().filter((h2) => h2.line <= line)) {
    if (ENDPOINT.test(h.title)) return shallowest > h.level ? h : null;
    shallowest = Math.min(shallowest, h.level);
  }
  return null;
}
function parseNote(text) {
  const all = text.split(/\r?\n/);
  let start = 0;
  let client = false;
  if (all[0]?.trimEnd() === "---") {
    const close = all.findIndex((l, i) => i > 0 && l.trimEnd() === "---");
    if (close > 0) {
      start = close + 1;
      client = all.slice(1, close).some((l) => /^type:\s*client\s*$/.test(l));
    }
  }
  const body = [];
  let fence = false;
  for (let i = start; i < all.length; i++) {
    if (all[i].startsWith("```")) fence = !fence;
    else if (!fence) body.push({ text: all[i], line: i });
  }
  const headings = [];
  for (const l of body) {
    const m = HEADING.exec(l.text);
    if (m) headings.push({ level: m[1].length, title: m[2], line: l.line });
  }
  const calls = [];
  const uses = [];
  for (let i = 0; i < body.length; i++) {
    const label2 = body[i].text.trim();
    if (label2 !== "Calls:" && label2 !== "Uses:") continue;
    const at = body[i].line;
    const links = [];
    while (i + 1 < body.length && /^[-*] /.test(body[i + 1].text.trim())) links.push(...lineLinks(body[++i].text));
    if (label2 === "Uses:") {
      if (client) uses.push(...links);
      continue;
    }
    const h = endpointHeading(headings, at);
    if (h) calls.push({ heading: plain(h.title), links });
  }
  return { headings, calls, uses };
}
function endpointAt(note, line) {
  const h = endpointHeading(note.headings, line);
  return h && plain(h.title);
}
var same = (a, b) => a.toLowerCase() === b.toLowerCase();
function resolveLinks(notes, resolve, from, links) {
  return links.map((l) => {
    const path = resolve(l.target, from);
    const note = path === null ? void 0 : notes.get(path);
    const headingOk = l.heading === null || !!note?.headings.some((h) => same(plain(h.title), plain(l.heading)));
    return { ...l, path, broken: path === null || !headingOk };
  });
}
function endpointRelations(notes, resolve, path, heading) {
  const hits = (from) => (l) => resolve(l.target, from) === path && l.heading !== null && same(plain(l.heading), heading);
  const calls = [];
  const calledBy = [];
  const usedBy = [];
  for (const [p, note] of notes) {
    for (const s of note.calls) {
      if (p === path && same(s.heading, heading)) calls.push(...resolveLinks(notes, resolve, p, s.links));
      if (s.links.some(hits(p))) calledBy.push({ path: p, heading: s.heading });
    }
    if (note.uses.some(hits(p))) usedBy.push({ path: p, heading: null });
  }
  return { calls, calledBy, usedBy };
}

// src/panel-endpoint.ts
function renderEndpointSection(el, plugin, file) {
  void render(el, plugin.app, file);
}
async function render(el, app, file) {
  const isEndpoints = file.name === "endpoints.md" || file.path.startsWith("external/");
  const isClient = app.metadataCache.getFileCache(file)?.frontmatter?.type === "client";
  if (file.extension !== "md" || !isEndpoints && !isClient) return;
  const line = isEndpoints ? cursorLine(app, file) : null;
  if (isEndpoints && line === null) return;
  const files = app.vault.getMarkdownFiles();
  const notes = new Map(
    await Promise.all(files.map(async (f) => [f.path, parseNote(await app.vault.cachedRead(f))]))
  );
  const note = notes.get(file.path);
  if (!note) return;
  const resolve = (target2, from) => app.metadataCache.getFirstLinkpathDest(target2, from)?.path ?? null;
  const open = (link) => void app.workspace.openLinkText(link, file.path);
  const raw = (path, heading) => notes.get(path)?.headings.find((h) => h.title.replaceAll("`", "").toLowerCase() === heading.toLowerCase())?.title ?? heading;
  const target = (t) => {
    const text = t.heading ? `${t.target}#${t.heading}` : t.target;
    const link = t.path === null ? null : t.heading ? `${t.path}#${raw(t.path, t.heading)}` : t.path;
    return { text, link, broken: t.broken };
  };
  const ref = (r) => {
    const name = r.path.replace(/\.md$/, "");
    return r.heading ? { text: `${name}#${r.heading}`, link: `${r.path}#${raw(r.path, r.heading)}` } : { text: name, link: r.path };
  };
  if (isEndpoints) {
    const heading = endpointAt(note, line);
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
function cursorLine(app, file) {
  const active = app.workspace.getActiveViewOfType(import_obsidian2.MarkdownView);
  const view = active?.file?.path === file.path ? active : app.workspace.getLeavesOfType("markdown").map((l) => l.view).find((v) => v instanceof import_obsidian2.MarkdownView && v.file?.path === file.path);
  return view ? view.editor.getCursor().line : null;
}
function list(el, title, entries, open) {
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

// src/panel.ts
var VIEW_TYPE = "constellation-panel";
var PanelView = class extends import_obsidian3.ItemView {
  constructor(leaf, plugin) {
    super(leaf);
    __publicField(this, "plugin");
    this.plugin = plugin;
  }
  getViewType() {
    return VIEW_TYPE;
  }
  getDisplayText() {
    return "Constellation";
  }
  getIcon() {
    return "sparkles";
  }
  async onOpen() {
    this.registerEvent(this.app.workspace.on("active-leaf-change", () => this.render()));
    const later = (0, import_obsidian3.debounce)(() => this.render(), 300, true);
    this.registerEvent(this.app.metadataCache.on("changed", later));
    this.registerEvent(this.app.vault.on("delete", later));
    this.registerEvent(this.app.vault.on("rename", later));
    let lastLine = -1;
    this.registerDomEvent(document, "selectionchange", () => {
      const line = this.app.workspace.getActiveViewOfType(import_obsidian3.MarkdownView)?.editor.getCursor().line;
      if (line === void 0 || line === lastLine) return;
      lastLine = line;
      later();
    });
    this.render();
  }
  render() {
    const el = this.contentEl;
    el.empty();
    el.addClass("constellation-panel");
    const file = this.app.workspace.getActiveFile();
    if (!file) {
      el.createEl("p", { text: "Open a note" });
      return;
    }
    renderRepoSection(el.createDiv({ cls: "constellation-section constellation-repo" }), this.plugin, file);
    renderEndpointSection(el.createDiv({ cls: "constellation-section constellation-endpoint" }), this.plugin, file);
  }
};

// src/settings.ts
function withDefaults(saved) {
  return { stalenessDays: 30, ...saved };
}
function parseDays(text) {
  const t = text.trim();
  return /^\d+$/.test(t) ? Number(t) : null;
}

// src/main.ts
var ConstellationPlugin = class extends import_obsidian4.Plugin {
  async onload() {
    this.settings = withDefaults(await this.loadData());
    this.registerView(VIEW_TYPE, (leaf) => new PanelView(leaf, this));
    this.addRibbonIcon("sparkles", "Open Constellation panel", () => this.openPanel());
    this.addCommand({ id: "open-panel", name: "Open Constellation panel", callback: () => this.openPanel() });
    this.addSettingTab(new ConstellationSettingTab(this));
    for (const kind of ["ingest", "refresh"]) {
      this.addCommand({
        id: `copy-${kind}-prompt`,
        name: `Copy ${kind} prompt`,
        checkCallback: (checking) => copyPrompt(this.app.workspace.getActiveFile(), kind, !checking)
      });
    }
    const onReadme = (file) => {
      if (file.name.toLowerCase() !== "readme.md" || repoOf(file.path)?.folder !== file.path.slice(0, file.path.lastIndexOf("/"))) return;
      for (const leaf of this.app.workspace.getLeavesOfType(VIEW_TYPE)) {
        if (leaf.view instanceof PanelView) leaf.view.render();
      }
    };
    this.registerEvent(this.app.metadataCache.on("changed", onReadme));
    this.registerEvent(this.app.metadataCache.on("deleted", onReadme));
    this.addCommand({
      id: "archive-ticked-items",
      name: "Archive ticked items",
      checkCallback: (checking) => {
        const file = this.app.workspace.getActiveFile();
        if (!file || file.name !== "bugs.md" && file.name !== "todo.md") return false;
        if (!checking) void this.archiveTicked(file);
        return true;
      }
    });
  }
  async openPanel() {
    const ws = this.app.workspace;
    const leaf = ws.getLeavesOfType(VIEW_TYPE)[0] ?? ws.getRightLeaf(false);
    if (!leaf) return;
    await leaf.setViewState({ type: VIEW_TYPE, active: true });
    ws.revealLeaf(leaf);
  }
  async archiveTicked(file) {
    const { vault, metadataCache } = this.app;
    const repo = file.parent?.path ?? "";
    const resolve = (target) => {
      if (vault.getFileByPath(`${repo}/${target}.md`)) return `${repo}/${target}`;
      return metadataCache.getFirstLinkpathDest(target, file.path)?.path.replace(/\.md$/, "") ?? target;
    };
    let done = null;
    await vault.process(file, (text) => {
      done = archiveTicked(file.path, text, /* @__PURE__ */ new Date(), resolve);
      return done?.text ?? text;
    });
    const a = done;
    if (!a) {
      new import_obsidian4.Notice("Nothing to archive: no ticked items in a Repo's bugs.md or todo.md.");
      return;
    }
    try {
      const archive = vault.getFileByPath(a.archivePath);
      if (archive) await vault.process(archive, (old) => appendToArchive(old, a));
      else {
        const folder = a.archivePath.slice(0, a.archivePath.lastIndexOf("/"));
        if (!vault.getFolderByPath(folder)) await vault.createFolder(folder);
        await vault.create(a.archivePath, appendToArchive(null, a));
      }
    } catch (e) {
      await vault.process(file, (text) => `${text}${text.endsWith("\n") || !text ? "" : "\n"}
<!-- archive failed, entries kept here -->
${a.entries}`);
      new import_obsidian4.Notice(`Could not write ${a.archivePath}: ${e}. The entries were kept at the end of ${file.name}.`);
      return;
    }
    new import_obsidian4.Notice(`Archived ${a.count} item${a.count === 1 ? "" : "s"} to ${a.archivePath}.`);
  }
  async saveSettings() {
    await this.saveData(this.settings);
    for (const leaf of this.app.workspace.getLeavesOfType(VIEW_TYPE)) {
      if (leaf.view instanceof PanelView) leaf.view.render();
    }
  }
};
var ConstellationSettingTab = class extends import_obsidian4.PluginSettingTab {
  constructor(plugin) {
    super(plugin.app, plugin);
    __publicField(this, "plugin");
    this.plugin = plugin;
  }
  display() {
    this.containerEl.empty();
    new import_obsidian4.Setting(this.containerEl).setName("Staleness threshold (days)").setDesc("A Repo verified longer ago than this is highlighted as stale.").addText(
      (text) => text.setValue(String(this.plugin.settings.stalenessDays)).onChange(async (value) => {
        const days = parseDays(value);
        if (days === null) return;
        this.plugin.settings.stalenessDays = days;
        await this.plugin.saveSettings();
      })
    );
  }
};
