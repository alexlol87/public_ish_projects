//! Files written into a new Vault for agents (`AGENTS.md`, `templates/`) and the copy-prompt texts.
//! Formats here must stay in step with the parser and the archiver; the tests parse and round-trip them.

use crate::vault::is_app_only;

/// The in-app cheat sheet; written to `.constellation/cheat-sheet.md` each time Help opens.
pub const CHEAT_SHEET: &str = include_str!("cheat_sheet.md");

/// `AGENTS.md`, written to the Vault root.
pub const AGENTS_MD: &str = r####"# Agent rules

This folder is a Vault of Markdown Notes describing the code of several repositories. Keep it accurate and cheap to
read. Any agent tool can follow these rules.

## Hard rules

- Read code only from repositories named in `repos.txt` (one name per line). Each is a sibling folder of this Vault.
  If a listed folder is missing, ask the user; do not search elsewhere.
- Skip `<project>/archive/` unless the user asks for it.
- Leave `clients/` Notes unedited unless the user asks. Read them freely.
- Write `unknown` where the source does not say. Guesses stay out.
- Store no local paths, secrets, tokens or personal data. Use the repository URL, never a path.
- Tag only with Tags that already appear in the Vault or in `tags.md`. Propose a new Tag to the user in your reply.
- Copy the layout of `templates/` for every new Note. Keep unknown frontmatter keys as they are.

## Layout

`<project>/README.md`, then one folder per Repo, named exactly like the repository:
`<project>/<repo>/` with `README.md`, and as they apply `endpoints.md`, `architecture.md`, `adr.md`,
`requirements.md`, `future.md`, `bugs.md`, `todo.md`. Shared APIs go in `external/<name>.md`, Clients in
`clients/<name>.md`. Each Note starts with `type:` frontmatter; see `templates/`.

Link with `[[wikilinks]]`: `[[<project>/<repo>/endpoints#GET /path]]`. Repos that are not services have no
`endpoints.md`.

## Endpoints and Calls

Every Endpoint is a `## METHOD /path` heading in the Repo's `endpoints.md`. Under it: summary, request, response,
`Calls:`, requirements, `Status:`, known bugs. `Calls:` is a line that is exactly `Calls:` followed by a bullet list
of Links to the Endpoints this one invokes, in other Repos or in `external/` Notes. Add one bullet per invoked
Endpoint, and create the target heading when it is missing. `Status:` is a bullet list of `implemented`
(complete, partial, planned or deprecated), `last_changed` (date and commit) and `missing`.

## Ingest

Document a Repo from its source. Done when every Endpoint of the Repo has a heading with all its parts, every Link
resolves, and the Repo `README.md` carries `repo_url`, `verified_commit` (current HEAD) and `verified_on` (today).

1. Confirm the repository is in `repos.txt` and its folder exists next to this Vault.
2. Read its build files, entry points and routing code. Fill `README.md` (purpose, tech stack, owning team, URL).
3. Write `endpoints.md`, `architecture.md` and whichever of the other Notes the source supports.
4. Record open defects in `bugs.md` and open work in `todo.md` as task items (format below).
5. Check every Link you wrote points at an existing Note and heading.

## Refresh

Bring a Repo up to date from the diff only. Done when each changed file in the diff is reflected in the Notes and
`verified_commit` / `verified_on` are updated.

1. Read `verified_commit` from the Repo `README.md`. If it is `unknown`, run Ingest instead.
2. Read only `git diff <verified_commit>..HEAD` in the repository.
3. Update the affected Endpoints, `Calls:`, `Status:` (`last_changed`), bugs and todos.
4. Archive items the diff fixed or finished (format below).
5. Set `verified_commit` to HEAD and `verified_on` to today.

## Answer

Search the Vault first (Notes, `Calls:`, backlinks). Open code only when the Vault cannot answer, and say so in the
reply. Name the Notes you used.

## Bugs, todos and the Archive

Open items are task items in the Repo's `bugs.md` or `todo.md`: `- [ ] short description → [[endpoints#GET /path]]`,
with detail on more-indented lines below. To close one, delete it there and append an entry to the Project's
archive: `<project>/archive/fixed-bugs.md` for bugs, `<project>/archive/done-todos.md` for todos. Create the file
with `type: archive` frontmatter if it is missing. One entry:

```markdown
### Total ignores discounts
- closed: YYYY-MM-DD
- source: [[shop/orders/endpoints#POST /orders]]
- what: Discounts are applied after tax.
- fix: Apply discounts before tax.
```

`source` is the Link from the item; with no Link, use `[[<project>/<repo>/README]]`."####;

/// File name (without `.md`) and text of each template, written to `templates/`.
pub const TEMPLATES: [(&str, &str); 12] = [
    (
        "project",
        r####"---
type: project
---
# <Project name>
What the product does and who it is for.

## Repos
- [[<project>/<repo>/README]]: one line each
"####,
    ),
    (
        "repo",
        r####"---
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
"####,
    ),
    (
        "endpoints",
        r####"---
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
"####,
    ),
    (
        "architecture",
        r####"---
type: architecture
---
# Architecture
Components, data stores and how they fit together.
"####,
    ),
    (
        "adr",
        r####"---
type: adr
---
# <Decision title>
What was decided, why, and what follows from it.
"####,
    ),
    (
        "requirements",
        r####"---
type: requirements
---
# Requirements
- What the Repo must do.
"####,
    ),
    (
        "future",
        r####"---
type: future
---
# Future
- Planned or wanted work that is not a todo yet.
"####,
    ),
    (
        "bugs",
        r####"---
type: bugs
---
# Bugs
- [ ] Short description → [[endpoints#GET /path]]
  Detail on an indented line.
"####,
    ),
    (
        "todo",
        r####"---
type: todo
---
# Todo
- [ ] Short description → [[endpoints#GET /path]]
"####,
    ),
    (
        "external-api",
        r####"---
type: external-api
---
# <External API name>
Who provides it and where its docs are.

## GET /path
What we use it for.
"####,
    ),
    (
        "client",
        r####"---
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
"####,
    ),
    (
        "archive",
        r####"---
type: archive
---
# Fixed bugs

### Short description
- closed: YYYY-MM-DD
- source: [[project/repo/endpoints#GET /path]]
- what: What it was.
- fix: How it was fixed.
"####,
    ),
];

pub fn ingest_prompt(repo: &str) -> String {
    format!("Follow AGENTS.md in this Vault and run the Ingest workflow for the repository \"{repo}\".")
}

pub fn refresh_prompt(repo: &str) -> String {
    format!("Follow AGENTS.md in this Vault and run the Refresh workflow for the repository \"{repo}\".")
}

/// A Repo is a folder two levels down (`project/repo`), outside the archive and the app's own folders.
pub fn is_repo_folder(relative_path: &str) -> bool {
    let c: Vec<&str> = relative_path.split('/').filter(|s| !s.is_empty()).collect();
    c.len() == 2 && !is_app_only(relative_path) && !["external", "clients", "archive"].contains(&c[0]) && c[1] != "archive"
}
