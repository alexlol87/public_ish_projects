# Fixed bugs and done todos are archived away from live Notes

Open bugs and todos live in each Repo's `bugs.md` and `todo.md`. Once fixed or done, they move to the Project's archive,
which agents are told not to read unless asked. Keeping closed items next to open ones would grow the lists without
limit and lead agents to treat old, fixed problems as current. We chose archiving over deleting so the history (what the
bug was and which Endpoint or Repo it came from) can still be found by people.
