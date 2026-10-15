# Mutation Testing with PIT (pitest) for a Reactive Spring Boot 4 Service

A practical guide for a Spring Boot 4 / Java 21 / Maven **reactive** service:

- Spring WebFlux controllers, tested with `WebTestClient`,
- outbound calls through `WebClient`, stubbed with WireMock,
- persistence through R2DBC on PostgreSQL, tested with Testcontainers,
- Reactor pipelines everywhere, tested with `StepVerifier`.

Reactive code needs extra care with mutation testing. Much of the logic lives in lambdas
passed to operators, assembling a pipeline is not the same as running it, and a test that
never subscribes passes no matter what the code does. This guide covers the pitest basics
and then the reactive-specific traps.

There is a companion guide for a Spring MVC service (`mutation_testing_intro.md`) that goes
deeper on some shared topics. This document is self-contained.

> **About versions and sources.** Versions were checked against Maven Central metadata in
> October 2026. Behaviour comes from the pitest README and release notes, the pitest source
> (Maven mojo parameters, mutator groups, detection statuses), the pitest.org docs, the
> Spring Boot 4.1 reference docs and source, the Reactor reference guide (testing chapter),
> the WireMock docs, the Testcontainers 2.x docs and the Arcmutate docs. Where something
> could not be verified, the guide says so.

---

## Contents

