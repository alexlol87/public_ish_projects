# springboot_java_utilities

A small Spring Boot 4.1 / Java 21 service whose real purpose is to show **what each Java quality tool catches, and what it cannot**: Spotless, Checkstyle, SpotBugs (+ Find Security Bugs), PMD (+ CPD) and SonarQube.

- `src/main`: product catalog REST API (controller, service, repository, an external-API client), H2 in-memory database.
- `src/test`: 19 tests. The HTTP client is tested against **WireMock servers whose stubs are JSON files** in `src/test/resources/wiremock/<scenario>/{mappings,__files}`: success, missing currency, HTTP 500, slow upstream (timeout).
- `src/demo`: four classes full of deliberate problems, compiled only with `-Pdemo`. They are what the tools are pointed at in the demos below.
- `config/`: the rule files for each tool (read them, they are commented).

```
mvn verify                  # tests + every quality gate; passes on the clean code
scripts/run-demo.sh         # all tools against src/demo, prints findings per rule, never fails
mvn spotless:apply          # fix formatting instead of just failing
mvn spring-boot:run         # app on :8080, e.g. GET /api/products, GET /api/products/1/price?currency=EUR
```

Needs JDK 21+ and Maven 3.9+. `.mvn/jvm.config` holds the `--add-exports` flags google-java-format needs on JDK 17+.

## How the tools differ

| Tool | Looks at | Question it answers | Fixes it itself? | Gate |
|------|----------|---------------------|------------------|------|
| Spotless | source text | Is it laid out the agreed way? | **Yes** (`apply`) | `spotless:check` @ verify |
| Checkstyle | source tokens | Does it follow our written conventions? | No | `checkstyle:check` @ verify |
| SpotBugs + FindSecBugs | **bytecode** | Will this misbehave or be exploitable? | No | `spotbugs:check` @ verify |
| PMD + CPD | source AST | Does it contain smells, dead code, copy/paste? | No | `pmd:check`, `pmd:cpd-check` @ verify |
| SonarQube | source + bytecode + the other tools' reports + coverage | What is the overall health, and is it getting worse? | No | Quality Gate on the server |

The overlap is intentional and is part of the lesson: `==` on strings is flagged by Checkstyle (`StringLiteralEquality`), PMD (`CompareObjectsWithEquals`), SpotBugs (`ES_COMPARING_PARAMETER_STRING_WITH_EQ`) and Sonar (S4973). Pick one tool as the owner of each rule family and exclude it elsewhere (see the exclusions in `config/pmd/ruleset.xml`) or developers see the same finding three times.

## 1. Spotless: formatting you never argue about

Config: `<spotless-maven-plugin>` in `pom.xml`. google-java-format (Google style), unused imports, annotation placement, trailing whitespace, `pom.xml` ordering (sortPom) and the WireMock JSON files.

```
mvn spotless:check          # fails listing exactly which lines differ
mvn spotless:apply          # rewrites files
mvn -Pdemo spotless:check   # demo: FormatViolations.java (Allman braces, 4-space indent, one-line blocks)
```

Why: formatting review comments disappear, and diffs only contain real changes. Run `apply` before committing; CI runs `check`. The demo profile widens Spotless to `src/**` (normally only `src/main` and `src/test`).

## 2. Checkstyle: conventions that need a human decision

Config: `config/checkstyle/checkstyle.xml` (about 60 modules, grouped and commented), `suppressions.xml` (lighter rules for tests, one exception for the Spring Boot main class).

Shown in `StyleViolations.java`: naming (`ConstantName`, `MemberName`, `MethodName`), `MagicNumber`, `NeedBraces`, `MissingSwitchDefault`, `StringLiteralEquality`, `EmptyCatchBlock`/`IllegalCatch`, `ParameterNumber`, `NestedIfDepth`, `BooleanExpressionComplexity`, `UpperEll`, `MissingJavadocType`, star/unused imports, `LineLength`.

Things worth showing in a talk:
- **Severity**: `TodoComment` and `ReturnCount` are `warning`; the plugin only fails on `error` (`violationSeverity`). Reported, not blocking.
- **Suppression** three ways: `suppressions.xml` (by file pattern), `@SuppressWarnings("checkstyle:MagicNumber")`, or deleting the module.
- Checkstyle also flags the layout mess in `FormatViolations.java` (`WhitespaceAround`, `LeftCurly`): that is the overlap with Spotless. Rule of thumb: Spotless owns anything it can rewrite.

```
mvn checkstyle:check                    # on the clean code: 0 violations
mvn -Pdemo checkstyle:checkstyle        # demo: report at target/checkstyle-result.xml
```

