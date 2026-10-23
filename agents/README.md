# agents: custom agents for GitHub Copilot in VS Code

Custom agents to download into your own projects (or into `~/.copilot/` for all of them). Each folder is one agent.

| Agent | What it is | Install |
|-------|------------|---------|
| [`ReviewAgent/`](ReviewAgent/) | **Code Reviewer**: an agent that never edits code and reviews changes against a Jira ticket (read with your `jira-cli` and `confluence-cli` skills), plan or requirements, and for unintended logic or endpoint changes, missed reuse, duplicated logic, KISS, YAGNI, DRY, SOLID and clean code. | One file, see [its README](ReviewAgent/README.md#install) |
| [`TesterAgent/`](TesterAgent/) | **Story Tester**: an agent that reads a Jira story (with your `jira-cli` skill), finds the test cases (positive, negative, boundary, and extra ones from the code) and creates the test files: Bruno requests in your open collection (a folder per story, a subfolder per scenario, in run order, following the collection's conventions), or a test plan with curl and browser steps. Runs nothing unless you ask, never against production, deletes only data it created, never edits code. | One file, see [its README](TesterAgent/README.md#install) |
| [`ServiceMapAgent/`](ServiceMapAgent/) | **Service Mapper**: maps a microservice system, one repository per session (Terraform and GitHub Actions repositories too), into an offline HTML map: every endpoint with when to use it, who calls whom, step-by-step diagrams of what each endpoint does down to the database, journeys across services, risks, data, infrastructure. Writes only the map's data files. [Demo](ServiceMapAgent/viewer/index.html). | One file plus the viewer folder, see [its README](ServiceMapAgent/README.md#set-up) |
