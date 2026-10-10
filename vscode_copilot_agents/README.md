# VS Code + GitHub Copilot for agents, subagents and skills

How to set up Visual Studio Code and the GitHub Copilot extension so agents do more of the work, with less context,
fewer AI credits and fewer approval interruptions.

Everything here was checked against the VS Code documentation approved on **2026-09-30**
([microsoft/vscode-docs](https://github.com/microsoft/vscode-docs), `docs/agents` and `docs/agent-customization`).
VS Code ships monthly and many agent settings are Experimental or Preview, so if a setting is greyed out or unknown,
look it up in the [AI settings reference](https://code.visualstudio.com/docs/agents/reference/ai-settings).

| File | What it is |
|------|------------|
| [`settings/user-settings.jsonc`](settings/user-settings.jsonc) | Recommended user settings, each one commented. Merge into your `settings.json`. |
| [`template/`](template/) | A starter kit to copy into a repository: `AGENTS.md`, a scoped instructions file, four custom agents (orchestrator, researcher, reviewer, planner), a `verify-change` skill, `.mcp.json` and workspace settings. |
| [`install-skills.sh`](install-skills.sh) | Installs skills from [`../skills_updated/`](../skills_updated/) (or any folder) so VS Code actually loads them. |

## Quick setup

1. **Update VS Code and the GitHub Copilot extension**, then sign in to GitHub.
2. **Apply the user settings**: Command Palette → **Preferences: Open User Settings (JSON)**, then merge in
   [`settings/user-settings.jsonc`](settings/user-settings.jsonc). The one you must not miss is
   `"github.copilot.chat.cli.customAgents.enabled": true`; it is off by default, and without it Copilot sessions ignore
   your custom agents.
3. **Use the Copilot harness**: in the chat input, set **Session Target** to **Copilot**. The Local harness is
   deprecated and will be removed.
4. **Copy [`template/`](template/) into your repository root** and replace the example content in `AGENTS.md` with
   your project's real commands and rules. Delete the parts you don't need.
5. **Install a few skills you'll actually use**:
   `./install-skills.sh ../skills_updated/superpowers` installs into `~/.copilot/skills/`.
6. **Check what loaded**: Command Palette → **Chat: Open Customizations**. Every agent, skill and instructions file
   should be listed for the Copilot target, with no validation errors or warnings. Tool names can differ per harness
   and a missing tool is silently ignored, so check the template agents too.
7. **Try it**: pick **Orchestrator** in the agent picker and give it a small, testable task. The `agents:` limits,
   handoffs, nesting and model order in [section 3](#3-custom-agents-and-subagents) are documented for the Local
   harness; check that Copilot honours them for you, or use Local if you depend on them.

## How the pieces fit

Start from a problem you've seen more than once, and add the smallest piece that fixes it.

| You keep seeing… | Use | Where it lives | Loaded when |
|------------------|-----|----------------|-------------|
| The agent forgets a project command or rule | **Project instructions** | `AGENTS.md` or `.github/copilot-instructions.md` | Every request |
| The rule only matters for some files | **Targeted instructions** | `.github/instructions/*.instructions.md` with `applyTo` | A matching file is edited, or the `description` matches the task |
| You explain the same multi-step procedure | **Skill** | `.github/skills/<name>/SKILL.md` | The agent decides it's relevant, or you type `/<name>` |
| A recurring role needs its own instructions or fewer tools | **Custom agent** | `.github/agents/<name>.agent.md` | You pick it, or another agent calls it as a subagent |
| The agent needs an outside system (browser, DB, tracker) | **MCP server** | `.mcp.json` | The agent calls one of its tools |
| Something must *always* happen (format, block a command) | **Hook** | `.github/hooks/*.json` | On a lifecycle event, regardless of the model |
| You want a ready-made bundle of the above | **Plugin** | Installed from a marketplace | Each part follows its own rule |

Instructions and skills guide the model; it can still ignore them. Hooks are the only deterministic piece.

Scope: put personal preferences at user level (`~/.copilot/…`), project rules in the repository (shared through
git), and organization rules in GitHub organization settings.

## 1. Pick the right harness and session

The **Session Target** control in the chat input picks the *harness*, the runtime that runs the agent loop.

| Target | Use it for |
|--------|------------|
| **Copilot** (recommended default) | Everyday coding. Runs on the Agent Host on your machine, a remote host or a Dev Container, and shares its runtime, skills and hooks with Copilot CLI and the GitHub Copilot app. |
| **Local** | Only if you need a VS Code extension tool or a model the Copilot harness doesn't offer. Deprecated: prompt files and the `chat.*FilesLocations` settings only work here. |
| **Claude** / **Codex** | You already use that provider's workflow (Claude uses `CLAUDE.md`, `.claude/agents`, `.claude/rules`). |
| **Cloud** | A well-scoped task that should come back as a pull request without your machine. In a Copilot session, `/delegate` hands the current task to the cloud. |

Session habits that pay off:

- **One task per session.** Start a new chat (`+`) when the topic changes; old context costs tokens on every turn.
- **Parallel work goes in worktrees.** In the Agents window, tick **New Worktree** so two sessions don't edit the same
  files. Worktree sessions run with **Allow all**, so use **Folder** when you want approval prompts.
  `git.worktreeIncludeFiles` (Experimental) copies ignored files into each worktree. Only list files the agent can
  safely read: under **Allow all**, a copied `.env` hands your secrets to an agent that never asks. A workspace value
  replaces the user one. For `node_modules`, `git.worktreeSymlinkFolders` (Experimental) links the folder instead, but
  changes through the link affect your main checkout.
- **`/fork`** to try an alternative without losing context; **`/compact focus on …`** when a long session gets slow.
- **Plan first** for anything spanning several files: the **Plan** agent (or the template's `Planner`) researches and
  writes a plan; review it, then implement.
- **`/rubber-duck <question>`** (Copilot harness) gets a read-only second opinion from a complementary model.

## 2. Instructions

- **One always-on file.** Prefer `AGENTS.md` at the repo root: Copilot, Codex and the Local harness all read it.
  `.github/copilot-instructions.md` works too. Avoid keeping both with different content.
- **Keep it short.** It's sent with every request. Write only what the agent can't infer from the code: the exact
  test, lint and build commands, architecture boundaries, non-obvious rules. Give the reason behind a rule; the model
  handles edge cases better when it knows why.
- **Move file-specific rules into `.github/instructions/*.instructions.md`** with an `applyTo` glob and a
  `description` saying when to use it (see [`template/.github/instructions/tests.instructions.md`](template/.github/instructions/tests.instructions.md)).
- **Monorepos**: nested `AGENTS.md` files per package. The Copilot harness applies its own nested `AGENTS.md` rules;
  the Local harness needs `chat.useNestedAgentsMdFiles`. Use `chat.useCustomizationsInParentRepositories` when you
  open a subfolder instead of the repo root.
- **Shell setup**: in local Copilot sessions, shell commands don't load `~/.bashrc` unless
  `chat.agentHost.shellTool.initScript.enabled` is on, so `nvm` or `pyenv` commands from `AGENTS.md` can fail.
- **Personal preferences** go in `~/.copilot/copilot-instructions.md` or `~/.copilot/instructions/`, never in the repo.
- **Memory is not instructions.** The agent's memory (`/memories/`) is local to your machine. When something in it
  proves true and useful, move it into `AGENTS.md` where the team can review it.
- Generate a first draft with `/init` in a Local session (in Copilot sessions: **Chat: Open Customizations** →
  **Overview**, then describe what you want), then cut it down. Generated instructions are usually too long.

## 3. Custom agents and subagents

> The delegation mechanics differ by harness. The `agents` field, `runSubagent`, nesting, model order and the
> `chat.subagents.*` settings below are documented for VS Code's own (Local) harness. The Copilot harness delegates
> through the Copilot SDK; see GitHub's
> [custom agents in Copilot](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-custom-agents)
> for what it honours, and check in **Chat: Open Customizations** that your agents show no validation warnings.
> Claude and Codex use their native subagent formats.

A **custom agent** is a `.agent.md` file: instructions plus a tool list plus an optional model. A **subagent** is any
agent the main agent starts in its own, separate context. It does a self-contained task and returns only its result,
so the main conversation stays small. Your custom agents become the subagents.

Turn on `github.copilot.chat.cli.customAgents.enabled` first. Agents live in `.github/agents/` (shared) or
`~/.copilot/agents/` (personal).

### The front matter that matters

```yaml
---
name: Researcher                  # how other agents refer to it; case-sensitive
description: Read-only codebase research. Finds files and patterns and reports back.
tools: ['read', 'search', 'web/fetch']   # only what the role needs
user-invocable: false             # hide from the agent picker; still callable as a subagent
model: ['<fast model>', '<fallback>']    # optional; tried in order; names as shown in the model picker
---
```

| Field | Use it to |
|-------|-----------|
| `tools` | Give each role the narrowest tool set. Read-only roles get `read`, `search`; implementers add `edit`, `execute`. Coordinators need `agent` to start subagents. |
| `agents` | Limit which subagents a coordinator may call: `['Researcher', 'Reviewer']`. `[]` disables delegation. |
| `user-invocable: false` | Keep helper agents out of the picker. |
| `disable-model-invocation: true` | Stop other agents from calling this one (you can still pick it). Listing it by name in a coordinator's `agents` overrides this. |
| `model` | Run cheap roles (research, search) on a cheaper model. Leave it out to inherit the chat's model. |
| `handoffs` | Add a button after a response, for example *Planner → "Implement the plan" → Orchestrator*. |

Built-in tool sets: `read`, `search`, `edit`, `execute`, `web`, `browser`, `agent` (plus single tools such as
`todos` and `web/fetch`). A tool that isn't
available is silently ignored, so a typo means a missing tool, not an error. An MCP server's tools are `<server>/*`.

### The pattern: coordinator plus read-only workers

The [`template/.github/agents/`](template/.github/agents/) folder implements it:

- **Orchestrator** (pick this one) plans, delegates research, implements, runs the checks, asks for review, fixes.
- **Researcher** and **Reviewer** are read-only, hidden from the picker, and return short structured reports.
- **Planner** writes a plan and hands off to Orchestrator.

Why it's efficient: the file reading and searching happens in the workers' contexts and is thrown away; the
coordinator only sees the summaries. Workers can run on a cheaper model, and several can run in parallel.

Rules that make subagents work well:

- **Write the delegated task as if for a stranger.** A subagent doesn't see your conversation. Give it the goal, the
  relevant context and decisions, what it may do ("do not edit files"), and the exact shape of the answer.
- **Parallelize independent questions**: "Research X and Y in parallel with two subagents, then compare."
- **Don't delegate small things.** Delegation costs tokens. A lookup of one or two files is cheaper done directly.
- **Nested delegation** needs `chat.subagents.allowInvocationsFromSubagents` (max depth 5). The template agents don't
  recurse, so the settings file leaves it off. Always write a stopping rule into a recursive agent.
- `chat.subagents.defaultToAuto` routes subagents without a pinned model to Auto. Auto here is not limited to the
  main model's cost tier, so pin `model:` on worker agents when cost matters.
- Watch them: in the Agents window each subagent opens as a read-only chat; `chat.subagents.showCreditUsage` shows
  what each one cost.

## 4. Skills

A skill is a folder with a `SKILL.md` and optional scripts, templates and examples. Only each skill's name and
description sit in context; the body loads when the agent decides the skill fits (or you type `/<name>`), and
supporting files load only when the body links to them. So you can install many skills cheaply, but every description
still costs a little context and competes for the agent's attention.

**Where**: `.github/skills/`, `.agents/skills/` or `.claude/skills/` in a repository; `~/.copilot/skills/`,
`~/.agents/skills/` or `~/.claude/skills/` for you personally. The same `SKILL.md` works in Copilot CLI, the Copilot
app, the Copilot cloud agent and other agents that follow the [Agent Skills](https://agentskills.io) standard.

**The rules that make a skill silently not load:**

- `name` must be lowercase letters, digits and hyphens, at most 64 characters, **and equal to its folder name**.
- No prefixes in `name` (`myorg/x`, `myorg:x`); plugins add their own prefix.
- `description` (max 1024 characters) must say what the skill does **and when to use it**. This is the only thing
  the agent sees when choosing.
- Supporting files must be linked from `SKILL.md` with relative paths, for example `[template](./template.ts)`.

**Who can trigger it:**

| Front matter | `/` command | Agent loads it automatically | Use for |
|--------------|:-----------:|:----------------------------:|---------|
| (default) | ✓ | ✓ | Most skills |
| `user-invocable: false` | | ✓ | Background knowledge |
| `disable-model-invocation: true` | ✓ | | Things you only want on demand (deploy, release) |

**`context: fork`** runs the skill in its own subagent and returns only the result. Use it for skills that read a lot
(reviews, audits, investigations). It needs `github.copilot.chat.skillTool.enabled`.

**Installing the skills from this repo.** [`../skills_updated/`](../skills_updated/) holds 97 skills in nested
folders, and three of them have a `name` that differs from their folder (`vercel-react-best-practices`,
`vercel-composition-patterns`, `design-taste-frontend`), which VS Code would skip. The script handles both:

```bash
./install-skills.sh ../skills_updated/superpowers           # one collection -> ~/.copilot/skills
./install-skills.sh ../skills_updated/popular/anthropic/skill-creator
TARGET=/path/to/repo/.github/skills ./install-skills.sh <folder>   # into a repository, for the team
FORCE=1 ./install-skills.sh <folder>                        # overwrite what's already installed
```

A relative `TARGET` is relative to your current directory, so use an absolute path or run it from the repo root.
Running it with no argument installs everything (96 skills; `test-driven-development` exists twice, so the second copy
is skipped, even with `FORCE=1`). Prefer installing the few collections you use.

**Making your own**: type `/create-skill <what it should do>`, or after a session that went well, ask "create a skill
from how we just did that". Keep the body a procedure (numbered steps, exact commands, what to report), not an essay.
The [`verify-change`](template/.github/skills/verify-change/SKILL.md) skill in the template is a small example.

## 5. MCP servers, hooks and plugins

**MCP servers** give agents external tools. For new servers use the portable files, which the Copilot harness reads
natively: `.mcp.json` in the repository (`mcpServers` object) or `~/.copilot/mcp-config.json` for you. `.vscode/mcp.json`
is the older VS Code-only format. Copilot sessions can currently use only **local** MCP servers that don't need
authentication. Every server's tools are added to every request, so enable only what the task needs: in Copilot
sessions, **Chat: Open Customizations** → **Tools** tab (applies to your whole profile); in Local sessions, the
**Configure Tools** button in the chat input. Never put API keys in the file. `${input:…}` variables work only in
the older `.vscode/mcp.json` format and only in Local sessions; for Copilot, pass secrets through the server's `env`
from your shell environment, and never commit them.

The template's `.mcp.json` is empty on purpose: a server in it starts for anyone who trusts the repo. For browser
work, try the built-in browser tools first. If you do need a server, pin its version, for example:

```jsonc
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@microsoft/mcp-server-playwright@<version>"]  // pin an exact version, never @latest
    }
  }
}
```

**Hooks** run your command at lifecycle points (before or after a tool call, at session start, before the agent
stops). Use them for what must always happen: format after edits, block a dangerous command, log tool use. The schema
depends on the harness: Copilot uses the
[GitHub Copilot hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference) (same as Copilot CLI),
Local uses VS Code's own. Files go in `.github/hooks/*.json`; `/create-hook <description>` drafts one. Treat hooks as
executable code and review them like code.

**Plugins** bundle skills, agents, MCP servers and hooks into one install. Enable `chat.plugins.enabled`, then search
`@agentPlugins` in the Extensions view. The default marketplaces are `github/copilot-plugins` and
`github/awesome-copilot`; add more with `chat.plugins.marketplaces`. Plugins can run code on your machine, so check the
publisher first. Plugins installed with Copilot CLI show up in VS Code automatically.

## 6. Spend less, get more

- **Auto model** as the default; pin a stronger model only for planning and hard debugging, and a cheaper one on
  worker agents. The cheapest model isn't the cheapest result if it needs retries.
- **Leave thinking effort at its default** unless the task is genuinely hard.
- **Keep tools few.** Large tool catalogs inflate every request. Give custom agents narrow `tools` lists, and turn
  off unused tools in **Chat: Open Customizations** → **Tools** (Copilot) or **Configure Tools** (Local).
- **Exclude noise** with `search.exclude` and `.gitignore`: build output, lockfiles, generated code, logs. Search hits
  count toward context even when the agent never opens the file.
- **Script repetitive loops.** Ten similar tool calls cost more than one script that returns a summary.
- **Ground the agent**: name the files, the error, and the success criterion in the prompt instead of letting it
  explore. Ask it to run the tests so it can check its own work.
- **Keep prompt prefixes stable** so the prompt cache hits. **Agent Debug Logs → Cache Explorer** shows the hit rate.
- **Measure**: hover a response for its credit cost, hover the context-window control for the session total, and run
  `/chronicle:cost-tips` for personal suggestions.
- `chat.tools.compressOutput.enabled` shrinks large terminal output before the model sees it.

## 7. Approvals without babysitting

- **Manual permissions** (default) plus a terminal allow-list is the best balance. Allow read-only git and your test,
  lint and build commands in `chat.tools.terminal.autoApprove` (see the settings file). A `false` rule asks; it never
  blocks. Use a hook to actually block something: `preToolUse` per the GitHub hooks reference in Copilot sessions,
  `PreToolUse` in VS Code's schema in Local sessions. `chat.permissions.default` sets the level new sessions start with.
- **Test and build commands run code from the repo.** An agent that edits `package.json` or `conftest.py` can then
  run anything without a prompt, so pair the allow-list with the sandbox (below).
- **Assisted permissions** (`chat.assistedPermissions.enabled`) has a model judge each call and asks you only when it
  doesn't approve. Fewer prompts, but the judge can be wrong.
- **Allow all** and **Autopilot** (keeps going until done, answers its own questions) are for trusted repos and
  worktrees. Pair them with the terminal **sandbox** (`chat.agent.sandbox.enabled`, Preview on macOS, Linux and WSL2;
  Experimental for the Copilot built-in shell), which still limits the file system when nothing asks you. It leaves
  the network open unless you set `chat.agent.sandbox.allowNetwork` to `false`; for the Copilot built-in shell that
  blocks all outbound access, without domain lists. `/sandbox-policy` shows what a Copilot session applies.
- `/yolo` turns on auto-approval for the current session only; `/disableYolo` turns it off. Prefer that to the global
  `chat.tools.global.autoApprove`.

## 8. Check it's working

- **Chat: Open Customizations** (or the gear icon in Chat) lists what the *selected harness* found. Select the harness
  first; the list differs per harness.
- Expand **References** under a response to see which instructions and skills were used.
- **Developer: Open Agent Debug Logs** shows discovery errors, the full request, tool calls and token use.
- The **[Chat Customizations Evaluations](https://marketplace.visualstudio.com/items?itemName=ms-vscode.vscode-chat-customizations-evaluations)**
  extension (or `/analyze-prompt`) flags contradictions and vague wording in instructions, agents and skills.

If something doesn't load: wrong harness selected, file in a location that harness doesn't read, `applyTo` not
matching, a skill `name` that doesn't match its folder, or custom agents not enabled for Copilot.

## Moving from older setups

- **Prompt files** (`.github/prompts/*.prompt.md`) are deprecated: the Copilot harness doesn't load them. Convert them
  to skills: **Chat: Open Customizations** → **Overview** → **Migrate Prompt Files**.
- **Chat modes** (`.chatmode.md`) are custom agents now: rename to `.agent.md` and move to `.github/agents/`.
- **`infer`** in agent front matter is replaced by `user-invocable` and `disable-model-invocation`.
- **`chat.agentFilesLocations`, `chat.instructionsFilesLocations`, `chat.agentSkillsLocations`,
  `chat.promptFilesLocations`** are deprecated; move the files to the standard folders above. The **Migrate Location
  Settings** card does it once you enable `chat.customizations.locationsMigration.enabled`.
- **User-level agents and instructions stored in your VS Code profile** aren't read by the Copilot harness; the
  **Migrate User Data Customizations** card moves them to `~/.copilot/` once you enable
  `chat.customizations.userDataMigration.enabled`.

## Sources

VS Code docs: [customization concepts](https://code.visualstudio.com/docs/agents/concepts/customization),
[custom instructions](https://code.visualstudio.com/docs/agent-customization/custom-instructions),
[custom agents](https://code.visualstudio.com/docs/agent-customization/custom-agents),
[subagents](https://code.visualstudio.com/docs/agents/run/subagents),
[agent skills](https://code.visualstudio.com/docs/agent-customization/agent-skills),
[agent harnesses](https://code.visualstudio.com/docs/agents/run/agent-harnesses),
[hooks](https://code.visualstudio.com/docs/agent-customization/hooks),
[MCP servers](https://code.visualstudio.com/docs/agent-customization/mcp-servers),
[agent plugins](https://code.visualstudio.com/docs/agent-customization/agent-plugins),
[approvals](https://code.visualstudio.com/docs/agents/run/approvals),
[optimize AI credit usage](https://code.visualstudio.com/docs/agents/guides/optimize-usage),
[best practices](https://code.visualstudio.com/docs/agents/best-practices),
[AI settings reference](https://code.visualstudio.com/docs/agents/reference/ai-settings).
Standards: [agentskills.io](https://agentskills.io), [agent-plugins.org](https://agent-plugins.org/).
