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
var import_obsidian5 = require("obsidian");

// src/relations.ts
var HEADING = /^(#{1,6}) +(\S.*?) *$/;
var CODE = /`[^`]+`/g;
var LINK = /\[\[([^\[\]|#]+)(?:#([^\[\]|]*))?(?:\|([^\[\]]*))?\]\]/g;
var ENDPOINT = /^`?(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) \//;
var plain = (title) => title.replaceAll("`", "");
var linksIn = (text) => text.split(/\r?\n/).flatMap(lineLinks);
function lineLinks(s) {
  const code = [...s.matchAll(CODE)].map((m) => [m.index, m.index + m[0].length]);
  return [...s.matchAll(LINK)].filter((m) => !code.some(([a, b]) => m.index < b && a < m.index + m[0].length)).map((m) => ({ target: m[1].trim(), heading: m[2] || null }));
}
function endpointHeading(headings, line) {
  let shallowest = Infinity;
  for (const h of [...headings].reverse().filter((h2) => h2.line <= line)) {
    if (ENDPOINT.test(h.title)) return shallowest > h.level ? h : null;
    shallowest = Math.min(shallowest, h.level);
  }
  return null;
}
function parseNote(text) {
  const all = text.split(/\r?\n/);
  let start = 0;
  let client = false;
  if (all[0]?.trimEnd() === "---") {
    const close = all.findIndex((l, i) => i > 0 && l.trimEnd() === "---");
    if (close > 0) {
      start = close + 1;
      client = all.slice(1, close).some((l) => /^type:\s*client\s*$/.test(l));
    }
  }
  const body = [];
  let fence = false;
  for (let i = start; i < all.length; i++) {
    if (all[i].startsWith("```")) fence = !fence;
    else if (!fence) body.push({ text: all[i], line: i });
  }
  const headings = [];
  for (const l of body) {
    const m = HEADING.exec(l.text);
    if (m) headings.push({ level: m[1].length, title: m[2], line: l.line });
  }
  const calls = [];
  const uses = [];
  for (let i = 0; i < body.length; i++) {
    const label2 = body[i].text.trim();
    if (label2 !== "Calls:" && label2 !== "Uses:") continue;
    const at = body[i].line;
    const links = [];
    while (i + 1 < body.length && /^[-*] /.test(body[i + 1].text.trim())) links.push(...lineLinks(body[++i].text));
    if (label2 === "Uses:") {
      if (client) uses.push(...links);
      continue;
    }
    const h = endpointHeading(headings, at);
    if (h) calls.push({ heading: plain(h.title), links });
  }
  return { headings, calls, uses };
}
function endpointAt(note, line) {
  const h = endpointHeading(note.headings, line);
  return h && plain(h.title);
}
var same = (a, b) => a.toLowerCase() === b.toLowerCase();
function resolveLinks(notes, resolve, from, links) {
  return links.map((l) => {
    const path = resolve(l.target, from);
    const note = path === null ? void 0 : notes.get(path);
    const headingOk = l.heading === null || !!note?.headings.some((h) => same(plain(h.title), plain(l.heading)));
    return { ...l, path, broken: path === null || !headingOk };
  });
}
function endpointRelations(notes, resolve, path, heading) {
  const hits = (from) => (l) => resolve(l.target, from) === path && l.heading !== null && same(plain(l.heading), heading);
  const calls = [];
  const calledBy = [];
  const usedBy = [];
  for (const [p, note] of notes) {
    for (const s of note.calls) {
      if (p === path && same(s.heading, heading)) calls.push(...resolveLinks(notes, resolve, p, s.links));
      if (s.links.some(hits(p))) calledBy.push({ path: p, heading: s.heading });
    }
    if (note.uses.some(hits(p))) usedBy.push({ path: p, heading: null });
  }
  return { calls, calledBy, usedBy };
}

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
function prompt(kind, repo) {
  return `Follow AGENTS.md in this Vault and run the ${kind === "ingest" ? "Ingest" : "Refresh"} workflow for the repository "${repo}".`;
}
function frontmatterValue(text, key) {
  const lines = text.split(/\r?\n/);
  if (lines[0]?.trimEnd() !== "---") return void 0;
  const close = lines.findIndex((l, i) => i > 0 && l.trimEnd() === "---");
  let value;
  for (const l of lines.slice(1, Math.max(close, 0))) {
    const at = l.indexOf(":");
    if (at >= 0 && l.slice(0, at).trim() === key) value = l.slice(at + 1).trim();
  }
  return value;
}

