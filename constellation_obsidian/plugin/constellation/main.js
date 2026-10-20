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
var import_obsidian3 = require("obsidian");

// src/panel.ts
var import_obsidian2 = require("obsidian");

// src/panel-repo.ts
function renderRepoSection(el, plugin, file) {
}

// src/panel-endpoint.ts
var import_obsidian = require("obsidian");

// src/relations.ts
var HEADING = /^(#{1,6}) +(\S.*?) *$/;
var CODE = /`[^`]+`/g;
var LINK = /\[\[([^\[\]|#]+)(?:#([^\[\]|]*))?(?:\|([^\[\]]*))?\]\]/g;
var ENDPOINT = /^`?(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) \//;
var plain = (title) => title.replaceAll("`", "");
function lineLinks(s) {
  const code = [...s.matchAll(CODE)].map((m) => [m.index, m.index + m[0].length]);
  return [...s.matchAll(LINK)].filter((m) => !code.some(([a, b]) => m.index < b && a < m.index + m[0].length)).map((m) => ({ target: m[1].trim(), heading: m[2] || null }));
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
    const label = body[i].text.trim();
    if (label !== "Calls:" && label !== "Uses:") continue;
    const at = body[i].line;
    const links = [];
    while (i + 1 < body.length && /^[-*] /.test(body[i + 1].text.trim())) links.push(...lineLinks(body[++i].text));
    if (label === "Uses:") {
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
  const active = app.workspace.getActiveViewOfType(import_obsidian.MarkdownView);
  const view = active?.file?.path === file.path ? active : app.workspace.getLeavesOfType("markdown").map((l) => l.view).find((v) => v instanceof import_obsidian.MarkdownView && v.file?.path === file.path);
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
var PanelView = class extends import_obsidian2.ItemView {
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
    const later = (0, import_obsidian2.debounce)(() => this.render(), 300, true);
    this.registerEvent(this.app.metadataCache.on("changed", later));
    this.registerEvent(this.app.vault.on("delete", later));
    this.registerEvent(this.app.vault.on("rename", later));
    let lastLine = -1;
    this.registerDomEvent(document, "selectionchange", () => {
      const line = this.app.workspace.getActiveViewOfType(import_obsidian2.MarkdownView)?.editor.getCursor().line;
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
var ConstellationPlugin = class extends import_obsidian3.Plugin {
  async onload() {
    this.settings = withDefaults(await this.loadData());
    this.registerView(VIEW_TYPE, (leaf) => new PanelView(leaf, this));
    this.addRibbonIcon("sparkles", "Open Constellation panel", () => this.openPanel());
    this.addCommand({ id: "open-panel", name: "Open Constellation panel", callback: () => this.openPanel() });
    this.addSettingTab(new ConstellationSettingTab(this));
  }
  async openPanel() {
    const ws = this.app.workspace;
    const leaf = ws.getLeavesOfType(VIEW_TYPE)[0] ?? ws.getRightLeaf(false);
    if (!leaf) return;
    await leaf.setViewState({ type: VIEW_TYPE, active: true });
    ws.revealLeaf(leaf);
  }
  async saveSettings() {
    await this.saveData(this.settings);
    for (const leaf of this.app.workspace.getLeavesOfType(VIEW_TYPE)) {
      if (leaf.view instanceof PanelView) leaf.view.render();
    }
  }
};
var ConstellationSettingTab = class extends import_obsidian3.PluginSettingTab {
  constructor(plugin) {
    super(plugin.app, plugin);
    __publicField(this, "plugin");
    this.plugin = plugin;
  }
  display() {
    this.containerEl.empty();
    new import_obsidian3.Setting(this.containerEl).setName("Staleness threshold (days)").setDesc("A Repo verified longer ago than this is highlighted as stale.").addText(
      (text) => text.setValue(String(this.plugin.settings.stalenessDays)).onChange(async (value) => {
        const days = parseDays(value);
        if (days === null) return;
        this.plugin.settings.stalenessDays = days;
        await this.plugin.saveSettings();
      })
    );
  }
};
