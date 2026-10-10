# agents: custom agents for GitHub Copilot in VS Code

Custom agents to download into your own projects (or into `~/.copilot/` for all of them). Each folder is one agent.

| Agent | What it is | Install |
|-------|------------|---------|
| [`ReviewAgent/`](ReviewAgent/) | **Code Reviewer**: an agent that never edits code and reviews changes against a Jira ticket (read with your `jira-cli` and `confluence-cli` skills), plan or requirements, and for unintended logic or endpoint changes, missed reuse, duplicated logic, KISS, YAGNI, DRY, SOLID and clean code. | One file, see [its README](ReviewAgent/README.md#install) |
| [`TesterAgent/`](TesterAgent/) | **Story Tester**: an agent that reads a Jira story (with your `jira-cli` skill) and writes Bruno requests for it into the open collection: a folder per story, a subfolder per positive, negative and boundary scenario, in run order, following the collection's conventions. Uses only variable references for the token and API key, never runs the requests unless you ask, never edits code. | One file, see [its README](TesterAgent/README.md#install) |
