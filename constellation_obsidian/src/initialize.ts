import { Notice, normalizePath, type App } from "obsidian";
import { planScaffold, starterFiles, withColorGroups, withExcluded, STARTER_FOLDERS, TEMPLATES_FOLDER } from "./scaffold.ts";

// Obsidian internals used below are undocumented (see the plugin's API notes); every access is guarded.
type ObsidianInternals = any;

/** The Initialize vault command: write the starter files (never overwriting), then set up Obsidian. */
export async function initializeVault(app: App) {
  const { vault } = app;
  const candidates = [...STARTER_FOLDERS, ...starterFiles().map((f) => f.path)];
  const existing = new Set<string>();
  for (const p of candidates) if (await vault.adapter.exists(p)) existing.add(p);
  const plan = planScaffold((p) => existing.has(p));

  const created: string[] = [];
  const skipped = [...plan.skipped];
  for (const d of plan.folders) {
    await vault.createFolder(d).catch(() => {}); // a race with another writer: the folder is there either way
    created.push(`${d}/`);
  }
  for (const f of plan.files) {
    try {
      await vault.create(f.path, f.text); // throws if the file appeared meanwhile: never overwrites
      created.push(f.path);
    } catch {
      skipped.push(f.path);
    }
  }
  new Notice(
    `Constellation: created ${created.length ? created.join(", ") : "nothing"}.` +
      (skipped.length ? `\nSkipped (already there): ${skipped.join(", ")}.` : ""),
    15000,
  );

  await guarded("Settings → Files and links → Excluded files: add AGENTS.md, repos.txt, tags.md, templates/", () =>
    setExcluded(app),
  );
  await guarded(`Settings → Templates → Template folder location: ${TEMPLATES_FOLDER}`, () => setTemplatesFolder(app));
  await guarded("Graph view → Groups: add a colour per type (project, repo, endpoint, external-api, client)", () =>
    setColorGroups(app),
  );
}

async function guarded(manual: string, apply: () => Promise<string | void>) {
  try {
    const note = await apply();
    if (note) new Notice(`Constellation: ${note}`, 15000);
  } catch {
    new Notice(`Constellation could not change this Obsidian setting. Set it by hand:\n${manual}`, 0);
  }
}

async function setExcluded(app: App) {
  const v = app.vault as ObsidianInternals;
  v.setConfig("userIgnoreFilters", withExcluded(v.getConfig("userIgnoreFilters")));
  const now: unknown = v.getConfig("userIgnoreFilters");
  if (!Array.isArray(now) || withExcluded(now).length !== now.length) throw new Error("not applied");
}

/** Reads a JSON file in the config folder ({} when missing), lets `edit` change it, writes it back. */
async function editConfigJson(app: App, name: string, edit: (cfg: ObsidianInternals) => void) {
  const p = normalizePath(`${app.vault.configDir}/${name}`);
  const a = app.vault.adapter;
  const cfg = (await a.exists(p)) ? JSON.parse(await a.read(p)) : {};
  edit(cfg);
  await a.write(p, JSON.stringify(cfg, null, 2));
}

async function setTemplatesFolder(app: App) {
  const tpl = (app as ObsidianInternals).internalPlugins.getPluginById("templates");
  if (tpl?.enabled && tpl.instance?.options) {
    tpl.instance.options.folder = TEMPLATES_FOLDER;
    await tpl.saveData(tpl.instance.options);
    return;
  }
  // Disabled: its in-memory options may be stale, so write templates.json, which it loads when turned on.
  await editConfigJson(app, "templates.json", (cfg) => (cfg.folder = TEMPLATES_FOLDER));
  return "the Templates core plugin is off. Turn it on in Settings → Core plugins to insert templates.";
}

async function setColorGroups(app: App) {
  const graph = (app as ObsidianInternals).internalPlugins.getPluginById("graph");
  if (!(graph?.enabled && graph.instance?.options)) {
    await editConfigJson(app, "graph.json", (cfg) => (cfg.colorGroups = withColorGroups(cfg.colorGroups)));
    return;
  }
  const o = graph.instance.options;
  o.colorGroups = withColorGroups(o.colorGroups);
  await graph.instance.saveOptions();
  // An open graph view writes its own copy of the options back on its next change, so push ours into it.
  let stale = false;
  for (const leaf of app.workspace.getLeavesOfType("graph")) {
    const engine = (leaf.view as ObsidianInternals).dataEngine;
    if (typeof engine?.setOptions === "function") engine.setOptions(o);
    else stale = true;
  }
  if (stale) return "close and reopen the graph view to see the new colour groups.";
}
