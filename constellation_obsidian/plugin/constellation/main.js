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
