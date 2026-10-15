# Mutation Testing with PIT (pitest) for a Spring Boot 4 MVC Service

A practical guide for a Spring Boot 4 / Java 21 / Maven service that:

- is mostly business logic (pricing, eligibility, validation, state transitions),
- makes many outbound REST calls (stubbed with WireMock in tests),
- persists to PostgreSQL (tested with Testcontainers),
- already has a decent test suite and a "nice" line-coverage number.

The goal is to find out whether those tests would actually catch a bug, and to keep
mutation testing fast enough that people keep running it.

> **About versions and sources.** Versions below were checked against Maven Central
> metadata in October 2026. Behaviour comes from the pitest README and release notes,
> the pitest source (Maven mojo parameters, mutator groups, detection statuses), the
> pitest.org quickstart docs, the Spring Boot 4.1 reference docs, the WireMock docs, the
> Testcontainers 2.x docs and the Arcmutate docs. Where something could not be verified,
> the guide says so.

---

## Contents

1. [First 30 minutes (quick start)](#1-first-30-minutes-quick-start)
2. [What mutation testing is, and why line coverage lies](#2-what-mutation-testing-is-and-why-line-coverage-lies)
3. [Versions used in this guide](#3-versions-used-in-this-guide)
4. [Installing pitest in a Spring Boot 4 Maven build](#4-installing-pitest-in-a-spring-boot-4-maven-build)
5. [Running it: full, scoped, incremental, parallel](#5-running-it-full-scoped-incremental-parallel)
6. [Reading the reports](#6-reading-the-reports)
7. [Mutators: which ones matter for business logic](#7-mutators-which-ones-matter-for-business-logic)
8. [Worked example: killing a surviving boundary mutant in pricing logic](#8-worked-example-killing-a-surviving-boundary-mutant-in-pricing-logic)
9. [Outbound REST calls: WireMock tests that kill retry and fallback mutants](#9-outbound-rest-calls-wiremock-tests-that-kill-retry-and-fallback-mutants)
10. [Slow tests: @SpringBootTest, Testcontainers PostgreSQL, WireMock](#10-slow-tests-springboottest-testcontainers-postgresql-wiremock)
11. [Keeping runtime sane: exclusions and changed-code-only runs](#11-keeping-runtime-sane-exclusions-and-changed-code-only-runs)
12. [Equivalent mutants](#12-equivalent-mutants)
13. [CI integration and thresholds](#13-ci-integration-and-thresholds)
14. [Common pitfalls](#14-common-pitfalls)
15. [Arcmutate (commercial plugins) notes](#15-arcmutate-commercial-plugins-notes)
16. [Checklist](#16-checklist)

---

## 1. First 30 minutes (quick start)

**Minute 0-5: add a `pitest` profile** to `pom.xml` (full snippet in
[section 4](#4-installing-pitest-in-a-spring-boot-4-maven-build)):

```xml
<profiles>
  <profile>
    <id>pitest</id>
    <build>
      <plugins>
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
          </dependencies>
          <configuration>
            <targetClasses>
              <param>com.example.shop.pricing.*</param>
            </targetClasses>
            <targetTests>
              <param>com.example.shop.pricing.*</param>
            </targetTests>
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
```

**Minute 5-10: run it on ONE package that holds real business logic.**

```bash
./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage
```

Check the console statistics before anything else:

```text
>> Line Coverage (for mutated classes only): 212/220 (96%)
>> Generated 140 mutations Killed 101 (72%)
>> Mutations with no coverage 4. Test strength 74%
>> Ran 410 tests (2.93 tests per mutation)
```

If you see `Ran 0 tests` or 0% line coverage while your tests pass under `./mvnw test`,
stop and read [section 4.4](#44-junit-6-compatibility-check-read-this) (JUnit 6
compatibility).

**Minute 10-20: open `target/pit-reports/index.html`.** Go to the class with the most
`SURVIVED` mutants. For each survivor, ask: "if someone made this exact change in a
pull request, which test should have failed?"

**Minute 20-30: kill one survivor.** Usually it is a boundary (`>=` became `>`) or a
removed call whose side effect nobody asserts. Add the missing test case or assertion,
re-run with history enabled so only affected mutants are re-analysed:

```bash
./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage -DwithHistory
```

Do not set a threshold yet. Measure first; gate later
([section 13](#13-ci-integration-and-thresholds)).

---

## 2. What mutation testing is, and why line coverage lies

### 2.1 The idea

Mutation testing makes small, deliberate changes ("mutants") to your **production
bytecode** and re-runs the tests that cover the changed line:

- If at least one test fails, the mutant is **killed**. Good: the tests noticed the bug.
- If all tests still pass, the mutant **survived**. The tests ran that code but would
  not catch that change.

pitest (PIT) does this at the bytecode level. It first runs a line-coverage analysis to
learn which tests touch which lines, then for each mutant runs only the covering tests,
fastest first, and stops as soon as one fails (pitest.org "Basic concepts").

### 2.2 Why line coverage lies

Line coverage says a line was executed. It says nothing about whether any assertion
depended on what that line did. Typical ways a 95%-covered service still ships bugs:

| What the code does | What the test does | Line coverage | Real protection |
|---|---|---|---|
| `if (qty >= 10) applyBulkDiscount()` | tests qty 5 and qty 20 | 100% | none at the boundary: `>` instead of `>=` passes |
| `auditLog.record(event)` | never checks the audit log | 100% | deleting the call passes |
| retries up to 3 times, then falls back | asserts only the fallback value | 100% | retrying 2 or 4 times passes |
| `return response.total()` | `assertThat(result).isNotNull()` | 100% | returning any non-null value passes |
| a controller calls a mocked service | asserts HTTP 200 | 100% of the controller | the service logic is never exercised |

Each row is a mutant that pitest generates by default and that survives against such a
test. Mutation testing measures **assertion quality**, not execution.

### 2.3 Terms

- **Mutation score**: detected mutants / all mutants (pitest prints this as
  `Killed N (x%)`).
- **Test strength**: detected mutants / mutants that had coverage. This ignores code no
  test runs, so it isolates "are my assertions good?" from "do I have tests here at all?".
- **Line coverage** (pitest's own figure): only for the classes being mutated.

---

## 3. Versions used in this guide

Checked against Maven Central `maven-metadata.xml` in October 2026:

| Artifact | Version | Notes |
|---|---|---|
| `org.pitest:pitest-maven` | **1.30.1** | 1.30.0 follows 1.25.x; the README says the jump happened because a release was mislabelled 1.29.10 |
| `org.pitest:pitest-junit5-plugin` | **1.2.3** | requires pitest >= 1.19.4 (plugin README) |
| `org.springframework.boot:spring-boot-starter-parent` | **4.1.1** (latest GA; 4.2.0-M2 is a milestone) | manages JUnit Jupiter **6.0.3**, Testcontainers **2.0.5**, Surefire **3.5.6** |
| `org.jacoco:jacoco-maven-plugin` | **0.8.15** | not managed by the Boot parent; set it yourself |
| `org.wiremock.integrations:wiremock-spring-boot` | **4.4.3** | release notes from 4.0.0 say "Compatible with SpringBoot 4"; pulls `wiremock-jetty12` 3.13.2 |
| `org.wiremock:wiremock-standalone` | **3.13.2** (stable; 4.0.0-beta.x also exists) | |
| `org.testcontainers:testcontainers-postgresql` | **2.0.5** (managed by Boot) | Testcontainers 2.x artifact name; the class is `org.testcontainers.postgresql.PostgreSQLContainer` |
| `com.arcmutate:arcmutate-spring` | 1.1.3 | commercial, needs a licence |
| `com.arcmutate:pitest-git-plugin` | 2.3.4 | commercial, needs a licence |

pitest 1.18.0 raised the minimum Java runtime to 11, so Java 21 is fine.

---

## 4. Installing pitest in a Spring Boot 4 Maven build

### 4.1 Where the JUnit plugin goes

The pitest JUnit 5 plugin must be on **pitest's** classpath (a `<dependency>` of the
`pitest-maven` plugin), **not** a test dependency of your project (plugin README:
"must be placed on the classpath of the pitest tool (not on the classpath of the project
being mutated)").

You do **not** need to add `junit-platform-launcher` yourself. Since pitest 1.14.0 the
Maven plugin adds a `junit-platform-launcher` (and, if needed, a `junit-jupiter-engine`)
matching the JUnit version your project uses. If you declared the launcher yourself,
pitest uses yours.

### 4.2 Recommended pom.xml layout

Everything pitest-related goes in a profile so normal builds are unaffected:

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
    <!-- Empty default so "@{argLine}" always resolves, even when JaCoCo is skipped.
         See 4.3. -->
    <argLine></argLine>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-webmvc</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-restclient</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>
    <dependency>
      <groupId>org.postgresql</groupId>
      <artifactId>postgresql</artifactId>
      <scope>runtime</scope>
    </dependency>

    <!-- tests -->
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-webmvc-test</artifactId>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-data-jpa-test</artifactId>
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
      <groupId>org.testcontainers</groupId>
      <artifactId>testcontainers-junit-jupiter</artifactId>
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
      <!-- JaCoCo for normal coverage reporting. -->
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
          <!-- "@{...}" is late-evaluated, so JaCoCo's agent is included. -->
          <argLine>@{argLine} -Xshare:off</argLine>
          <!-- Slow tests carry the "integration" tag; see section 10. -->
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
                <param>com.example.shop.*</param>
              </targetClasses>
              <targetTests>
                <param>com.example.shop.*</param>
              </targetTests>
              <excludedClasses>
                <param>com.example.shop.ShopApplication</param>
                <param>com.example.shop.config.*</param>
                <param>com.example.shop.*.dto.*</param>
                <param>com.example.shop.generated.*</param>
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

Notes on that snippet:

- `-Xshare:off` in the surefire `argLine` is only an example of a JVM flag. Put your own
  flags there; pitest will pick them up (see 4.3).
- `excludedGroups` on surefire is also read by pitest (see 4.3), so tagged integration
  tests are excluded from mutation runs too unless you configure pitest's own
  `excludedGroups`/`includedGroups`.
- The `mutators` list is explained in [section 7](#7-mutators-which-ones-matter-for-business-logic).
  `EXPERIMENTAL_BIG_DECIMAL` is in pitest core; it swaps `add`/`subtract`,
  `multiply`/`divide`, `min`/`max` and similar on `BigDecimal`, which the default `MATH`
  mutator never touches.
- `avoidCallsTo` stops pitest from creating mutants for calls into the listed packages
  (logging is the classic case; removing a `log.info(...)` call can never be detected
  and is not worth detecting).

### 4.3 argLine, Surefire and JaCoCo: what pitest does since 1.15.4

pitest forks "minion" JVMs to run your tests. Those JVMs need the same flags your
Surefire runs use (`--add-opens`, `-javaagent` for Mockito, system properties, and so on).

Since **1.15.4**, pitest reads the Surefire plugin configuration and reuses it (release
notes for 1.15.4, 1.15.5, 1.15.8, 1.16.0, 1.17.4, 1.20.2; `SurefireConfigConverter` in the
pitest source):

| Surefire setting | What pitest does with it |
|---|---|
| `<argLine>` | appended to pitest's own `argLine` (1.15.4). `@{prop}` and `${prop}` are replaced with project properties (1.15.5/1.15.8). `${settings.localRepository}` is expanded (1.17.4). Args files (`@file`) are handled (1.20.2). |
| `<environmentVariables>` | copied (1.16.0) |
| `<excludes>` | turned into `excludedTestClasses` |
| `<groups>` / `<excludedGroups>` | used as pitest's included/excluded groups (JUnit 5/6 tags), **unless** you set groups in the pitest config |
| `<testFailureIgnore>` | becomes `skipFailingTests` |

Also:

- pitest adds `-ea` automatically (1.16.0).
- **JaCoCo:** pitest removes any `-javaagent` containing `jacoco` from the minion command
  line (it has done this since #1070, and the current launcher code still does). Release
  1.25.7 also disables JaCoCo transformations at bytecode level. You do not need to
  disable JaCoCo when running pitest.
- To turn off argLine import (for example if Surefire's argLine contains something that
  breaks pitest), set `<parseSurefireArgLine>false</parseSurefireArgLine>`. To turn off
  all Surefire config import, set `<parseSurefireConfig>false</parseSurefireConfig>`.

**Upgrade warning (from the 1.15.4 notes):** if you previously duplicated Surefire's
argLine in pitest's `<jvmArgs>` or `<argLine>`, you now get those flags twice. Remove
the duplicates.

**Unresolved `@{argLine}` pitfall:** pitest replaces `@{argLine}` using the project
properties. If no `argLine` property exists (for example JaCoCo's `prepare-agent` did not
run because you skipped it), the literal text `@{argLine}` can end up on the JVM command
line and the minion fails to start. The empty `<argLine></argLine>` property in 4.2 is
the usual Surefire-style protection.

### 4.4 JUnit 6 compatibility check (read this)

Spring Boot 4.x manages **JUnit 6** (6.0.3 in Boot 4.1.1). The JUnit 5 plugin README
documents compatibility with JUnit Platform 1.x only, and there is an **open issue**
(`pitest/pitest-junit5-plugin#113`, opened April 2026) reporting that a Spring Boot 4.0.5
project on JUnit Platform 6.0.3 got 0% coverage and "Ran 0 tests". That report used
Gradle with older plugin versions (pitest 1.22.1, junit5 plugin 1.2.2); the maintainer
asked for a reproduction, and no fix was released at the time of writing.

**Not verified here:** whether pitest 1.30.1 + pitest-junit5-plugin 1.2.3 on Maven with
JUnit 6.0.x works out of the box. pitest's Maven plugin does add a launcher matching your
JUnit version, which is the mechanism that fixed this class of problem for JUnit 5
upgrades, so it may well work. Check it on your project:

1. Run pitest on a small package.
2. Confirm the statistics show non-zero line coverage and `Ran N tests` with N > 0.
3. If you get 0 tests and 0% coverage although `./mvnw test` passes, you have hit the
   compatibility problem. Options: follow issue #113 for a fixed plugin release; or, as a
   temporary measure, pin JUnit to the last 5.x line in the `pitest` profile by overriding
   `junit-jupiter.version` (only if your tests do not use JUnit 6-only features, and
   accepting that you are testing against a different JUnit than production builds).

### 4.5 Why a profile and not a bound execution

You can bind `mutationCoverage` to a lifecycle phase, but:

- the default phase of the goal is `verify`, so `./mvnw verify` would always run it;
- most teams want unit tests on every build and mutation testing on demand, nightly, or
  on changed code in PRs.

With the profile, invoke the goal explicitly. `test-compile` is enough: pitest runs the
tests itself, so Surefire does not need to run first.

```bash
./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage
```

If you prefer a bound execution in the profile:

```xml
<executions>
  <execution>
    <id>pitest</id>
    <phase>verify</phase>
    <goals><goal>mutationCoverage</goal></goals>
  </execution>
</executions>
```

Then `./mvnw -Ppitest verify` runs Surefire **and** pitest (tests run twice; acceptable in
a nightly job).

---

## 5. Running it: full, scoped, incremental, parallel

All parameters below are real `pitest-maven` mojo parameters (checked in `PitMojo.java`).
Most have a `-D` property of the same name.

### 5.1 Full run

```bash
./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage
```

If `targetClasses` is not set, pitest "defaults target classes to match packages in build
directory" (every package that has compiled classes).

### 5.2 Scoped runs (the everyday loop)

Mutate one package and run only its tests:

```bash
./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage \
  -DtargetClasses='com.example.shop.pricing.*' \
  -DtargetTests='com.example.shop.pricing.*'
```

Mutate a single class:

```bash
./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage \
  -DtargetClasses='com.example.shop.pricing.PriceCalculator*' \
  -DtargetTests='com.example.shop.pricing.PriceCalculatorTest'
```

The trailing `*` on the class glob also matches nested and anonymous classes
(`PriceCalculator$1`) and lambda holders. pitest globs: `*` matches any run of
characters including dots, `?` matches one character.

**Command-line values replace the POM list**, they do not add to it.

### 5.3 Incremental analysis (history files)

pitest can store results and reuse them when neither the class nor its covering tests
changed:

```bash
# Local convenience: history file is kept under java.io.tmpdir
./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage -DwithHistory

# Explicit files (CI: cache this file between runs)
./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage \
  -DhistoryInputFile=.pitest/history.bin \
  -DhistoryOutputFile=.pitest/history.bin
```

From the pitest docs:

- `withHistory=true` puts the history file in `java.io.tmpdir`, and **when it is set the
  explicit input/output file parameters are ignored**.
- If input and output are different files, swapping them between runs is your job.

History files have been invalidated by some pitest upgrades in the past (the release notes
say so for older versions). After upgrading pitest, delete the history file if results look
odd.

### 5.4 Threads

```xml
<threads>4</threads>
```

- Default is 1.
- Each thread drives its own minion JVM, so memory use grows with threads. With Spring
  contexts and containers per JVM ([section 10](#10-slow-tests-springboottest-testcontainers-postgresql-wiremock)),
  4 threads can mean 4 application contexts and 4 PostgreSQL containers.
- `<features><feature>+auto_threads</feature></features>` guesses a thread count; the
  pitest release notes say it is meant for local use and **not recommended on CI**.
- The JUnit 5 plugin disables JUnit parallel execution inside pitest
  (`junit.jupiter.execution.parallel.enabled=false`), so parallelism comes only from
  pitest threads.

### 5.5 Timeouts

A mutant can create an infinite loop (for example `attempt++` becoming `attempt--`).
pitest kills a test run that takes longer than:

```
normal test time * timeoutFactor + timeoutConstant
```

Defaults in `pitest-maven` 1.30.1: `timeoutFactor = 1.25`, `timeoutConstant = 3000` ms.
Such mutants are reported as `TIMED_OUT` and count as detected.

Raise `timeoutConstant` (for example 5000-10000) if you see many `TIMED_OUT` results on
code that should not loop. Spring and container tests have high variance in their timing,
and a garbage collection pause or a slow container is enough to trip the limit.

### 5.6 Other useful switches

| Parameter | Use |
|---|---|
| `-DskipPitest` | skip pitest (property is `skipPitest`, not `skip`) |
| `-Dpit.dryRun=true` | compute coverage and generate mutants without analysing them (1.17.3+); good for sizing a run |
| `-DexcludedTestClasses=...` | do not run these tests during mutation analysis |
| `-DfailWhenNoMutations=false` | do not fail when the filter matches nothing (useful for changed-code runs) |
| `<verbosity>` | console detail level (`DEFAULT` is the default) |
| `<maxMutationsPerClass>` | caps mutants per class (default -1, unlimited); gives a cheap sample on huge classes |
| `<exportLineCoverage>true</exportLineCoverage>` | writes pitest's line coverage data |
| `<extraFeatures>` / `-DextraFeatures` | add feature strings without overwriting the configured `features` list (1.15.0) |

**Careful with `-DskipTests`:** the pitest mojo has a `skipTests` parameter bound to the
`skipTests` property. `-DskipTests` therefore skips pitest as well.

---

## 6. Reading the reports

### 6.1 Where they are

With `timestampedReports=false` (the mojo default) the report is written to:

```
target/pit-reports/index.html      # HTML
target/pit-reports/mutations.xml   # if XML is in outputFormats
target/pit-reports/mutations.csv   # if CSV is in outputFormats
```

With `timestampedReports=true` each run goes to a `target/pit-reports/YYYYMMDDHHMI/`
subdirectory.

### 6.2 HTML report

- **Project summary:** number of classes, line coverage, mutation coverage, test strength.
- **Package and class tables** with the same three columns.
- **Class page:** your source with each line shaded by coverage. Lines that have mutants
  carry a marker; expand it to see each mutant's description and status. Since 1.16.2 the
  report lists the **covering tests for surviving mutants**, which tells you exactly which
  tests ran and failed to notice.
- Bottom of the page: active mutators and the tests examined.

Typical mutant descriptions:

```text
changed conditional boundary                                  -> SURVIVED
removed conditional - replaced comparison check with false    -> KILLED
removed call to com/example/shop/audit/AuditLog::record       -> SURVIVED
replaced return value with null for com/example/.../quote     -> KILLED
Replaced integer addition with subtraction                    -> KILLED
Changed increment from 1 to -1                                -> TIMED_OUT
```

### 6.3 Statuses

From pitest's `DetectionStatus` enum. "Detected" is what counts towards the score.

| Status | Detected? | Meaning | What to do |
|---|---|---|---|
| `KILLED` | yes | a test failed with the mutant | nothing |
| `SURVIVED` | no | covering tests ran and all passed | add or strengthen assertions, or accept it as equivalent |
| `NO_COVERAGE` | no | no test executes this line | write a test, or exclude the code if it is not worth testing |
| `TIMED_OUT` | yes | tests exceeded the timeout (usually an infinite loop) | fine, unless it shows up on code that cannot loop; then raise `timeoutConstant` |
| `NON_VIABLE` | yes | mutant bytecode was invalid and could not be loaded | nothing |
| `MEMORY_ERROR` | yes | minion ran out of memory | fine occasionally; if frequent, raise `-Xmx` in `jvmArgs` |
| `RUN_ERROR` | yes | the minion crashed or failed for some other reason | investigate if frequent; often environment problems (ports, Docker, files) |
| `EQUIVALENT` | yes | marked equivalent by a plugin or interceptor | added in 1.25.0 ("introduce equivalent status"). Not verified here: whether any open-source mechanism lets you mark a mutant as equivalent by hand. |
| `NOT_STARTED`, `STARTED` | no | internal states; should not appear in a finished report | a crashed run |

`TIMED_OUT`, `MEMORY_ERROR` and `RUN_ERROR` count as detected. A suite that is unstable
under pitest can therefore show a *higher* score than it deserves. Check how many of your
"kills" have these statuses.

### 6.4 XML report for scripts

`mutations.xml` holds one `<mutation>` element per mutant, with `status` and `detected`
attributes and child elements such as `sourceFile`, `mutatedClass`, `mutatedMethod`,
`lineNumber`, `mutator`, `killingTest` and `description`. Example queries with
`xmllint`:

```bash
# how many survived
xmllint --xpath 'count(//mutation[@status="SURVIVED"])' target/pit-reports/mutations.xml

# survivors as class:line  description
python3 - target/pit-reports/mutations.xml <<'EOF'
import sys, xml.etree.ElementTree as ET
for m in ET.parse(sys.argv[1]).getroot().iter("mutation"):
    if m.get("status") == "SURVIVED":
        print(f'{m.findtext("mutatedClass")}:{m.findtext("lineNumber")}  {m.findtext("description")}')
EOF
```

---

## 7. Mutators: which ones matter for business logic

### 7.1 The groups (as implemented in pitest 1.30.x)

Taken from `StandardMutatorGroups.java` and `ReturnsMutatorGroup.java` in the pitest
source:

| Group | Contents |
|---|---|
| `DEFAULTS` | `CONDITIONALS_BOUNDARY`, `INCREMENTS`, `INVERT_NEGS`, `MATH`, `VOID_METHOD_CALLS`, `REMOVE_CONDITIONALS_ORDER_ELSE`, `REMOVE_CONDITIONALS_EQUAL_ELSE`, and the `RETURNS` family (`TRUE_RETURNS`, `FALSE_RETURNS`, `PRIMITIVE_RETURNS`, `EMPTY_RETURNS`, `NULL_RETURNS`) |
| `STRONGER` | `DEFAULTS` + `EXPERIMENTAL_SWITCH`, `REMOVE_CONDITIONALS_ORDER_IF`, `REMOVE_CONDITIONALS_EQUAL_IF` |
| `ALL` | every registered mutator, including experimental ones |

**Doc discrepancy:** parts of the pitest.org mutators page still list "Negate
Conditionals" in `DEFAULTS`. Since pitest 1.7.x (release note #943, "replace negate
conditional with remove conditional") the default group uses the `REMOVE_CONDITIONALS_*_ELSE`
variants instead. `NEGATE_CONDITIONALS` still exists and you can enable it by name. The
source code is the authority here.

What `_IF` and `_ELSE` mean: `ORDER` covers `<`, `<=`, `>`, `>=`; `EQUAL` covers `==` and
`!=`. `_ELSE` forces the condition so the else path (or skip) is always taken; `_IF` forces
the guarded block to always run.

### 7.2 What matters for a business-logic service

| Mutator | Why it matters here |
|---|---|
| `CONDITIONALS_BOUNDARY` | the most valuable one for pricing, limits, eligibility, dates. Kills come only from tests **at** the boundary |
| `REMOVE_CONDITIONALS_*` | shows rules that no test checks from both sides |
| `VOID_METHOD_CALLS` | removes calls like `auditLog.record()`, `publisher.publishEvent()`, `repository.deleteById()`. Survivors mean nobody checks the side effect |
| `RETURNS` family | survivors mean callers' tests do not check the returned value (`isNotNull()` style assertions) |
| `MATH` | primitive arithmetic only (`int`, `long`, `double`); **not** `BigDecimal` |
| `EXPERIMENTAL_BIG_DECIMAL` | swaps `add`/`subtract`, `multiply`/`divide`, `min`/`max`, `negate`/`plus` and similar on `BigDecimal`. Without it, money arithmetic written with `BigDecimal` is barely mutated |
| `INCREMENTS` | loop counters; in retry loops these often show up as `TIMED_OUT` |
| `REMOVE_CONDITIONALS_*_IF` (STRONGER) | useful once DEFAULTS is mostly green |

Recommended progression:

1. Start with `DEFAULTS` + `EXPERIMENTAL_BIG_DECIMAL` on business packages.
2. When the score there is stable and high, try `STRONGER` on the same packages.
3. Treat `ALL` as an exploration tool. It includes research-grade and experimental
   mutators that produce many equivalent or noisy mutants.

Feature filters worth knowing:

- `+funmodifiablecollection` (1.15.8+, off by default) filters mutants on
  `Collections.unmodifiable*` wrappers in defensive code.
- `-frecord` turns **off** the filter for junk mutants in Java records. It is on by
  default, which is what you want.

---

## 8. Worked example: killing a surviving boundary mutant in pricing logic

### 8.1 The production code

```java
package com.example.shop.pricing;

import java.math.BigDecimal;
import java.math.RoundingMode;

public final class PriceCalculator {

    static final int BULK_MIN_QUANTITY = 10;
    static final BigDecimal BULK_RATE = new BigDecimal("0.05");
    static final BigDecimal GOLD_RATE = new BigDecimal("0.10");
    static final BigDecimal MAX_RATE = new BigDecimal("0.12");

    public BigDecimal totalFor(CustomerTier tier, BigDecimal unitPrice, int quantity) {
        if (quantity <= 0) {
            throw new IllegalArgumentException("quantity must be positive");
        }
        BigDecimal gross = unitPrice.multiply(BigDecimal.valueOf(quantity));

        BigDecimal rate = BigDecimal.ZERO;
        if (quantity >= BULK_MIN_QUANTITY) {
            rate = rate.add(BULK_RATE);
        }
        if (tier == CustomerTier.GOLD) {
            rate = rate.add(GOLD_RATE);
        }
        if (rate.compareTo(MAX_RATE) > 0) {
            rate = MAX_RATE;
        }

        BigDecimal discount = gross.multiply(rate);
        return gross.subtract(discount).setScale(2, RoundingMode.HALF_UP);
    }
}
```

```java
package com.example.shop.pricing;

public enum CustomerTier { STANDARD, GOLD }
```

### 8.2 The "100% coverage" test

```java
package com.example.shop.pricing;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;

class PriceCalculatorTest {

    private final PriceCalculator calculator = new PriceCalculator();

    @Test
    void standardCustomerSmallOrderPaysFullPrice() {
        assertThat(calculator.totalFor(CustomerTier.STANDARD, new BigDecimal("10.00"), 5))
                .isEqualByComparingTo("50.00");
    }

    @Test
    void standardCustomerBigOrderGetsBulkDiscount() {
        assertThat(calculator.totalFor(CustomerTier.STANDARD, new BigDecimal("10.00"), 20))
                .isEqualByComparingTo("190.00");
    }

    @Test
    void goldCustomerSmallOrderGetsGoldDiscount() {
        assertThat(calculator.totalFor(CustomerTier.GOLD, new BigDecimal("10.00"), 5))
                .isEqualByComparingTo("45.00");
    }

    @Test
    void goldCustomerBigOrderIsCappedAtMaxRate() {
        // 5% + 10% = 15%, capped at 12%
        assertThat(calculator.totalFor(CustomerTier.GOLD, new BigDecimal("10.00"), 20))
                .isEqualByComparingTo("176.00");
    }
}
```

JaCoCo line coverage: every line except the `throw`. Branch coverage misses the
`quantity <= 0` branch. Everything looks fine.

### 8.3 What pitest reports (DEFAULTS + EXPERIMENTAL_BIG_DECIMAL)

Representative results for the main lines (exact mutant counts depend on the compiled
bytecode):

| Line | Mutant | Status | Why |
|---|---|---|---|
| `quantity <= 0` | changed conditional boundary | **SURVIVED** | no test uses quantity 0 |
| `quantity <= 0` | removed conditional (comparison replaced) | SURVIVED | the mutant that never throws behaves like the original for every tested input |
| `quantity >= BULK_MIN_QUANTITY` | changed conditional boundary | **SURVIVED** | tests use 5 and 20, never 10 |
| `quantity >= BULK_MIN_QUANTITY` | removed conditional (else) | KILLED | qty 20 expects a discount |
| `tier == GOLD` | removed conditional (else) | KILLED | gold tests expect a discount |
| `rate.compareTo(MAX_RATE) > 0` | changed conditional boundary | SURVIVED | **equivalent**, see 12 |
| `rate.compareTo(MAX_RATE) > 0` | removed conditional (else) | KILLED | the cap test expects 176.00, not 170.00 |
| `rate.add(BULK_RATE)` | BigDecimal add -> subtract | KILLED | |
| `gross.subtract(discount)` | BigDecimal subtract -> add | KILLED | |
| `return ...` | replaced return value with null | KILLED | |

How the boundary mutant works: the Java compiler turns `if (quantity >= 10) { ... }` into
"jump past the block if `quantity < 10`". `CONDITIONALS_BOUNDARY` changes that to "jump if
`quantity <= 10`", which behaves exactly like `quantity > 10` in the source. At 5 and 20
both versions agree. Only quantity **10** tells them apart.

### 8.4 The tests that kill the survivors

```java
import static org.assertj.core.api.Assertions.assertThatIllegalArgumentException;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

    @ParameterizedTest(name = "qty {0} -> {1}")
    @CsvSource({
            "9,  90.00",   // just below the bulk threshold: no discount
            "10, 95.00",   // exactly at the threshold: 5% discount   <- kills the boundary mutant
            "11, 104.50"   // just above
    })
    void bulkDiscountStartsExactlyAtTenUnits(int quantity, String expectedTotal) {
        assertThat(calculator.totalFor(CustomerTier.STANDARD, new BigDecimal("10.00"), quantity))
                .isEqualByComparingTo(expectedTotal);
    }

    @Test
    void zeroQuantityIsRejected() {                     // kills "quantity <= 0" boundary
        assertThatIllegalArgumentException()
                .isThrownBy(() -> calculator.totalFor(CustomerTier.STANDARD, BigDecimal.TEN, 0))
                .withMessageContaining("quantity");
    }

    @Test
    void oneUnitIsAccepted() {                          // the other side of that boundary
        assertThat(calculator.totalFor(CustomerTier.STANDARD, BigDecimal.TEN, 1))
                .isEqualByComparingTo("10.00");
    }
```

The general rule: **for every comparison, test the value on the boundary and one value
on each side.** For dates this means "exactly at expiry", for money "exactly at the
limit", for counts "exactly N".

Re-run with history and the survivors move to `KILLED`:

```bash
./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage \
  -DtargetClasses='com.example.shop.pricing.PriceCalculator*' \
  -DtargetTests='com.example.shop.pricing.PriceCalculatorTest' \
  -DwithHistory
```

### 8.5 A VOID_METHOD_CALLS survivor

Business services often look like this:

```java
public Order place(OrderRequest request) {
    Order order = Order.from(request, priceCalculator);
    orderRepository.save(order);
    auditLog.record(AuditEvent.orderPlaced(order.id(), order.total()));
    return order;
}
```

`auditLog.record(...)` is a void call. A test that asserts only on the returned `Order`
lets the "removed call to AuditLog::record" mutant survive. Kill it by asserting the side
effect:

```java
@Test
void placingAnOrderWritesAnAuditEntry() {
    Order order = service.place(request);

    verify(auditLog).record(AuditEvent.orderPlaced(order.id(), order.total()));
}
```

`orderRepository.save(order)` returns a value, so it is a non-void call and the default
mutators do not remove it. `NON_VOID_METHOD_CALLS` exists but is not in `DEFAULTS` or
`STRONGER`.

---

## 9. Outbound REST calls: WireMock tests that kill retry and fallback mutants

Services with many outbound calls hide a lot of logic in error handling: which statuses
are retried, how many attempts, what the fallback returns, which headers and bodies are
sent. Tests that only stub a happy-path `200` leave all of that unprotected.

### 9.1 A client with hand-written retry and fallback

```java
package com.example.shop.inventory;

import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;

public class StockClient {

    private final RestClient restClient;
    private final int maxAttempts;

    public StockClient(RestClient restClient, int maxAttempts) {
        this.restClient = restClient;
        this.maxAttempts = maxAttempts;
    }

    public StockLevel stockFor(String sku) {
        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
            try {
                StockLevel level = restClient.get()
                        .uri("/stock/{sku}", sku)
                        .header("X-Client", "shop")
                        .retrieve()
                        .body(StockLevel.class);
                return level != null ? level : StockLevel.unknown(sku);
            } catch (HttpClientErrorException.NotFound e) {
                return StockLevel.unknown(sku);          // 404: do not retry
            } catch (HttpServerErrorException | ResourceAccessException e) {
                // 5xx or I/O problem (including read timeout): retry
            }
        }
        return StockLevel.unknown(sku);                  // retries exhausted: fallback
    }
}
```

```java
package com.example.shop.inventory;

public record StockLevel(String sku, int available, boolean known) {
    public static StockLevel unknown(String sku) {
        return new StockLevel(sku, 0, false);
    }
}
```

`RestClient`'s default status handling throws `HttpClientErrorException` subclasses for
4xx and `HttpServerErrorException` subclasses for 5xx. I/O failures, including timeouts,
are wrapped in `ResourceAccessException`.

Mutants that matter here:

- `attempt <= maxAttempts` boundary: one fewer attempt. **The returned value is
  identical** (fallback either way), so only a test that counts requests can kill it.
- `attempt++` increment: becomes `attempt--`, an infinite loop when the server keeps
  failing; reported as `TIMED_OUT`.
- `level != null` removed conditional: only a test with an empty `200` body kills it.
- `NULL_RETURNS` on each `return`: killed only by tests that assert the result's content.

### 9.2 Fast WireMock unit tests (no Spring context)

For pitest, the cheapest useful test is a plain JUnit test with WireMock's JUnit Jupiter
extension: no Spring context, millisecond runtime, dynamic port.

```java
package com.example.shop.inventory;

import static com.github.tomakehurst.wiremock.client.WireMock.*;
import static com.github.tomakehurst.wiremock.core.WireMockConfiguration.wireMockConfig;
import static com.github.tomakehurst.wiremock.stubbing.Scenario.STARTED;
import static org.assertj.core.api.Assertions.assertThat;

import com.github.tomakehurst.wiremock.junit5.WireMockExtension;
import java.time.Duration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.RegisterExtension;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

class StockClientTest {

    @RegisterExtension
    static WireMockExtension wm = WireMockExtension.newInstance()
            .options(wireMockConfig().dynamicPort())
            .build();

    private StockClient client;

    @BeforeEach
    void setUp() {
        JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory();
        factory.setReadTimeout(Duration.ofMillis(300));
        RestClient restClient = RestClient.builder()
                .baseUrl(wm.baseUrl())
                .requestFactory(factory)
                .build();
        client = new StockClient(restClient, 3);
    }

    @Test
    void returnsStockAndSendsClientHeader() {
        wm.stubFor(get("/stock/ABC-1").willReturn(okJson("""
                {"sku":"ABC-1","available":7,"known":true}""")));

        assertThat(client.stockFor("ABC-1")).isEqualTo(new StockLevel("ABC-1", 7, true));

        wm.verify(1, getRequestedFor(urlEqualTo("/stock/ABC-1"))
                .withHeader("X-Client", equalTo("shop")));
    }

    @Test
    void retriesAfter503AndSucceeds() {
        wm.stubFor(get("/stock/ABC-1").inScenario("flaky")
                .whenScenarioStateIs(STARTED)
                .willReturn(serviceUnavailable())
                .willSetStateTo("recovered"));
        wm.stubFor(get("/stock/ABC-1").inScenario("flaky")
                .whenScenarioStateIs("recovered")
                .willReturn(okJson("""
                        {"sku":"ABC-1","available":3,"known":true}""")));

        assertThat(client.stockFor("ABC-1").available()).isEqualTo(3);
        wm.verify(2, getRequestedFor(urlEqualTo("/stock/ABC-1")));
    }

    @Test
    void givesUpAfterExactlyThreeAttemptsOn5xx() {
        wm.stubFor(get("/stock/ABC-1").willReturn(serverError()));

        assertThat(client.stockFor("ABC-1")).isEqualTo(StockLevel.unknown("ABC-1"));
        // Kills the "attempt <= maxAttempts" boundary mutant (would make 2 calls)
        wm.verify(3, getRequestedFor(urlEqualTo("/stock/ABC-1")));
    }

    @Test
    void doesNotRetryOn404() {
        wm.stubFor(get("/stock/NOPE").willReturn(notFound()));

        assertThat(client.stockFor("NOPE").known()).isFalse();
        wm.verify(1, getRequestedFor(urlEqualTo("/stock/NOPE")));
    }

    @Test
    void timeoutIsTreatedLikeA5xx() {
        wm.stubFor(get("/stock/SLOW").willReturn(okJson("{}").withFixedDelay(1_000)));

        assertThat(client.stockFor("SLOW")).isEqualTo(StockLevel.unknown("SLOW"));
        wm.verify(3, getRequestedFor(urlEqualTo("/stock/SLOW")));
    }

    @Test
    void emptyBodyFallsBackToUnknown() {
        wm.stubFor(get("/stock/EMPTY").willReturn(ok()));

        assertThat(client.stockFor("EMPTY")).isEqualTo(StockLevel.unknown("EMPTY"));
    }
}
```

What each test kills:

| Test | Mutants it kills |
|---|---|
| `returnsStockAndSendsClientHeader` | null-return on the success path. The `withHeader` check guards against regressions; `.header(...)` is a non-void call, so default mutators do not remove it (`NON_VOID_METHOD_CALLS` or Arcmutate operators would) |
| `retriesAfter503AndSucceeds` | mutants that stop retrying after the first 5xx |
| `givesUpAfterExactlyThreeAttemptsOn5xx` | `<=` boundary in the loop (request count) |
| `doesNotRetryOn404` | changes that retry 4xx |
| `timeoutIsTreatedLikeA5xx` | removal of the I/O-error branch (the timeout would propagate) |
| `emptyBodyFallsBackToUnknown` | `level != null` removed conditional |

Rules for WireMock tests that kill mutants:

1. **Count requests** with `verify(n, ...)` whenever the number of calls is behaviour
   (retries, caching, batching, dedup).
2. **Verify what was sent**: path, query parameters, headers, body (`equalToJson`).
   Otherwise mutants in request-building code survive.
3. **Exercise every status class you handle**: 2xx, empty 2xx, 4xx you handle specially,
   other 4xx, 5xx, timeout, connection fault (`aResponse().withFault(...)`).
4. **Use scenarios** (`inScenario` / `whenScenarioStateIs` / `willSetStateTo`) for
   fail-then-succeed sequences.
5. **Keep delays small and timeouts short.** Every test runs many times under pitest; a
   5-second `withFixedDelay` multiplies into minutes.

### 9.3 WireMock with a Spring context

When the client is a Spring bean configured from properties, use
`wiremock-spring-boot`. `@EnableWireMock` starts WireMock and writes its URL into the
Spring environment (default property `wiremock.server.baseUrl`; configurable via
`@ConfigureWireMock(baseUrlProperties = ...)`):

```java
@SpringBootTest
@EnableWireMock({
        @ConfigureWireMock(name = "inventory", baseUrlProperties = "clients.inventory.base-url"),
        @ConfigureWireMock(name = "payments", baseUrlProperties = "clients.payments.base-url")
})
@Tag("integration")
class CheckoutFlowIT {

    @InjectWireMock("inventory")
    WireMockServer inventory;

    @InjectWireMock("payments")
    WireMockServer payments;

    @Autowired
    CheckoutService checkoutService;

    @Test
    void paymentFailureReleasesReservedStock() {
        inventory.stubFor(post("/reservations").willReturn(created()));
        inventory.stubFor(delete(urlPathMatching("/reservations/.*")).willReturn(noContent()));
        payments.stubFor(post("/charges").willReturn(serverError()));

        assertThatThrownBy(() -> checkoutService.checkout(cart()))
                .isInstanceOf(PaymentFailedException.class);

        // A removed "releaseReservation()" call survives without this line.
        inventory.verify(1, deleteRequestedFor(urlPathMatching("/reservations/.*")));
    }
}
```

Use dynamic ports (the default). Fixed ports collide when pitest runs several minion JVMs
in parallel.

---

## 10. Slow tests: @SpringBootTest, Testcontainers PostgreSQL, WireMock

### 10.1 Why slow tests hurt more under pitest

For each mutant pitest runs the covering tests, fastest first, until one fails. A test
that covers many lines and is slow (a full `@SpringBootTest`) gets run for **every
surviving mutant on every line it touches**. The Arcmutate performance docs describe the
same effect: slow tests that cover large parts of the codebase "disproportionately
increase analysis times".

Also, per the Arcmutate Spring docs:

- "tests using Spring test extensions may fail to detect mutants" without their Spring
  plugin, which clears the Spring context after each test so mutated code is executed;
- even with that plugin, pitest "only supports mutation testing with unit tests that run
  all code and tests within the same JVM. It cannot be used with integration tests that
  launch a web server."

The exact mechanism behind the first point is not documented in the open-source pitest
docs, so it was not verified here. The practical conclusion is the same either way.

### 10.2 Strategy: test business logic without Spring, tag the rest

1. Keep pricing, eligibility, mapping and state-machine logic in plain classes and
   unit-test them without Spring. This is where the mutation score matters and where
   pitest is fast.
2. Use test slices (`@WebMvcTest`, `@DataJpaTest`) for framework wiring.
3. Tag full-context and container tests and exclude them from pitest:

```java
@Tag("integration")
@SpringBootTest
class OrderRepositoryIT { ... }
```

```xml
<!-- in the pitest plugin configuration -->
<excludedGroups>
  <param>integration</param>
</excludedGroups>
```

If Surefire already has `<excludedGroups>integration</excludedGroups>`, pitest inherits it
(section 4.3), unless you set groups in the pitest configuration.

4. Optionally run a **separate, nightly** pitest pass that includes integration tests for
   the repository/adapter packages only:

```bash
./mvnw -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage \
  -DtargetClasses='com.example.shop.persistence.*' \
  -DtargetTests='com.example.shop.persistence.*IT' \
  -DincludedGroups=integration \
  -DtimeoutConstant=15000 -Dthreads=2
```

This works when the `integration` exclusion comes from Surefire: once any group is set on
pitest itself, pitest ignores Surefire's groups. If you configured `excludedGroups` inside
the pitest plugin, put the nightly settings in a second profile instead, because the
exclusion would still remove the tagged tests.

### 10.3 Testcontainers PostgreSQL that survives thousands of reruns

Under pitest the same test class runs many times in the same minion JVM. The
`@Testcontainers` + static `@Container` pattern starts and stops the container **per test
class**, so every rerun can pay container start-up again. The Spring Boot docs also warn
that this pattern can conflict with Spring's context caching when the container is stopped
before a cached context is reused.

Use a **singleton container** (Testcontainers docs, "Singleton containers") together with
Boot's `@ServiceConnection`:

```java
package com.example.shop.testsupport;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.postgresql.PostgreSQLContainer;

@TestConfiguration(proxyBeanMethods = false)
public class PostgresTestConfig {

    @Bean
    @ServiceConnection
    PostgreSQLContainer postgres() {
        return new PostgreSQLContainer("postgres:17-alpine");
    }
}
```

```java
@DataJpaTest
@Import(PostgresTestConfig.class)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Tag("integration")
class OrderRepositoryIT { ... }
```

A container declared as a bean lives as long as the Spring context. Spring caches the
context per JVM, so each pitest minion starts one container and reuses it for every test
that shares that context configuration.

Notes:

- Testcontainers 2.x moved PostgreSQL to `org.testcontainers.postgresql.PostgreSQLContainer`
  in the `testcontainers-postgresql` artifact. Older examples import
  `org.testcontainers.containers.PostgreSQLContainer`; that is the 1.x API.
- Pick the image tag your production database uses. `postgres:17-alpine` above is a
  placeholder.
- With `threads=4` you get up to 4 containers (one per minion JVM). Watch the Docker
  host's memory.
- **Data isolation:** tests that leave rows behind make later tests behave differently,
  and under pitest the order and subset of tests differ from Surefire. Use transactional
  tests (`@DataJpaTest` is transactional by default) or truncate tables in `@BeforeEach`.

### 10.4 Timeouts for slow tests

The timeout is relative to each test's measured normal time, so slow tests get longer
timeouts automatically. Variance is the problem (container hiccups, GC). If you see
`TIMED_OUT` mutants in code that cannot loop, raise `timeoutConstant`. Treat a high
`TIMED_OUT` share in an integration-heavy run with suspicion, because it inflates the
score.

### 10.5 Mocks of the code being mutated

A `@WebMvcTest` with `@MockitoBean PricingService` never runs the real `PricingService`.
Its mutants get no coverage from that test. That is correct, but people often expect
controller tests to "cover" the service. Make sure every class in `targetClasses` has tests
that run its **real** code.

---

## 11. Keeping runtime sane: exclusions and changed-code-only runs

### 11.1 Exclude code that is not worth mutating

| What | How |
|---|---|
| `@SpringBootApplication` main class | `excludedClasses`: `com.example.shop.ShopApplication` |
| `@Configuration` classes, properties holders | `excludedClasses`: `com.example.shop.config.*` |
| DTOs and records with no logic | `excludedClasses`: `com.example.shop.*.dto.*` (records' generated members are already filtered by default) |
| OpenAPI/MapStruct generated code | `excludedClasses` by package or suffix (`*MapperImpl`) |
| Lombok-generated methods | filtered automatically **if** Lombok adds `@lombok.Generated` (`lombok.addLombokGeneratedAnnotation = true` in `lombok.config`) |
| `toString`/`equals`/`hashCode` | `excludedMethods` |
| Logging calls | `avoidCallsTo` |
| A specific method you have decided not to test | annotate it (see below) |

**Annotation-based exclusion** (pitest's `FANN` feature, source:
`ExcludedAnnotationInterceptorFactory`): pitest skips classes and methods annotated with
any annotation whose simple name is `Generated`, `DoNotMutate` or `CoverageIgnore`,
provided the annotation has **CLASS or RUNTIME retention**. You can define your own:

```java
package com.example.shop.testing;

import java.lang.annotation.*;

@Retention(RetentionPolicy.CLASS)
@Target({ElementType.TYPE, ElementType.METHOD, ElementType.CONSTRUCTOR})
public @interface DoNotMutate {}
```

Caveat: `javax.annotation.processing.Generated` and `jakarta.annotation.Generated` have
SOURCE retention, so code generators that only use those are **not** filtered (the pitest
release notes say this explicitly for `javax.annotation.Generated`). Exclude such code by
package instead.

### 11.2 Mutating only changed code

**`scmMutationCoverage` no longer exists.** It was deprecated in 1.17.1 ("Warn about
future SCM goal removal") and removed in **1.18.0** ("Fully remove deprecated scm maven
goal"). Guides that show `mvn pitest:scmMutationCoverage -Dinclude=ADDED,MODIFIED` are out
of date.

Current options:

**Option A: a git-diff script that sets `targetClasses`** (free, good enough for
single-module projects):

```bash
#!/usr/bin/env bash
# Mutate only production classes changed relative to the target branch.
set -euo pipefail
BASE="${BASE_REF:-origin/main}"

CLASSES=$(git diff --name-only --diff-filter=AMR "$BASE"...HEAD -- 'src/main/java/*.java' \
  | sed -e 's#^src/main/java/##' -e 's#\.java$#*#' -e 's#/#.#g' \
  | paste -sd, -)

if [ -z "$CLASSES" ]; then
  echo "No production Java changes; skipping mutation testing."
  exit 0
fi

./mvnw -B -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage \
  -DtargetClasses="$CLASSES" \
  -DfailWhenNoMutations=false
```

Limitations:

- It works per class, not per line. A one-line change in a big class mutates the whole
  class.
- `com.example.Foo*` also matches `com.example.FooBar`. Usually harmless.
- In multi-module builds the paths include the module directory; adapt the `sed` and run
  per module.
- Changing only a test does not trigger mutation of the code it tests.
- CI checkouts need enough history for the merge base (`fetch-depth: 0` on GitHub
  Actions).

**Option B: Arcmutate git plugin** (commercial; `com.arcmutate:pitest-git-plugin`, needs
a licence file). Per its docs it analyses at line level, with modes for changed code,
changed tests, or both:

```bash
mvn -Ppitest -Dfeatures="+GIT(from[origin/main])" test-compile org.pitest:pitest-maven:mutationCoverage
```

See [section 15](#15-arcmutate-commercial-plugins-notes).

**Option C: history files in CI.** Cache the history file between pipeline runs (5.3).
Unchanged classes with unchanged tests are not re-analysed, so a full run gets cheaper
over time.

---

## 12. Equivalent mutants

An **equivalent mutant** changes the code without changing behaviour. No test can kill it.

### 12.1 Examples from this guide

The cap check in `PriceCalculator`:

```java
if (rate.compareTo(MAX_RATE) > 0) { rate = MAX_RATE; }
```

The boundary mutant changes `> 0` to `>= 0`. The only input that tells them apart is
`rate` exactly equal to `MAX_RATE`, and then both versions end with
`rate == MAX_RATE` anyway. On top of that, the possible rates (0, 0.05, 0.10, 0.15) never
equal 0.12. **Equivalent.**

Other common equivalents in business services:

- **Caches and short-circuits:** `if (cache.containsKey(k)) return cache.get(k);`
  Removing the check recomputes the same value.
- **Defensive checks the caller already guarantees:** `Math.max(0, x)` where `x` is
  never negative.
- **Loop bounds that the data never reaches**, or `break` conditions also enforced by the
  loop header.
- **Calls with no observable effect** in tests: metrics counters, `log.debug`, tracing.
  Use `avoidCallsTo` for whole packages.

### 12.2 How to deal with them

1. **Prove it is equivalent.** Try to write a failing test for two minutes. Many
   "equivalent" mutants are real gaps.
2. **Simplify the code.** Equivalent mutants often point at redundant code. Removing a
   redundant check removes the mutant and makes the code clearer. In the example above,
   `rate = rate.min(MAX_RATE);` replaces the `if` (note that with
   `EXPERIMENTAL_BIG_DECIMAL` on, `min` -> `max` is then a new mutant, which the cap test
   kills).
3. **Exclude narrowly.** `@DoNotMutate` on a small method, or `avoidCallsTo` for a
   metrics package. Never exclude a whole business class because of one equivalent.
4. **Budget for them.** Because equivalents exist, 100% is usually not a sensible target.
   That is one reason to set thresholds slightly below what you reach
   ([section 13](#13-ci-integration-and-thresholds)).

pitest already filters many known equivalent patterns (for example divide by -1, boxed
`Boolean.TRUE/FALSE` returns, empty returns in some contexts, infinite-loop detection via
static analysis, `try-with-resources` and record boilerplate).

---

## 13. CI integration and thresholds

### 13.1 Threshold parameters

All in `PitMojo.java`:

| Parameter | Fails the build when |
|---|---|
| `mutationThreshold` | mutation score (detected / total) is below the value |
| `coverageThreshold` | pitest line coverage (mutated classes only) is below the value |
| `testStrengthThreshold` | test strength (detected / covered) is below the value |
| `maxSurviving` | more than N mutants survive (default -1 = off) |
| `thresholdPrecision` | number of decimals allowed in the thresholds above (1.25.4+; default 0) |

Integer thresholds have a blind spot that the pitest docs illustrate: on a large codebase
a whole percentage point is many lines or mutants. Use decimals:

```xml
<configuration>
  <mutationThreshold>74.5</mutationThreshold>
  <testStrengthThreshold>80.0</testStrengthThreshold>
  <thresholdPrecision>1</thresholdPrecision>
</configuration>
```

### 13.2 What target is realistic

Opinion, not from the pitest docs:

- **Core business packages** (pricing, rules, calculations): aim for **80-90%** mutation
  score with `DEFAULTS` (+ `EXPERIMENTAL_BIG_DECIMAL`). Survivors there are usually real
  gaps.
- **Adapters, controllers, persistence**: 60-75% is normal; many survivors are framework
  wiring or equivalent.
- **Whole service, first measurement**: often 50-70% even with 85%+ line coverage.

Set the gate a little **below** your current number and ratchet it up. A gate above
reality gets switched off. Gating on **test strength** is often fairer than gating on
mutation score, because untested code shows up in the coverage number anyway.

### 13.3 GitHub Actions example

Two jobs: changed classes on every PR (fast), and full analysis nightly with a cached
history file.

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
          fetch-depth: 0            # needed for the merge base
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "21"
          cache: maven
      - name: Mutate changed classes
        env:
          BASE_REF: origin/${{ github.base_ref }}
        run: ./scripts/pitest-changed.sh   # the script from section 11.2
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
      - name: Restore pitest history
        uses: actions/cache@v4
        with:
          path: .pitest
          key: pitest-history-${{ github.sha }}
          restore-keys: pitest-history-
      - name: Full mutation analysis
        run: |
          mkdir -p .pitest
          ./mvnw -B -Ppitest test-compile org.pitest:pitest-maven:mutationCoverage \
            -DhistoryInputFile=.pitest/history.bin \
            -DhistoryOutputFile=.pitest/history.bin \
            -DmutationThreshold=74.5 -DthresholdPrecision=1
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: pit-report-nightly
          path: target/pit-reports/
```

Notes:

- GitHub-hosted Ubuntu runners have Docker, so Testcontainers tests work if you include
  them.
- Do not put a whole-project threshold on the changed-code job. The score of three
  changed classes swings a lot. Use `maxSurviving` or review the report instead, or apply
  a threshold only above a minimum mutant count.
- Avoid `+auto_threads` on CI (pitest release notes). Set `threads` explicitly to the
  runner's core count or less.

---

## 14. Common pitfalls

**Flaky tests.** A test that fails randomly "kills" mutants it never detected, which
inflates the score, or makes the coverage stage fail. pitest requires the suite to pass
unmutated first. Fix or quarantine flaky tests (`excludedTestClasses`) before trusting
any number.

**Test-order dependencies.** pitest runs a subset of tests, ordered by speed, often one
test class at a time. Tests that rely on data or static state left by another test fail
or behave differently. Symptoms: green with Surefire, red or odd under pitest. Make
every test set up its own state.

**Shared containers and databases.** A singleton container is shared by every test in a
minion JVM. Leftover rows from one mutant run affect the next. Isolate with transactions
or truncation, and never assert on global row counts unless you control them.

**Fixed ports.** WireMock on port 8080 or 8888 breaks as soon as `threads > 1` (several
minion JVMs). Use dynamic ports everywhere.

**Timing assumptions.** `Thread.sleep`, "should complete within 200 ms" assertions and
real-time retry backoffs make tests slow and cause timeouts under load. Inject `Clock`
and backoff durations so tests can use zero or tiny delays.

**Mocks of the mutated code.** If the class under test is mocked or spied in most tests,
its mutants show `NO_COVERAGE` or survive. Mock collaborators, not the subject.

**Asserting too little.** `assertThat(result).isNotNull()`, `verify(repo).save(any())`
and `status().isOk()` alone kill almost nothing. Assert values, arguments
(`ArgumentCaptor` or exact objects) and response bodies.

**Spring context per test method.** `@DirtiesContext(AFTER_EACH_TEST_METHOD)` makes every
mutant run pay for context start-up. Avoid it in tests that pitest runs.

**`-DskipTests` skips pitest.** See 5.6.

**Duplicated JVM args after upgrading past 1.15.4.** See 4.3.

**Expecting `scmMutationCoverage` to work.** Removed in 1.18.0. See 11.2.

**Trusting `TIMED_OUT`/`RUN_ERROR` kills.** They count as detected. If they are a large
share of your kills, your score is inflated by environment problems.

**Changing too much at once.** Turning on `ALL` mutators on the whole codebase produces
thousands of survivors and nobody reads the report. Go package by package.

---

## 15. Arcmutate (commercial plugins) notes

Arcmutate sells pitest plugins. They need a licence file (`arcmutate-licence.txt` at the
repository root, or in the pitest reports directory). Pricing and whether any plugins
are free for some uses were not checked; see their site. What their docs confirm:

**`com.arcmutate:arcmutate-spring`** (latest on Maven Central: 1.1.3):

- Adds a `SPRING` mutator group with annotation mutators, for example
  `REMOVE_SECURITY` (removes `@PreAuthorize`, `@PostAuthorize`, `@RolesAllowed`,
  `@Secured`, `@PreFilter`, `@PostFilter`) and `REMOVE_VALIDATION` (removes `@Min`, `@Max`,
  `@NotEmpty`, `@Pattern` from jakarta and javax validation).
- Clears the Spring context after each test (similar to
  `@DirtiesContext(AFTER_EACH_TEST_METHOD)` plus clearing caches Spring keeps outside the
  context) so mutants are actually executed in Spring tests.
- Still only works with tests that run in the same JVM; **not** with tests that launch a
  web server.

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
      <artifactId>arcmutate-spring</artifactId>
      <version>1.1.3</version>
    </dependency>
  </dependencies>
  <configuration>
    <mutators>
      <mutator>DEFAULTS</mutator>
      <mutator>SPRING</mutator>
    </mutators>
  </configuration>
</plugin>
```

**`com.arcmutate:pitest-git-plugin`** (2.3.4): changed-code analysis via
`-Dfeatures="+GIT(from[<ref>])"`. GitHub/GitLab/Bitbucket/Azure plugins can post results
to pull requests.

**`com.arcmutate:base`** (1.7.2): extended operators (an `EXTENDED` group meant to be used
with `DEFAULTS` or `STRONGER`), and features such as `+slow_tests(max[500])` to exclude slow
tests.

**`com.arcmutate:pitest-accelerator-junit5`**: speeds up JUnit 5 tests that use only a
supported subset of Jupiter features. Not verified here: compatibility with JUnit 6.

Arcmutate docs show pitest 1.22.0 in their examples. Compatibility of each plugin
version with pitest 1.30.1 was not verified here.

---

## 16. Checklist

- [ ] `pitest-maven` 1.30.1 and `pitest-junit5-plugin` 1.2.3 in a `pitest` profile; the
      JUnit plugin is a **plugin dependency**, not a test dependency.
- [ ] First run shows `Ran N tests` with N > 0 and non-zero line coverage (JUnit 6 check,
      4.4).
- [ ] No duplicated JVM flags between Surefire `argLine` and pitest `jvmArgs`/`argLine`;
      empty `<argLine/>` property defined.
- [ ] JaCoCo left as is (pitest strips the agent).
- [ ] `targetClasses` points at business packages; config, DTOs, generated code and the
      main class excluded; logging in `avoidCallsTo`.
- [ ] Mutators: `DEFAULTS` + `EXPERIMENTAL_BIG_DECIMAL` for money logic; `STRONGER` later.
- [ ] Business logic is tested without Spring; integration tests tagged and excluded from
      the regular pitest run.
- [ ] Testcontainers PostgreSQL uses a singleton/bean container with `@ServiceConnection`,
      and tests isolate their data.
- [ ] WireMock on dynamic ports; tests verify request counts, headers and bodies, and
      cover 4xx, 5xx, timeout and empty-body paths.
- [ ] Every comparison in business code has a test at the boundary.
- [ ] Survivors reviewed; equivalents documented, simplified away, or excluded narrowly.
- [ ] History file used locally (`-DwithHistory`) and cached in CI.
- [ ] PRs mutate changed classes only (git-diff script or Arcmutate); no
      `scmMutationCoverage` (removed in 1.18.0).
- [ ] Threshold with decimals (`thresholdPrecision`), set slightly below the current
      score, ratcheted over time.
- [ ] `TIMED_OUT` / `RUN_ERROR` share checked; flaky and order-dependent tests fixed.
