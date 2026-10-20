import { ItemView, MarkdownView, debounce, type WorkspaceLeaf } from "obsidian";
import type ConstellationPlugin from "./main.ts";
import { renderRepoSection } from "./panel-repo.ts";
import { renderEndpointSection } from "./panel-endpoint.ts";

export const VIEW_TYPE = "constellation-panel";

/** Right-sidebar view. Each section renders into its own element; call render() to refresh. */
export class PanelView extends ItemView {
  plugin: ConstellationPlugin;

  constructor(leaf: WorkspaceLeaf, plugin: ConstellationPlugin) {
    super(leaf);
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
    // Note changes, including ones made on disk, and the cursor moving to another line.
    const later = debounce(() => this.render(), 300, true);
    this.registerEvent(this.app.metadataCache.on("changed", later));
    this.registerEvent(this.app.vault.on("delete", later));
    this.registerEvent(this.app.vault.on("rename", later));
    let lastLine = -1;
    this.registerDomEvent(document, "selectionchange", () => {
      const line = this.app.workspace.getActiveViewOfType(MarkdownView)?.editor.getCursor().line;
      if (line === undefined || line === lastLine) return;
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
    void renderRepoSection(el.createDiv({ cls: "constellation-section constellation-repo" }), this.plugin, file);
    void renderEndpointSection(el.createDiv({ cls: "constellation-section constellation-endpoint" }), this.app, file);
  }
}
