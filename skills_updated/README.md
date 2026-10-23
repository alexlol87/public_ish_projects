# skills_updated

Agent skills for Claude Code (and other agents that read `SKILL.md`), copied at their latest versions:

| Folder | Source | Version | License |
|--------|--------|---------|---------|
| [`matt-pocock/`](matt-pocock/) | [mattpocock/skills](https://github.com/mattpocock/skills): Matt Pocock's skills for real engineers | `5beb35b` (2026-10-19) | MIT ([LICENSE](matt-pocock/LICENSE)) |
| [`caveman/`](caveman/) | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman): the core `caveman` skill | `bad48a0` (2026-10-17) | Apache-2.0 ([LICENSE](caveman/LICENSE), [NOTICE](caveman/NOTICE)) |
| [`ponytail/`](ponytail/) | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail): the core `ponytail` skill | `09c434a` (2026-10-18) | MIT ([LICENSE](ponytail/LICENSE)) |
| [`superpowers/`](superpowers/) | [obra/superpowers](https://github.com/obra/superpowers): Jesse Vincent's development methodology as 15 composable skills (brainstorm → plan → TDD → review → finish) | `bb92a77` (2026-10-09) | MIT ([LICENSE](superpowers/LICENSE)) |
| [`shadcn/`](shadcn/) | [shadcn/improve](https://github.com/shadcn/improve): the `improve` skill (read-only codebase advisor that writes implementation plans) | `cac56e1` (2026-09-12) | MIT ([LICENSE](shadcn/LICENSE.md)) |
| [`cursor/`](cursor/) | [cursor/plugins](https://github.com/cursor/plugins) (`cursor-team-kit`): the `thermo-nuclear-code-quality-review` skill | `a66a893` (2026-10-20) | MIT ([LICENSE](cursor/LICENSE)) |
| [`humanlayer/`](humanlayer/) | [humanlayer/skills](https://github.com/humanlayer/skills): all 7 plugins' skills: `visual-pr`, `show-me`, `rpi` (research, plan, implement workflow), `build-iterated-agentic-loop`, `design-control-loop`, `improve-claude-md`, `narrow-react-prop-types` | `653b641` (2026-10-08) | MIT ([LICENSE](humanlayer/LICENSE)) |
| [`popular/vercel/`](popular/vercel/) | [vercel-labs/skills](https://github.com/vercel-labs/skills) (`find-skills`), [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser) (`agent-browser`), [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills) (React best practices, composition patterns, web design guidelines) | `a80e4c9` (2026-10-19), `5ee8691` (2026-10-19), `063bee9` (2026-08-28) | `find-skills` MIT ([LICENSE](popular/vercel/find-skills/LICENSE)), `agent-browser` Apache-2.0 ([LICENSE](popular/vercel/agent-browser/LICENSE)), agent-skills MIT (stated in its README and front matter; the repo ships no LICENSE file) |
| [`popular/anthropic/`](popular/anthropic/) | [anthropics/skills](https://github.com/anthropics/skills): `frontend-design`, `skill-creator`, `webapp-testing`, `mcp-builder` | `dbd4588` (2026-10-09) | Apache-2.0 (a `LICENSE.txt` in each skill) |
| [`popular/karpathy/`](popular/karpathy/) | [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills): `karpathy-guidelines`, Andrej Karpathy's observations on LLM coding mistakes as one skill | `2c60614` (2026-04-20) | MIT (stated in its README and front matter; the repo ships no LICENSE file) |
| [`popular/addy-osmani/`](popular/addy-osmani/) | [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills): Addy Osmani's 25 production engineering skills (spec → plan → build → test → review → ship) and their shared `references/` checklists | `aeac41d` (2026-10-13) | MIT ([LICENSE](popular/addy-osmani/LICENSE)) |
| [`popular/ui-ux-pro-max/`](popular/ui-ux-pro-max/) | [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill): the `ui-ux-pro-max` skill with its searchable design data | `56ea9cf` (2026-10-14) | MIT ([LICENSE](popular/ui-ux-pro-max/LICENSE)) |
| [`popular/taste-skill/`](popular/taste-skill/) | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill): the main `taste-skill` (`design-taste-frontend`, tasteskill v2 with its scripts, library, references and assets) | `6010f91` (2026-10-20) | MIT ([LICENSE](popular/taste-skill/LICENSE)) |
| [`popular/impeccable/`](popular/impeccable/) | [pbakaus/impeccable](https://github.com/pbakaus/impeccable): the `impeccable` frontend design skill (v4.7.0) | `dad8dbb` (2026-10-20) | Apache-2.0 ([LICENSE](popular/impeccable/LICENSE), [NOTICE](popular/impeccable/NOTICE.md)) |
| [`html-anything/`](html-anything/) | [nexu-io/html-anything](https://github.com/nexu-io/html-anything): three templates from `next/src/lib/templates/skills` (`deck-guizang-editorial`, `doc-kami-parchment`, `magazine-poster`), translated from Chinese to English | `975fb3b` (2026-10-13) | Apache-2.0 ([LICENSE](html-anything/LICENSE)) |

## New in this update (2026-10-05)

Everything under [`popular/`](popular/) is new: 38 skills from the most installed and most starred skill sources that
this folder didn't have yet. Popularity comes from the [skills.sh](https://www.skills.sh/) install counts and GitHub
stars, as aggregated by [LinklyAI/best-skills](https://github.com/LinklyAI/best-skills) on 2026-10-05.

| Skill | Why it's here | Folder |
|-------|---------------|--------|
| `find-skills` | #1 most installed skill on skills.sh (3.7M installs): finds and installs a skill for whatever you ask about | [`popular/vercel/find-skills`](popular/vercel/find-skills/) |
| `agent-browser` | #1 on the Best-100 ranking (1.03M installs): browser automation for agents. Needs the CLI: `npm i -g agent-browser && agent-browser install` | [`popular/vercel/agent-browser`](popular/vercel/agent-browser/) |
| `frontend-design` | Most installed design skill (954k installs): distinctive UI instead of templated defaults | [`popular/anthropic/frontend-design`](popular/anthropic/frontend-design/) |
| `vercel-react-best-practices` | 770k installs: React and Next.js performance rules from Vercel Engineering | [`popular/vercel/react-best-practices`](popular/vercel/react-best-practices/) |
| `web-design-guidelines` | 699k installs: reviews UI code against Vercel's Web Interface Guidelines | [`popular/vercel/web-design-guidelines`](popular/vercel/web-design-guidelines/) |
| `design-taste-frontend` | 563k installs, 92k stars: anti-slop landing pages, portfolios and redesigns | [`popular/taste-skill/taste-skill`](popular/taste-skill/taste-skill/) |
| `skill-creator` | 399k installs: Anthropic's skill for writing, testing and tuning skills | [`popular/anthropic/skill-creator`](popular/anthropic/skill-creator/) |
| `ui-ux-pro-max` | 383k installs, 133k stars: UI/UX design with searchable styles, palettes, font pairings and UX rules (its scripts need Python 3) | [`popular/ui-ux-pro-max/ui-ux-pro-max`](popular/ui-ux-pro-max/ui-ux-pro-max/) |
| `vercel-composition-patterns` | 374k installs: React composition patterns (compound components, no boolean-prop sprawl, React 19) | [`popular/vercel/composition-patterns`](popular/vercel/composition-patterns/) |
| `impeccable` | 312k installs, 76k stars: design, critique, audit and polish frontend interfaces (`/impeccable audit`, `polish`, …) | [`popular/impeccable/impeccable`](popular/impeccable/impeccable/) |
| `webapp-testing` | 170k installs: test local web apps with Playwright (screenshots, console logs) | [`popular/anthropic/webapp-testing`](popular/anthropic/webapp-testing/) |
| `mcp-builder` | 123k installs: build MCP servers in Python (FastMCP) or TypeScript | [`popular/anthropic/mcp-builder`](popular/anthropic/mcp-builder/) |
| `karpathy-guidelines` | #3 most starred skill repo (217k stars): think before coding, simplicity first, surgical changes, verifiable goals | [`popular/karpathy/karpathy-guidelines`](popular/karpathy/karpathy-guidelines/) |
| Addy Osmani's 25 skills | 101k stars: a full engineering workflow (`spec-driven-development`, `planning-and-task-breakdown`, `incremental-implementation`, `code-review-and-quality`, `security-and-hardening`, `shipping-and-launch`, …), with `using-agent-skills` as the router | [`popular/addy-osmani/skills`](popular/addy-osmani/skills/) |

The skills already here were checked against their sources on the same day. Their skill files had not changed: newer
commits in Matt Pocock's skills, ponytail and Cursor's plugins only touched docs and files this folder doesn't
carry, so only their versions above moved.

Looked at and left out: Anthropic's `docx`, `pdf`, `pptx` and `xlsx` skills (proprietary license, not
redistributable); vendor-specific packs (Prisma, Supabase, Neon, Azure, Remotion, HeyGen HyperFrames, Feishu/Lark);
ClawHub-only skills without a public repository (`self-improving-agent`, `proactive-agent`); and the
`*/superpowers` image/video/Twitter skills trending on skills.sh, which are copies spread over several look-alike
accounts with near-identical install counts, not obra's Superpowers.

On 2026-10-20 all sources were re-checked again. Updated: impeccable to 4.7.0 (its plugin copy, with new desktop and native-platform handling in its references); taste-skill (new `app-screens` and `scenes` references, app and scene assets and scripts); ponytail (the `off` argument hint); caveman's README; and Matt Pocock's beta `chief-of-staff` (a wiki section for long-running goals). Added the five ponytail companion skills (`ponytail-audit`, `ponytail-debt`, `ponytail-gain`, `ponytail-help`, `ponytail-review`) under [`ponytail-companions/`](ponytail-companions/). The other sources are unchanged at their recorded skills: Vercel's `find-skills`, `agent-browser`, and the three `agent-skills` (React, composition, web design) match upstream; Cursor's `thermo-nuclear-code-quality-review` matches upstream. Not added, because the folder tracks only the core skills or the popularity list: caveman's `caveman-*`, `ultracave`, `megacave` and other new caveman skills; Vercel's `deploy-to-vercel`, `react-native-skills`, `react-view-transitions`, `vercel-cli-with-tokens`, `vercel-optimize` and `writing-guidelines`; and the cursor-team-kit skills other than `thermo-nuclear-code-quality-review`.

On 2026-10-15 all sources were re-checked. Updated: Matt Pocock's skills (engineering and productivity wording fixes),
caveman, ponytail (rewritten core skill), Superpowers (`brainstorming`, `requesting-code-review`, `systematic-debugging`
and three scripts; `spec-document-reviewer-prompt.md` became `builder-check-prompt.md`), seven Addy Osmani skills and
`performance-checklist.md`, Impeccable 4.5.2, and taste-skill, which is now tasteskill v2 and ships its own scripts,
library and references. Only the version moved for shadcn, Cursor, HumanLayer, Vercel, Anthropic, Karpathy and
UI UX Pro Max (their skill files are unchanged).

On 2026-10-06 Matt Pocock's skills moved to `6fd9479`: a new beta skill, `chief-of-staff` (run a long-running goal
in one session by coordinating subagents), and small wording fixes in `implement`, `to-tickets`, `handoff`,
`claude-handoff` and `setup-matt-pocock-skills`.

Matt Pocock's skills keep his folders: `engineering`, `productivity`, `misc`, and `in-progress` (his beta skills,
which he says can change or disappear). `thermo-nuclear-code-quality-review` is Cursor's skill: it lives in Cursor's
`cursor-team-kit` plugin, and the Next.js repository has no skill by that name. Each skill is a folder with a
`SKILL.md` plus any files it refers to.

## Install

Copy a skill's folder into `~/.claude/skills/` (all projects) or `.claude/skills/` in a repository (that project
only). For example:

```sh
cp -r skills_updated/matt-pocock/engineering/tdd ~/.claude/skills/
cp -r skills_updated/caveman skills_updated/ponytail ~/.claude/skills/
cp -r skills_updated/ponytail-companions/* ~/.claude/skills/   # the five ponytail companion skills
cp -r skills_updated/superpowers/* ~/.claude/skills/        # every superpowers skill (plus its LICENSE file)
cp -r skills_updated/shadcn/improve skills_updated/cursor/thermo-nuclear-code-quality-review ~/.claude/skills/
cp -r skills_updated/humanlayer/*/ ~/.claude/skills/
cp -r skills_updated/own/reverse-grill-me ~/.claude/skills/   # pairs with humanlayer/show-me
cp -r skills_updated/popular/vercel/find-skills skills_updated/popular/anthropic/frontend-design ~/.claude/skills/
```

Addy Osmani's skills link to checklists in `popular/addy-osmani/references/` with paths like
`../../references/security-checklist.md`. With the skills in `~/.claude/skills/`, those resolve to
`~/.claude/references/`, so copy both:

```sh
cp -r skills_updated/popular/addy-osmani/skills/* ~/.claude/skills/
cp -r skills_updated/popular/addy-osmani/references ~/.claude/
```

Claude Code picks skills up by their `description`; user-invoked ones also run as `/name` (e.g. `/grill-me`,
`/caveman`). Several of Matt's engineering skills expect `/setup-matt-pocock-skills` to be run once per repository
first. Superpowers' `using-superpowers` skill is what makes the agent reach for the other superpowers skills, so
install it with them. The original repositories also offer installers (`npx skills@latest add mattpocock/skills`,
plugin marketplaces) that keep a copy up to date.

HumanLayer's `visual-pr` and `show-me` only run when you ask for them (`/visual-pr`, `/show-me`). So does
`/reverse-grill-me` (in `own/`): it quizzes you, one yes/no question at a time, on every change in a PR or diff,
and explains the ones you didn't know about, with `show-me` style diagrams. `visual-pr` needs the
`gh` CLI: it creates or updates the current branch's PR, and saves the description under `.humanlayer/tasks/`. Its
`{SKILLBASE}` paths mean the skill's own folder.

## Skills

The names and descriptions below come from each skill's `SKILL.md`.

<!-- skills:begin (generated by scripts/skills_index.py, do not edit by hand) -->
### Matt Pocock: engineering

| Skill | Description |
|-------|-------------|
| [`ask-matt`](matt-pocock/engineering/ask-matt/SKILL.md) | Ask which skill or flow fits your situation. A router over the skills in this repo. |
| [`code-review`](matt-pocock/engineering/code-review/SKILL.md) | Review the changes since a fixed point (commit, branch, tag, or merge-base) along two axes: Standards (does the code follow this repo's documented coding standards?) and Spec (does the code match what the originating issue/spec asked for?). Runs both reviews in parallel sub-agents and reports them side by side. Use when the user wants to review a branch, a PR, work-in-progress changes, or asks to "review since X". |
| [`codebase-design`](matt-pocock/engineering/codebase-design/SKILL.md) | Shared vocabulary for designing deep modules. Use when the user wants to design or improve a module's interface, find deepening opportunities, decide where a seam goes, make code more testable or AI-navigable, or when another skill needs the deep-module vocabulary. |
| [`diagnosing-bugs`](matt-pocock/engineering/diagnosing-bugs/SKILL.md) | Diagnosis loop for hard bugs and performance regressions. Use when the user says "diagnose"/"debug this", or reports something broken/throwing/failing/slow. |
| [`domain-modeling`](matt-pocock/engineering/domain-modeling/SKILL.md) | Build and sharpen a project's domain model. Use when discussing codebase terminology, writing or editing a GLOSSARY.md, or recording or editing an ADR. |
| [`grill-with-docs`](matt-pocock/engineering/grill-with-docs/SKILL.md) | A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go. |
| [`implement`](matt-pocock/engineering/implement/SKILL.md) | Implement a piece of work based on a spec or set of tickets. |
| [`implement-spec`](matt-pocock/engineering/implement-spec/SKILL.md) | Implement the result of /to-spec and /to-tickets in code. |
| [`improve-codebase-architecture`](matt-pocock/engineering/improve-codebase-architecture/SKILL.md) | Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick. |
| [`pr`](matt-pocock/engineering/pr/SKILL.md) | Use when writing a PR body. |
| [`prototype`](matt-pocock/engineering/prototype/SKILL.md) | Build a throwaway prototype to answer a design question. Use when the user wants to sanity-check whether a state model or logic feels right, or explore what a UI should look like. |
| [`research`](matt-pocock/engineering/research/SKILL.md) | Investigate a question against high-trust primary sources and capture the findings as a Markdown file in the repo. Use when the user wants a topic researched, docs or API facts gathered, or reading legwork delegated to a background agent. |
| [`retro`](matt-pocock/engineering/retro/SKILL.md) | Conduct a retrospective on a coding session. |
| [`setup-matt-pocock-skills`](matt-pocock/engineering/setup-matt-pocock-skills/SKILL.md) | Configure this repo for the engineering skills: set up its issue tracker, triage label vocabulary, and domain doc layout. Run once before first use of the other engineering skills. |
| [`tdd`](matt-pocock/engineering/tdd/SKILL.md) | Test-driven development. Use when the user wants to build features or fix bugs test-first, mentions "red-green-refactor", or wants integration tests. |
| [`to-spec`](matt-pocock/engineering/to-spec/SKILL.md) | Turn the current conversation into a spec and publish it to the project issue tracker: no interview, just synthesis of what you've already discussed. |
| [`to-tickets`](matt-pocock/engineering/to-tickets/SKILL.md) | Break a plan, spec, or the current conversation into a set of tracer-bullet tickets, each declaring its blocking edges, published to the configured tracker (edges as text in one file per ticket locally, or native blocking links on a real tracker). |
| [`triage`](matt-pocock/engineering/triage/SKILL.md) | Move issues and external PRs through a state machine of triage roles, categorise, verify, grill if needed, and write agent-ready briefs. |
| [`wayfinder`](matt-pocock/engineering/wayfinder/SKILL.md) | Plan a huge chunk of work (more than one agent session can hold) as a shared map of decision tickets on your issue tracker, and resolve them one at a time until the way to the destination is clear. |
| [`wizard`](matt-pocock/engineering/wizard/SKILL.md) | Generate an interactive bash wizard that walks a human through steps only they can perform. Use when provisioning infrastructure, setting up credentials or CI secrets, walking an unfamiliar third-party dashboard, or running a one-off migration or cutover. Don't invoke this for steps the agent can perform itself. |

### Matt Pocock: productivity

| Skill | Description |
|-------|-------------|
| [`grill-me`](matt-pocock/productivity/grill-me/SKILL.md) | A relentless interview to sharpen a plan or design. |
| [`grilling`](matt-pocock/productivity/grilling/SKILL.md) | Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases. |
| [`handoff`](matt-pocock/productivity/handoff/SKILL.md) | Compact the current conversation into a handoff document for another agent to pick up. |
| [`teach`](matt-pocock/productivity/teach/SKILL.md) | Teach the user a new skill or concept, within this workspace. |
| [`to-questionnaire`](matt-pocock/productivity/to-questionnaire/SKILL.md) | Turn a decision you can't fully answer into a questionnaire for someone else to fill in. |
| [`wait-what`](matt-pocock/productivity/wait-what/SKILL.md) | Stop. That last message did not land: re-pitch it. |
| [`writing-for-agents`](matt-pocock/productivity/writing-for-agents/SKILL.md) | Writing documents for agents. Use when creating or editing skills, or modifying AGENTS.md or CLAUDE.md. |

### Matt Pocock: misc (kept around, rarely used)

| Skill | Description |
|-------|-------------|
| [`git-guardrails-claude-code`](matt-pocock/misc/git-guardrails-claude-code/SKILL.md) | Set up Claude Code hooks to block dangerous git commands (push, reset --hard, clean, branch -D, etc.) before they execute. Use when user wants to prevent destructive git operations, add git safety hooks, or block git push/reset in Claude Code. |
| [`migrate-to-shoehorn`](matt-pocock/misc/migrate-to-shoehorn/SKILL.md) | Migrate test files from `as` type assertions to @total-typescript/shoehorn. Use when user mentions shoehorn, wants to replace `as` in tests, or needs partial test data. |
| [`scaffold-exercises`](matt-pocock/misc/scaffold-exercises/SKILL.md) | Create exercise directory structures with sections, problems, solutions, and explainers that pass linting. Use when user wants to scaffold exercises, create exercise stubs, or set up a new course section. |
| [`setup-pre-commit`](matt-pocock/misc/setup-pre-commit/SKILL.md) | Set up Husky pre-commit hooks with lint-staged (Prettier), type checking, and tests in the current repo. Use when user wants to add pre-commit hooks, set up Husky, configure lint-staged, or add commit-time formatting/typechecking/testing. |

### Matt Pocock: in progress (beta, may change or disappear)

| Skill | Description |
|-------|-------------|
| [`chief-of-staff`](matt-pocock/in-progress/chief-of-staff/SKILL.md) | Pursue a long-running goal in a single session by co-ordinating subagents. |
| [`claude-handoff`](matt-pocock/in-progress/claude-handoff/SKILL.md) | Hand the current conversation off to a fresh background agent that picks up the work immediately. |
| [`loop-me`](matt-pocock/in-progress/loop-me/SKILL.md) | Grill me about specs for the workflows I want to build, within this workspace. |
| [`setup-ts-deep-modules`](matt-pocock/in-progress/setup-ts-deep-modules/SKILL.md) | Wire dependency-cruiser into a TypeScript repo so each package is a deep module, with implementation hidden in subfolders and reachable only through its entry-point files. User-invoked. |
| [`writing-beats`](matt-pocock/in-progress/writing-beats/SKILL.md) | Writing, exploit; assemble raw material into a journey of beats, grounding each term before a beat leans on it. |
| [`writing-fragments`](matt-pocock/in-progress/writing-fragments/SKILL.md) | Writing, explore: mine raw fragments, no structure yet. |
| [`writing-shape`](matt-pocock/in-progress/writing-shape/SKILL.md) | Writing, exploit: shape raw material into an article, paragraph by paragraph. |

### Superpowers (obra)

| Skill | Description |
|-------|-------------|
| [`brainstorming`](superpowers/brainstorming/SKILL.md) | You MUST use this before any creative work - creating features, building components, adding functionality, modifying behavior, or planning anything new, in software or out of it (a talk, a business, a renovation). |
| [`diagnosing-superpowers`](superpowers/diagnosing-superpowers/SKILL.md) | Use when a superpowers session went wrong and your human partner wants to know why — repeated work, ignored plans, stumbles, poor results, a skill that didn't fire, "it took too long", "why is it so expensive", "what is it doing" — or wants to build a bug report for the superpowers maintainers, for the current session or a past one identified by id or path, on any harness. |
| [`dispatching-parallel-agents`](superpowers/dispatching-parallel-agents/SKILL.md) | Use when facing 2+ independent tasks that can be worked on without shared state or sequential dependencies |
| [`executing-plans`](superpowers/executing-plans/SKILL.md) | Use when executing an implementation plan in the current session as the implementer yourself — your human partner chose inline execution, or no subagent tool is available |
| [`finishing-a-development-branch`](superpowers/finishing-a-development-branch/SKILL.md) | Use when implementation is complete, all tests pass, and you need to decide how to integrate the work |
| [`receiving-code-review`](superpowers/receiving-code-review/SKILL.md) | Use when receiving code review feedback, before implementing suggestions, especially if feedback seems unclear or technically questionable - requires technical rigor and verification, not performative agreement or blind implementation |
| [`requesting-code-review`](superpowers/requesting-code-review/SKILL.md) | Use when completing tasks, implementing major features, or before merging to verify work meets requirements |
| [`subagent-driven-development`](superpowers/subagent-driven-development/SKILL.md) | Use when executing implementation plans with independent tasks in the current session |
| [`systematic-debugging`](superpowers/systematic-debugging/SKILL.md) | Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes |
| [`test-driven-development`](superpowers/test-driven-development/SKILL.md) | Use when implementing any feature or bugfix, before writing implementation code |
| [`using-git-worktrees`](superpowers/using-git-worktrees/SKILL.md) | Use when starting feature work that needs isolation from current workspace or before executing implementation plans - ensures an isolated workspace exists via native tools or git worktree fallback |
| [`using-superpowers`](superpowers/using-superpowers/SKILL.md) | Use when starting any conversation - establishes how to find and use skills, requiring skill invocation before ANY response including clarifying questions |
| [`verification-before-completion`](superpowers/verification-before-completion/SKILL.md) | Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always |
| [`writing-plans`](superpowers/writing-plans/SKILL.md) | Use when you have a spec or requirements for a multi-step task, before touching code |
| [`writing-skills`](superpowers/writing-skills/SKILL.md) | Use when creating new skills, editing existing skills, or verifying skills work before deployment |

### Caveman

| Skill | Description |
|-------|-------------|
| [`caveman`](caveman/SKILL.md) | Terse caveman voice: answer first, fluff gone, every technical fact kept. Use for /caveman, "caveman mode", "talk like caveman", "be brief", "less tokens". Stays on until "stop caveman" or "normal mode". |

### Ponytail

| Skill | Description |
|-------|-------------|
| [`ponytail`](ponytail/SKILL.md) | Lazy senior dev mode: the smallest change that fully solves the task, and a reply a busy human understands in one read. Use on any coding task (writing, fixing, refactoring, reviewing, choosing dependencies) and when the user says "ponytail", "be lazy", "simplest solution", "yagni", or complains about over-engineering or bloat. Levels: lite, full (default), ultra. |

### Ponytail companions (audit, debt, gain, help, review)

| Skill | Description |
|-------|-------------|
| [`ponytail-audit`](ponytail-companions/ponytail-audit/SKILL.md) | Quality audit of a whole repo: bugs, security holes, what breaks under real load, risky code without tests, slow paths, and what to delete, merge or split. Ranked, each finding explained in plain English. One-shot report, changes nothing. Use for "audit this codebase", "review the whole repo", "find bloat", "what can I delete", /ponytail-audit. |
| [`ponytail-debt`](ponytail-companions/ponytail-debt/SKILL.md) | List every `shortcut:` comment (and older `ponytail:` ones) as a debt ledger. One-shot report, changes nothing. Use for "ponytail debt", "what did ponytail defer", "list the shortcuts", /ponytail-debt. |
| [`ponytail-gain`](ponytail-companions/ponytail-gain/SKILL.md) | Show ponytail's measured savings (code, cost, speed) from the benchmark. One-shot display. Use for /ponytail-gain, "what does ponytail save", "ponytail impact". |
| [`ponytail-help`](ponytail-companions/ponytail-help/SKILL.md) | Quick reference for ponytail levels, skills and commands. One-shot display. Use for /ponytail-help, "ponytail help", "how do I use ponytail". |
| [`ponytail-review`](ponytail-companions/ponytail-review/SKILL.md) | Quality review of a change: is the logic right, is it safe, does it hold under real load, is risky code tested, is it fast enough, and is every line needed. Reads the connected code, not only the diff. Each finding is explained in plain English. Use for "review this", "code review", "review the last commit", "review my PR", "is this over-engineered", /ponytail-review. |

### shadcn

| Skill | Description |
|-------|-------------|
| [`improve`](shadcn/improve/SKILL.md) | Survey any codebase as a senior advisor and produce prioritized, self-contained implementation plans for OTHER models/agents to execute. Strictly read-only on source code — never implements, fixes, or refactors anything itself. Use when asked to audit a codebase, find improvement opportunities (bugs, security, performance, test coverage, tech debt, migrations, DX), suggest features or where to take the project next (roadmap, product direction), or generate handoff plans for another agent to implement. |

### Cursor

| Skill | Description |
|-------|-------------|
| [`thermo-nuclear-code-quality-review`](cursor/thermo-nuclear-code-quality-review/SKILL.md) | Run an extremely strict maintainability review for abstraction quality, giant files, and spaghetti-condition growth. Use for a thermo-nuclear code quality review, thermonuclear review, deep code quality audit, or especially harsh maintainability review. |

### HumanLayer

| Skill | Description |
|-------|-------------|
| [`build-iterated-agentic-loop`](humanlayer/build-iterated-agentic-loop/SKILL.md) | build a repo-local skill and install a matching iterated coding-agent GitHub Actions workflow, prompt, memory file, and reference templates |
| [`design-control-loop`](humanlayer/design-control-loop/SKILL.md) | interview the user to design an agentic control loop (sensor, controller, actuator under disturbances) tailored to their codebase, then build it as locally-runnable components plus a scheduled coding-agent workflow |
| [`improve-claude-md`](humanlayer/improve-claude-md/SKILL.md) | improve a CLAUDE.md file using <important if> blocks to improve instruction adherence |
| [`narrow-react-prop-types`](humanlayer/narrow-react-prop-types/SKILL.md) | narrow React component prop types to match live code paths |
| [`rpi`](humanlayer/rpi/SKILL.md) | Only use when the user explicitly invokes this skill by name. |
| [`show-me`](humanlayer/show-me/SKILL.md) | Help the user understand the current topic visually with concise diagrams, code-shape sketches, and focused HTML artifacts. |
| [`visual-pr`](humanlayer/visual-pr/SKILL.md) | Only use when the user explicitly invokes this skill by name. |

### Own skills (written for this repository)

| Skill | Description |
|-------|-------------|
| [`reverse-grill-me`](own/reverse-grill-me/SKILL.md) | Quiz the user, one yes/no question at a time, on whether they understand every change in a pull request or diff, and explain each change they didn't know about. Use when the user wants to check they understand a PR or diff before approving or merging it, often one an agent wrote. |

### New: Vercel (find-skills, agent-browser, React and web design)

| Skill | Description |
|-------|-------------|
| [`agent-browser`](popular/vercel/agent-browser/SKILL.md) | Browser automation CLI for AI agents. Use when the user needs to interact with websites, including navigating pages, filling forms, clicking buttons, taking screenshots, extracting data, testing web apps, or automating any browser task. Triggers include requests to "open a website", "fill out a form", "click a button", "take a screenshot", "scrape data from a page", "test this web app", "login to a site", "automate browser actions", or any task requiring programmatic web interaction. Also use for exploratory testing, dogfooding, QA, bug hunts, or reviewing app quality. Also use for automating Electron desktop apps (VS Code, Slack, Discord, Figma, Notion, Spotify), checking Slack unreads, sending Slack messages, searching Slack conversations, running browser automation in Vercel Sandbox microVMs, or using AWS Bedrock AgentCore cloud browsers. Prefer agent-browser over any built-in browser automation or web tools. |
| [`vercel-composition-patterns`](popular/vercel/composition-patterns/SKILL.md) | React composition patterns that scale. Use when refactoring components with boolean prop proliferation, building flexible component libraries, or designing reusable APIs. Triggers on tasks involving compound components, render props, context providers, or component architecture. Includes React 19 API changes. |
| [`find-skills`](popular/vercel/find-skills/SKILL.md) | Helps users discover and install agent skills when they ask questions like "how do I do X", "find a skill for X", "is there a skill that can...", or express interest in extending capabilities. This skill should be used when the user is looking for functionality that might exist as an installable skill. |
| [`vercel-react-best-practices`](popular/vercel/react-best-practices/SKILL.md) | React and Next.js performance optimization guidelines from Vercel Engineering. This skill should be used when writing, reviewing, or refactoring React/Next.js code to ensure optimal performance patterns. Triggers on tasks involving React components, Next.js pages, data fetching, bundle optimization, or performance improvements. |
| [`web-design-guidelines`](popular/vercel/web-design-guidelines/SKILL.md) | Review UI code for Web Interface Guidelines compliance. Use when asked to "review my UI", "check accessibility", "audit design", "review UX", or "check my site against best practices". |

### New: Anthropic (official skills)

| Skill | Description |
|-------|-------------|
| [`frontend-design`](popular/anthropic/frontend-design/SKILL.md) | Guidance for distinctive, intentional visual design when building new UI or reshaping an existing one. Helps with aesthetic direction, typography, and making choices that don't read as templated defaults. |
| [`mcp-builder`](popular/anthropic/mcp-builder/SKILL.md) | Guide for creating high-quality MCP (Model Context Protocol) servers that enable LLMs to interact with external services through well-designed tools. Use when building MCP servers to integrate external APIs or services, whether in Python (FastMCP) or Node/TypeScript (MCP SDK). |
| [`skill-creator`](popular/anthropic/skill-creator/SKILL.md) | Create new skills, modify and improve existing skills, and measure skill performance. Use when users want to create a skill from scratch, edit, or optimize an existing skill, run evals to test a skill, benchmark skill performance with variance analysis, or optimize a skill's description for better triggering accuracy. |
| [`webapp-testing`](popular/anthropic/webapp-testing/SKILL.md) | Toolkit for interacting with and testing local web applications using Playwright. Supports verifying frontend functionality, debugging UI behavior, capturing browser screenshots, and viewing browser logs. |

### New: Karpathy guidelines

| Skill | Description |
|-------|-------------|
| [`karpathy-guidelines`](popular/karpathy/karpathy-guidelines/SKILL.md) | Behavioral guidelines to reduce common LLM coding mistakes. Use when writing, reviewing, or refactoring code to avoid overcomplication, make surgical changes, surface assumptions, and define verifiable success criteria. |

### New: Addy Osmani's agent skills

| Skill | Description |
|-------|-------------|
| [`api-and-interface-design`](popular/addy-osmani/skills/api-and-interface-design/SKILL.md) | Guides stable API and interface design. Use when designing APIs, module boundaries, or any public interface. Use when creating REST or GraphQL endpoints, defining type contracts between modules, or establishing boundaries between frontend and backend. |
| [`browser-testing-with-devtools`](popular/addy-osmani/skills/browser-testing-with-devtools/SKILL.md) | Tests in real browsers via Chrome DevTools MCP. Use when building or debugging anything that runs in a browser. Use when you need to inspect the DOM, capture console errors, analyze network requests, profile performance, or verify visual output with real runtime data. Requires the chrome-devtools MCP server to be configured. |
| [`ci-cd-and-automation`](popular/addy-osmani/skills/ci-cd-and-automation/SKILL.md) | Automates CI/CD pipeline setup. Use when setting up or modifying build and deployment pipelines. Use when you need to automate quality gates, configure test runners in CI, or establish deployment strategies. |
| [`code-review-and-quality`](popular/addy-osmani/skills/code-review-and-quality/SKILL.md) | Conducts multi-axis code review. Use before merging any change. Use when reviewing code written by yourself, another agent, or a human. Use when you need to assess code quality across multiple dimensions before it enters the main branch. Use when asked to review a diff or a pull request, even when the diff is pasted inline. |
| [`code-simplification`](popular/addy-osmani/skills/code-simplification/SKILL.md) | Simplifies code for clarity. Use when refactoring code for clarity without changing behavior. Use when code works but is harder to read, maintain, or extend than it should be. Use when reviewing code that has accumulated unnecessary complexity. |
| [`constraint-driven-development`](popular/addy-osmani/skills/constraint-driven-development/SKILL.md) | Establishes a project's quality bar as a written contract and stops agents quietly lowering it. Interviews the user on which dimensions matter, supplies sane default thresholds when they have no number in mind, records everything in CONSTRAINTS.md, and watches the diff for a weakened bar — new @ts-ignore or eslint-disable suppressions, skipped or deleted tests, assertions stripped out, unimplemented stubs, thresholds edited down. Use when no quality bar is written down, when the user says "set up constraints" or "define our standards", when the user wants dimensions they care about — accessibility, web performance, coverage — set up as enforced constraints, when an agent keeps silencing checks or skipping tests to get to green, when you need a coverage or performance threshold and don't know what number to pick, or when an agent writes more code than anyone will read. |
| [`context-engineering`](popular/addy-osmani/skills/context-engineering/SKILL.md) | Optimizes agent context setup. Use when starting a new session, when agent output quality degrades, when switching between tasks, or when you need to configure rules files and context for a project. |
| [`debugging-and-error-recovery`](popular/addy-osmani/skills/debugging-and-error-recovery/SKILL.md) | Guides systematic root-cause debugging. Use when tests fail, builds break, something that worked yesterday broke, behavior doesn't match expectations, or you encounter any unexpected error. Use when you need to figure out what broke and why — a systematic approach to finding and fixing the root cause rather than guessing. |
| [`deprecation-and-migration`](popular/addy-osmani/skills/deprecation-and-migration/SKILL.md) | Manages deprecation and migration. Use when removing old systems, APIs, or features. Use when migrating users from one implementation to another. Use when migrating a database schema in production, such as renaming or dropping a column without downtime (expand/contract). Use when deciding whether to maintain or sunset existing code. |
| [`documentation-and-adrs`](popular/addy-osmani/skills/documentation-and-adrs/SKILL.md) | Records decisions and documentation. Use when you need to document an architecture decision (ADR) or the reasoning behind a design choice, when changing public APIs, shipping features, or when you need to record context that future engineers and agents will need to understand the codebase. |
| [`doubt-driven-development`](popular/addy-osmani/skills/doubt-driven-development/SKILL.md) | Subjects every non-trivial decision to a fresh-context adversarial review before it stands. Use when you want every assumption cross-examined before proceeding, when stress-testing a plan for hidden failure modes, when correctness matters more than speed, when working in unfamiliar code, when stakes are high (production auth, security-sensitive logic, a high-stakes migration, irreversible operations), or any time a confident output would be cheaper to verify now than to debug later. |
| [`frontend-ui-engineering`](popular/addy-osmani/skills/frontend-ui-engineering/SKILL.md) | Builds production-quality, accessible, responsive user-facing UIs. Use when building or modifying interfaces and pages, creating components, implementing layouts, meeting WCAG accessibility requirements, managing state, or when the output needs to look and feel production-quality rather than AI-generated. |
| [`git-workflow-and-versioning`](popular/addy-osmani/skills/git-workflow-and-versioning/SKILL.md) | Structures git workflow practices. Use when making any code change. Use when committing, branching, resolving conflicts, splitting uncommitted work in a messy working tree into clean atomic commits, opening or reviewing a pull request (PR), pushing to a remote, or when you need to organize work across multiple parallel streams. Use when cutting a release, choosing a semantic version bump, tagging, or writing a changelog. |
| [`idea-refine`](popular/addy-osmani/skills/idea-refine/SKILL.md) | Refines raw ideas into sharp, actionable concepts through structured divergent and convergent thinking. Use when an idea is still vague, when you need to stress-test assumptions before committing to a plan, or when you want to expand options before converging on one. Triggers on "ideate", "refine this idea", or "stress-test my plan". |
| [`incremental-implementation`](popular/addy-osmani/skills/incremental-implementation/SKILL.md) | Delivers changes incrementally in thin, verifiable slices. Use when implementing any feature or change that touches more than one file, or when picking up the next task from a plan. Use when rolling a change out behind a feature flag, when you're about to write a large amount of code at once, or when a task feels too big to land in one step. |
| [`interview-me`](popular/addy-osmani/skills/interview-me/SKILL.md) | Extracts what the user actually wants instead of what they think they should want. Achieves this through one-question-at-a-time interview until ~95% confidence about the underlying intent. Use when an ask is underspecified ("build me X" without "for whom" or "why now"), when the user explicitly invokes ("interview me", "grill me", "are we sure?", "stress-test my thinking"), or when you catch yourself silently filling in ambiguous requirements before any plan, spec, or code exists. |
| [`observability-and-instrumentation`](popular/addy-osmani/skills/observability-and-instrumentation/SKILL.md) | Instruments code so production behavior is visible and diagnosable. Use when adding logging, metrics, tracing, or alerting. Use when shipping any feature that runs in production and you need evidence it works. Use when production issues are reported but you can't tell what happened from the available data. |
| [`performance-optimization`](popular/addy-osmani/skills/performance-optimization/SKILL.md) | Optimizes application performance across frontend, backend, queries, and databases. Use when performance requirements exist, when you suspect performance regressions, when Core Web Vitals or load times need improvement, when N+1 query patterns need fixing, or when profiling reveals bottlenecks. |
| [`planning-and-task-breakdown`](popular/addy-osmani/skills/planning-and-task-breakdown/SKILL.md) | Breaks work into ordered tasks. Use when you have a spec or clear requirements and need to break work into implementable tasks. Use when a task feels too large to start, when you need to estimate scope, or when parallel work is possible. |
| [`security-and-hardening`](popular/addy-osmani/skills/security-and-hardening/SKILL.md) | Hardens code against vulnerabilities. Use when auditing an input handler for vulnerabilities, when handling user input, authentication, data storage, or external integrations, or when checking a login flow is safe against the OWASP Top Ten. Use when building any feature that accepts untrusted data, manages user sessions, or interacts with third-party services. Use when auditing dependencies for known vulnerabilities, triaging package-manager audit findings, or assessing supply-chain risk in a new package. Use when personal data or privacy compliance (GDPR, CCPA) is involved. |
| [`shipping-and-launch`](popular/addy-osmani/skills/shipping-and-launch/SKILL.md) | Prepares production launches. Use when preparing to deploy to production, or when asking what needs to be in place before shipping. Use when you need a pre-launch checklist, when setting up monitoring, when planning a staged rollout, or when you need a rollback strategy. |
| [`source-driven-development`](popular/addy-osmani/skills/source-driven-development/SKILL.md) | Grounds every implementation decision in official documentation. Use when you want to verify an approach against the official docs before implementing it, or when you want authoritative, source-cited code free from outdated patterns. Use when building with any framework or library where correctness matters. |
| [`spec-driven-development`](popular/addy-osmani/skills/spec-driven-development/SKILL.md) | Creates specs before coding. Use when starting a new project, feature, or significant change and no specification exists yet. Use when drafting a PRD or requirements document with objectives and scope, or when requirements are unclear, ambiguous, or only exist as a vague idea. Use when a single requirement spans several independently testable capabilities and needs decomposing into a capability map of modules before specifying. |
| [`test-driven-development`](popular/addy-osmani/skills/test-driven-development/SKILL.md) | Drives development with tests using the red-green-refactor loop. Use when implementing any logic, fixing any bug, or changing any behavior. Use when you need to prove that code works, when a bug report arrives, or when you're about to modify existing functionality. Use when asked to add tests to a function, fix a bug in it or change its behavior, even when the code is pasted inline and the request does not mention tests. |
| [`using-agent-skills`](popular/addy-osmani/skills/using-agent-skills/SKILL.md) | Discovers and invokes agent skills. Use when starting a session, or when you need to decide which skill or workflow applies to the piece of work at hand. This is the meta-skill that governs how all other skills are discovered and invoked. |

### New: UI UX Pro Max

| Skill | Description |
|-------|-------------|
| [`ui-ux-pro-max`](popular/ui-ux-pro-max/ui-ux-pro-max/SKILL.md) | UI/UX design intelligence for web, mobile, and desktop. This skill should be used when designing, building, reviewing, or fixing interfaces, including pages, components, design systems, accessibility, interaction, responsive layout, typography, color, charts, and stack-specific UI implementation. Searchable local data: 79 searchable styles (50 active), 192 product palettes and reasoning profiles, 74 font pairings, 119 UX guidelines, 105 icons, 17 GSAP presets, 25 chart types, and 22 stacks. |

### New: Taste Skill

| Skill | Description |
|-------|-------------|
| [`design-taste-frontend`](popular/taste-skill/taste-skill/SKILL.md) | tasteskill v2, the anti-slop frontend skill. Art direction for websites, distilled from a study of 247 curated gallery sites (One Page Love, Awwwards Sites of the Day). Deals researched directions (idea, composition, type, palette, photographs, section blueprints) from a library, enforces a strict no-slop house style with a real-browser inspector, and runs a look-and-fix loop on screenshots. Use this whenever you build, design, redesign, restyle, polish or review a landing page, marketing site, portfolio, product page, one-pager, hero or any public-facing web page, in any stack (HTML/CSS, React, Next.js, Vue, Svelte, Astro, Tailwind) — also when the user says a page looks generic, templated, "AI-made", sloppy, or asks to make it look designed, premium, award-level or less like every other site. Also for app screens: dashboards, admin and analytics views, settings, inboxes and other screens people work in, with their own run and rules. |

### New: Impeccable

| Skill | Description |
|-------|-------------|
| [`impeccable`](popular/impeccable/impeccable/SKILL.md) | Use when the user wants to design, redesign, shape, critique, audit, polish, simplify, harden, animate, or otherwise improve a frontend interface: websites, landing pages, dashboards, product UI, components, forms, settings, onboarding, empty states, and native iOS or Android screens. Handles UX review, hierarchy, layout, typography, color, motion, UX copy, accessibility, responsive behavior, edge cases, and capturing or documenting design systems (DESIGN.md, tokens). Also for making bland UI bolder, loud UI quieter, or ambitious visual effects. Not for backend-only or non-UI tasks. |

### Awesome Copilot: review

| Skill | Description |
|-------|-------------|
| [`pr-address-feedback`](awesome-copilot/review/pr-address-feedback/SKILL.md) | Walk through PR review comments one-by-one, deciding for each whether to act on the feedback or reply with reasoning, and build an approvable resolution plan before changing anything. Use when the user wants to address, respond to, or triage PR review feedback. |
| [`security-review`](awesome-copilot/review/security-review/SKILL.md) | AI-powered codebase security scanner that reasons about code like a security researcher — tracing data flows, understanding component interactions, and catching vulnerabilities that pattern-matching tools miss. Use this skill when asked to scan code for security vulnerabilities, find bugs, check for SQL injection, XSS, command injection, exposed API keys, hardcoded secrets, insecure dependencies, access control issues, or any request like "is my code secure?", "review for security issues", "audit this codebase", or "check for vulnerabilities". Covers injection flaws, authentication and access control bugs, secrets exposure, weak cryptography, insecure dependencies, and business logic issues across JavaScript, TypeScript, Python, Java, PHP, Go, Ruby, and Rust. |
| [`test-gap-audit`](awesome-copilot/review/test-gap-audit/SKILL.md) | Run a read-only audit for missing, weak, stale, or mis-scoped test coverage. If the user does not name a scope, audit the full repository and identify important code paths, routes, features, services, workflows, and contracts that lack proper tests. If the user names a feature, PR, branch, route, workflow, service, bug fix, API, security-sensitive path, or risky code change, focus only on that specific scope. Use when the user asks what tests are missing, whether coverage is enough, what regression tests to add, or how to prove a change is safe. This is not a general bug audit and not a security review; it evaluates whether behavior is covered by tests. |

### Awesome Copilot: development

| Skill | Description |
|-------|-------------|
| [`java-hibernate-jpa`](awesome-copilot/development/java-hibernate-jpa/SKILL.md) | Diagnose and fix Hibernate ORM / Jakarta Persistence problems in plain Java: N+1 queries, lazy loading errors, identifier generation, entity equals/hashCode, cascades, pagination, batching, locking, caching, Lombok on entities, and Hibernate 6/7 differences. Use when reviewing or writing JPA entities, mappings, and queries. Framework-neutral. |
| [`java-springboot`](awesome-copilot/development/java-springboot/SKILL.md) | Get best practices for developing applications with Spring Boot. |
| [`java-upgrade`](awesome-copilot/development/java-upgrade/SKILL.md) | Upgrade a Java project to a newer JDK (11 to 17, 17 to 21, 21 to 25) and adopt the new language and library features. Detects the current Java version from the build files, then loads only the matching per-version guide. Use when the user asks to upgrade Java, modernize Java code, or adopt records, sealed classes, pattern matching, virtual threads or other new Java features. For automated end-to-end upgrades see the modernize-java plugin. |
| [`javax-to-jakarta-migration`](awesome-copilot/development/javax-to-jakarta-migration/SKILL.md) | Migrate Java code from javax.* to jakarta.* namespace. Use only when the user explicitly asks for a javax to jakarta namespace or framework migration (for example to Tomcat 10+/11 or Jakarta EE), or when java-upgrade or spring-boot-4-migration delegates it. Finding javax imports alone does not authorize a migration. |
| [`multi-stage-dockerfile`](awesome-copilot/development/multi-stage-dockerfile/SKILL.md) | Create optimized multi-stage Dockerfiles for any language or framework |
| [`refactor-plan`](awesome-copilot/development/refactor-plan/SKILL.md) | Create a concrete plan before starting a multi-file refactor. Use when the user asks to plan, sequence, scope, or safely execute a refactor across multiple files; always investigate first, output the plan, and wait for confirmation before making code changes. |
| [`ruff-recursive-fix`](awesome-copilot/development/ruff-recursive-fix/SKILL.md) | Run Ruff checks with optional scope and rule overrides, apply safe and unsafe autofixes iteratively, review each change, and resolve remaining findings with targeted edits or user decisions. |
| [`sql-optimization`](awesome-copilot/development/sql-optimization/SKILL.md) | Universal SQL performance optimization assistant for comprehensive query tuning, indexing strategies, and database performance analysis across all SQL databases (MySQL, PostgreSQL, SQL Server, Oracle). Provides execution plan analysis, pagination optimization, batch operations, and performance monitoring guidance. |

### Awesome Copilot: testing

| Skill | Description |
|-------|-------------|
| [`java-junit`](awesome-copilot/testing/java-junit/SKILL.md) | Write, review and fix Java unit tests with JUnit 5 and JUnit 6 (Jupiter), AssertJ and Mockito: assertions, parameterized and nested tests, mocking rules, deterministic time and randomness, Surefire vs Failsafe, JaCoCo coverage, optional PIT mutation testing, and guardrails for agents (never skip or delete failing tests). Use when adding, refactoring or debugging tests in Maven or Gradle projects. Framework-neutral. |
| [`java-testcontainers`](awesome-copilot/testing/java-testcontainers/SKILL.md) | Write reliable integration tests in plain Java with Testcontainers 2.x: JUnit Jupiter lifecycle, singleton containers, reuse, generic containers, wait strategies, networks, init scripts, Docker Compose, CI and Docker/Podman setup. Use when adding or fixing Testcontainers tests, or migrating from 1.x. Framework-neutral. |
| [`pytest-coverage`](awesome-copilot/testing/pytest-coverage/SKILL.md) | Run pytest tests with coverage, discover lines missing coverage, and increase coverage to 100%. |
| [`spring-boot-testing`](awesome-copilot/testing/spring-boot-testing/SKILL.md) | Expert Spring Boot 4 testing specialist that selects the best Spring Boot testing techniques for your situation with Junit 6 and AssertJ. |

### Awesome Copilot: debugging

| Skill | Description |
|-------|-------------|
| [`java-debugging`](awesome-copilot/debugging/java-debugging/SKILL.md) | Debug Java applications systematically: JDWP remote debugging, jdb, VS Code and IntelliJ attach, debugging Maven/Gradle tests, Spring Boot and Quarkus dev mode, containers, breakpoints/logpoints, and reading stack traces. Use when the user needs to find the cause of a Java bug, exception, wrong behavior, or failing test, or asks how to attach a debugger. |
| [`java-diagnostics`](awesome-copilot/debugging/java-diagnostics/SKILL.md) | Symptom-first runtime diagnostics for JVM applications using JDK tools: jcmd, jstack, jmap, jstat, JFR, GC logs, async-profiler, Native Memory Tracking, and Eclipse MAT. Use when a Java app has high CPU, memory leaks or OutOfMemoryError, slow startup, deadlocks or thread starvation, long GC pauses, native memory growth, or slow requests. Includes permission tiers for safe use. |

### Awesome Copilot: docs and onboarding

| Skill | Description |
|-------|-------------|
| [`acquire-codebase-knowledge`](awesome-copilot/docs-and-onboarding/acquire-codebase-knowledge/SKILL.md) | Use this skill when the user explicitly asks to map, document, or onboard into an existing codebase. Trigger for prompts like "map this codebase", "document this architecture", "onboard me to this repo", or "create codebase docs". Do not trigger for routine feature implementation, bug fixes, or narrow code edits unless the user asks for repository-level discovery. |
| [`context-map`](awesome-copilot/docs-and-onboarding/context-map/SKILL.md) | Generate a map of all files relevant to a task before making changes |
| [`create-agentsmd`](awesome-copilot/docs-and-onboarding/create-agentsmd/SKILL.md) | Prompt for generating an AGENTS.md file for a repository |
| [`create-architectural-decision-record`](awesome-copilot/docs-and-onboarding/create-architectural-decision-record/SKILL.md) | Create an Architectural Decision Record (ADR) document for AI-optimized decision documentation. |

### Awesome Copilot: productivity

| Skill | Description |
|-------|-------------|
| [`brag-sheet`](awesome-copilot/productivity/brag-sheet/SKILL.md) | Turn vague "what did I do?" into evidence-backed impact statements for performance reviews, self-reviews, promotion packets, and weekly updates. Uniquely mines Copilot CLI session logs to reconstruct forgotten work, plus git commits and GitHub PRs. Enforces a 3-part impact contract (action → result → evidence). Works standalone with zero dependencies. Trigger for: "brag", "log work", "what did I do", "backfill my work history", "performance review", "self-review", "self assessment", "write impact statement", "review prep", "promo packet", "promotion case", "weekly update", "status report", "accomplishments", "what did I ship", "I forgot to log my work", "summarize my work", "track my wins", "what should I highlight", "end of half", "career growth", "work journal", or any request to document, summarize, or organize work accomplishments. |
| [`conventional-commit`](awesome-copilot/productivity/conventional-commit/SKILL.md) | Prompt and workflow for generating conventional commit messages using a structured XML format. Guides users to create standardized, descriptive commit messages in line with the Conventional Commits specification, including instructions, examples, and validation. |
| [`git-commit`](awesome-copilot/productivity/git-commit/SKILL.md) | Use this skill when the user wants to make a Git commit or split changes into more than one commit. Also use it when the user types "/commit" or asks for a conventional commit. The skill examines the diff, stages the related files, writes a Conventional Commits message, and runs git commit. Do not use it when the user wants only a commit message and no commit. Do not use it to push, open a pull request, rebase, or change the commit history. |
| [`harness-engineering`](awesome-copilot/productivity/harness-engineering/SKILL.md) | Adopt repository-level harness engineering for coding agents. Use when a user wants to prevent repeated AI coding-agent mistakes by turning failures into durable instructions, drift checks, regression tests, failure memory, and adoption reports tailored to the target repository. |
| [`remember`](awesome-copilot/productivity/remember/SKILL.md) | Transforms lessons learned into domain-organized memory instructions (global or workspace). Syntax: `/remember [>domain [scope]] lesson clue` where scope is `global` (default), `user`, `workspace`, or `ws`. |

### HTML Anything (nexu-io, translated to English)

| Skill | Description |
|-------|-------------|
| [`deck-guizang-editorial`](html-anything/deck-guizang-editorial/SKILL.md) | E-magazine × e-ink: 10 layouts and 5 palettes (Monocle ink, Indigo Porcelain, Forest Ink, Kraft Paper, Dune) |
| [`doc-kami-parchment`](html-anything/doc-kami-parchment/SKILL.md) | Warm parchment ground (#f5f4ed) + single ink-blue accent (#1B365D) + one serif typeface: editorial-grade typesetting |
| [`magazine-poster`](html-anything/magazine-poster/SKILL.md) | Sunday-paper style: large serif headline, two-column body text, numbered sections |
<!-- skills:end -->

## Updating

Copy the newer skill folders over these, update the versions in the table above, then regenerate the list:

```sh
cd skills_updated && python3 scripts/skills_index.py --write
```

CI (`.github/workflows/skills.yml`) runs `python3 scripts/skills_index.py`. It fails if a skill lacks a name or
description, or if this list is out of date.
