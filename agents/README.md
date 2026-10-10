# agents: custom agents for GitHub Copilot in VS Code

Custom agents to download into your own projects (or into `~/.copilot/` for all of them). Each folder is one agent.

| Agent | What it is | Install |
|-------|------------|---------|
| [`ReviewAgent/`](ReviewAgent/) | **Code Reviewer**: an agent that never edits code and reviews changes against a Jira ticket (read with your `jira-cli` and `confluence-cli` skills), plan or requirements, and for unintended logic or endpoint changes, missed reuse, duplicated logic, KISS, YAGNI, DRY, SOLID and clean code. | One file, see [its README](ReviewAgent/README.md#install) |
| [`TesterAgent/`](TesterAgent/) | **Story Tester**: an agent that tests only the parts of a Jira story you choose (read with your `jira-cli` skill), with `curl`, the browser and other tools, after you approve its test plan. Takes secrets only as environment variables and never shows them. Never edits code. | One file, see [its README](TesterAgent/README.md#install) |