1. [First 30 minutes (quick start)](#1-first-30-minutes-quick-start)
2. [Mutation testing in one page, and why line coverage lies (more so in reactive code)](#2-mutation-testing-in-one-page-and-why-line-coverage-lies-more-so-in-reactive-code)
3. [Versions used in this guide](#3-versions-used-in-this-guide)
4. [Installing pitest in a reactive Spring Boot 4 Maven build](#4-installing-pitest-in-a-reactive-spring-boot-4-maven-build)
5. [Running it](#5-running-it)
6. [Reading reports and statuses](#6-reading-reports-and-statuses)
7. [Mutators, and what they do to reactive code](#7-mutators-and-what-they-do-to-reactive-code)
8. [Why mutating reactive pipelines is tricky](#8-why-mutating-reactive-pipelines-is-tricky)
9. [StepVerifier patterns that kill mutants](#9-stepverifier-patterns-that-kill-mutants)
10. [Worked example: a surviving boundary mutant inside a `map` lambda](#10-worked-example-a-surviving-boundary-mutant-inside-a-map-lambda)
11. [WebClient + WireMock: retries, timeouts, fallbacks](#11-webclient--wiremock-retries-timeouts-fallbacks)
12. [WebTestClient controller tests](#12-webtestclient-controller-tests)
13. [R2DBC with Testcontainers PostgreSQL](#13-r2dbc-with-testcontainers-postgresql)
14. [Keeping runtime sane](#14-keeping-runtime-sane)
15. [Equivalent mutants](#15-equivalent-mutants)
16. [CI integration and thresholds](#16-ci-integration-and-thresholds)
17. [Pitfalls: general and Reactor-specific](#17-pitfalls-general-and-reactor-specific)
18. [Arcmutate notes (reactive operators, Spring)](#18-arcmutate-notes-reactive-operators-spring)
19. [Checklist](#19-checklist)

---

## 1. First 30 minutes (quick start)

**Minute 0-5: add the `pitest` profile** from [section 4.2](#42-pomxml).

**Minute 5-10: grep your tests for StepVerifier calls with no terminal `verify`.** This is
the most common reactive testing bug and it ruins any mutation score:

```bash
# Rough heuristic: StepVerifier chains in files that never call verify/verifyComplete/verifyError...
grep -rL --include='*Test.java' -E 'verify(Complete|Error|ErrorMatches|ErrorMessage|ErrorSatisfies|ThenAssertThat)?\(' src/test/java \
  | xargs grep -l 'StepVerifier' || true
```

A `StepVerifier` without a terminal `verify*()` call never subscribes and never asserts.

**Minute 10-15: run pitest on one package with real business logic.**

```bash
./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage \
  -DtargetClasses='com.example.quotes.pricing.*' \
  -DtargetTests='com.example.quotes.pricing.*'
```

Check that the statistics show `Ran N tests` with N > 0 and non-zero line coverage. If
not, read [4.4](#44-junit-6-compatibility-check).

**Minute 15-25: open `target/pit-reports/index.html`.** In reactive classes, look at:

- `NO_COVERAGE` mutants on lines **inside lambdas** (`map`, `flatMap`, `filter`,
  `onErrorResume`) next to lines that are covered. That pattern means the pipeline is
  assembled in a test but never subscribed, or never reaches that operator.
- `SURVIVED` boundary mutants in rules.

**Minute 25-30: fix one thing.** Usually you replace a non-subscribing test with a
`StepVerifier` that asserts the value and completion, or add a boundary case. Re-run
with `-DwithHistory`.

---

## 2. Mutation testing in one page, and why line coverage lies (more so in reactive code)

pitest changes your compiled production code one small edit at a time (a **mutant**:
`>=` becomes `>`, a void call is removed, a return value becomes `null`), then runs the
tests that cover that line:

- a test fails: the mutant is **killed** (good);
- all pass: the mutant **survived**, so your tests would miss that bug;
- no test runs the line: **no coverage**.

pitest first measures line coverage per test, then runs only covering tests per mutant,
fastest first (pitest.org "Basic concepts").

Line coverage lies in any codebase: it measures execution, not assertions. In reactive
code it lies more, because **assembly and execution are different moments**:

```java
public Mono<Order> place(Order order) {
    return repository.save(order)                                  // line A: runs at assembly
            .flatMap(saved -> events.publish(saved).thenReturn(saved)); // line B: lambda runs only on subscription
}
```

A test that calls `place(order)` without subscribing executes line A, so line A is
"covered". Line A also builds the `flatMap` operator, so the line of the lambda may look
covered too, depending on how the coverage tool attributes lines. The lambda body (a
separate synthetic method in bytecode) never runs. The test can even
`verify(repository).save(order)` and pass, because `save` is *called* at assembly, even
though nothing was ever saved.

pitest measures coverage per **bytecode method and line** while running each test, so
mutants in the lambda body correctly show `NO_COVERAGE` for such a test. That makes
mutation testing a good detector for the "nothing subscribed" class of bugs, as long as
you read the report at the mutant level and not only the percentage.

Terms:

- **Mutation score** = detected / all mutants.
- **Test strength** = detected / mutants with coverage (ignores untested code; measures
  assertion quality).

---

## 3. Versions used in this guide

Checked against Maven Central `maven-metadata.xml` in October 2026:

| Artifact | Version | Notes |
|---|---|---|
| `org.pitest:pitest-maven` | **1.30.1** | follows 1.25.x; the README explains the jump (a release was mislabelled 1.29.10) |
| `org.pitest:pitest-junit5-plugin` | **1.2.3** | requires pitest >= 1.19.4 |
| `org.springframework.boot:spring-boot-starter-parent` | **4.1.1** (latest GA) | manages JUnit Jupiter 6.0.3, Reactor BOM 2025.0.7, Testcontainers 2.0.5, r2dbc-postgresql 1.1.2.RELEASE, Surefire 3.5.6 |
| `io.projectreactor:reactor-test` | managed by Boot (via the Reactor BOM) | latest on Central: 3.8.7 |
| `org.jacoco:jacoco-maven-plugin` | **0.8.15** | not managed by Boot |
| `org.wiremock.integrations:wiremock-spring-boot` | **4.4.3** | 4.0.0 release notes: "Compatible with SpringBoot 4"; brings `wiremock-jetty12` 3.13.2 |
| `org.testcontainers:testcontainers-postgresql`, `testcontainers-r2dbc` | **2.0.5** (managed by Boot) | Testcontainers 2.x artifact names |
| `com.arcmutate:base` | 1.7.2 | commercial; reactive operators (section 18) |
| `com.arcmutate:arcmutate-spring` | 1.1.3 | commercial |

Spring Boot 4 split auto-configuration into modules with their own starters. Checked in
the 4.1.1 POMs:

- `spring-boot-starter-webflux` does **not** include the WebClient auto-configuration. Add
  `spring-boot-starter-webclient` if you inject `WebClient.Builder`.
- `spring-boot-starter-webflux-test` brings `spring-boot-starter-test`, `reactor-test`
  and the WebTestClient support.
- `spring-boot-starter-data-r2dbc-test` brings `reactor-test` and the `@DataR2dbcTest`
  slice.

---

## 4. Installing pitest in a reactive Spring Boot 4 Maven build

### 4.1 Key facts

- The JUnit plugin must be a **dependency of the `pitest-maven` plugin**, not a test
  dependency (plugin README).
- pitest's Maven plugin adds a `junit-platform-launcher` (and, if missing, a
  `junit-jupiter-engine`) matching your project's JUnit version (since 1.14.0). You do not
  add the launcher yourself.
- Since 1.15.4 pitest reads Surefire's configuration: `argLine` (with `@{...}`/`${...}`
  replaced), `environmentVariables` (1.16.0), `excludes`, `groups`/`excludedGroups`
  (unless set on pitest) and `testFailureIgnore`. If you used to copy Surefire's
  argLine into pitest's `jvmArgs`, remove the copy or the flags appear twice. Disable the
  import with `<parseSurefireArgLine>false</parseSurefireArgLine>` or
  `<parseSurefireConfig>false</parseSurefireConfig>`.
- pitest strips any `-javaagent` containing `jacoco` from its minion JVMs and (1.25.7+)
  disables JaCoCo transformations, so JaCoCo can stay configured.
- pitest adds `-ea` to minion JVMs automatically (1.16.0).

### 4.2 pom.xml

```xml
<project>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>4.1.1</version>
    <relativePath/>
  </parent>

  <properties>
    <java.version>21</java.version>
    <pitest.version>1.30.1</pitest.version>
    <pitest-junit5.version>1.2.3</pitest-junit5.version>
    <jacoco.version>0.8.15</jacoco.version>
    <!-- Empty default so "@{argLine}" always resolves (also inside pitest). -->
    <argLine></argLine>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-webflux</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-webclient</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-data-r2dbc</artifactId>
    </dependency>
    <dependency>
      <groupId>org.postgresql</groupId>
      <artifactId>r2dbc-postgresql</artifactId>
      <scope>runtime</scope>
    </dependency>

    <!-- tests -->
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-webflux-test</artifactId>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-data-r2dbc-test</artifactId>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-testcontainers</artifactId>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.testcontainers</groupId>
      <artifactId>testcontainers-postgresql</artifactId>
      <scope>test</scope>
    </dependency>
    <dependency>
      <!-- Spring Boot's own R2DBC module declares this next to testcontainers-postgresql
           for the R2DBC @ServiceConnection support. -->
      <groupId>org.testcontainers</groupId>
      <artifactId>testcontainers-r2dbc</artifactId>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.wiremock.integrations</groupId>
      <artifactId>wiremock-spring-boot</artifactId>
      <version>4.4.3</version>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.jacoco</groupId>
        <artifactId>jacoco-maven-plugin</artifactId>
        <version>${jacoco.version}</version>
        <executions>
          <execution>
            <id>prepare-agent</id>
            <goals><goal>prepare-agent</goal></goals>
          </execution>
          <execution>
            <id>report</id>
            <phase>verify</phase>
            <goals><goal>report</goal></goals>
          </execution>
        </executions>
      </plugin>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-surefire-plugin</artifactId>
        <configuration>
          <argLine>@{argLine}</argLine>
          <excludedGroups>integration</excludedGroups>
        </configuration>
      </plugin>
    </plugins>
  </build>

  <profiles>
    <profile>
      <id>pitest</id>
      <build>
        <plugins>
          <plugin>
            <groupId>org.pitest</groupId>
            <artifactId>pitest-maven</artifactId>
            <version>${pitest.version}</version>
            <dependencies>
              <dependency>
                <groupId>org.pitest</groupId>
                <artifactId>pitest-junit5-plugin</artifactId>
                <version>${pitest-junit5.version}</version>
              </dependency>
            </dependencies>
            <configuration>
              <targetClasses>
                <param>com.example.quotes.*</param>
              </targetClasses>
              <targetTests>
                <param>com.example.quotes.*</param>
              </targetTests>
              <excludedClasses>
                <param>com.example.quotes.QuotesApplication</param>
                <param>com.example.quotes.config.*</param>
                <param>com.example.quotes.*.dto.*</param>
              </excludedClasses>
              <excludedMethods>
                <param>toString</param>
                <param>hashCode</param>
                <param>equals</param>
              </excludedMethods>
              <avoidCallsTo>
                <avoidCallsTo>org.slf4j</avoidCallsTo>
                <avoidCallsTo>org.apache.commons.logging</avoidCallsTo>
                <avoidCallsTo>java.util.logging</avoidCallsTo>
              </avoidCallsTo>
              <mutators>
                <mutator>DEFAULTS</mutator>
                <mutator>EXPERIMENTAL_BIG_DECIMAL</mutator>
              </mutators>
              <threads>4</threads>
              <timeoutConstant>5000</timeoutConstant>
              <jvmArgs>
                <value>-Xmx1g</value>
              </jvmArgs>
              <outputFormats>
                <param>HTML</param>
                <param>XML</param>
              </outputFormats>
              <timestampedReports>false</timestampedReports>
            </configuration>
          </plugin>
        </plugins>
      </build>
    </profile>
  </profiles>
</project>
```

### 4.3 The empty `argLine` property

pitest resolves `@{argLine}` from the project properties. If JaCoCo's `prepare-agent` did
not run and no `argLine` property exists, the literal `@{argLine}` can reach the minion's
command line and the JVM fails to start. Declaring an empty `<argLine></argLine>` property
avoids that, as it does for Surefire.

### 4.4 JUnit 6 compatibility check

Boot 4.1.1 manages **JUnit 6.0.3**. The JUnit 5 plugin README documents JUnit Platform 1.x,
and there is an **open issue** (`pitest/pitest-junit5-plugin#113`, April 2026) reporting
0% coverage and "Ran 0 tests" for a Spring Boot 4.0.5 / JUnit Platform 6.0.3 project.
That report used Gradle with older versions (pitest 1.22.1, plugin 1.2.2). The maintainer
asked for a reproduction, and no fix had been released at the time of writing.

**Not verified here:** whether pitest 1.30.1 + plugin 1.2.3 + Maven + JUnit 6.0.x works.
After the first run, check that line coverage is non-zero and `Ran N tests` has N > 0. If
both are zero although `./mvnw test` passes, you have hit the issue. Watch #113, or as a
stop-gap pin JUnit 5.x inside the `pitest` profile by overriding the
`junit-jupiter.version` property (only if your tests use no JUnit 6-only API).

### 4.5 Invocation

```bash
./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage
```

`test-compile` is enough because pitest runs the tests itself. The goal's default phase is
`verify` if you prefer binding it in the profile (`./mvnw -Ppitest verify` then runs
Surefire and pitest).

---

## 5. Running it

Every option below is a `pitest-maven` mojo parameter (checked in `PitMojo.java`). Most
take a `-D` property of the same name.

| Goal | Command / setting |
|---|---|
| Full run | `./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage` |
| One package | `-DtargetClasses='com.example.quotes.pricing.*' -DtargetTests='com.example.quotes.pricing.*'` |
| One class (and its lambdas/inner classes) | `-DtargetClasses='com.example.quotes.pricing.LoyaltyDiscountService*'` |
| Incremental, local | `-DwithHistory` (history file in `java.io.tmpdir`; when set, explicit history files are ignored) |
| Incremental, CI | `-DhistoryInputFile=.pitest/history.bin -DhistoryOutputFile=.pitest/history.bin` and cache the file |
| Parallelism | `<threads>4</threads>` (default 1; one minion JVM per thread) |
| Timeouts | `timeoutFactor` (default 1.25) and `timeoutConstant` (default 3000 ms): limit = normal time x factor + constant |
| Size a run without analysing | `-Dpit.dryRun=true` (1.17.3+) |
| Skip | `-DskipPitest` (note: `-DskipTests` also skips pitest, because the mojo binds `skipTests`) |
| Scoped run that may match nothing | `-DfailWhenNoMutations=false` |

Notes for reactive projects:

- The JUnit 5 plugin turns off JUnit's parallel execution inside pitest; only pitest
  `threads` give parallelism.
- `+auto_threads` exists but the pitest release notes say it is not recommended on CI.
- Raise `timeoutConstant` if many mutants are `TIMED_OUT` in code that cannot loop.
  Reactor tests with real delays (WireMock latency, real backoff) have high timing
  variance.
- After upgrading pitest, delete old history files if results look wrong. Some past
  releases invalidated them.

---

## 6. Reading reports and statuses

Report location with `timestampedReports=false` (the default): `target/pit-reports/index.html`,
plus `mutations.xml` when XML output is enabled.

The HTML report shows line coverage, mutation coverage and test strength per package and
class. The class view shows source lines, each mutant's description and status, and, since
1.16.2, the **covering tests for surviving mutants**.

Statuses (from pitest's `DetectionStatus` enum):

| Status | Counts as detected | Meaning in a reactive codebase |
|---|---|---|
| `KILLED` | yes | a test failed |
| `SURVIVED` | no | covering tests ran and passed. Often an assertion gap: `expectNextCount(1)` instead of checking the value, no request-count check |
| `NO_COVERAGE` | no | no test executed it. In lambdas: often a test that never subscribes, or a branch of the pipeline (`switchIfEmpty`, `onErrorResume`) no test reaches |
| `TIMED_OUT` | yes | usually an infinite loop. In Reactor, also a pipeline that never completes, met by a `StepVerifier.verify()` with no timeout |
| `NON_VIABLE` | yes | invalid bytecode |
| `MEMORY_ERROR` | yes | minion out of memory |
| `RUN_ERROR` | yes | minion crashed (ports, Docker, leaked threads...) |
| `EQUIVALENT` | yes | added in 1.25.0 for plugins/interceptors that mark equivalents. Not verified here: whether you can mark mutants by hand with open-source pitest alone |
| `NOT_STARTED`, `STARTED` | no | should not appear in a finished run |

`TIMED_OUT`, `MEMORY_ERROR` and `RUN_ERROR` count as kills. A large share of them means
your score is inflated by slow or unstable tests, not earned by assertions.

Extract survivors from the XML for scripts:

```bash
python3 - target/pit-reports/mutations.xml <<'EOF'
import sys, xml.etree.ElementTree as ET
for m in ET.parse(sys.argv[1]).getroot().iter("mutation"):
    if m.get("status") in ("SURVIVED", "NO_COVERAGE"):
        print(m.get("status"), f'{m.findtext("mutatedClass")}.{m.findtext("mutatedMethod")}:{m.findtext("lineNumber")}',
              m.findtext("description"))
EOF
```

Lambda bodies show up with synthetic method names such as `lambda$quote$0` in
`mutatedMethod`, which tells you a mutant sits inside an operator's lambda.

---

## 7. Mutators, and what they do to reactive code

### 7.1 Groups as implemented in pitest 1.30.x

From `StandardMutatorGroups.java` / `ReturnsMutatorGroup.java`:

| Group | Contents |
|---|---|
| `DEFAULTS` | `CONDITIONALS_BOUNDARY`, `INCREMENTS`, `INVERT_NEGS`, `MATH`, `VOID_METHOD_CALLS`, `REMOVE_CONDITIONALS_ORDER_ELSE`, `REMOVE_CONDITIONALS_EQUAL_ELSE`, `RETURNS` (= `TRUE_RETURNS`, `FALSE_RETURNS`, `PRIMITIVE_RETURNS`, `EMPTY_RETURNS`, `NULL_RETURNS`) |
| `STRONGER` | `DEFAULTS` + `EXPERIMENTAL_SWITCH`, `REMOVE_CONDITIONALS_ORDER_IF`, `REMOVE_CONDITIONALS_EQUAL_IF` |
| `ALL` | everything registered, including experimental mutators |

The pitest.org mutators page partly still lists "Negate Conditionals" in the defaults.
Since 1.7.x (release note #943) the defaults use `REMOVE_CONDITIONALS_*_ELSE` instead. The
code is the authority. `NEGATE_CONDITIONALS` and `NON_VOID_METHOD_CALLS` can still be
enabled by name.

`EXPERIMENTAL_BIG_DECIMAL` (pitest core) swaps `BigDecimal` operations (`add`/`subtract`,
`multiply`/`divide`, `min`/`max`, `negate`/`plus`, ...). `MATH` only touches primitive
arithmetic, so enable this mutator for money logic.

### 7.2 How each default mutator meets a Reactor pipeline

| Mutator | Effect on reactive code |
|---|---|
| `CONDITIONALS_BOUNDARY`, `REMOVE_CONDITIONALS_*` | apply inside lambdas (`filter(o -> o.total() > LIMIT)`, `map(...)`) and in plain helpers. These are your business rules and the most valuable mutants |
| `RETURNS` (`NULL_RETURNS`) on a method returning `Mono`/`Flux` | `return pipeline;` becomes `return null;`. Any test that touches the method fails with an NPE (at `StepVerifier.create(null)` or the next operator). **Cheap kills**: they say nothing about assertions and inflate the score |
| `RETURNS` inside lambdas | e.g. a `map` lambda returning `null`: Reactor rejects null values with an NPE, so a test that subscribes kills it; a test that never subscribes reports it as no coverage |
| `EMPTY_RETURNS` | applies to `Optional`, collections, `String` and `Stream`, which are less common in reactive signatures. `Mono`/`Flux` are not in pitest's list (Arcmutate adds that, see 18) |
| `VOID_METHOD_CALLS` | removes `void` calls, e.g. `metrics.increment()` inside `doOnNext`, `sink.complete()`, `log.warn` (exclude logging with `avoidCallsTo`). Survivors mean no test checks that side effect |
| (not in defaults) operator calls | `map`, `flatMap`, `filter`, `retryWhen`, `timeout`, `onErrorResume`, `switchIfEmpty` are **non-void** method calls. Default pitest never removes or swaps them. A "forgotten `.then(...)`" bug cannot be produced by default mutators |
| `INCREMENTS` | counters in loops or `AtomicInteger` arithmetic in custom retry logic |

The key consequence: with open-source pitest, **mutants land in your lambdas and helper
methods, not in the operator wiring**. Pipeline structure (which operator, in what order)
is protected only by tests that check behaviour end to end, and only mutated by extra
plugins (section 18).

Practical advice that follows from this:

- **Extract business rules from lambdas into named methods**
  (`map(this::applyDiscount)`, or a static `discountRate(int)`). They are easier to
  unit-test without Reactor, and pitest reports them with readable method names.
- Keep pipelines thin: wiring in the pipeline, decisions in plain methods.

---

## 8. Why mutating reactive pipelines is tricky

### 8.1 Operators are method calls; behaviour lives in lambdas

```java
return customers.findById(id)                       // non-void call: not mutated by default
        .filter(c -> c.status() == Status.ACTIVE)    // lambda: EQUAL_ELSE mutant here
        .map(c -> discountRate(c.lifetimeOrders()))  // lambda: RETURNS mutant here
        .defaultIfEmpty(BigDecimal.ZERO);            // non-void call: not mutated by default
```

The `filter` and `map` calls themselves are not mutated by default; their lambdas are.
Each lambda compiles to a synthetic method (`lambda$quote$0`) that pitest mutates like
any other method. pitest release 1.17.2 ("Exclude lambdas in methods excluded by
annotation") confirms lambdas are treated as part of their enclosing method for
exclusions.

### 8.2 Tests that pass because nothing subscribes

Three common shapes:

```java
// 1. No terminal verify(): StepVerifier never subscribes. Asserts NOTHING.
StepVerifier.create(service.quote(1L, new BigDecimal("100.00")))
        .expectNextMatches(q -> q.total().compareTo(new BigDecimal("95.00")) == 0);

// 2. Calling the method and checking a mock interaction that happens at assembly time.
service.place(order);
verify(repository).save(order);          // save() was CALLED (to build the Mono); nothing was saved

// 3. Asserting only on the publisher object.
assertThat(service.quote(1L, total)).isNotNull();   // kills only NULL_RETURNS on the method
```

Under pitest, the lambdas in these pipelines show `NO_COVERAGE`. The `return` mutant on the
method itself gets killed (shape 3) or survives, which can make a class look half-tested
when it is effectively untested.

### 8.3 VOID_METHOD_CALLS on reactive side effects

```java
return paymentClient.charge(order)
        .doOnNext(receipt -> metrics.recordCharge(receipt.amount()))   // void call in lambda
        .doOnError(ex -> alerts.paymentFailed(order.id(), ex));        // void call in lambda
```

Both calls are removed by `VOID_METHOD_CALLS`. To kill them, a test must subscribe **and**
check the side effect (`verify(metrics).recordCharge(...)`, an in-memory `MeterRegistry`,
a fake `alerts`). In the error path the test must drive the pipeline into `doOnError`,
which needs a failing `charge` (WireMock 5xx or a stub returning `Mono.error(...)`).

By contrast, if `alerts.paymentFailed(...)` returns `Mono<Void>`, it is a non-void call:
the default mutators will not remove it, and the classic bug (returning a `Mono<Void>`
from `doOnError` that nobody subscribes to, so the alert never goes out) cannot be found
by mutation. Catch it with a `PublisherProbe` test (9.4).

### 8.4 Time

Retries with backoff, `timeout`, `delayElements` and `interval` make tests slow under
pitest, because every mutant re-runs them. Mutants that change counters or conditions can
make a pipeline wait forever (`TIMED_OUT`, slow) instead of failing fast. Use virtual
time where possible (9.3) and short, configurable durations where real I/O is involved
(section 11).

---

## 9. StepVerifier patterns that kill mutants

All from the Reactor reference guide, testing chapter (`reactor-test`): `StepVerifier`,
`TestPublisher`, `PublisherProbe`.

### 9.1 Always terminate, always bound

```java
StepVerifier.create(service.quote(42L, new BigDecimal("100.00")))
        .assertNext(q -> assertThat(q.total()).isEqualByComparingTo("95.00"))
        .expectComplete()
        .verify(Duration.ofSeconds(5));
```

- `assertNext` / `expectNext(value)` check the **value**. `expectNextCount(1)` survives
  every mutant that changes the value.
- `expectComplete()` checks that the sequence ends with completion and emits nothing more.
  A mutant that emits an extra element or errors after the value is killed.
- `verify(Duration)` bounds the wait. Plain `verifyComplete()` waits without a limit; a
  mutant that never completes then runs until pitest's timeout (slow `TIMED_OUT`). If you
  prefer `verifyComplete()`, set a global default once:

```java
@BeforeAll
static void boundStepVerifier() {
    StepVerifier.setDefaultTimeout(Duration.ofSeconds(5));
}
```

### 9.2 Errors: check the type and the content

```java
StepVerifier.create(service.quote(-1L, BigDecimal.TEN))
        .expectErrorSatisfies(ex -> assertThat(ex)
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("customerId"))
        .verify(Duration.ofSeconds(5));
```

`verifyError()` without a type survives mutants that turn one error into another.

### 9.3 Virtual time for retries, delays and timeouts

From the Reactor docs: `StepVerifier.withVirtualTime` swaps Reactor's default schedulers for
a `VirtualTimeScheduler`, and it takes a **`Supplier`** so the publisher is created
**after** the virtual scheduler is installed. `thenAwait(Duration)` advances virtual time.
`expectNoEvent(Duration)` fails if any signal arrives, and the subscription counts as an
event, so use `expectSubscription().expectNoEvent(...)`.

```java
@Test
void retriesTwiceWithBackoffThenFallsBack() {
    AtomicInteger calls = new AtomicInteger();
    WebClient alwaysUnavailable = WebClient.builder()
            .exchangeFunction(request -> {
                calls.incrementAndGet();
                return Mono.just(ClientResponse.create(HttpStatus.SERVICE_UNAVAILABLE).build());
            })
            .build();
    ShippingQuoteClient client = new ShippingQuoteClient(
            alwaysUnavailable, 2, Duration.ofSeconds(1), Duration.ofSeconds(5));

    StepVerifier.withVirtualTime(() -> client.quote("AB12CD", 1500))   // created inside the supplier
            .expectSubscription()
            .thenAwait(Duration.ofMinutes(1))                           // jump past all backoffs
            .assertNext(q -> assertThat(q).isEqualTo(ShippingQuote.flatRate(1500)))
            .expectComplete()
            .verify(Duration.ofSeconds(5));

    assertThat(calls).hasValue(3);                                      // 1 call + 2 retries
}
```

Why this kills more mutants than a real-time test:

- It runs in milliseconds, so pitest can afford to run it for every mutant.
- `calls == 3` kills mutants that change the retry count or the retry filter.
- The value assertion kills mutants in the fallback computation.

The stub `exchangeFunction` above needs no network. Virtual time **does not** apply to real
network I/O (Netty threads run in real time), so with WireMock use short real durations
instead (section 11).

### 9.4 PublisherProbe for "was this branch used?"

From the Reactor docs: `PublisherProbe` wraps a publisher and records whether it was
subscribed, requested or cancelled. Ideal for `switchIfEmpty`, `onErrorResume`, and calls
that return `Mono<Void>`:

```java
@Test
void unknownCustomerTriggersDefaultPricingLookup() {
    PublisherProbe<BigDecimal> defaultRate = PublisherProbe.of(Mono.just(BigDecimal.ZERO));
    when(customers.findById(99L)).thenReturn(Mono.empty());
    when(rates.defaultRate()).thenReturn(defaultRate.mono());

    StepVerifier.create(service.quote(99L, new BigDecimal("100.00")))
            .assertNext(q -> assertThat(q.total()).isEqualByComparingTo("100.00"))
            .expectComplete()
            .verify(Duration.ofSeconds(5));

    defaultRate.assertWasSubscribed();
}

@Test
void failedPaymentSendsAlert() {
    PublisherProbe<Void> alert = PublisherProbe.empty();
    when(paymentClient.charge(any())).thenReturn(Mono.error(new PaymentDeclinedException("card")));
    when(alerts.paymentFailed(any(), any())).thenReturn(alert.mono());

    StepVerifier.create(checkout.pay(order))
            .expectError(PaymentDeclinedException.class)
            .verify(Duration.ofSeconds(5));

    alert.assertWasSubscribed();    // catches "returned a Mono<Void> nobody subscribed to"
}
```

### 9.5 TestPublisher for misbehaving or slow sources

`TestPublisher` lets a test emit signals by hand (`next`, `complete`, `error`) and check
how your operators react, for example error in the middle of a `Flux`, or an empty
source. Use it when a mutant survives because your stubs only ever produce one happy
value.

---

## 10. Worked example: a surviving boundary mutant inside a `map` lambda

### 10.1 Production code

```java
package com.example.quotes.pricing;

import java.math.BigDecimal;
import java.math.RoundingMode;
import reactor.core.publisher.Mono;

public class LoyaltyDiscountService {

    private final CustomerRepository customers;   // reactive repository

    public LoyaltyDiscountService(CustomerRepository customers) {
        this.customers = customers;
    }

    public Mono<PriceQuote> quote(long customerId, BigDecimal basketTotal) {
        return customers.findById(customerId)
                .map(customer -> discountRate(customer.lifetimeOrders()))
                .defaultIfEmpty(BigDecimal.ZERO)
                .map(rate -> PriceQuote.of(basketTotal, rate));
    }

    static BigDecimal discountRate(int lifetimeOrders) {
        if (lifetimeOrders >= 50) {
            return new BigDecimal("0.10");
        }
        if (lifetimeOrders >= 10) {
            return new BigDecimal("0.05");
        }
        return BigDecimal.ZERO;
    }
}
```

```java
package com.example.quotes.pricing;

import java.math.BigDecimal;
import java.math.RoundingMode;

public record PriceQuote(BigDecimal basket, BigDecimal rate, BigDecimal total) {
    static PriceQuote of(BigDecimal basket, BigDecimal rate) {
        BigDecimal total = basket.subtract(basket.multiply(rate)).setScale(2, RoundingMode.HALF_UP);
        return new PriceQuote(basket, rate, total);
    }
}
```

`CustomerRepository` is a Spring Data `ReactiveCrudRepository<Customer, Long>`;
`Customer` is a record with a `lifetimeOrders()` component.

### 10.2 The existing tests

```java
class LoyaltyDiscountServiceTest {

    private final CustomerRepository customers = mock(CustomerRepository.class);
    private final LoyaltyDiscountService service = new LoyaltyDiscountService(customers);

    @Test
    void regularCustomer() {
        when(customers.findById(1L)).thenReturn(Mono.just(new Customer(1L, 20)));

        StepVerifier.create(service.quote(1L, new BigDecimal("100.00")))
                .expectNextCount(1)                         // weak
                .verifyComplete();
    }

    @Test
    void loyalCustomer() {
        when(customers.findById(2L)).thenReturn(Mono.just(new Customer(2L, 80)));

        StepVerifier.create(service.quote(2L, new BigDecimal("100.00")))
                .assertNext(q -> assertThat(q.total()).isEqualByComparingTo("90.00"))
                .verifyComplete();
    }

    @Test
    void newCustomerPaysFullPrice() {
        when(customers.findById(3L)).thenReturn(Mono.just(new Customer(3L, 2)));

        StepVerifier.create(service.quote(3L, new BigDecimal("100.00")))
                .assertNext(q -> assertThat(q.total()).isEqualByComparingTo("100.00"))
                .verifyComplete();
    }
}
```

Line coverage: everything except the `defaultIfEmpty` path's consequences. It looks fine.

### 10.3 What pitest reports

Representative results (DEFAULTS + EXPERIMENTAL_BIG_DECIMAL):

| Location | Mutant | Status | Why |
|---|---|---|---|
| `discountRate`: `>= 50` | changed conditional boundary | **SURVIVED** | tests use 2, 20, 80; never 50 |
| `discountRate`: `>= 10` | changed conditional boundary | **SURVIVED** | never 10 |
| `discountRate`: `>= 10` | removed conditional (else) | **SURVIVED** | only `regularCustomer` (20 orders) reaches it, and it asserts `expectNextCount(1)` |
| `discountRate`: `return new BigDecimal("0.05")` | replaced return value with null | KILLED | `PriceQuote.of` throws an NPE on `multiply(null)` |
| `lambda$quote$1` (`PriceQuote.of(...)`) | replaced return value with null | KILLED | Reactor rejects a `null` from `map` |
| `quote` | replaced return value with null | KILLED | cheap kill |
| `PriceQuote.of`: `subtract` | BigDecimal subtract -> add | KILLED | `loyalCustomer` checks the total |

Note that the "unknown customer" path (`defaultIfEmpty`) has no test at all, yet nothing
in the table shows it: `defaultIfEmpty` is a non-void operator call, so the defaults do
not mutate it. Mutation testing does not replace thinking about paths.

### 10.4 Tests that kill the survivors

```java
@ParameterizedTest(name = "{0} lifetime orders -> total {1}")
@CsvSource({
        "9,  100.00",
        "10,  95.00",     // kills the >= 10 boundary mutant
        "11,  95.00",
        "49,  95.00",
        "50,  90.00",     // kills the >= 50 boundary mutant
        "51,  90.00"
})
void discountTiersStartExactlyAtTheirThresholds(int lifetimeOrders, String expectedTotal) {
    when(customers.findById(7L)).thenReturn(Mono.just(new Customer(7L, lifetimeOrders)));

    StepVerifier.create(service.quote(7L, new BigDecimal("100.00")))
            .assertNext(q -> assertThat(q.total()).isEqualByComparingTo(expectedTotal))
            .expectComplete()
            .verify(Duration.ofSeconds(5));
}

@Test
void unknownCustomerPaysFullPrice() {
    when(customers.findById(404L)).thenReturn(Mono.empty());

    StepVerifier.create(service.quote(404L, new BigDecimal("100.00")))
            .assertNext(q -> {
                assertThat(q.rate()).isEqualByComparingTo("0");
                assertThat(q.total()).isEqualByComparingTo("100.00");
            })
            .expectComplete()
            .verify(Duration.ofSeconds(5));
}
```

Also replace `expectNextCount(1)` in `regularCustomer` with a value assertion. Because
`discountRate` is a static method with no Reactor in it, you can also add a plain
parameterized test for it. That is the fastest kind of test for pitest to run.

---

## 11. WebClient + WireMock: retries, timeouts, fallbacks

### 11.1 The client

```java
package com.example.quotes.shipping;

import java.time.Duration;
import java.util.concurrent.TimeoutException;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import reactor.core.Exceptions;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;

public class ShippingQuoteClient {

    private final WebClient webClient;
    private final int maxRetries;
    private final Duration firstBackoff;
    private final Duration perAttemptTimeout;

    public ShippingQuoteClient(WebClient webClient, int maxRetries,
                               Duration firstBackoff, Duration perAttemptTimeout) {
        this.webClient = webClient;
        this.maxRetries = maxRetries;
        this.firstBackoff = firstBackoff;
        this.perAttemptTimeout = perAttemptTimeout;
    }

    public Mono<ShippingQuote> quote(String postcode, int weightGrams) {
        return webClient.get()
                .uri(b -> b.path("/quotes")
                        .queryParam("postcode", postcode)
                        .queryParam("weight", weightGrams)
                        .build())
                .retrieve()
                .bodyToMono(ShippingQuote.class)
                .timeout(perAttemptTimeout)
                .retryWhen(Retry.backoff(maxRetries, firstBackoff)
                        .filter(ShippingQuoteClient::isRetryable))
                .switchIfEmpty(Mono.fromSupplier(() -> ShippingQuote.flatRate(weightGrams)))
                .onErrorResume(Exceptions::isRetryExhausted,
                        ex -> Mono.just(ShippingQuote.flatRate(weightGrams)));
    }

    static boolean isRetryable(Throwable ex) {
        if (ex instanceof WebClientResponseException response) {
            return response.getStatusCode().is5xxServerError();
        }
        return ex instanceof TimeoutException;
    }
}
```

```java
package com.example.quotes.shipping;

public record ShippingQuote(String carrier, long priceCents, boolean fallback) {
    public static ShippingQuote flatRate(int weightGrams) {
        return new ShippingQuote("FLAT", weightGrams <= 1000 ? 499 : 999, true);
    }
}
```

Behaviour: 5xx and per-attempt timeouts are retried (`Retry.backoff`); when retries are
exhausted (`Exceptions.isRetryExhausted`) or the body is empty, it falls back to a flat
rate. A 4xx is not retried and propagates as a `WebClientResponseException` subclass.
`timeout()` is placed **before** `retryWhen`, so each attempt has its own timeout.

Mutants worth killing:

- `isRetryable`: removed conditionals (`is5xxServerError`, `instanceof TimeoutException`)
  and `TRUE_RETURNS`/`FALSE_RETURNS` on its returns.
- `flatRate`: the `<= 1000` boundary and the `RETURNS`/value mutants.
- `NULL_RETURNS` on lambdas (`Mono.fromSupplier(() -> ...)`).

Not mutated by default: the operator chain (`timeout`, `retryWhen`, `switchIfEmpty`,
`onErrorResume`). Tests still protect it as behaviour.

### 11.2 Fast tests: WireMock JUnit extension, no Spring context

```java
package com.example.quotes.shipping;

import static com.github.tomakehurst.wiremock.client.WireMock.*;
import static com.github.tomakehurst.wiremock.core.WireMockConfiguration.wireMockConfig;
import static com.github.tomakehurst.wiremock.stubbing.Scenario.STARTED;
import static org.assertj.core.api.Assertions.assertThat;

import com.github.tomakehurst.wiremock.junit5.WireMockExtension;
import java.time.Duration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.RegisterExtension;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import reactor.test.StepVerifier;

class ShippingQuoteClientTest {

    private static final Duration WAIT = Duration.ofSeconds(5);

    @RegisterExtension
    static WireMockExtension wm = WireMockExtension.newInstance()
            .options(wireMockConfig().dynamicPort())
            .build();

    private ShippingQuoteClient client;

    @BeforeEach
    void setUp() {
        WebClient webClient = WebClient.builder().baseUrl(wm.baseUrl()).build();
        // Tiny real backoff and timeout: these tests run once per mutant.
        client = new ShippingQuoteClient(webClient, 2, Duration.ofMillis(10), Duration.ofMillis(300));
    }

    @Test
    void returnsCarrierQuoteAndSendsQueryParameters() {
        wm.stubFor(get(urlPathEqualTo("/quotes")).willReturn(okJson("""
                {"carrier":"ACME","priceCents":650,"fallback":false}""")));

        StepVerifier.create(client.quote("AB12CD", 800))
                .expectNext(new ShippingQuote("ACME", 650, false))
                .expectComplete()
                .verify(WAIT);

        wm.verify(1, getRequestedFor(urlPathEqualTo("/quotes"))
                .withQueryParam("postcode", equalTo("AB12CD"))
                .withQueryParam("weight", equalTo("800")));
    }

    @Test
    void retriesAfter503AndSucceeds() {
        wm.stubFor(get(urlPathEqualTo("/quotes")).inScenario("flaky")
                .whenScenarioStateIs(STARTED)
                .willReturn(serviceUnavailable())
                .willSetStateTo("ok"));
        wm.stubFor(get(urlPathEqualTo("/quotes")).inScenario("flaky")
                .whenScenarioStateIs("ok")
                .willReturn(okJson("""
                        {"carrier":"ACME","priceCents":700,"fallback":false}""")));

        StepVerifier.create(client.quote("AB12CD", 800))
                .expectNext(new ShippingQuote("ACME", 700, false))
                .expectComplete()
                .verify(WAIT);

        wm.verify(2, getRequestedFor(urlPathEqualTo("/quotes")));
    }

    @Test
    void fallsBackAfterExactlyThreeAttemptsOn5xx() {
        wm.stubFor(get(urlPathEqualTo("/quotes")).willReturn(serverError()));

        StepVerifier.create(client.quote("AB12CD", 1500))
                .expectNext(new ShippingQuote("FLAT", 999, true))
                .expectComplete()
                .verify(WAIT);

        wm.verify(3, getRequestedFor(urlPathEqualTo("/quotes")));   // 1 + 2 retries
    }

    @Test
    void doesNotRetryOrFallBackOn404() {
        wm.stubFor(get(urlPathEqualTo("/quotes")).willReturn(notFound()));

        StepVerifier.create(client.quote("ZZ99ZZ", 800))
                .expectErrorSatisfies(ex -> assertThat(ex)
                        .isInstanceOf(WebClientResponseException.NotFound.class))
                .verify(WAIT);

        wm.verify(1, getRequestedFor(urlPathEqualTo("/quotes")));
    }

    @Test
    void slowResponsesAreRetriedThenFallBack() {
        wm.stubFor(get(urlPathEqualTo("/quotes"))
                .willReturn(okJson("{}").withFixedDelay(1_000)));   // > 300 ms per-attempt timeout

        StepVerifier.create(client.quote("AB12CD", 1000))
                .expectNext(new ShippingQuote("FLAT", 499, true))   // also pins the <= 1000 boundary
                .expectComplete()
                .verify(WAIT);

        wm.verify(3, getRequestedFor(urlPathEqualTo("/quotes")));
    }

    @Test
    void emptyBodyFallsBack() {
        wm.stubFor(get(urlPathEqualTo("/quotes")).willReturn(ok()));

        StepVerifier.create(client.quote("AB12CD", 1001))
                .expectNext(new ShippingQuote("FLAT", 999, true))   // other side of the boundary
                .expectComplete()
                .verify(WAIT);
    }
}
```

What kills what:

| Test | Kills |
|---|---|
| `returnsCarrierQuote...` | value mutants on the success path; query parameters protect request building (non-void calls, so no default mutants there) |
| `retriesAfter503AndSucceeds` | `is5xxServerError` removed-conditional / `FALSE_RETURNS` in `isRetryable` |
| `fallsBackAfterExactlyThreeAttemptsOn5xx` | fallback value mutants, and behaviour changes to the retry count |
| `doesNotRetryOrFallBackOn404` | `TRUE_RETURNS` on `isRetryable` (would retry 404) |
| `slowResponsesAreRetried...` | removal of the `TimeoutException` branch; `flatRate` at weight 1000 |
| `emptyBodyFallsBack` | `flatRate` at weight 1001; the `switchIfEmpty` lambda's return |

Notes:

- Keep the WireMock delay just above the timeout. Each extra second is multiplied by the
  number of mutants that run this test.
- `Retry.backoff` adds jitter by default. With 10 ms base backoff it does not matter;
  never assert on exact timings in WireMock tests.
- For precise timing checks (backoff growth, "no retry before X"), use the virtual-time
  test from 9.3 with a stub `exchangeFunction`, not WireMock.
- Use dynamic ports. pitest's parallel minions would collide on fixed ports.

### 11.3 With a Spring context

When the `WebClient` is built from Boot configuration (`WebClient.Builder` from
`spring-boot-starter-webclient`, base URL from properties), use `wiremock-spring-boot`:

```java
@SpringBootTest
@EnableWireMock(@ConfigureWireMock(name = "shipping", baseUrlProperties = "clients.shipping.base-url"))
@Tag("integration")
class ShippingIntegrationIT {

    @InjectWireMock("shipping")
    WireMockServer shipping;

    @Autowired
    ShippingQuoteClient client;

    @Test
    void usesConfiguredBaseUrl() {
        shipping.stubFor(get(urlPathEqualTo("/quotes")).willReturn(okJson("""
                {"carrier":"ACME","priceCents":650,"fallback":false}""")));

        StepVerifier.create(client.quote("AB12CD", 800))
                .expectNext(new ShippingQuote("ACME", 650, false))
                .expectComplete()
                .verify(Duration.ofSeconds(5));
    }
}
```

Keep these few. The logic is already covered by the fast tests above, and Spring tests are
expensive under pitest (section 14).

---

## 12. WebTestClient controller tests

`@WebFluxTest` auto-configures `WebTestClient` without starting a server, and is usually
combined with `@MockitoBean` collaborators (Spring Boot docs). This is the cheapest way to
mutate controller code:

```java
@WebFluxTest(QuoteController.class)
class QuoteControllerTest {

    @Autowired
    WebTestClient web;

    @MockitoBean
    LoyaltyDiscountService discounts;

    @Test
    void returnsQuoteJson() {
        when(discounts.quote(1L, new BigDecimal("100.00")))
                .thenReturn(Mono.just(new PriceQuote(new BigDecimal("100.00"),
                        new BigDecimal("0.05"), new BigDecimal("95.00"))));

        web.get().uri("/customers/1/quote?basket=100.00")
                .exchange()
                .expectStatus().isOk()
                .expectBody()
                .jsonPath("$.total").isEqualTo(95.00)
                .jsonPath("$.rate").isEqualTo(0.05);
    }

    @Test
    void unknownCustomerIs404() {
        when(discounts.quote(eq(404L), any())).thenReturn(Mono.empty());

        web.get().uri("/customers/404/quote?basket=100.00")
                .exchange()
                .expectStatus().isNotFound();
    }
}
```

(Imports omitted: several Boot test annotations moved packages in Boot 4 when
auto-configuration was split into modules. Let your IDE resolve them against
`spring-boot-starter-webflux-test`.)

Remember: `LoyaltyDiscountService` is a mock here, so this test contributes **no**
coverage to it. Its mutants must be killed by its own tests.

`@SpringBootTest(webEnvironment = RANDOM_PORT)` + `@AutoConfigureWebTestClient` starts a real
server. Per the Arcmutate Spring docs, pitest (even with their Spring plugin) "cannot be
used with integration tests that launch a web server". Tag such tests and exclude them
from pitest.

---

## 13. R2DBC with Testcontainers PostgreSQL

### 13.1 Setup that survives many reruns

Under pitest each test class runs many times in the same minion JVM. A container
started per test class (`@Testcontainers` + static `@Container`) pays start-up again and
again; the Spring Boot docs also warn that this pattern can clash with Spring's context
cache. Declare the container as a bean with `@ServiceConnection`. It then lives as long as
the cached context, so you get one container per minion JVM:

```java
package com.example.quotes.testsupport;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.postgresql.PostgreSQLContainer;

@TestConfiguration(proxyBeanMethods = false)
public class PostgresTestConfig {

    @Bean
    @ServiceConnection
    PostgreSQLContainer postgres() {
        return new PostgreSQLContainer("postgres:17-alpine");   // use your production major version
    }
}
```

For a `PostgreSQLContainer`, Boot creates **both** JDBC and R2DBC connection details by
default (Boot docs; `@ServiceConnection(type = ...)` narrows it). The R2DBC side comes from
`PostgresR2dbcContainerConnectionDetailsFactory`, which uses
`PostgreSQLR2DBCDatabaseContainer` from Testcontainers. Add `testcontainers-r2dbc` next to
`testcontainers-postgresql`, as Boot's own build does.

Testcontainers 2.x moved the class to `org.testcontainers.postgresql.PostgreSQLContainer`.
Imports from `org.testcontainers.containers` are the 1.x API.

### 13.2 A repository test

```java
@DataR2dbcTest
@Import(PostgresTestConfig.class)
@Tag("integration")
class CustomerRepositoryIT {

    @Autowired
    CustomerRepository customers;

    @Autowired
    DatabaseClient db;

    @BeforeEach
    void cleanTables() {
        // @DataR2dbcTest is NOT transactional by default (Spring Boot docs): clean up yourself.
        StepVerifier.create(db.sql("TRUNCATE TABLE customer RESTART IDENTITY").then())
                .expectComplete()
                .verify(Duration.ofSeconds(5));
    }

    @Test
    void findsLoyalCustomersFromThreshold() {
        StepVerifier.create(customers.saveAll(List.of(
                                new Customer(null, 49), new Customer(null, 50), new Customer(null, 51)))
                        .thenMany(customers.findLoyal(50)))
                .expectNextCount(2)
                .expectComplete()
                .verify(Duration.ofSeconds(10));
    }
}
```

(Schema creation is assumed to be handled by your project, for example `schema.sql` with
`spring.sql.init.mode=always`, or a migration tool. Flyway and Liquibase need a JDBC
connection, which the same container also provides.)

### 13.3 What mutation testing can and cannot do for persistence

- **SQL in `@Query` strings or `DatabaseClient.sql("...")` is not mutated.** pitest
  mutates bytecode instructions, not string constants (unless you enable experimental
  inline-constant mutators, which do not understand SQL anyway). A wrong `>=` in a query
  is caught only by an integration test with boundary data, as above. Mutation scores say
  nothing about it.
- What pitest **can** mutate in the persistence layer: Java mapping code, conditional
  logic in adapters, and how results are combined in services. Test those with plain unit
  tests where possible.
- Recommendation: keep R2DBC/Testcontainers tests out of the regular pitest run (tag +
  `excludedGroups`). Run them in normal CI for correctness, and optionally in a nightly
  pitest pass scoped to the persistence package:

```bash
./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage \
  -DtargetClasses='com.example.quotes.persistence.*' \
  -DtargetTests='com.example.quotes.persistence.*IT' \
  -DincludedGroups=integration -Dthreads=2 -DtimeoutConstant=15000
```

This works when the `integration` exclusion comes from Surefire: pitest ignores
Surefire's groups once any group is set on pitest itself. If you put `excludedGroups` into
the pitest configuration, use a separate profile for the nightly pass.

- With `threads=4` there may be 4 containers at once (one per minion JVM). Size the Docker
  host for that.

---

## 14. Keeping runtime sane

### 14.1 Test pyramid for pitest

1. **Plain unit tests** of rules (`discountRate`, `isRetryable`, `flatRate`) with no
   Reactor: fastest, most kills per second.
2. **Reactor unit tests** with mocks or stub publishers and `StepVerifier`, virtual time
   for anything time-based.
3. **WireMock tests without Spring** for clients (11.2).
4. **Slices** (`@WebFluxTest`, `@DataR2dbcTest`): fewer, and only for wiring.
5. **Full `@SpringBootTest`, real server, containers**: tagged and excluded from the
   regular pitest run.

Arcmutate's performance docs describe the mechanism: pitest runs faster tests first and
falls back to slower ones only when faster ones do not kill the mutant, so slow tests that
cover a lot get executed again and again for survivors.

Per the Arcmutate Spring docs, Spring test extensions "may fail to detect mutants" without
their Spring plugin, which clears the context after each test. The underlying mechanism is
not documented in open-source pitest and was not verified here. Either way, keep business
logic testable without Spring.

### 14.2 Exclusions

- `excludedClasses`: main application class, `@Configuration`, DTOs/records without logic,
  generated clients (OpenAPI), mapper implementations.
- `excludedMethods`: `toString`, `equals`, `hashCode`.
- `avoidCallsTo`: logging packages; consider metrics/tracing packages too if those calls
  are not something you want tests to verify.
- Annotation-based: pitest skips classes and methods annotated with an annotation whose
  simple name is `Generated`, `DoNotMutate` or `CoverageIgnore`, **if** it has CLASS or
  RUNTIME retention (`FANN` feature, pitest source). `javax.annotation.processing.Generated`
  and `jakarta.annotation.Generated` are SOURCE-retention and therefore not detected;
  exclude such generated code by package.

### 14.3 Only mutate what changed

`scmMutationCoverage` was deprecated in 1.17.1 and **removed in 1.18.0**. Options:

**A. git diff -> `targetClasses`** (free):

```bash
#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE_REF:-origin/main}"
CLASSES=$(git diff --name-only --diff-filter=AMR "$BASE"...HEAD -- 'src/main/java/*.java' \
  | sed -e 's#^src/main/java/##' -e 's#\.java$#*#' -e 's#/#.#g' | paste -sd, -)
[ -z "$CLASSES" ] && { echo "No production changes"; exit 0; }
./mvnw -B -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage \
  -DtargetClasses="$CLASSES" -DfailWhenNoMutations=false
```

Per-class granularity; `Foo*` also matches `FooBar`; adapt paths for multi-module builds;
CI checkout needs the merge base (`fetch-depth: 0`).

**B. Arcmutate git plugin** (commercial): line-level changed-code analysis with
`-Dfeatures="+GIT(from[origin/main])"`.

**C. History files** cached between CI runs (section 5).

---

## 15. Equivalent mutants

An equivalent mutant changes code without changing behaviour; no test can kill it.

Reactive-flavoured examples:

- **Guard before an operator that already handles the case:**

  ```java
  if (items.isEmpty()) { return Flux.empty(); }
  return Flux.fromIterable(items).map(this::price);
  ```

  Removing the `isEmpty` check produces `Flux.fromIterable(emptyList)`, which is also
  empty. Equivalent (fix: delete the guard).
- **Redundant `filter`:** `filter(x -> x != null)` on a source that cannot emit nulls (Reactor
  forbids `null` elements). Removing the condition changes nothing.
- **Boundary on an unreachable value:** a cap check `if (rate.compareTo(MAX) > 0)` where
  the possible rates never equal `MAX`.
- **Caching:** `cache()` or a memo map; removing the check that consults the cache
  recomputes the same value.
- **Metrics/log calls** (`VOID_METHOD_CALLS`): undetectable by design. Use `avoidCallsTo`
  for the package, or assert on an in-memory meter registry if the metric matters.

How to handle them:

1. Try for two minutes to write a failing test. Many "equivalents" are real gaps.
2. Prefer simplifying the code (equivalent mutants often mark redundant code).
3. Exclude narrowly (`@DoNotMutate` on one small method), never a whole class.
4. Leave headroom in thresholds. 100% is rarely sensible.

pitest already filters many known equivalent patterns. Arcmutate's base plugin release
notes mention improved filtering of equivalent mutants in methods returning
`reactor.core.publisher.Flux` and similar reactive types.

---

## 16. CI integration and thresholds

Threshold parameters (`PitMojo.java`): `mutationThreshold`, `coverageThreshold`,
`testStrengthThreshold`, `maxSurviving`, and `thresholdPrecision` (1.25.4+) to allow
decimals. The pitest docs warn about the integer-threshold blind spot (a whole percentage
point hides a lot on large codebases), so use decimals:

```xml
<mutationThreshold>72.5</mutationThreshold>
<testStrengthThreshold>80.0</testStrengthThreshold>
<thresholdPrecision>1</thresholdPrecision>
```

**Realistic targets (opinion):** 80-90% on pure business-rule packages; 60-75% on
adapters, controllers and clients (more equivalent and framework-driven mutants); a first
whole-service run on a reactive codebase is often well below its line coverage, because of
non-subscribing tests and `expectNextCount`-style assertions. Gate slightly below the
current value and ratchet up. Test strength is often the fairer gate.

GitHub Actions sketch:

```yaml
name: mutation-testing
on:
  pull_request:
  schedule:
    - cron: "0 2 * * *"

jobs:
  pr-changed-code:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "21"
          cache: maven
      - run: ./scripts/pitest-changed.sh
        env:
          BASE_REF: origin/${{ github.base_ref }}
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: pit-report-pr
          path: target/pit-reports/

  nightly-full:
    if: github.event_name == 'schedule'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "21"
          cache: maven
      - uses: actions/cache@v4
        with:
          path: .pitest
          key: pitest-history-${{ github.sha }}
          restore-keys: pitest-history-
      - run: |
          mkdir -p .pitest
          ./mvnw -B -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage \
            -DhistoryInputFile=.pitest/history.bin \
            -DhistoryOutputFile=.pitest/history.bin \
            -DmutationThreshold=72.5 -DthresholdPrecision=1
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: pit-report-nightly
          path: target/pit-reports/
```

Do not gate PR runs on a percentage: the score of a handful of changed classes swings
wildly. Review the survivors, or use `maxSurviving`. Set `threads` explicitly on CI; do
not use `+auto_threads` there.

---

## 17. Pitfalls: general and Reactor-specific

### 17.1 Reactor-specific

- **Missing terminal `verify*()`** on `StepVerifier`: nothing subscribes, nothing is
  asserted. The most damaging reactive test bug.
- **`verifyComplete()` without a timeout**: mutants that never complete become slow
  `TIMED_OUT`s. Use `verify(Duration)` or `StepVerifier.setDefaultTimeout`.
- **`expectNextCount(n)` instead of value assertions**: survives every value mutant.
- **Virtual time misuse**: creating the publisher outside the `withVirtualTime` supplier
  (it then captures the real scheduler and waits in real time); expecting virtual time to
  speed up real network calls (it does not); forgetting that `expectNoEvent` treats the
  subscription as an event.
- **Real-time backoffs and delays in tests**: make durations constructor or config
  parameters so tests use milliseconds.
- **Fire-and-forget `.subscribe()` inside production code**: the work outlives the test
  that started it, runs into the next test, and makes results order- and timing-dependent
  (also under pitest's minion reuse). Return the publisher instead; if you must keep it,
  test with Awaitility (included in `spring-boot-starter-test`) and make it deterministic.
- **Blocking calls in tests** (`block()`): acceptable for setup, but `block()` on an empty
  `Mono` returns `null` and hides "empty vs value" mutants. Prefer `StepVerifier`.
- **Global hooks** (`Hooks.onOperatorDebug()`, BlockHound, debug agents) installed in test
  static initialisers: they slow every mutant run and change stack traces. Keep them out
  of the pitest run, or enable them only in a dedicated test.
- **Hot or shared publishers** (`cache()`, `share()`, sinks held in singletons): state
  leaks between tests and between mutant runs. Create fresh instances per test.
- **`Mono<Void>` side effects not chained**: default mutators cannot simulate "forgot to
  subscribe". Use `PublisherProbe.assertWasSubscribed()`.
- **Mocks returning `null` instead of `Mono.empty()`**: an unstubbed Mockito method
  returning `Mono` gives `null`, which causes NPEs that "kill" mutants for the wrong reason.
  Stub every reactive method you use, or use a default answer that returns empty
  publishers.

### 17.2 General

- **Flaky tests** inflate scores (false kills) or break the coverage stage. pitest requires
  the unmutated suite to pass. Fix or exclude them (`excludedTestClasses`).
- **Test-order dependence**: pitest runs subsets, fastest first, often single classes.
  Every test must set up its own state.
- **Shared containers**: one container per minion serves many tests. Truncate tables in
  `@BeforeEach` (R2DBC slices are not transactional by default).
- **Fixed ports** for WireMock or servers break with `threads > 1`.
- **Timing assertions** ("completes within 200 ms") are flaky under pitest's load.
- **Mocks of the mutated code**: a class that is mocked in most tests gets no coverage
  from them.
- **`-DskipTests` also skips pitest.**
- **Duplicate JVM flags** after upgrading past 1.15.4 (Surefire argLine now imported).
- **Expecting `scmMutationCoverage`**: removed in 1.18.0.
- **Trusting `TIMED_OUT`/`RUN_ERROR` kills**: they inflate the score.

---

## 18. Arcmutate notes (reactive operators, Spring)

Arcmutate sells pitest plugins. Each needs a licence file (`arcmutate-licence.txt` in the
repository root or the pitest report directory). Pricing and any free tiers were not
checked; see their site. The following is what their docs confirm.

**Base plugin, `com.arcmutate:base`** (latest on Central: 1.7.2). Extended operators,
with an `EXTENDED` group recommended together with `DEFAULTS` or `STRONGER`. The operators
relevant to Reactor:

- `REACTIVE_RETURNS`: for methods returning `Mono`, `Flux` (and RxJava types), replaces the
  return with the type's `empty()` instead of pitest's `null`. Empty is a far more
  meaningful mutant than null (section 7.2).
- `EXTREME_EMPTY`: replaces a whole method body with an empty return (`Mono.empty()`,
  `Flux.empty()`, empty collections, ...).
- An operator that removes `filter` calls on `java.util.stream.Stream`, `Flux` and RxJava
  types (the docs describe it; the exact operator name was not confirmed here).
- Operators that swap `flatMap`, `switchMap` and `concatMap` (base plugin 1.3.1 release
  notes), for example `REACTIVE_SWITCHMAP_TO_FLATMAP` for `Flux` and RxJava types.
- Improved filtering of equivalent mutants in methods with reactive return types.
- Features such as `+slow_tests(max[500])` to exclude slow tests.

These mutate exactly what open-source pitest leaves alone in a reactive codebase: the
operator wiring.

```xml
<plugin>
  <groupId>org.pitest</groupId>
  <artifactId>pitest-maven</artifactId>
  <version>1.30.1</version>
  <dependencies>
    <dependency>
      <groupId>org.pitest</groupId>
      <artifactId>pitest-junit5-plugin</artifactId>
      <version>1.2.3</version>
    </dependency>
    <dependency>
      <groupId>com.arcmutate</groupId>
      <artifactId>base</artifactId>
      <version>1.7.2</version>
    </dependency>
  </dependencies>
  <configuration>
    <mutators>
      <mutator>STRONGER</mutator>
      <mutator>EXTENDED</mutator>
    </mutators>
  </configuration>
</plugin>
```

**Spring plugin, `com.arcmutate:arcmutate-spring`** (1.1.3): `SPRING` mutator group with
annotation mutators (`REMOVE_SECURITY` for `@PreAuthorize`, `@Secured`, `@RolesAllowed`
and similar; `REMOVE_VALIDATION` for `@Min`, `@Max`, `@NotEmpty`, `@Pattern`). It also clears
the Spring context after each test so mutants are executed in Spring tests. Not for tests
that launch a web server. Whether it has WebFlux-specific behaviour was not found in the
docs.

**Git plugin, `com.arcmutate:pitest-git-plugin`** (2.3.4): changed-code analysis
(`+GIT(from[<ref>])`), plus PR integrations for GitHub, GitLab, Bitbucket and Azure.

Arcmutate's examples use pitest 1.22.0. Compatibility of these plugin versions with pitest
1.30.1, and of `pitest-accelerator-junit5` with JUnit 6, was not verified here.

---

## 19. Checklist

- [ ] `pitest-maven` 1.30.1 + `pitest-junit5-plugin` 1.2.3 as a **plugin dependency** in a
      `pitest` profile.
- [ ] First run shows `Ran N tests` (N > 0) and non-zero coverage (JUnit 6 check, 4.4).
- [ ] Empty `<argLine/>` property; no JVM flags duplicated between Surefire and pitest;
      JaCoCo left alone.
- [ ] `spring-boot-starter-webclient` added if you use `WebClient.Builder` (Boot 4 split).
- [ ] Every `StepVerifier` ends in `verify(Duration)` (or a global default timeout is set).
- [ ] Value assertions (`expectNext(value)`, `assertNext`) instead of `expectNextCount`.
- [ ] Error tests check type and message (`expectErrorSatisfies`).
- [ ] Time-based logic tested with `withVirtualTime` (publisher created in the supplier).
- [ ] `PublisherProbe` checks for `switchIfEmpty` / `onErrorResume` / `Mono<Void>` side
      effects.
- [ ] Business rules extracted from lambdas into named methods with plain unit tests.
- [ ] WireMock tests on dynamic ports, tiny real delays, verifying request counts, query
      parameters, headers and bodies; 4xx/5xx/timeout/empty paths covered.
- [ ] Testcontainers PostgreSQL as a `@ServiceConnection` bean (one per minion JVM);
      `testcontainers-r2dbc` present; tables cleaned per test.
- [ ] Integration, real-server and container tests tagged and excluded from the regular
      pitest run.
- [ ] Mutators: `DEFAULTS` + `EXPERIMENTAL_BIG_DECIMAL`; consider `STRONGER`, and Arcmutate
      `EXTENDED` if you want operator-level mutants.
- [ ] Survivors reviewed; equivalents simplified away or excluded narrowly.
- [ ] Changed-code runs on PRs (git-diff script or Arcmutate); full nightly with cached
      history; no `scmMutationCoverage`.
- [ ] Decimal thresholds with `thresholdPrecision`, slightly below the current score.
- [ ] Share of `TIMED_OUT` / `RUN_ERROR` checked.
