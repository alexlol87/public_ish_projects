import { Plugin, PluginSettingTab, Setting } from "obsidian";
import { PanelView, VIEW_TYPE } from "./panel.ts";
import { withDefaults, parseDays, type Settings } from "./settings.ts";

export default class ConstellationPlugin extends Plugin {
  declare settings: Settings;

  async onload() {
    this.settings = withDefaults(await this.loadData());
    this.registerView(VIEW_TYPE, (leaf) => new PanelView(leaf, this));
    this.addRibbonIcon("sparkles", "Open Constellation panel", () => this.openPanel());
    this.addCommand({ id: "open-panel", name: "Open Constellation panel", callback: () => this.openPanel() });
    this.addSettingTab(new ConstellationSettingTab(this));
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