// src/archiver.ts
var TASK = /^([ \t]*)(?:[-*+]|\d+[.)]) \[([ xX])\] ?(.*?)\r?\n?$/;
var indent = (s) => s.length - s.trimStart().length;
var isTaskNote = (name) => name === "bugs.md" || name === "todo.md";
function archiveTicked(path, text, on, resolve = (t) => t) {
  const file = path.split("/").pop();
  const repo = repoOf(path);
  if (!repo || !isTaskNote(file)) return null;
  const closed = on.toISOString().slice(0, 10);
  const lines = text.split(/(?<=\n)/);
  let kept = "";
  let fence = false;
  const entries = [];
  for (let i = 0; i < lines.length; i++) {
    if (/^\s*(```|~~~)/.test(lines[i])) fence = !fence;
    const m = fence ? null : TASK.exec(lines[i]);
    if (!m || m[2] === " ") {
      kept += lines[i];
      continue;
    }
    let end = i + 1;
    while (end < lines.length && lines[end].trim() !== "" && indent(lines[end]) > m[1].length) end++;
    const own = [];
    for (let j = i + 1; j < end; j++) {
      const c = TASK.exec(lines[j]);
      if (c?.[2] !== " ") {
        own.push(lines[j]);
        continue;
      }
      kept += lines[j];
      while (j + 1 < end && indent(lines[j + 1]) > c[1].length) kept += lines[++j];
    }
    const title = m[3].split(" \u2192 ")[0].trim() || "(no text)";
    const rest = own.map((l) => l.trim()).filter(Boolean).join(" ");
    const link = linksIn([lines[i], ...own].join(""))[0];
    const source = link ? `[[${resolve(link.target)}${link.heading ? `#${link.heading}` : ""}]]` : `[[${repo.folder}/README]]`;
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
    archivePath: `${repo.project}/archive/${bug ? "fixed-bugs.md" : "done-todos.md"}`,
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
  const text = old + (old === "" ? "" : old.endsWith("\n") ? "\n" : "\n\n") + a.entries;
  return old.includes("\r\n") ? old + text.slice(old.length).replace(/\n/g, "\r\n") : text;
}

// src/panel.ts
var import_obsidian3 = require("obsidian");

// src/panel-repo.ts
var import_obsidian = require("obsidian");
function isRepoReadme(file) {
  return file.name.toLowerCase() === "readme.md" && repoOf(file.path)?.folder === file.parent?.path;
}
async function repoInfo(plugin, file) {
  const repo = repoOf(file.path);
  if (!repo) return null;
  const folder = plugin.app.vault.getAbstractFileByPath(repo.folder);
  const readme = folder instanceof import_obsidian.TFolder ? folder.children.find((f) => f instanceof import_obsidian.TFile && isRepoReadme(f)) : void 0;
  const text = readme ? await plugin.app.vault.cachedRead(readme) : "";
  if (frontmatterValue(text, "type") !== "repo") return { ...repo, label: "no repo README", stale: true };
  const s = staleness(frontmatterValue(text, "verified_on"), (/* @__PURE__ */ new Date()).toISOString().slice(0, 10));
  return { ...repo, label: label(s), stale: isStale(s, plugin.settings.stalenessDays) };
}
function copyPrompt(file, kind, copy = true) {
  const repo = file && repoOf(file.path);
  if (!repo) return false;
  if (copy) {
    navigator.clipboard.writeText(prompt(kind, repo.name)).then(
      () => new import_obsidian.Notice(`Copied ${kind} prompt`),
      () => new import_obsidian.Notice(`Could not copy the ${kind} prompt`)
    );
  }
  return true;
}
async function renderRepoSection(el, plugin, file) {
  const info = await repoInfo(plugin, file);
  if (!info) return;
  el.createEl("h4", { text: `Repo ${info.name}` });
  el.createDiv({ text: info.label, cls: info.stale ? "constellation-staleness mod-warning" : "constellation-staleness" });
  const row = el.createDiv({ cls: "constellation-buttons" });
  row.createEl("button", { text: "Copy ingest prompt" }).onclick = () => copyPrompt(file, "ingest");
  row.createEl("button", { text: "Copy refresh prompt" }).onclick = () => copyPrompt(file, "refresh");
}

// src/panel-endpoint.ts
var import_obsidian2 = require("obsidian");
async function renderEndpointSection(el, app, file) {
  const isEndpoints = file.name === "endpoints.md" || file.path.startsWith("external/");
  const isClient = app.metadataCache.getFileCache(file)?.frontmatter?.type === "client";
  if (file.extension !== "md" || !isEndpoints && !isClient) return;
  const line = isEndpoints ? cursorLine(app, file) : null;
  if (isEndpoints && line === null) return;
  const files = app.vault.getMarkdownFiles();
  const notes = new Map(
    await Promise.all(files.map(async (f) => [f.path, parseNote(await app.vault.cachedRead(f))]))
  );
  const note = notes.get(file.path);
  if (!note) return;
  const resolve = (target2, from) => app.metadataCache.getFirstLinkpathDest(target2, from)?.path ?? null;
  const open = (link) => void app.workspace.openLinkText(link, file.path);
  const raw = (path, heading) => notes.get(path)?.headings.find((h) => h.title.replaceAll("`", "").toLowerCase() === heading.toLowerCase())?.title ?? heading;
  const target = (t) => {
    const text = t.heading ? `${t.target}#${t.heading}` : t.target;
    const link = t.path === null ? null : t.heading ? `${t.path}#${raw(t.path, t.heading)}` : t.path;
    return { text, link, broken: t.broken };
  };
  const ref = (r) => {
    const name = r.path.replace(/\.md$/, "");
    return r.heading ? { text: `${name}#${r.heading}`, link: `${r.path}#${raw(r.path, r.heading)}` } : { text: name, link: r.path };
  };
  if (isEndpoints) {
    const heading = endpointAt(note, line);
    if (!heading) return;
    const r = endpointRelations(notes, resolve, file.path, heading);
    el.createEl("h4", { text: heading });
    list(el, "Calls", r.calls.map(target), open);
    list(el, "Called by", r.calledBy.map(ref), open);
    list(el, "Used by clients", r.usedBy.map(ref), open);
  } else {
    list(el, "Uses", resolveLinks(notes, resolve, file.path, note.uses).map(target), open);
  }
}
function cursorLine(app, file) {
  const active = app.workspace.getActiveViewOfType(import_obsidian2.MarkdownView);
  const view = active?.file?.path === file.path ? active : app.workspace.getLeavesOfType("markdown").map((l) => l.view).find((v) => v instanceof import_obsidian2.MarkdownView && v.file?.path === file.path);
  return view ? view.editor.getCursor().line : null;
}
function list(el, title, entries, open) {
  el.createEl("h5", { text: title });
  if (!entries.length) {
    el.createEl("p", { text: "none", cls: "constellation-none" });
    return;
  }
  const ul = el.createEl("ul");
  for (const e of entries) {
    const li = ul.createEl("li");
    const a = li.createEl("a", { text: e.text, cls: e.broken ? "internal-link is-unresolved" : "internal-link" });
    if (e.broken) li.createSpan({ text: " (broken)", cls: "constellation-broken-label" });
    const link = e.link;
    if (link) a.addEventListener("click", (ev) => (ev.preventDefault(), open(link)));
  }
}

// src/panel.ts
var VIEW_TYPE = "constellation-panel";
var PanelView = class extends import_obsidian3.ItemView {
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
    this.registerEvent(this.app.workspace.on("active-leaf-change", (leaf) => leaf !== this.leaf && this.render()));
    const later = (0, import_obsidian3.debounce)(() => this.render(), 300, true);
    this.registerEvent(this.app.metadataCache.on("changed", later));
    this.registerEvent(this.app.vault.on("delete", later));
    this.registerEvent(this.app.vault.on("rename", later));
    let lastLine = -1;
    this.registerDomEvent(document, "selectionchange", () => {
      const line = this.app.workspace.getActiveViewOfType(import_obsidian3.MarkdownView)?.editor.getCursor().line;
      if (line === void 0 || line === lastLine) return;
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
};

// src/initialize.ts
var import_obsidian4 = require("obsidian");

// src/scaffold.ts
var AGENTS_MD = `# Agent rules

This folder is a Vault of Markdown Notes describing the code of several repositories. Keep it accurate and cheap to
read. Any agent tool can follow these rules.

## Hard rules

- Read code only from repositories named in \`repos.txt\` (one name per line). Each is a sibling folder of this Vault.
  If a listed folder is missing, ask the user; do not search elsewhere.
- Skip \`<project>/archive/\` unless the user asks for it.
- Leave \`clients/\` Notes unedited unless the user asks. Read them freely.
- Write \`unknown\` where the source does not say. Guesses stay out.
- Store no local paths, secrets, tokens or personal data. Use the repository URL, never a path.
- Tag only with Tags that already appear in the Vault or in \`tags.md\`. Propose a new Tag to the user in your reply.
- Copy the layout of \`templates/\` for every new Note. Keep unknown frontmatter keys as they are.

## Layout

\`<project>/README.md\`, then one folder per Repo, named exactly like the repository:
\`<project>/<repo>/\` with \`README.md\`, and as they apply \`endpoints.md\`, \`architecture.md\`, \`adr.md\`,
\`requirements.md\`, \`future.md\`, \`bugs.md\`, \`todo.md\`. Shared APIs go in \`external/<name>.md\`, Clients in
\`clients/<name>.md\`. Each Note starts with \`type:\` frontmatter; see \`templates/\`.

Link with \`[[wikilinks]]\`: \`[[<project>/<repo>/endpoints#GET /path]]\`. Repos that are not services have no
\`endpoints.md\`.

## Endpoints and Calls

Every Endpoint is a \`## METHOD /path\` heading in the Repo's \`endpoints.md\`. Under it: summary, request, response,
\`Calls:\`, requirements, \`Status:\`, known bugs. \`Calls:\` is a line that is exactly \`Calls:\` followed by a bullet list
of Links to the Endpoints this one invokes, in other Repos or in \`external/\` Notes. Add one bullet per invoked
Endpoint, and create the target heading when it is missing. \`Status:\` is a bullet list of \`implemented\`
(complete, partial, planned or deprecated), \`last_changed\` (date and commit) and \`missing\`.

## Ingest

Document a Repo from its source. Done when every Endpoint of the Repo has a heading with all its parts, every Link
resolves, and the Repo \`README.md\` carries \`repo_url\`, \`verified_commit\` (current HEAD) and \`verified_on\` (today).

1. Confirm the repository is in \`repos.txt\` and its folder exists next to this Vault.
2. Read its build files, entry points and routing code. Fill \`README.md\` (purpose, tech stack, owning team, URL).
3. Write \`endpoints.md\`, \`architecture.md\` and whichever of the other Notes the source supports.
4. Record open defects in \`bugs.md\` and open work in \`todo.md\` as task items (format below).
5. Check every Link you wrote points at an existing Note and heading.

## Refresh

Bring a Repo up to date from the diff only. Done when each changed file in the diff is reflected in the Notes and
\`verified_commit\` / \`verified_on\` are updated.

1. Read \`verified_commit\` from the Repo \`README.md\`. If it is \`unknown\`, run Ingest instead.
2. Read only \`git diff <verified_commit>..HEAD\` in the repository.
3. Update the affected Endpoints, \`Calls:\`, \`Status:\` (\`last_changed\`), bugs and todos.
4. Archive items the diff fixed or finished (format below).
5. Set \`verified_commit\` to HEAD and \`verified_on\` to today.

## Answer

Search the Vault first (Notes, \`Calls:\`, backlinks). Open code only when the Vault cannot answer, and say so in the
reply. Name the Notes you used.

## Bugs, todos and the Archive

Open items are task items in the Repo's \`bugs.md\` or \`todo.md\`: \`- [ ] short description \u2192 [[endpoints#GET /path]]\`,
with detail on more-indented lines below. To close one, delete it there and append an entry to the Project's
archive: \`<project>/archive/fixed-bugs.md\` for bugs, \`<project>/archive/done-todos.md\` for todos. Create the file
with \`type: archive\` frontmatter if it is missing. One entry:

\`\`\`markdown
### Total ignores discounts
- closed: YYYY-MM-DD
- source: [[shop/orders/endpoints#POST /orders]]
- what: Discounts are applied after tax.
- fix: Apply discounts before tax.
\`\`\`

\`source\` is the Link from the item; with no Link, use \`[[<project>/<repo>/README]]\`.`;
var TEMPLATES = {
  "project": `---
type: project
---
# <Project name>
What the product does and who it is for.

## Repos
- [[<project>/<repo>/README]]: one line each
`,
  "repo": `---
type: repo
repo_url: unknown
verified_commit: unknown
verified_on: unknown
---
# <repo>
- Purpose: unknown
- Tech stack: unknown
- Owning team: unknown

Notes: [[endpoints]], [[architecture]], [[requirements]], [[future]], [[bugs]], [[todo]]
`,
  "endpoints": `---
type: endpoint
---
# Endpoints

## GET /path
Summary: what it does.

Request: parameters and body, or unknown.

Response: status codes and body, or unknown.

Calls:
- [[other-repo/endpoints#GET /path]]

Requirements: what it must satisfy.

Status:
- implemented: complete
- last_changed: YYYY-MM-DD abc1234
- missing: none

Known bugs: [[bugs]]
`,
  "architecture": `---
type: architecture
---
# Architecture
Components, data stores and how they fit together.
`,
  "adr": `---
type: adr
---
# <Decision title>
What was decided, why, and what follows from it.
`,
  "requirements": `---
type: requirements
---
# Requirements
- What the Repo must do.
`,
  "future": `---
type: future
---
# Future
- Planned or wanted work that is not a todo yet.
`,
  "bugs": `---
type: bugs
---
# Bugs
- [ ] Short description \u2192 [[endpoints#GET /path]]
  Detail on an indented line.
`,
  "todo": `---
type: todo
---
# Todo
- [ ] Short description \u2192 [[endpoints#GET /path]]
`,
  "external-api": `---
type: external-api
---
# <External API name>
Who provides it and where its docs are.

## GET /path
What we use it for.
`,
  "client": `---
type: client
---
# <Client name>
- Who they are: unknown
- What they do: unknown
- SLA: unknown
- Auth method: unknown
- Docs they rely on: unknown

Uses:
- [[project/repo/endpoints#GET /path]]
`,
  "archive": `---
type: archive
---
# Fixed bugs

### Short description
- closed: YYYY-MM-DD
- source: [[project/repo/endpoints#GET /path]]
- what: What it was.
- fix: How it was fixed.
`
};
function starterFiles() {
  return [
    { path: "README.md", text: "# Vault\n\nWhat this vault covers.\n" },
    { path: "AGENTS.md", text: AGENTS_MD },
    { path: "repos.txt", text: "# One repository name per line.\n" },
    { path: "tags.md", text: "# Tags\n\n- #example: what this tag means\n" },
    ...Object.entries(TEMPLATES).map(([name, text]) => ({ path: `templates/${name}.md`, text }))
  ];
}
var STARTER_FOLDERS = ["templates", "external", "clients"];
function planScaffold(exists) {
  const all = starterFiles();
  return {
    folders: STARTER_FOLDERS.filter((d) => !exists(d)),
    files: all.filter((f) => !exists(f.path)),
    skipped: all.filter((f) => exists(f.path)).map((f) => f.path)
  };
}
var TEMPLATES_FOLDER = "templates";
var EXCLUDED = ["AGENTS.md", "repos.txt", "tags.md", "templates/"];
function withExcluded(current) {
  const cur = current ?? [];
  return [...cur, ...EXCLUDED.filter((e) => !cur.includes(e))];
}
var GROUPS = [
  ["[type:project]", 13936428],
  ["[type:repo]", 4494328],
  ["[type:endpoint]", 4176208],
  ['[type:"external-api"]', 14380328],
  ["[type:client]", 11238904]
].map(([query, rgb]) => ({ query, color: { a: 1, rgb } }));
function withColorGroups(current) {
  const have = current ?? [];
  return [...have, ...GROUPS.filter((o) => !have.some((g) => g.query === o.query)).map((g) => ({ query: g.query, color: { ...g.color } }))];
}
function colorGroupsLeftAlone(current) {
  return GROUPS.filter((o) => (current ?? []).some((g) => g.query === o.query)).map((g) => g.query);
}
function chooseTemplatesFolder(current) {
  const c = typeof current === "string" ? current.trim() : "";
  return c ? { folder: c, keptFrom: c } : { folder: TEMPLATES_FOLDER, keptFrom: null };
}

// src/initialize.ts
async function initializeVault(app) {
  const { vault } = app;
  const candidates = [...STARTER_FOLDERS, ...starterFiles().map((f) => f.path)];
  const existing = /* @__PURE__ */ new Set();
  for (const p of candidates) if (await vault.adapter.exists(p)) existing.add(p);
  const plan = planScaffold((p) => existing.has(p));
  const created = [];
  const skipped = [...plan.skipped];
  for (const d of plan.folders) {
    await vault.createFolder(d).catch(() => {
    });
    created.push(`${d}/`);
  }
  for (const f of plan.files) {
    try {
      await vault.create(f.path, f.text);
      created.push(f.path);
    } catch {
      skipped.push(f.path);
    }
  }
  new import_obsidian4.Notice(
    `Constellation: created ${created.length ? created.join(", ") : "nothing"}.` + (skipped.length ? `
Skipped (already there): ${skipped.join(", ")}.` : ""),
    15e3
  );
  await guarded(
    "Settings \u2192 Files and links \u2192 Excluded files: add AGENTS.md, repos.txt, tags.md, templates/",
    () => setExcluded(app)
  );
  await guarded(`Settings \u2192 Templates \u2192 Template folder location: ${TEMPLATES_FOLDER}`, () => setTemplatesFolder(app));
  await guarded(
    "Graph view \u2192 Groups: add a colour per type (project, repo, endpoint, external-api, client)",
    () => setColorGroups(app)
  );
}
async function guarded(manual, apply) {
  try {
    const note = await apply();
    if (note) new import_obsidian4.Notice(`Constellation: ${note}`, 15e3);
  } catch {
    new import_obsidian4.Notice(`Constellation could not change this Obsidian setting. Set it by hand:
${manual}`, 0);
  }
}
async function setExcluded(app) {
  const v = app.vault;
  v.setConfig("userIgnoreFilters", withExcluded(v.getConfig("userIgnoreFilters")));
  const now = v.getConfig("userIgnoreFilters");
  if (!Array.isArray(now) || withExcluded(now).length !== now.length) throw new Error("not applied");
}
async function editConfigJson(app, name, edit) {
  const p = (0, import_obsidian4.normalizePath)(`${app.vault.configDir}/${name}`);
  const a = app.vault.adapter;
  const cfg = await a.exists(p) ? JSON.parse(await a.read(p)) : {};
  edit(cfg);
  await a.write(p, JSON.stringify(cfg, null, 2));
}
async function setTemplatesFolder(app) {
  const tpl = app.internalPlugins.getPluginById("templates");
  const kept = (folder) => folder ? `kept your Template folder "${folder}" (Constellation's templates are in ${TEMPLATES_FOLDER}/; point the setting there to use them).` : void 0;
  if (tpl?.enabled && tpl.instance?.options) {
    const { folder, keptFrom: keptFrom2 } = chooseTemplatesFolder(tpl.instance.options.folder);
    if (keptFrom2) return kept(keptFrom2);
    tpl.instance.options.folder = folder;
    await tpl.saveData(tpl.instance.options);
    return;
  }
  let keptFrom = null;
  await editConfigJson(app, "templates.json", (cfg) => {
    const c = chooseTemplatesFolder(cfg.folder);
    keptFrom = c.keptFrom;
    cfg.folder = c.folder;
  });
  return keptFrom ? kept(keptFrom) : "the Templates core plugin is off. Turn it on in Settings \u2192 Core plugins to insert templates.";
}
async function setColorGroups(app) {
  const graph = app.internalPlugins.getPluginById("graph");
  let left = [];
  const note = () => left.length ? `left your existing graph colours for ${left.join(", ")} alone.` : void 0;
  if (!(graph?.enabled && graph.instance?.options)) {
    await editConfigJson(app, "graph.json", (cfg) => {
      left = colorGroupsLeftAlone(cfg.colorGroups);
      cfg.colorGroups = withColorGroups(cfg.colorGroups);
    });
    return note();
  }
  const o = graph.instance.options;
  left = colorGroupsLeftAlone(o.colorGroups);
  o.colorGroups = withColorGroups(o.colorGroups);
  await graph.instance.saveOptions();
  let stale = false;
  for (const leaf of app.workspace.getLeavesOfType("graph")) {
    const engine = leaf.view.dataEngine;
    if (typeof engine?.setOptions === "function") engine.setOptions(o);
    else stale = true;
  }
  const reopen = stale ? "close and reopen the graph view to see the new colour groups." : void 0;
  return [note(), reopen].filter(Boolean).join(" ") || void 0;
}

// src/settings.ts
function withDefaults(saved) {
  return { stalenessDays: 30, ...saved };
}
var MAX_DAYS = 36500;
function parseDays(text) {
  const t = text.trim();
  const n = /^\d+$/.test(t) ? Number(t) : 0;
  return n >= 1 && n <= MAX_DAYS ? n : null;
}

// src/main.ts
var ConstellationPlugin = class extends import_obsidian5.Plugin {
  async onload() {
    this.settings = withDefaults(await this.loadData());
    this.registerView(VIEW_TYPE, (leaf) => new PanelView(leaf, this));
    this.addRibbonIcon("sparkles", "Open Constellation panel", () => this.openPanel());
    this.addCommand({ id: "open-panel", name: "Open Constellation panel", callback: () => this.openPanel() });
    this.addSettingTab(new ConstellationSettingTab(this));
    this.addCommand({ id: "initialize-vault", name: "Initialize vault", callback: () => initializeVault(this.app) });
    for (const kind of ["ingest", "refresh"]) {
      this.addCommand({
        id: `copy-${kind}-prompt`,
        name: `Copy ${kind} prompt`,
        checkCallback: (checking) => copyPrompt(this.app.workspace.getActiveFile(), kind, !checking)
      });
    }
    const onReadme = (file) => {
      if (isRepoReadme(file)) this.renderPanels();
    };
    this.registerEvent(this.app.metadataCache.on("changed", onReadme));
    this.registerEvent(this.app.metadataCache.on("deleted", onReadme));
    this.addCommand({
      id: "archive-ticked-items",
      name: "Archive ticked items",
      // Always available, so a hotkey outside a Repo's bugs.md / todo.md gets the notice instead of silence.
      callback: () => {
        const file = this.app.workspace.getActiveFile();
        if (file) void this.archiveTicked(file);
        else new import_obsidian5.Notice("Nothing to archive: open a Repo's bugs.md or todo.md.");
      }
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
  /** Edit a Note as the user sees it: through its open editor (one undoable change, unsaved typing kept), else on disk. */
  async edit(file, fn) {
    const editor = this.app.workspace.getLeavesOfType("markdown").map((l) => l.view).find((v) => v instanceof import_obsidian5.MarkdownView && v.file === file)?.editor;
    if (!editor) {
      await this.app.vault.process(file, fn);
      return;
    }
    const before = editor.getValue();
    const after = fn(before);
    if (after === before) return;
    const cursor = editor.getCursor();
    editor.setValue(after);
    editor.setCursor(cursor);
  }
  async archiveTicked(file) {
    const { vault, metadataCache } = this.app;
    const repo = repoOf(file.path)?.folder ?? "";
    const resolve = (target) => {
      if (vault.getAbstractFileByPath(`${repo}/${target}.md`) instanceof import_obsidian5.TFile) return `${repo}/${target}`;
      return metadataCache.getFirstLinkpathDest(target, file.path)?.path.replace(/\.md$/, "") ?? target;
    };
    let done = null;
    await this.edit(file, (text) => {
      done = archiveTicked(file.path, text, /* @__PURE__ */ new Date(), resolve);
      return done?.text ?? text;
    });
    const a = done;
    if (!a) {
      new import_obsidian5.Notice("Nothing to archive: no ticked items in a Repo's bugs.md or todo.md.");
      return;
    }
    try {
      const archive = vault.getAbstractFileByPath(a.archivePath);
      if (archive instanceof import_obsidian5.TFile) await vault.process(archive, (old) => appendToArchive(old, a));
      else {
        const folder = a.archivePath.slice(0, a.archivePath.lastIndexOf("/"));
        if (!(vault.getAbstractFileByPath(folder) instanceof import_obsidian5.TFolder)) await vault.createFolder(folder);
        await vault.create(a.archivePath, appendToArchive(null, a));
      }
    } catch (e) {
      await this.edit(file, (text) => `${text}${text.endsWith("\n") || !text ? "" : "\n"}
<!-- archive failed, entries kept here -->
${a.entries}`);
      new import_obsidian5.Notice(`Could not write ${a.archivePath}: ${e}. The entries were kept at the end of ${file.name}.`);
      return;
    }
    new import_obsidian5.Notice(`Archived ${a.count} item${a.count === 1 ? "" : "s"} to ${a.archivePath}.`);
  }
  async saveSettings() {
    await this.saveData(this.settings);
    this.renderPanels();
  }
};
var ConstellationSettingTab = class extends import_obsidian5.PluginSettingTab {
  constructor(plugin) {
    super(plugin.app, plugin);
    __publicField(this, "plugin");
    this.plugin = plugin;
  }
  display() {
    this.containerEl.empty();
    new import_obsidian5.Setting(this.containerEl).setName("Staleness threshold (days)").setDesc("A Repo verified longer ago than this is highlighted as stale.").addText(
      (text) => text.setValue(String(this.plugin.settings.stalenessDays)).onChange(async (value) => {
        const days = parseDays(value);
        text.inputEl.toggleClass("mod-warning", days === null);
        error.setText(days === null ? `Enter a whole number of days from 1 to ${MAX_DAYS}. Still using ${this.plugin.settings.stalenessDays}.` : "");
        if (days === null) return;
        this.plugin.settings.stalenessDays = days;
        await this.plugin.saveSettings();
      }).inputEl.addEventListener("blur", () => {
        text.setValue(String(this.plugin.settings.stalenessDays));
        text.inputEl.removeClass("mod-warning");
        error.setText("");
      })
    );
    const error = this.containerEl.createDiv({ cls: "setting-item-description mod-warning" });
  }
};
