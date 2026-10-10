# Jesse Vincent: Copilot's default agent with obra's Superpowers

**Jesse Vincent** is the default GitHub Copilot agent in VS Code with one difference: its only skills are the 15
skills of [obra/superpowers](https://github.com/obra/superpowers) (MIT), Jesse Vincent's development methodology
(brainstorm → plan → test-driven implementation → review → finish the branch). It keeps the default agent's tools,
model and subagents.

| File | What it is |
|------|------------|
| [`.github/agents/jesse-vincent.agent.md`](.github/agents/jesse-vincent.agent.md) | The agent: where its skills are, how to use them, and the list of skills. |
| [`files.txt`](files.txt) | What the installers download: the agent file and each skill's files (with their scripts) from [`../../skills_updated/superpowers/`](../../skills_updated/superpowers/). |

Install, from your project's root folder (PowerShell and user-level install:
[`../README.md`](../README.md#install)):

```bash
curl -fsSL https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/install.sh | sh -s -- JesseVincent
```

Like Superpowers' own plugins, which load `using-superpowers` at the start of every session, the agent reads
`using-superpowers` before its first answer in every conversation; that skill makes it check for a fitting skill
before it does anything. So "let's build X" starts with `brainstorming`, and "fix this bug" with
`systematic-debugging`. Superpowers' scripts (`executing-plans`, `subagent-driven-development`, the `brainstorming`
visual companion) are shell scripts, so they need a Unix shell: macOS, Linux, WSL or Git Bash.

How the skills are kept to this agent, and how to update: [`../README.md`](../README.md#the-skill-agents).
