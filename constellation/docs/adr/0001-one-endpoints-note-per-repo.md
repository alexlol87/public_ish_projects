# One endpoints Note per Repo, with Calls in the body

Each Repo describes all its Endpoints as `##` headings in a single `endpoints.md`, and each Endpoint lists the
Endpoints it invokes in a `Calls:` bullet list of `[[repo/endpoints#METHOD /path]]` Links under its heading. We chose
this over one Note per Endpoint to keep Repo folders small and readable for people and agents. As a result, Calls cannot
live in frontmatter (frontmatter is per file), and the graph draws Call edges between endpoints Notes and lists the
Endpoint pairs on hover instead of showing one Node per Endpoint.
