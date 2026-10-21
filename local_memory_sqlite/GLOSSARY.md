# Glossary

**Memory**: one fact, preference or instruction the agent keeps between sessions. It has a one-line title and a body.

**Scope**: where a memory applies.
- **Global**: applies in every session, whatever repository is open.
- **Repository**: applies only in sessions that work in one repository.

**Repository key**: the name that identifies where a session works, so repository memories follow it across clones and moves.
- A git repository: `landing_zone/repo_name`.
- A folder that is not a git repository: `local/<folder name>`.
- A chat with no folder open: `local/chat`.

**Load mode**: when a memory reaches the agent.
- **always**: given to the agent in full at session start.
- **on_demand**: only its title is shown at session start; the agent fetches the body by searching when it needs it.

_Avoid_: "permanent". It mixes up "always loaded" with "never expires".

**Expiry**: the moment after which a memory no longer exists. It is never shown, never returned and gets deleted. A memory may be set to never expire.

**Session start context**: what the agent receives when a session begins: the always memories in full plus the on_demand titles, for global scope and the current repository. In a multi-repository workspace: global scope only, plus the list of repositories.

**Multi-repository workspace**: a multi-root `.code-workspace`, or an open folder that is not itself a git repository but holds several repositories. Each repository keeps its own memories.

**Repository load**: in a multi-repository workspace, the agent fetches a repository's memories before working in it; as a backup they are also appended to the first tool result that touches the repository, once per session.

**Remember**: storing a memory because the user said what to keep.

**Reflection**: the agent reviewing the conversation for things worth keeping.
- **Proposed reflection** (`alx-reflect`): the agent proposes, the user decides what gets stored.
- **Auto reflection** (`alx-reflect-auto`): the agent stores what it judges worth keeping for the current repository, without asking. It may update an existing memory instead of adding a duplicate.

**Forget**: deleting memories the user names.
