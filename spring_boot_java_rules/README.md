# Spring Boot Java rules for agents

`AGENTS.md` templates for Java / Spring Boot services. They give coding agents (Claude Code, Codex, GitHub Copilot,
Cursor…) the same Java style, coding and test rules a reviewer would apply.

| File | For |
|------|-----|
| [`AGENTS.common.md`](AGENTS.common.md) | Rules shared by every service: formatting (IntelliJ default), naming, control flow, types and null, Lombok, MapStruct, exceptions, logging, REST, configuration, architecture, unit tests (JUnit Jupiter, AssertJ, Mockito) and WireMock tests. Rule IDs `C-`. |
| [`AGENTS.mvc-hibernate.md`](AGENTS.mvc-hibernate.md) | Java 25, Spring Boot 4, Spring MVC on Tomcat, Spring Data JPA / Hibernate 7, `RestClient`, `MockMvcTester`, `@DataJpaTest`. Rule IDs `M-`. |
| [`AGENTS.webflux-r2dbc.md`](AGENTS.webflux-r2dbc.md) | Java 21, Spring Boot 4, WebFlux on Netty (`Mono` / `Flux`), Spring Data R2DBC, `WebClient`, `StepVerifier`, `WebTestClient`, `@DataR2dbcTest`. Rule IDs `W-`. |

## Choosing the rules

Wherever teams commonly disagree (braces on one-line `if`, early return vs `else`, `var`, `final`, Lombok vs
records, BDD Mockito, test names, package layout…), the files list every option as a checkbox, with code examples
and one marked *(recommended)*:

```markdown
### C-1.4 Braces on single-statement blocks

- [ ] **A: braces on every `if`, `else`, `for`, `while`, `do`** *(recommended)*
- [ ] **B: one-line guard clauses without braces allowed**

**Decision:** ____
```

Until a rule is decided, agents follow the recommended option. To decide a rule, keep the chosen option and delete the
other options, the marker, the examples you do not need and the `Decision:` line. Delete whole rules you do not want.
Shorter files work better for agents, so trim hard.

## Putting the rules in a repository

Agents load a file named `AGENTS.md` at the repository root. There is no include mechanism, so pick one:

**A. Two files.** Copy the stack file as `AGENTS.md` and `AGENTS.common.md` next to it. The first lines of the stack
file tell the agent to read `AGENTS.common.md`.

```bash
cp AGENTS.common.md ../my-service/
cp AGENTS.webflux-r2dbc.md ../my-service/AGENTS.md
```

**B. One merged file.** More reliable (nothing for the agent to follow up on), but you keep two copies in sync. The
`sed` drops the "read `AGENTS.common.md`" block from the stack file:

```bash
{ cat AGENTS.common.md; echo; sed '/^<!-- Delete this block/,/^$/d' AGENTS.webflux-r2dbc.md; } > ../my-service/AGENTS.md
```

Use `AGENTS.mvc-hibernate.md` instead of `AGENTS.webflux-r2dbc.md` for the blocking services.

For Claude Code, which reads `CLAUDE.md`, add a `CLAUDE.md` containing the single line `@AGENTS.md` (it imports the
file), or symlink it: `ln -s AGENTS.md CLAUDE.md`.

## Checked against

Written for Java 21 / 25 and Spring Boot 4.x (Spring Framework 7, Hibernate 7, Jackson 3, JUnit Jupiter, WireMock 3).
Version-specific rules say which version they need. Check them again when you upgrade.
