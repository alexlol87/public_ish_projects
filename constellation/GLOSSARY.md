# Constellation

A Linux and macOS app for keeping what a team knows about its projects and microservices in linked markdown notes, so
people and agents can answer questions without reading the code.

## Structure

**Vault**:
The single root folder the app opens. It holds every Project and the shared `external/` folder.
_Avoid_: Workspace, library

**Project**:
A top-level folder in the Vault for one product or system, which groups the Repos that make it up.
_Avoid_: Product, solution

**Repo**:
A folder inside a Project for one source repository (usually one microservice), holding the Notes about it.
_Avoid_: Service folder, repository directory

**Repo list**:
The file at the Vault root naming, one per line, the only source repositories agents may read. It may include
repositories that are not services, such as infrastructure.
_Avoid_: Allowlist, repo config

**External API**:
A third-party API (e.g. Stripe) that Repos call. It lives under `external/` in the Vault so several Projects can share it.
_Avoid_: Integration, third party

**Client**:
A team or system that calls our Endpoints (not a paying customer). Each Client has one Note, written by people rather
than agents.
_Avoid_: Customer, consumer, user

## Knowledge

**Bug**:
A known defect in a Repo or Endpoint that is still open.
_Avoid_: Issue, defect

**Todo**:
Open work on a Repo, such as a refactoring, that is not a Bug.
_Avoid_: Task, tech debt item

**Archive**:
The per-Project place where fixed Bugs and done Todos go, kept for people and ignored by agents.
_Avoid_: History, done list

**Verified commit**:
The commit of a Repo's source that its Notes were last checked against. It is what "up to date" means.
_Avoid_: Last sync, snapshot

## Notes and graph

**Note**:
One markdown file in the Vault.
_Avoid_: Page, document, file

**Note type**:
The kind of a Note, as stated in its frontmatter: project, repo, endpoint, architecture, adr, requirements, future,
external-api, client, bugs, todo, archive or note.
_Avoid_: Category, kind

**Endpoint**:
One operation a Repo or External API exposes (e.g. `POST /orders`), described as a heading in that Repo's endpoints Note.
_Avoid_: Route, API (on its own)

**Node**:
A Note or folder as it appears in the graph.
_Avoid_: Vertex, point

**Link**:
A `[[...]]` reference from one Note to another Note or to one of its headings.
_Avoid_: Reference, relation

**Call**:
A Link that says one Endpoint invokes another Endpoint, possibly in another Repo or an External API.
_Avoid_: Dependency, request (for this meaning)

**Tag**:
A `#label` in a Note's text or frontmatter that groups Notes across folders. Tags can nest (`#team/payments`).
_Avoid_: Label, category, mention

**Tag list**:
The file at the Vault root naming the Tags agents may use, one per line with a short meaning.
_Avoid_: Tag registry, vocabulary

**Containment**:
The relationship between a folder and what it directly holds, shown in the graph separately from Links.
_Avoid_: Parent link, hierarchy edge
