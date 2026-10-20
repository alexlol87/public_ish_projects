import { Notice, TFile, TFolder } from "obsidian";
import type ConstellationPlugin from "./main.ts";
import { repoOf, staleness, isStale, label, ingestPrompt, refreshPrompt, type Repo } from "./repo.ts";

/** The Repo of `file` with its staleness label, or null outside a Repo. Mirrors the standalone app's right pane. */
function repoInfo(plugin: ConstellationPlugin, file: TFile): (Repo & { label: string; stale: boolean }) | null {
  const repo = repoOf(file.path);
  if (!repo) return null;
  const folder = plugin.app.vault.getAbstractFileByPath(repo.folder);
  const readme = folder instanceof TFolder
    ? folder.children.find((f): f is TFile => f instanceof TFile && f.name.toLowerCase() === "readme.md")
    : undefined;
  const fm = readme && plugin.app.metadataCache.getFileCache(readme)?.frontmatter;
  if (fm?.type !== "repo") return { ...repo, label: "no repo README", stale: true };
  const v: unknown = fm.verified_on;
  const s = staleness(v instanceof Date ? v.toISOString().slice(0, 10) : v == null ? undefined : String(v),
    new Date().toISOString().slice(0, 10));
  return { ...repo, label: label(s), stale: isStale(s, plugin.settings.stalenessDays) };
}

/** True if `file` is in a Repo; copies the prompt when `copy` is set. Backs the two commands and the buttons. */
export function copyPrompt(file: TFile | null, kind: "ingest" | "refresh", copy = true): boolean {
  const repo = file && repoOf(file.path);
  if (!repo) return false;
  if (copy) {
    const text = kind === "ingest" ? ingestPrompt(repo.name) : refreshPrompt(repo.name);
    navigator.clipboard.writeText(text).then(
      () => new Notice(`Copied ${kind} prompt`),
      () => new Notice(`Could not copy the ${kind} prompt`),
    );
  }
  return true;
}

/** Repo section of the panel (ticket 03). Leave `el` empty when the file is not in a Repo. */
export function renderRepoSection(el: HTMLElement, plugin: ConstellationPlugin, file: TFile) {
  const info = repoInfo(plugin, file);
  if (!info) return;
  el.createEl("h4", { text: `Repo ${info.name}` });
  el.createDiv({ text: info.label, cls: info.stale ? "constellation-staleness mod-warning" : "constellation-staleness" });
  const row = el.createDiv({ cls: "constellation-buttons" });
  row.createEl("button", { text: "Copy ingest prompt" }).onclick = () => copyPrompt(file, "ingest");
  row.createEl("button", { text: "Copy refresh prompt" }).onclick = () => copyPrompt(file, "refresh");
}
