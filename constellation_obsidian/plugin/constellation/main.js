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
function renderEndpointSection(el, plugin, file) {
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