## 3. SpotBugs + Find Security Bugs: bugs a style tool cannot see

Config: plugin block in `pom.xml` (effort `Max`, threshold `Low`, Find Security Bugs added as a detector plugin), `config/spotbugs/exclude.xml` (every exclusion carries a reason).

Shown in `BugViolations.java` (it analyses compiled bytecode, so the code must compile): `SQL_INJECTION_JDBC`, `COMMAND_INJECTION`, `PATH_TRAVERSAL_IN`, `HARD_CODE_PASSWORD`, `WEAK_MESSAGE_DIGEST_MD5`, `PREDICTABLE_RANDOM`, `NP_NULL_ON_SOME_PATH`, `RV_RETURN_VALUE_IGNORED`, `ES_COMPARING_PARAMETER_STRING_WITH_EQ`, `EI_EXPOSE_REP`, `OS_OPEN_STREAM`, `HE_EQUALS_USE_HASHCODE`, `DM_STRING_CTOR`.

The real code needed two exclusions, both documented in `exclude.xml`: JPA entity fields written reflectively by Hibernate, and `EI_EXPOSE_REP2` for constructor-injected Spring beans. `ProductRepository` uses a bound `@Query` parameter, the safe counterpart of the SQL injection demo.

```
mvn spotbugs:check                      # clean code: 0 bugs
mvn spotbugs:gui                        # browse a report interactively
mvn -Pdemo compile spotbugs:spotbugs    # demo: target/spotbugsXml.xml
```

## 4. PMD and CPD: smells, dead code, duplication

Config: `config/pmd/ruleset.xml`. Strategy: enable each PMD category (best practices, code style, design, error prone, multithreading, performance, security) then exclude the rules that are opinion or that Checkstyle/Spotless already own; every exclusion has a comment. `failurePriority=3` fails on priority 1-3 only.

Shown in `SmellViolations.java`: `UnusedPrivateField`, `UnusedPrivateMethod`, `UnusedAssignment`, `ReturnEmptyCollectionRatherThanNull`, `SystemPrintln`, `AvoidPrintStackTrace`, `EmptyCatchBlock`, `SimplifyBooleanReturns`, `AvoidDuplicateLiterals`, `CyclomaticComplexity`, `CognitiveComplexity`, `UseStringBufferForStringAppends`, `UseLocaleWithCaseConversions`. **CPD** (copy/paste detector) reports `priceWithVat` / `invoiceWithVat` as one duplicated block (`minimumTokens=60`).

```
mvn pmd:check pmd:cpd-check             # clean code: passes
mvn -Pdemo pmd:pmd pmd:cpd              # demo: target/pmd.xml, target/cpd.xml
```

## 5. SonarQube: the dashboard and the gate

Config: `sonar.*` properties in `pom.xml`, `docker-compose.yml` (Community Edition). The scanner reads sources, bytecode, **JaCoCo coverage**, and **imports the Checkstyle, PMD and SpotBugs reports as external issues**, so one UI shows everything.

```
docker compose up -d                    # wait ~1 min, open http://localhost:9000 (admin/admin, then change it)
# UI: My Account > Security > generate a token
export SONAR_TOKEN=...
mvn clean verify sonar:sonar -Dsonar.token=$SONAR_TOKEN                      # the clean code
mvn -Pdemo clean test checkstyle:checkstyle pmd:pmd spotbugs:spotbugs \
    sonar:sonar -Dsonar.token=$SONAR_TOKEN -Dsonar.projectKey=springboot-java-utilities-demo   # the bad code
```

What to show in the UI: issue types (Bug / Vulnerability / Code Smell / Security Hotspot), the built-in **Quality Gate** ("Sonar way": no new bugs/vulnerabilities, coverage on new code >= 80%, duplication < 3%), the **new code vs overall code** split, effort estimates (technical debt), and the rules Sonar has that the others lack: cognitive complexity (S3776), duplicated string literals (S1192), commented-out code (S125), hardcoded credentials (S2068).

Sonar adds what the others do not: history, coverage, a pass/fail gate on *new* code only (so an old codebase can adopt it without fixing everything first), and pull-request decoration in the paid editions.

## Adopting this on an existing project

1. Add Spotless, run `apply` once in its own commit (add that commit to `.git-blame-ignore-revs`).
2. Add the others with `failOnViolation=false`, look at the reports, trim rules that are noise (exclusions with reasons).
3. Turn the gates on one tool at a time. For legacy code let Sonar's "new code" gate block regressions while the old findings are paid down.
