import { Notice, Plugin, PluginSettingTab, Setting, TFile, TFolder } from "obsidian";
import { archiveTicked, appendToArchive, isTaskNote } from "./archiver.ts";
import { PanelView, VIEW_TYPE } from "./panel.ts";
import { initializeVault } from "./initialize.ts";
import { copyPrompt, isRepoReadme } from "./panel-repo.ts";
import { withDefaults, parseDays, MAX_DAYS, type Settings } from "./settings.ts";

export default class ConstellationPlugin extends Plugin {
  declare settings: Settings;

  async onload() {
    this.settings = withDefaults(await this.loadData());
    this.registerView(VIEW_TYPE, (leaf) => new PanelView(leaf, this));
    this.addRibbonIcon("sparkles", "Open Constellation panel", () => this.openPanel());
    this.addCommand({ id: "open-panel", name: "Open Constellation panel", callback: () => this.openPanel() });
    this.addSettingTab(new ConstellationSettingTab(this));
    this.addCommand({ id: "initialize-vault", name: "Initialize vault", callback: () => initializeVault(this.app) });
    for (const kind of ["ingest", "refresh"] as const) {
      this.addCommand({
        id: `copy-${kind}-prompt`,
        name: `Copy ${kind} prompt`,
        checkCallback: (checking) => copyPrompt(this.app.workspace.getActiveFile(), kind, !checking),
      });
    }
    // Re-render the panel when a Repo README changes on disk (its verified_on drives the Repo section).
    const onReadme = (file: TFile) => {
      if (isRepoReadme(file)) this.renderPanels();
    };
    this.registerEvent(this.app.metadataCache.on("changed", onReadme));
    this.registerEvent(this.app.metadataCache.on("deleted", onReadme));
    this.addCommand({
      id: "archive-ticked-items",
      name: "Archive ticked items",
      checkCallback: (checking) => {
        const file = this.app.workspace.getActiveFile();
        if (!file || !isTaskNote(file.name)) return false;
        if (!checking) void this.archiveTicked(file);
        return true;
      },
    });
  }

  renderPanels() {
    for (const leaf of this.app.workspace.getLeavesOfType(VIEW_TYPE)) {
      if (leaf.view instanceof PanelView) leaf.view.render();
    }
  }

  async openPanel() {
    const ws = this.app.workspace;
    const leaf = ws.getLeavesOfType(VIEW_TYPE)[0] ?? ws.getRightLeaf(false);
    if (!leaf) return;
    await leaf.setViewState({ type: VIEW_TYPE, active: true });
    ws.revealLeaf(leaf);
  }

  async archiveTicked(file: TFile) {
    const { vault, metadataCache } = this.app;
    const repo = file.parent?.path ?? "";
    // Like the standalone app: a target inside the Repo first, then Obsidian's resolver, else the target as written.
    const resolve = (target: string) => {
      if (vault.getAbstractFileByPath(`${repo}/${target}.md`) instanceof TFile) return `${repo}/${target}`;
      return metadataCache.getFirstLinkpathDest(target, file.path)?.path.replace(/\.md$/, "") ?? target;
    };
    let done: ReturnType<typeof archiveTicked> = null;
    await vault.process(file, (text) => {
      done = archiveTicked(file.path, text, new Date(), resolve);
      return done?.text ?? text;
    });
    const a = done as ReturnType<typeof archiveTicked>;
    if (!a) {
      new Notice("Nothing to archive: no ticked items in a Repo's bugs.md or todo.md.");
      return;
    }
    try {
      const archive = vault.getAbstractFileByPath(a.archivePath);
      if (archive instanceof TFile) await vault.process(archive, (old) => appendToArchive(old, a));
      else {
        const folder = a.archivePath.slice(0, a.archivePath.lastIndexOf("/"));
        if (!(vault.getAbstractFileByPath(folder) instanceof TFolder)) await vault.createFolder(folder);
        await vault.create(a.archivePath, appendToArchive(null, a));
      }
    } catch (e) {
      // The items are already gone from the Note: put the entries back in it rather than lose them.
      await vault.process(file, (text) => `${text}${text.endsWith("\n") || !text ? "" : "\n"}\n<!-- archive failed, entries kept here -->\n${a.entries}`);
      new Notice(`Could not write ${a.archivePath}: ${e}. The entries were kept at the end of ${file.name}.`);
      return;
    }
    new Notice(`Archived ${a.count} item${a.count === 1 ? "" : "s"} to ${a.archivePath}.`);
  }

  async saveSettings() {
    await this.saveData(this.settings);
    this.renderPanels();
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
        text
          .setValue(String(this.plugin.settings.stalenessDays))
          .onChange(async (value) => {
            const days = parseDays(value);
            text.inputEl.toggleClass("mod-warning", days === null);
            error.setText(days === null ? `Enter a whole number of days from 1 to ${MAX_DAYS}. Still using ${this.plugin.settings.stalenessDays}.` : "");
            if (days === null) return;
            this.plugin.settings.stalenessDays = days;
            await this.plugin.saveSettings();
          })
          .inputEl.addEventListener("blur", () => {
            // Show what is in force rather than the rejected text.
            text.setValue(String(this.plugin.settings.stalenessDays));
            text.inputEl.removeClass("mod-warning");
            error.setText("");
          }),
      );
    const error = this.containerEl.createDiv({ cls: "setting-item-description mod-warning" });
  }
}
