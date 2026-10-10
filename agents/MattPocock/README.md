# Matt Pocock: Copilot's default agent with Matt Pocock's skills

**Matt Pocock** is the default GitHub Copilot agent in VS Code with one difference: its only skills are the 27
`engineering` and `productivity` skills of [mattpocock/skills](https://github.com/mattpocock/skills) (MIT), the same
set his own plugin installs. It keeps the default agent's tools, model and subagents.

| File | What it is |
|------|------------|
| [`.github/agents/matt-pocock.agent.md`](.github/agents/matt-pocock.agent.md) | The agent: where its skills are, how to use them, and the list of skills. |
| [`files.txt`](files.txt) | What the installers download: the agent file and each skill's files from [`../../skills_updated/matt-pocock/`](../../skills_updated/matt-pocock/). |

Install, from your project's root folder (PowerShell and user-level install:
[`../README.md`](../README.md#install)):

```bash
curl -fsSL https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/install.sh | sh -s -- MattPocock
```

Most of Matt's skills run only when you name them (`/tdd` and `/diagnosing-bugs` are picked on their own; `/grill-me`,
`/to-spec`, `/to-tickets`, `/implement` and `/triage` wait for you). In a new repository, start with
`/setup-matt-pocock-skills`: it records your issue tracker, triage labels and docs layout, which several of the other
skills read. Not sure which skill fits? Ask `/ask-matt`.

How the skills are kept to this agent, and how to update: [`../README.md`](../README.md#the-skill-agents).
