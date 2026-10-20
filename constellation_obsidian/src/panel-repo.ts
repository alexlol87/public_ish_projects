import { Notice, TFile, TFolder } from "obsidian";
import type ConstellationPlugin from "./main.ts";
import { repoOf, staleness, isStale, label, prompt, frontmatterValue, type Repo } from "./repo.ts";

/** A Repo's own README (`project/repo/README.md`, any case). */
export function isRepoReadme(file: TFile): boolean {
  return file.name.toLowerCase() === "readme.md" && repoOf(file.path)?.folder === file.parent?.path;
}

/** The Repo of `file` with its staleness label, or null outside a Repo. Mirrors the standalone app's right pane. */
async function repoInfo(plugin: ConstellationPlugin, file: TFile): Promise<(Repo & { label: string; stale: boolean }) | null> {
  const repo = repoOf(file.path);
  if (!repo) return null;
  const folder = plugin.app.vault.getAbstractFileByPath(repo.folder);
  const readme = folder instanceof TFolder ? folder.children.find((f): f is TFile => f instanceof TFile && isRepoReadme(f)) : undefined;
  // Raw text, not the metadata cache: it turns `verified_on` into a Date and would accept loose forms like 2026-6-5.
  const text = readme ? await plugin.app.vault.cachedRead(readme) : "";
  if (frontmatterValue(text, "type") !== "repo") return { ...repo, label: "no repo README", stale: true };
  const s = staleness(frontmatterValue(text, "verified_on"), new Date().toISOString().slice(0, 10));
  return { ...repo, label: label(s), stale: isStale(s, plugin.settings.stalenessDays) };
}

/** True if `file` is in a Repo; copies the prompt when `copy` is set. Backs the two commands and the buttons. */
export function copyPrompt(file: TFile | null, kind: "ingest" | "refresh", copy = true): boolean {
  const repo = file && repoOf(file.path);
  if (!repo) return false;
  if (copy) {
    navigator.clipboard.writeText(prompt(kind, repo.name)).then(
      () => new Notice(`Copied ${kind} prompt`),
      () => new Notice(`Could not copy the ${kind} prompt`),
    );
  }
  return true;
}

/** Repo section of the panel (ticket 03). Leave `el` empty when the file is not in a Repo. */
export async function renderRepoSection(el: HTMLElement, plugin: ConstellationPlugin, file: TFile) {
  const info = await repoInfo(plugin, file);
  if (!info) return;
  el.createEl("h4", { text: `Repo ${info.name}` });
  el.createDiv({ text: info.label, cls: info.stale ? "constellation-staleness mod-warning" : "constellation-staleness" });
  const row = el.createDiv({ cls: "constellation-buttons" });
  row.createEl("button", { text: "Copy ingest prompt" }).onclick = () => copyPrompt(file, "ingest");
  row.createEl("button", { text: "Copy refresh prompt" }).onclick = () => copyPrompt(file, "refresh");
}
