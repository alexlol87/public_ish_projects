# awesome-copilot skills

Skills copied from [github/awesome-copilot](https://github.com/github/awesome-copilot) at commit `d85f762d6e521abf5fe16703946e9b38adc42da7`, MIT licensed (see `LICENSE`).

Each skill sits in the folder of its main bucket. The table also tags its stack and any second bucket, and says when to reach for it. **Must have** = install now, **Situational** = install when that task comes up.

| Skill | Bucket | Also | Stack | When to use it | Priority |
| --- | --- | --- | --- | --- | --- |
| `pr-address-feedback` | review | productivity | any | A PR came back with review comments to work through | Must have |
| `test-gap-audit` | review | testing | any | Before a release, or when inheriting code, to see what is untested | Must have |
| `security-review` | review | | any | Before merging auth, input handling or data access changes | Situational |
| `java-springboot` | development | | Java, Spring Boot | Writing or reviewing any Spring Boot service code | Must have |
| `java-hibernate-jpa` | development | debugging | Java, Hibernate | N+1 queries, `LazyInitializationException`, writing entities and mappings | Must have |
| `refactor-plan` | development | | any | A refactor that touches more than a few files, before any edit | Must have |
| `ruff-recursive-fix` | development | review | Python | Cleaning lint errors in a Python repo or before a PR | Must have |
| `sql-optimization` | development | debugging | SQL, Hibernate | A slow query or endpoint, including SQL that Hibernate generates | Situational |
| `java-upgrade` | development | | Java | Moving to a newer JDK (17 to 21, 21 to 25) | Situational |
| `javax-to-jakarta-migration` | development | | Java, Spring Boot | Upgrading to Spring Boot 3+ or Jakarta EE | Situational |
| `multi-stage-dockerfile` | development | | any | Writing or slimming a Dockerfile for a service | Situational |
| `spring-boot-testing` | testing | | Java, Spring Boot | Choosing test slices (`@WebMvcTest`, `@DataJpaTest`) and writing Spring tests. Written for Boot 4 and JUnit 6 | Must have |
| `java-junit` | testing | | Java | Writing or fixing unit tests with JUnit, AssertJ, Mockito | Must have |
| `java-testcontainers` | testing | | Java | Integration tests against a real database or broker | Must have |
| `pytest-coverage` | testing | | Python | Raising coverage or finding untested lines in Python | Must have |
| `java-debugging` | debugging | | Java, Spring Boot | Attaching a debugger to a test, a container or a remote JVM | Situational |
| `java-diagnostics` | debugging | | Java | Memory leaks, high CPU, stuck threads, GC pauses in a running JVM | Situational |
| `acquire-codebase-knowledge` | docs and onboarding | | any | Joining a new repo or mapping an unfamiliar service | Situational |
| `context-map` | docs and onboarding | development | any | Before a change, to list every file it touches | Situational |
| `create-agentsmd` | docs and onboarding | productivity | any | A repo has no `AGENTS.md` or Copilot instructions yet | Situational |
| `create-architectural-decision-record` | docs and onboarding | | any | Recording why a design choice was made | Situational |
| `remember` | productivity | | any | Copilot made a mistake you never want repeated: `/remember` it | Must have |
| `harness-engineering` | productivity | | any | The same agent mistake keeps happening across sessions | Must have |
| `git-commit` | productivity | | any | Writing commits or splitting changes into several. Pick this or `conventional-commit` | Must have |
| `conventional-commit` | productivity | | any | Your team uses Conventional Commits (`feat:`, `fix:`) | Situational |
| `brag-sheet` | productivity | | any | Before a performance review or a weekly update | Situational |

To update a skill: `gh skills install github/awesome-copilot <name>`, or copy its folder again from `skills/<name>` upstream into the bucket folder here.
