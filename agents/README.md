# agents: custom agents for GitHub Copilot in VS Code

Custom agents to download into your own projects (or into `~/.copilot/` for all of them). Each folder is one agent.

| Agent | What it is | Install |
|-------|------------|---------|
| [`ReviewAgent/`](ReviewAgent/) | **Code Reviewer**: a read-only agent that reviews code changes against the Jira story, plan or requirements you give it, and for unintended logic or endpoint changes, missed reuse, duplicated logic, KISS, YAGNI, DRY, SOLID and clean code. | One file, see [its README](ReviewAgent/README.md#install) |
| [`MattPocock/`](MattPocock/) | **Matt Pocock**: Copilot's default agent with [Matt Pocock's skills](https://github.com/mattpocock/skills) (27: `tdd`, `diagnosing-bugs`, `grill-me`, `to-spec`, `code-review`, …) as its only skills. | `install.sh MattPocock` |
| [`JesseVincent/`](JesseVincent/) | **Jesse Vincent**: Copilot's default agent with obra's [Superpowers](https://github.com/obra/superpowers) (15: `brainstorming`, `writing-plans`, `test-driven-development`, `systematic-debugging`, …) as its only skills. | `install.sh JesseVincent` |

## The skill agents

**Matt Pocock** and **Jesse Vincent** are the default agent (the **Agent** entry of the agent picker) with one
difference: their skills. They keep the default agent's tools, model and subagents, because their agent files leave
`tools`, `model` and `agents` out, and their instructions only say where their skills are and how to use them.

VS Code has no setting that gives a skill to one agent only: every skill in `.github/skills/`, `.agents/skills/`,
`.claude/skills/` or `~/.copilot/skills/` is offered to every agent. So these agents keep their skills in
`agent-skills/<name>/` next to their agent file, a folder VS Code doesn't load skills from, and each agent's
instructions list its skills (name, when to use it, file) and tell it to read a skill's `SKILL.md` when it fits.
Other agents, the default one included, don't see these skills.

They are told not to use any other skill. If you also have skills installed in the usual folders, VS Code still
lists those to every agent, so the model can see them; for a clean split, keep the usual folders empty and install
your skills through agents like these.

The skills come from [`../skills_updated/`](../skills_updated/), which keeps them at their latest versions, so
reinstalling updates them:

- **Matt Pocock**: the `engineering` and `productivity` skills, the same set his own plugin installs. His `misc` skills
  ("kept around, rarely used") and his beta `in-progress` skills are left out.
- **Jesse Vincent**: all 15 Superpowers skills. Like Superpowers' own plugins, which load `using-superpowers` at the
  start of every session, the agent reads `using-superpowers` before its first answer in every conversation.

### Install

From your project's root folder. This writes `.github/agents/<name>.agent.md` and `.github/agent-skills/<name>/`;
commit them to share the agent with your team.

```bash
curl -fsSL https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/install.sh | sh -s -- MattPocock
curl -fsSL https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/install.sh | sh -s -- JesseVincent
```

On Windows (PowerShell):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/install.ps1))) MattPocock
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/install.ps1))) JesseVincent
```

Add `--user` (PowerShell: `-User`) to install into `~/.copilot/agents/` and `~/.copilot/agent-skills/` instead, for
all your projects. Run the same command again to update; it replaces the agent's skills folder as a whole.

Then:

1. In VS Code user settings, turn on `github.copilot.chat.cli.customAgents.enabled` (off by default; without it
   Copilot sessions ignore custom agents). See [`../vscode_copilot_agents/`](../vscode_copilot_agents/) for the rest
   of the recommended setup.
2. Command Palette → **Chat: Open Customizations** → **Agents** should list **Matt Pocock** and **Jesse Vincent**.
   Don't put other `.md` files in `.github/agents/`: VS Code loads every one of them as an agent.

### Use

Pick **Matt Pocock** or **Jesse Vincent** in the agent picker and work as you would with the default agent. The agent
picks a skill when one fits; to ask for one, name it (`/tdd`, "use grill-me", "brainstorm this with me"). Skills
marked **on request** in the agent file (for example Matt's `grill-me` and `teach`) run only when you name them.

With a user-level install the skills live outside your workspace, so VS Code may ask you to allow reading them the
first time.

## Maintaining

[`scripts/skill_agents.py`](scripts/skill_agents.py) builds each skill agent's skills table and its `files.txt` (the
files the installers download) from `skills_updated/`. After updating `skills_updated/`, run
`python3 agents/scripts/skill_agents.py --write` from the repository root. The `agents` workflow fails when they are
out of date, checks ReviewAgent's tools, and installs both skill agents from the checkout to compare them with
`skills_updated/`.
