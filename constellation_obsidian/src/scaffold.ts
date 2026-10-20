// Ported as text from constellation/core/src/agent_files.rs and vault.rs `create`. Keep in step with it.

/** `AGENTS.md`, written to the Vault root. */
export const AGENTS_MD = `# Agent rules

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

Open items are task items in the Repo's \`bugs.md\` or \`todo.md\`: \`- [ ] short description → [[endpoints#GET /path]]\`,
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

/** File name (without `.md`) and text of each template, written to `templates/`. */
export const TEMPLATES: Record<string, string> = {
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
- [ ] Short description → [[endpoints#GET /path]]
  Detail on an indented line.
`,
  "todo": `---
type: todo
---
# Todo
- [ ] Short description → [[endpoints#GET /path]]
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
`,
};

export interface StarterFile {
  path: string;
  text: string;
}

/** The files `create` writes into a new Vault. */
export function starterFiles(): StarterFile[] {
  return [
    { path: "README.md", text: "# Vault\n\nWhat this vault covers.\n" },
    { path: "AGENTS.md", text: AGENTS_MD },
    { path: "repos.txt", text: "# One repository name per line.\n" },
    { path: "tags.md", text: "# Tags\n\n- #example: what this tag means\n" },
    ...Object.entries(TEMPLATES).map(([name, text]) => ({ path: `templates/${name}.md`, text })),
  ];
}

export interface ScaffoldPlan {
  folders: string[];
  files: StarterFile[];
  skipped: string[];
}

/** What Initialize writes, given which vault paths already exist. Existing files are skipped, never overwritten. */
export function planScaffold(exists: (path: string) => boolean): ScaffoldPlan {
  const all = starterFiles();
  return {
    folders: ["templates", "external", "clients"].filter((d) => !exists(d)),
    files: all.filter((f) => !exists(f.path)),
    skipped: all.filter((f) => exists(f.path)).map((f) => f.path),
  };
}

/** Obsidian's core Templates plugin folder. */
export const TEMPLATES_FOLDER = "templates";

const EXCLUDED = ["AGENTS.md", "repos.txt", "tags.md", "templates/"];

/** Obsidian's Excluded files (`userIgnoreFilters`, prefix matches) with the app-only files added. */
export function withExcluded(current: string[] | null | undefined): string[] {
  const cur = current ?? [];
  return [...cur, ...EXCLUDED.filter((e) => !cur.includes(e))];
}

/** A graph colour group as stored in `graph.json`. */
export interface ColorGroup {
  query: string;
  color: { a: number; rgb: number };
}

const GROUPS: ColorGroup[] = [
  ["[type:project]", 0xd4a72c],
  ["[type:repo]", 0x4493f8],
  ["[type:endpoint]", 0x3fb950],
  ['[type:"external-api"]', 0xdb6d28],
  ["[type:client]", 0xab7df8],
].map(([query, rgb]) => ({ query: query as string, color: { a: 1, rgb: rgb as number } }));

/** The graph's colour groups with one group per Note type; ours replace same-query groups, the user's are kept. */
export function withColorGroups(current: ColorGroup[] | null | undefined): ColorGroup[] {
  const mine = (current ?? []).filter((g) => !GROUPS.some((o) => o.query === g.query));
  return [...mine, ...GROUPS.map((g) => ({ query: g.query, color: { ...g.color } }))];
}
