import { Plugin, PluginSettingTab, Setting, type TFile } from "obsidian";
import { PanelView, VIEW_TYPE } from "./panel.ts";
import { copyPrompt } from "./panel-repo.ts";
import { repoOf } from "./repo.ts";
import { withDefaults, parseDays, type Settings } from "./settings.ts";

export default class ConstellationPlugin extends Plugin {
  declare settings: Settings;

  async onload() {
    this.settings = withDefaults(await this.loadData());
    this.registerView(VIEW_TYPE, (leaf) => new PanelView(leaf, this));
    this.addRibbonIcon("sparkles", "Open Constellation panel", () => this.openPanel());
    this.addCommand({ id: "open-panel", name: "Open Constellation panel", callback: () => this.openPanel() });
    this.addSettingTab(new ConstellationSettingTab(this));
    for (const kind of ["ingest", "refresh"] as const) {
      this.addCommand({
        id: `copy-${kind}-prompt`,
        name: `Copy ${kind} prompt`,
        checkCallback: (checking) => copyPrompt(this.app.workspace.getActiveFile(), kind, !checking),
      });
    }
    // Re-render the panel when a Repo README changes on disk (its verified_on drives the Repo section).
    const onReadme = (file: TFile) => {
      if (file.name.toLowerCase() !== "readme.md" || repoOf(file.path)?.folder !== file.path.slice(0, file.path.lastIndexOf("/"))) return;
      for (const leaf of this.app.workspace.getLeavesOfType(VIEW_TYPE)) {
        if (leaf.view instanceof PanelView) leaf.view.render();
      }
    };
    this.registerEvent(this.app.metadataCache.on("changed", onReadme));
    this.registerEvent(this.app.metadataCache.on("deleted", onReadme));
    // Later tickets register their commands here.
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
}

class ConstellationSettingTab extends PluginSettingTab {
  plugin: ConstellationPlugin;

  constructor(plugin: ConstellationPlugin) {
    super(plugin.app, plugin);
    this.plugin = plugin;
  }

  display() {
    this.containerEl.empty();
    new Setting(this.containerEl)
      .setName("Staleness threshold (days)")
      .setDesc("A Repo verified longer ago than this is highlighted as stale.")
      .addText((text) =>
        text.setValue(String(this.plugin.settings.stalenessDays)).onChange(async (value) => {
          const days = parseDays(value);
          if (days === null) return;
          this.plugin.settings.stalenessDays = days;
          await this.plugin.saveSettings();
        }),
      );
  }
}
