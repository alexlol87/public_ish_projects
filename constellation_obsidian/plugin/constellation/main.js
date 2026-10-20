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
var import_obsidian2 = require("obsidian");

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
var import_obsidian = require("obsidian");

// src/panel-repo.ts
function renderRepoSection(el, plugin, file) {
}

// src/panel-endpoint.ts
function renderEndpointSection(el, plugin, file) {
}

// src/panel.ts
var VIEW_TYPE = "constellation-panel";
var PanelView = class extends import_obsidian.ItemView {
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
var ConstellationPlugin = class extends import_obsidian2.Plugin {
  async onload() {
    this.settings = withDefaults(await this.loadData());
    this.registerView(VIEW_TYPE, (leaf) => new PanelView(leaf, this));
    this.addRibbonIcon("sparkles", "Open Constellation panel", () => this.openPanel());
    this.addCommand({ id: "open-panel", name: "Open Constellation panel", callback: () => this.openPanel() });
    this.addSettingTab(new ConstellationSettingTab(this));
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
      new import_obsidian2.Notice("Nothing to archive: no ticked items in a Repo's bugs.md or todo.md.");
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
      new import_obsidian2.Notice(`Could not write ${a.archivePath}: ${e}. The entries were kept at the end of ${file.name}.`);
      return;
    }
    new import_obsidian2.Notice(`Archived ${a.count} item${a.count === 1 ? "" : "s"} to ${a.archivePath}.`);
  }
  async saveSettings() {
    await this.saveData(this.settings);
    for (const leaf of this.app.workspace.getLeavesOfType(VIEW_TYPE)) {
      if (leaf.view instanceof PanelView) leaf.view.render();
    }
  }
};
var ConstellationSettingTab = class extends import_obsidian2.PluginSettingTab {
  constructor(plugin) {
    super(plugin.app, plugin);
    __publicField(this, "plugin");
    this.plugin = plugin;
  }
  display() {
    this.containerEl.empty();
    new import_obsidian2.Setting(this.containerEl).setName("Staleness threshold (days)").setDesc("A Repo verified longer ago than this is highlighted as stale.").addText(
      (text) => text.setValue(String(this.plugin.settings.stalenessDays)).onChange(async (value) => {
        const days = parseDays(value);
        if (days === null) return;
        this.plugin.settings.stalenessDays = days;
        await this.plugin.saveSettings();
      })
    );
  }
};
