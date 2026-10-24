# AGENTS.common.md: Java and Spring Boot rules shared by every service

These rules apply to every Java / Spring Boot repository, blocking (Spring MVC + Hibernate) and reactive (WebFlux +
R2DBC). The stack file (`AGENTS.mvc-hibernate.md` or `AGENTS.webflux-r2dbc.md`) adds the stack-specific rules. When a
stack rule and a common rule disagree, the stack rule wins.

## How to read this file

- Rule IDs: `C-` common, `M-` Spring MVC + Hibernate, `W-` WebFlux + R2DBC. Refer to rules by ID in reviews.
- A rule with checkboxes is **not decided yet**. Until the team decides, follow the option marked *(recommended)*.
- A rule without options is fixed: follow it.
- Scope of a change: follow the rules in new and changed code. Do not reformat or rewrite untouched code to match
  them, unless the task asks for it.
- When existing code in the module consistently does something else, match the module and mention the difference in
  your summary. Do not mix two styles in one class.

> **For the team:** tick one box per rule, delete the other options, the *(recommended)* marker, the examples you do
> not need and the `Decision:` line. Rules you do not want: delete them. Shorter is better for agents.

---

## C-0 Agent workflow

### C-0.1 Before you finish

- Build and test with the Maven wrapper: `./mvnw verify` (or `./mvnw test` while iterating, `./mvnw test
  -Dtest=OrderServiceTest` for one class, `-Dtest=OrderServiceTest#rejectsEmptyCart` for one method).
- Every change compiles, all tests pass, no new compiler warnings.
- New or changed behavior has a test (see C-15).
- Do not finish with `@Disabled` tests, commented-out code, `System.out.println`, or `TODO`s you added without a
  ticket.

### C-0.2 Things you never do without asking

- Add, remove or upgrade a dependency or Maven plugin.
- Change public API contracts: endpoint paths, request/response JSON, status codes, event payloads, DB schema.
- Change `application*.yml` values for non-test profiles.
- Touch CI files, Dockerfiles, Helm charts or other deployment config.
- Delete or weaken a test to make the build pass.

### C-0.3 Maven wrapper or local Maven

- [ ] **A: `./mvnw` only** *(recommended)*: same Maven version for everyone and in CI.
- [ ] **B: `mvn`**: the locally installed Maven.

**Decision:** ____

---

## C-1 Formatting (IntelliJ IDEA default formatter)

The team formats with the IntelliJ IDEA Ultimate default Java code style. Agents cannot run IntelliJ, so write code
that already matches it:

- 4 spaces indentation, no tabs. Continuation indent 8 spaces.
- Line length 120 (IntelliJ's hard wrap). Wrap long argument lists and method chains, one item per line.
- Opening brace on the same line (`if (x) {`), `} else {` on one line.
- One blank line between methods. No more than one consecutive blank line. File ends with a newline.
- One space after keywords (`if (`, `for (`, `while (`, `switch (`, `catch (`), around binary operators and after
  commas. No space between a method name and `(`.
- Annotations on their own line above classes, methods and fields; parameter annotations inline.

### C-1.1 Enforcing the format

- [ ] **A: IntelliJ only, code style committed to the repo** *(recommended)*: export the scheme to
  `.idea/codeStyles/Project.xml` (or an `.editorconfig`) and commit it, so every developer has the same settings.
  Agents follow the rules above.
- [ ] **B: IntelliJ only, nothing committed**: everyone uses their IDE defaults.
- [ ] **C: IntelliJ formatter from the command line**: `idea format -s <style.xml> -r src` in a pre-commit hook or CI
  step (needs IntelliJ installed where it runs).
- [ ] **D: a Maven formatter (Spotless with palantir-java-format / google-java-format / Eclipse)**: `./mvnw
  spotless:apply` formats, `spotless:check` fails the build. Breaks from the IntelliJ default style.

**Decision:** ____

### C-1.2 Wildcard imports

IntelliJ's default collapses to `import foo.*` at 5 classes from one package (3 for static imports).

- [ ] **A: never use wildcard imports** *(recommended)*: set both counts to 999 in the committed scheme. Diffs stay
  readable and name clashes are visible.
- [ ] **B: IntelliJ default (5 / 3)**.
- [ ] **C: wildcards only for static test imports** (`Assertions.*`, `Mockito.*`, `WireMock.*`).

**Decision:** ____

### C-1.3 Import order

- [ ] **A: IntelliJ default**: all other imports, blank line, `javax.*`/`java.*`, blank line, static imports
  *(recommended)*.
- [ ] **B: static imports first**, then everything else alphabetically.

No unused imports. No fully qualified class names in code when an import works (exception: two classes with the
same simple name).

**Decision:** ____

### C-1.4 Braces on single-statement blocks

```java
// A
if (order == null) {
    return;
}

// B
if (order == null) return;

// C
if (order == null)
    return;
```

- [ ] **A: braces on every `if`, `else`, `for`, `while`, `do`** *(recommended)*: no "added a second line, forgot the
  braces" bugs, consistent diffs.
- [ ] **B: one-line guard clauses without braces allowed** (`if (x) return;`, `if (x) throw ...;`), braces everywhere
  else.
- [ ] **C: braces optional whenever the body is one statement**, on the same line or indented on the next line.

**Decision:** ____

### C-1.5 Wrapping method chains (streams, builders, Reactor, AssertJ)

```java
// A
return orders.stream()
        .filter(Order::isPaid)
        .map(orderMapper::toDto)
        .toList();

// B
return orders.stream().filter(Order::isPaid).map(orderMapper::toDto).toList();
```

- [ ] **A: one call per line when the chain has 2+ operations after the source** *(recommended)*.
- [ ] **B: keep on one line while it fits in 120 columns**.

**Decision:** ____

### C-1.6 Wrapping long parameter / argument lists

```java
// A: one per line, closing parenthesis on the last argument
public Order createOrder(
        CustomerId customerId,
        List<OrderLine> lines,
        DeliveryAddress address) {

// B: fill the line, wrap where needed
public Order createOrder(CustomerId customerId, List<OrderLine> lines,
        DeliveryAddress address) {
```

- [ ] **A: when it does not fit, one parameter per line** *(recommended)*.
- [ ] **B: IntelliJ "wrap if long" default**.

**Decision:** ____

### C-1.7 Operator position when wrapping

- [ ] **A: operator at the start of the new line** (`&& isActive`, `+ suffix`, `? a`, `: b`) *(recommended)*:
  IntelliJ default.
- [ ] **B: operator at the end of the line**.

**Decision:** ____

### C-1.8 Blank lines inside methods

- [ ] **A: allowed to separate logical steps, never more than one** *(recommended)*.
- [ ] **B: no blank lines inside methods**: split the method instead.
- [ ] **C: given/when/then style blocks only in tests**.

**Decision:** ____

---

## C-2 Naming

Fixed rules:

- Classes and records `UpperCamelCase`, nouns (`OrderService`, `InvoiceLine`). Interfaces are nouns or adjectives,
  no `I` prefix.
- Methods `lowerCamelCase`, verbs (`calculateTotal`, `findByEmail`). Booleans read as questions: `isActive`,
  `hasItems`, `canCancel`, `shouldRetry`.
- Constants `UPPER_SNAKE_CASE` (`static final` and deeply immutable). Enum constants `UPPER_SNAKE_CASE`.
- Packages lowercase, no underscores (`com.example.orders.payment`).
- No abbreviations a new team member would not know (`customer`, not `cust`; `request`, not `rq`). Accepted: `id`,
  `dto`, `url`, `uri`, `http`, `json`, `api`, `db`, `config`.
- No Hungarian notation, no `m`/`_` prefixes, no type in the name (`customerList` → `customers`).
- Loop variables `i`, `j` only for index loops; lambdas use a real name unless the type makes it obvious
  (`orders.forEach(order -> ...)`, `.map(Order::id)`).
- A test class is named after the class it tests: `OrderService` → `OrderServiceTest` (unit), `OrderServiceIT`
  (integration, see C-15.2).

### C-2.1 Acronyms in names

- [ ] **A: acronyms as words**: `HttpClient`, `XmlParser`, `customerId`, `parseJson` *(recommended)*.
- [ ] **B: acronyms in capitals**: `HTTPClient`, `XMLParser`, `customerID`, `parseJSON`.

**Decision:** ____

### C-2.2 Service interfaces and the `Impl` suffix

```java
// A
@Service
public class OrderService { ... }

// B
public interface OrderService { ... }
@Service
public class OrderServiceImpl implements OrderService { ... }
```

- [ ] **A: no interface when there is one implementation** *(recommended)*: Mockito mocks classes; Spring proxies
  classes (CGLIB). Add an interface when a second implementation appears.
- [ ] **B: interface + `Impl` for every service**.
- [ ] **C: interface only for ports to external systems** (clients, publishers), named after the role
  (`PaymentGateway`), implementation named after the technology (`StripePaymentGateway`).

**Decision:** ____

### C-2.3 DTO naming

- [ ] **A: by role**: `CreateOrderRequest`, `OrderResponse`, `OrderSummaryResponse`; inbound client models
  `PaymentProviderResponse` *(recommended)*.
- [ ] **B: `Dto` suffix**: `OrderDto`, `CreateOrderDto`.
- [ ] **C: `Dto` for internal transfer objects, `Request`/`Response` for the REST layer**.

**Decision:** ____

### C-2.4 Repository / data access method names

- [ ] **A: Spring Data names** (`findById`, `findAllByStatus`, `existsByEmail`, `deleteById`) everywhere, also in
  custom code *(recommended)*.
- [ ] **B: free names in custom repositories** (`loadOrderWithLines`), Spring Data names in derived queries.

`find...` returns `Optional`/empty, `get...` throws when missing (pick and keep, see C-4.4).

**Decision:** ____

### C-2.5 Test method names

```java
// A
@Test
void rejectsOrderWhenCartIsEmpty() { }

// B
@Test
void createOrder_emptyCart_throwsValidationException() { }

// C
@Test
void should_throwValidationException_when_cartIsEmpty() { }

// D
@Test
@DisplayName("rejects the order when the cart is empty")
void emptyCart() { }
```

- [ ] **A: behaviour as a sentence in camelCase** *(recommended)*.
- [ ] **B: `method_condition_expectedResult`**.
- [ ] **C: `should_..._when_...`**.
- [ ] **D: short method name + `@DisplayName`**.

**Decision:** ____

---

## C-3 Control flow

### C-3.1 Early return vs `else`

```java
// A: guard clause / early return, no else
public Discount discountFor(Customer customer) {
    if (customer.isVip()) {
        return Discount.VIP;
    }
    return Discount.NONE;
}

// B: explicit else
public Discount discountFor(Customer customer) {
    if (customer.isVip()) {
        return Discount.VIP;
    } else {
        return Discount.NONE;
    }
}

// C: single exit point
public Discount discountFor(Customer customer) {
    Discount discount = Discount.NONE;
    if (customer.isVip()) {
        discount = Discount.VIP;
    }
    return discount;
}
```

- [ ] **A: early return; no `else` after a branch that returns or throws** *(recommended)*: less nesting, the happy
  path is not indented.
- [ ] **B: always write the `else` when both branches return**.
- [ ] **C: one `return` per method**.

**Decision:** ____

### C-3.2 Guard clauses for validation

- [ ] **A: validate and throw at the top of the method, then the happy path** *(recommended)*.
- [ ] **B: nested `if` for the valid case, `throw` in the `else`**.

**Decision:** ____

### C-3.3 Maximum nesting depth

- [ ] **A: max 2 levels** of `if`/loop nesting inside a method; extract a method or use early returns beyond that
  *(recommended)*.
- [ ] **B: max 3 levels**.
- [ ] **C: no limit, review decides**.

**Decision:** ____

### C-3.4 Ternary operator

```java
String label = order.isPaid() ? "Paid" : "Pending";
```

- [ ] **A: allowed for a simple value choice; never nested, never with side effects** *(recommended)*.
- [ ] **B: allowed anywhere, nesting forbidden**.
- [ ] **C: forbidden, always `if`/`else`**.

**Decision:** ____

### C-3.5 Returning booleans

```java
// A
return order.total().compareTo(limit) > 0;

// B
if (order.total().compareTo(limit) > 0) {
    return true;
}
return false;
```

- [ ] **A: return the expression** *(recommended)*.
- [ ] **B: explicit `if` for readability when the expression is complex**: extract a well-named variable or method
  instead of `if`/`return true`/`return false`.

**Decision:** ____

### C-3.6 `switch`

```java
// A: switch expression with arrows
BigDecimal fee = switch (method) {
    case CARD -> CARD_FEE;
    case TRANSFER -> BigDecimal.ZERO;
    case CASH -> throw new UnsupportedPaymentException(method);
};

// B: classic switch statement
```

- [ ] **A: switch expressions with `->` always; over an enum or a sealed type, list every case and no `default`, so
  the compiler fails when a value is added** *(recommended)*.
- [ ] **B: switch expressions, with a `default` that throws**.
- [ ] **C: classic `switch` statement allowed**: every case ends with `break`/`return`/`throw`; no fall-through.

**Decision:** ____

### C-3.7 Pattern matching

- [ ] **A: use pattern matching for `instanceof` (`if (event instanceof OrderPaid paid)`) and record patterns /
  type patterns in `switch` instead of casts and `if`/`else instanceof` chains** *(recommended)*.
- [ ] **B: pattern matching for `instanceof` only; no record patterns in `switch`**.

**Decision:** ____

### C-3.8 Loops vs streams

- [ ] **A: streams for transform/filter/collect; a `for` loop when there are side effects, checked exceptions, early
  exit on complex conditions, or index access** *(recommended)*.
- [ ] **B: streams wherever possible**.
- [ ] **C: loops by default, streams only for simple one-step transforms**.

Fixed: no side effects inside `map`/`filter`; `forEach` on a stream only as the terminal step; no `peek` except for
debugging; no nested streams more than one level deep (extract a method).

**Decision:** ____

### C-3.9 Lambdas vs method references

- [ ] **A: method references when they fit (`.map(Order::id)`), lambdas otherwise; lambdas longer than ~3 lines go
  into a named private method** *(recommended)*.
- [ ] **B: lambdas always**.

**Decision:** ____

### C-3.10 `null` comparisons

- [ ] **A: `x == null` / `x != null` in code; `Objects::isNull` / `Objects::nonNull` only as method references**
  *(recommended)*.
- [ ] **B: `Objects.isNull(x)` / `Objects.nonNull(x)` always**.

Fixed: no Yoda conditions (`null == x`). Constant first only for `equals` with a possibly-null value:
`"ADMIN".equals(role)` or `Objects.equals(a, b)`.

**Decision:** ____

---

## C-4 Variables, types and null

### C-4.1 `var`

```java
var orders = new ArrayList<Order>();        // type obvious
var total = calculator.totalFor(cart);      // type not obvious
```

- [ ] **A: `var` only when the type is obvious from the right-hand side** (constructor, literal, factory method named
  after the type, cast) *(recommended)*.
- [ ] **B: never use `var`**.
- [ ] **C: `var` for every local variable**.

Fixed: never `var` with a diamond (`var list = new ArrayList<>()` gives `ArrayList<Object>`), never Lombok
`val`/`var`.

**Decision:** ____

### C-4.2 `final` on locals and parameters

- [ ] **A: `final` on fields always; not on locals and parameters** *(recommended)*: effectively final is enough;
  less noise.
- [ ] **B: `final` on fields, parameters and locals**.
- [ ] **C: `final` on fields and parameters**.

**Decision:** ____

### C-4.3 Null annotations (JSpecify)

Spring Framework 7 / Spring Boot 4 annotate their APIs with JSpecify (`@NullMarked`, `@Nullable`).

- [ ] **A: `@NullMarked` in every `package-info.java`; mark nullable things with `org.jspecify.annotations.Nullable`**
  *(recommended)*: non-null is the default; IntelliJ warns on misuse. Optionally NullAway in the build.
- [ ] **B: `@Nullable` only on the few return values / parameters that can be null, no `@NullMarked`**.
- [ ] **C: no null annotations**.

**Decision:** ____

### C-4.4 `Optional`

Fixed:

- `Optional` only as a return type for "may be missing". Never as a field, method parameter, collection element or
  entity/DTO property.
- Never return `null` from a method that returns `Optional`, a collection or an array: return `Optional.empty()`,
  `List.of()`.
- Never call `Optional.get()`; use `orElseThrow(() -> new OrderNotFoundException(id))`, `map`, `orElse`, `orElseGet`.
- `orElse(expensiveCall())` evaluates eagerly: use `orElseGet(() -> expensiveCall())`.
- Do not use `Optional.ofNullable(x).ifPresent(...)` instead of a plain `if (x != null)`.

### C-4.5 Collections

- [ ] **A: return unmodifiable collections (`List.of`, `Stream.toList()`, `List.copyOf`); copy collection
  parameters you store** *(recommended)*.
- [ ] **B: return whatever the code builds; callers must not mutate**.

Fixed: `Stream.toList()` instead of `collect(Collectors.toList())`. `List.of()` does not accept `null` elements.
Use `getFirst()` / `getLast()` (Java 21 sequenced collections) instead of `get(0)` / `get(size() - 1)`.

**Decision:** ____

### C-4.6 Records

- [ ] **A: records for DTOs, value objects, query projections, configuration properties and events** *(recommended)*.
- [ ] **B: records only for DTOs; Lombok `@Value` for the rest**.
- [ ] **C: Lombok classes everywhere, no records**.

Fixed: validate and normalise in the compact constructor; copy mutable components (`List.copyOf`). Records are not
JPA entities (see M- rules).

**Decision:** ____

### C-4.7 Value objects for IDs and money

- [ ] **A: plain types (`Long`/`UUID` IDs, `BigDecimal` money)** *(recommended for existing codebases)*.
- [ ] **B: small records for domain IDs and money** (`record OrderId(UUID value)`, `record Money(BigDecimal amount,
  Currency currency)`): the compiler stops you from passing a customer ID as an order ID.

Fixed for money: `BigDecimal`, never `double`/`float`. Create from `String` or `BigDecimal.valueOf(long)`, not
`new BigDecimal(0.1)`. Compare with `compareTo`, not `equals` (`2.0` vs `2.00`). Always pass a `RoundingMode` to
`divide`/`setScale`.

**Decision:** ____

### C-4.8 Dates and times

Fixed: `java.time` only (`Instant`, `LocalDate`, `OffsetDateTime`, `Duration`). No `Date`, `Calendar`,
`SimpleDateFormat`. Timestamps stored and exchanged in UTC.

- [ ] **A: inject a `Clock` bean; never call `Instant.now()` / `LocalDate.now()` without a clock** *(recommended)*:
  tests can fix the time.
- [ ] **B: `Instant.now()` allowed; tests tolerate time windows**.

**Decision:** ____

### C-4.9 Magic numbers and strings

- [ ] **A: named constant for any literal with a business meaning; `0`, `1`, `""` and literals used once next to
  their explanation are fine** *(recommended)*.
- [ ] **B: no literals in code except `0`, `1`, `-1`**.

Fixed: configurable values (timeouts, limits, URLs) go to `@ConfigurationProperties`, not constants.

**Decision:** ____

### C-4.10 Constants location

- [ ] **A: `private static final` in the class that uses it; shared constants in the class that owns the concept** (an
  enum, the domain class) *(recommended)*.
- [ ] **B: a `Constants` class per module**.

Fixed: no constants interfaces.

**Decision:** ____

### C-4.11 String building

- [ ] **A: `+` for short concatenation, `"...%s".formatted(x)` for templates, text blocks for multi-line (JSON, SQL)
  and `StringBuilder` only inside loops** *(recommended)*.
- [ ] **B: `String.format(...)` instead of `.formatted(...)`**.

**Decision:** ____

### C-4.12 Enums

Fixed: compare with `==`. Never persist or expose `ordinal()`. Store/serialize by `name()` or an explicit code field.
Unknown values from external systems map to an explicit `UNKNOWN` constant or a clear error, decided per integration.

---

## C-5 Classes and methods

### C-5.1 Method length

- [ ] **A: aim for ≤ 30 lines; above that, extract named private methods** *(recommended)*.
- [ ] **B: hard limit 50 lines (enforced by review / Checkstyle)**.
- [ ] **C: no limit, readability decides**.

**Decision:** ____

### C-5.2 Number of parameters

- [ ] **A: max 4; beyond that, group into a record (command / criteria object)** *(recommended)*.
- [ ] **B: max 7 (Sonar default)**.

Fixed: no boolean flag parameters that switch behaviour (`send(order, true)`): two methods or an enum.

**Decision:** ____

### C-5.3 Class size and responsibility

- [ ] **A: one responsibility per class; split a service above ~300 lines or ~7 injected dependencies**
  *(recommended)*.
- [ ] **B: no explicit limit**.

**Decision:** ____

### C-5.4 Member order inside a class

- [ ] **A: static constants, static fields, instance fields, constructors, public methods, then private methods
  ordered after the public method that first uses them** *(recommended)*.
- [ ] **B: by visibility: public, protected, package-private, private**.
- [ ] **C: IntelliJ "Rearrange code" default**.

**Decision:** ____

### C-5.5 Visibility

- [ ] **A: as narrow as possible: package-private classes and methods when nothing outside the package uses them**
  *(recommended)*.
- [ ] **B: `public` classes, `private` helpers**.

Fixed: test classes and test methods are package-private (`class OrderServiceTest`, `void ...()`), no `public`
(JUnit Jupiter).

**Decision:** ____

### C-5.6 Static utility classes

- [ ] **A: allowed for pure, stateless helpers: `final` class, private constructor, no Spring dependencies**
  *(recommended)*.
- [ ] **B: forbidden: make it a Spring bean**.

Fixed: check `java.util`, Apache Commons / Spring utils (`StringUtils`, `CollectionUtils`, `Assert`) already on the
classpath before writing one.

**Decision:** ____

### C-5.7 Inheritance

Fixed: composition over inheritance. No abstract base services or base controllers for code reuse. Abstract base
classes only for frameworks that need them (e.g. a shared test base class, see C-15.13). Mark classes not designed for
extension `final` where Spring does not need to proxy them (records, value objects, utilities, mappers).

### C-5.8 `equals`, `hashCode`, `toString`

Fixed: always override `equals` and `hashCode` together. Records already do. Never put secrets or personal data in
`toString`. Entities have their own rules (stack files).

---

## C-6 Dependency injection and Spring beans

Fixed:

- Constructor injection only. No `@Autowired` on fields or setters (tests included, except where JUnit/Spring
  requires field injection, e.g. `@MockitoBean`, `@Autowired MockMvc` in Spring tests).
- Dependency fields are `private final`.
- No `@Autowired` on a single constructor.
- No `ApplicationContext.getBean(...)` in application code.
- No circular dependencies; do not fix one with `@Lazy`.
- Beans are stateless; no mutable instance fields in singletons.

### C-6.1 Constructor style

```java
// A
@Service
@RequiredArgsConstructor
public class OrderService {
    private final OrderRepository orderRepository;
    private final Clock clock;
}

// B
@Service
public class OrderService {
    private final OrderRepository orderRepository;
    private final Clock clock;

    public OrderService(OrderRepository orderRepository, Clock clock) {
        this.orderRepository = orderRepository;
        this.clock = clock;
    }
}
```

- [ ] **A: Lombok `@RequiredArgsConstructor`** *(recommended)*.
- [ ] **B: explicit constructor**.

Fixed with A: to put `@Qualifier`/`@Value` on a constructor parameter, add `lombok.copyableAnnotations +=
org.springframework.beans.factory.annotation.Qualifier` to `lombok.config` or write the constructor by hand.

**Decision:** ____

### C-6.2 Stereotype annotations

- [ ] **A: `@RestController`, `@Service`, `@Repository` (custom data access only), `@Component` for anything else,
  `@Configuration` for bean factories** *(recommended)*.
- [ ] **B: `@Component` everywhere except controllers and configuration**.

**Decision:** ____

### C-6.3 `@Bean` methods vs component scanning

- [ ] **A: component scanning for our classes; `@Bean` in a `@Configuration` for third-party objects** (`Clock`,
  clients, `ObjectMapper` customisers) *(recommended)*.
- [ ] **B: explicit `@Bean` definitions for all services**.

**Decision:** ____

---

## C-7 Lombok

Fixed:

- Allowed: `@Getter`, `@Setter` (on fields that need it, not class-wide on domain objects), `@RequiredArgsConstructor`,
  `@Builder`, `@Slf4j`, `@ToString` with `exclude`/`onlyExplicitlyIncluded`, `@EqualsAndHashCode` outside entities.
- Forbidden: `@SneakyThrows`, `val`/`var`, `@Cleanup`, `@Synchronized`, `@Delegate`, `@UtilityClass`, experimental
  features (`lombok.experimental.*`).
- No `@Data` and no `@EqualsAndHashCode` / `@ToString` on JPA entities (lazy loading, cycles; see `M-`).
- Commit a `lombok.config` at the repo root:

```properties
config.stopBubbling = true
lombok.addLombokGeneratedAnnotation = true
lombok.anyConstructor.addConstructorProperties = false
lombok.log.fieldName = log
```

### C-7.1 `@Data` on DTOs

- [ ] **A: no `@Data`: records for DTOs** *(recommended)*.
- [ ] **B: `@Data` allowed on mutable DTOs only**.

**Decision:** ____

### C-7.2 `@Builder`

- [ ] **A: only for types with 4+ fields or many optional fields; also allowed on records** *(recommended)*.
- [ ] **B: on every DTO and value object**.
- [ ] **C: never; use constructors / static factories**.

Fixed: `@Builder` + `@Singular` for collections when used; `toBuilder = true` only when the code needs copies.

**Decision:** ____

### C-7.3 `@Value` vs records

- [ ] **A: records; no Lombok `@Value`** *(recommended)*.
- [ ] **B: `@Value` allowed when a class needs inheritance or a hidden field**.

**Decision:** ____

---

## C-8 MapStruct

Fixed:

- Mappers are interfaces annotated with `@Mapper`, one per aggregate/feature (`OrderMapper`), in the package of the
  layer that uses them.
- Mappers only map. No repository calls, no business rules, no service injection. Computed fields use `expression`,
  `@AfterMapping` or a `default` method only when trivial.
- Unmapped fields are explicit: either mapped or `@Mapping(target = "x", ignore = true)` with a reason if it is not
  obvious.
- Lombok + MapStruct: `maven-compiler-plugin` `annotationProcessorPaths` lists `lombok`, `mapstruct-processor` and
  `lombok-mapstruct-binding`; keep all three when editing the pom.

### C-8.1 Shared configuration

```java
@MapperConfig(
        componentModel = MappingConstants.ComponentModel.SPRING,
        injectionStrategy = InjectionStrategy.CONSTRUCTOR,
        unmappedTargetPolicy = ReportingPolicy.ERROR)
public interface MapStructConfig {
}

@Mapper(config = MapStructConfig.class)
public interface OrderMapper {
    OrderResponse toResponse(Order order);
}
```

- [ ] **A: one `@MapperConfig` as above; every mapper uses `config = MapStructConfig.class`** *(recommended)*.
- [ ] **B: compiler options in the pom** (`-Amapstruct.defaultComponentModel=spring`,
  `-Amapstruct.unmappedTargetPolicy=ERROR`).

**Decision:** ____

### C-8.2 Unmapped target policy

- [ ] **A: `ERROR`**: a new field that nobody maps fails the build *(recommended)*.
- [ ] **B: `WARN`**.
- [ ] **C: `IGNORE`**.

**Decision:** ____

### C-8.3 Mapping direction

- [ ] **A: map entity ↔ domain/DTO in the service layer; controllers receive and return DTOs only** *(recommended)*.
- [ ] **B: controllers call the mapper; services work with entities only**.

**Decision:** ____

### C-8.4 Mapper tests

- [ ] **A: test mappers with non-trivial mappings (renames, expressions, nested objects, enums); get the instance with
  `Mappers.getMapper(OrderMapper.class)` or `new OrderMapperImpl()` without Spring** *(recommended)*.
- [ ] **B: test every mapper**.
- [ ] **C: no direct mapper tests; covered by service/controller tests**.

**Decision:** ____

---

## C-9 Exceptions and error handling

Fixed:

- Never swallow an exception (`catch (Exception e) {}`). Either handle it (recover, return a fallback that is part of
  the contract), or rethrow / wrap it with the original as the cause.
- Catch the most specific type. No `catch (Exception)` / `catch (Throwable)` except at a top-level boundary (scheduled
  job, message listener) that logs and continues.
- Log an exception **or** rethrow it, not both (it would be logged twice).
- Do not use exceptions for normal control flow.
- Exception messages include the identifiers needed to debug (`"Order %s not found".formatted(id)`), never secrets or
  personal data.
- Map exceptions to HTTP responses in one `@RestControllerAdvice`, not in controllers.
- Never return a stack trace or internal exception message to API clients.

### C-9.1 Checked vs unchecked

- [ ] **A: unchecked (`RuntimeException`) domain exceptions; wrap checked exceptions from libraries at the boundary**
  *(recommended)*.
- [ ] **B: checked exceptions for recoverable business errors**.

**Decision:** ____

### C-9.2 Exception hierarchy

- [ ] **A: a small base class (`BusinessException` with an error code) and specific subclasses (`OrderNotFoundException`,
  `PaymentDeclinedException`)** *(recommended)*.
- [ ] **B: one generic `ApiException(HttpStatus, code, message)`**.
- [ ] **C: Spring's `ResponseStatusException` / `ErrorResponseException` thrown directly from services**.

Fixed: domain/service code does not know about HTTP status codes in A; the advice maps exception → status.

**Decision:** ____

### C-9.3 Error response body

```json
{
  "type": "https://api.example.com/problems/order-not-found",
  "title": "Order not found",
  "status": 404,
  "detail": "Order 42 does not exist",
  "instance": "/api/v1/orders/42",
  "code": "ORDER_NOT_FOUND"
}
```

- [ ] **A: RFC 9457 Problem Details (`ProblemDetail`), with an extra `code` property for clients**
  *(recommended)*: built into Spring; enable with `spring.mvc.problemdetails.enabled=true` /
  `spring.webflux.problemdetails.enabled=true` or by extending `ResponseEntityExceptionHandler`.
- [ ] **B: our own error body (`ErrorResponse(code, message, details, timestamp)`)**.

**Decision:** ____

### C-9.4 Validation errors

- [ ] **A: 400 with a list of field errors (`field`, `message`, rejected value only when it is not sensitive)**
  *(recommended)*.
- [ ] **B: 400 with the first error message only**.
- [ ] **C: 422 Unprocessable Entity for business validation, 400 for malformed requests**.

**Decision:** ____

---

## C-10 Logging

Fixed:

- SLF4J through Lombok `@Slf4j` (field `log`). No `System.out`, `printStackTrace()`, `java.util.logging`.
- Placeholders, not concatenation: `log.info("Order {} paid", orderId)`. Exception as the last argument, no
  placeholder for it: `log.error("Payment failed for order {}", orderId, e)`.
- Never log secrets, tokens, passwords, full card numbers, full request/response bodies with personal data.
- No logging inside tight loops; log the summary.
- Levels: `ERROR` = someone must act; `WARN` = unexpected but handled; `INFO` = business events and lifecycle
  (started, order created); `DEBUG` = details for troubleshooting; `TRACE` = rarely.

### C-10.1 Where to log

- [ ] **A: at boundaries (incoming request summary, outgoing calls, messages, scheduled jobs) and on business
  events; not in every method** *(recommended)*.
- [ ] **B: entry/exit logging of every service method at `DEBUG`**.

**Decision:** ____

### C-10.2 Log format

- [ ] **A: Spring Boot structured logging (`logging.structured.format.console=ecs` or `logstash`) in deployed
  environments, plain text locally** *(recommended)*.
- [ ] **B: plain text everywhere**.
- [ ] **C: Logback with a JSON encoder configured in `logback-spring.xml`**.

**Decision:** ____

### C-10.3 Correlation IDs

- [ ] **A: Micrometer Tracing (`traceId`/`spanId` in the MDC/log pattern), propagated on outgoing HTTP calls**
  *(recommended)*.
- [ ] **B: a custom `X-Correlation-Id` header filter + MDC**.
- [ ] **C: none**.

**Decision:** ____

---

## C-11 Comments and Javadoc

Fixed:

- Comments explain **why**, not what. Do not restate the code.
- No commented-out code. No author tags, change logs or dates in comments (git has them).
- `TODO` only with a ticket: `// TODO(PROJ-123): remove after the v1 endpoint is retired`.
- Keep comments correct when you change the code next to them.

### C-11.1 Javadoc

- [ ] **A: Javadoc only on public API that others call without reading the code (shared libraries, client
  interfaces, non-obvious public methods)** *(recommended)*.
- [ ] **B: Javadoc on every public class and method**.
- [ ] **C: no Javadoc; names and tests document the code**.

**Decision:** ____

---

## C-12 REST API (both stacks)

Fixed:

- Controllers are thin: map the request, call one service method, map the response. No business logic, no
  repository calls.
- Never expose entities; requests and responses are DTOs.
- Validate input with Jakarta Bean Validation (`@Valid @RequestBody`, `@NotNull`, `@Size`, `@Positive`) at the
  controller; business rules in the service.
- Paths: plural nouns, kebab-case, no verbs (`/orders/{orderId}/line-items`). Actions that are not CRUD:
  sub-resource (`POST /orders/{id}/cancellation`) or `POST /orders/{id}:cancel`, decided per API.
- Status codes: `200` read/update with body, `201` create (+ `Location` header), `204` no body, `400` invalid input,
  `401` unauthenticated, `403` forbidden, `404` not found, `409` conflict / optimistic lock, `422` see C-9.4, `500`
  unexpected. `GET` never changes state; `PUT` and `DELETE` are idempotent.
- JSON properties camelCase; dates ISO-8601 strings; money as string or `{amount, currency}`, decided per API, never
  floating point.

### C-12.1 API versioning

- [ ] **A: version in the path: `/api/v1/orders`** *(recommended)*.
- [ ] **B: Spring Framework 7 API versioning (`@GetMapping(version = "1")`) with a header or media type**.
- [ ] **C: no versioning; only backward-compatible changes**.

**Decision:** ____

### C-12.2 Response type

```java
// A
@PostMapping
@ResponseStatus(HttpStatus.CREATED)
public OrderResponse create(@Valid @RequestBody CreateOrderRequest request) { ... }

// B
@PostMapping
public ResponseEntity<OrderResponse> create(@Valid @RequestBody CreateOrderRequest request) { ... }
```

- [ ] **A: return the DTO + `@ResponseStatus`; `ResponseEntity` only when headers or status vary** *(recommended)*.
- [ ] **B: always `ResponseEntity`**.

**Decision:** ____

### C-12.3 Pagination

- [ ] **A: `page`/`size`/`sort` query parameters, response is Spring Data's `PagedModel`** *(recommended)*:
  `{ "content": [...], "page": { "size": 20, "number": 0, "totalElements": 42, "totalPages": 3 } }`. Return
  `new PagedModel<>(page)` (works on both stacks), or in Spring MVC return `Page` with
  `@EnableSpringDataWebSupport(pageSerializationMode = VIA_DTO)`. Never serialise a raw `PageImpl`: its JSON is not
  stable.
- [ ] **B: cursor-based (`?after=<id>&limit=50`)** for large or fast-changing collections.
- [ ] **C: no pagination unless a list can exceed N items**.

Fixed: always cap `size` (e.g. max 100).

**Decision:** ____

### C-12.4 OpenAPI documentation

- [ ] **A: springdoc-openapi generated from code; `@Operation`/`@Schema` only where the generated doc is unclear**
  *(recommended)*.
- [ ] **B: contract-first: OpenAPI YAML in the repo, interfaces/DTOs generated with `openapi-generator-maven-plugin`**.
- [ ] **C: no OpenAPI**.

**Decision:** ____

### C-12.5 Request DTO validation messages

- [ ] **A: default Bean Validation messages** *(recommended)*.
- [ ] **B: message keys in `ValidationMessages.properties` (translatable)**.

**Decision:** ____

---

## C-13 Configuration

Fixed:

- No secrets in `application*.yml` or code; read them from environment variables / the secret store
  (`${DB_PASSWORD}`).
- Every property our code reads has a default or fails at startup (validated `@ConfigurationProperties`).
- Profile-specific files only for real differences (`application-local.yml`, `application-test.yml`).

### C-13.1 Reading properties

```java
@Validated
@ConfigurationProperties(prefix = "clients.payment")
public record PaymentClientProperties(
        @NotNull URI baseUrl,
        @NotNull Duration connectTimeout,
        @NotNull Duration readTimeout) {
}
```

- [ ] **A: typed `@ConfigurationProperties` records (+ `@ConfigurationPropertiesScan`); `@Value` only in tests**
  *(recommended)*.
- [ ] **B: `@Value` allowed for single values**.

**Decision:** ____

### C-13.2 File format

- [ ] **A: YAML (`application.yml`)** *(recommended)*.
- [ ] **B: `.properties`**.

**Decision:** ____

---

## C-14 Architecture and packages

### C-14.1 Package structure

```
// A: by feature
com.example.shop.order       OrderController, OrderService, OrderRepository, Order, OrderMapper, dto/
com.example.shop.payment     ...
com.example.shop.common      shared config, error handling

// B: by layer
com.example.shop.controller
com.example.shop.service
com.example.shop.repository
com.example.shop.entity
com.example.shop.dto
com.example.shop.mapper

// C: hexagonal (ports and adapters)
com.example.shop.order.domain        model + ports (interfaces)
com.example.shop.order.application   use cases
com.example.shop.order.adapter.in.web
com.example.shop.order.adapter.out.persistence
```

- [ ] **A: package by feature** *(recommended)*: everything for one feature together, more package-private classes.
- [ ] **B: package by layer**.
- [ ] **C: hexagonal**.

Fixed: follow whatever structure the repo already has; do not mix two.

**Decision:** ____

### C-14.2 Layer rules

Fixed:

- Controller → service → repository / client. No skipping (controller → repository) and no reverse calls.
- Services do not depend on web types (`HttpServletRequest`, `ServerWebExchange`, `ResponseEntity`).
- Transactions are opened in the service layer (see stack files).
- External systems are behind a client class (`PaymentClient`) owned by our code; services never build HTTP calls
  themselves.

### C-14.3 Enforcing architecture

- [ ] **A: ArchUnit tests for layer and package rules** *(recommended once rules are agreed)*.
- [ ] **B: Spring Modulith (`ApplicationModules.of(App.class).verify()`)** for package-by-feature.
- [ ] **C: code review only**.

**Decision:** ____

---

## C-15 Tests: general and unit tests

### C-15.1 Test stack

Fixed:

- JUnit Jupiter (JUnit 6 with Spring Boot 4; same API as JUnit 5). No JUnit 4, no `junit-vintage`.
- **AssertJ for every assertion**: `assertThat(actual).isEqualTo(expected)`. Never JUnit `assertEquals`,
  `assertTrue`, `assertNotNull`, `assertThrows`, and never Hamcrest `assertThat`. Import:
  `import static org.assertj.core.api.Assertions.assertThat;`.
- Mockito for mocks (`mockito-junit-jupiter`).
- WireMock for HTTP calls to other services (C-16).
- No real network calls to anything outside the test (no shared dev environments, no internet).

### C-15.2 Test types and naming

| Type | Name | Runs with | Spring context | Uses |
|---|---|---|---|---|
| Unit | `*Test` | Surefire (`./mvnw test`) | none | JUnit, Mockito, AssertJ |
| Slice | `*Test` | Surefire | partial (`@WebMvcTest`, `@WebFluxTest`, `@DataJpaTest`, `@DataR2dbcTest`, `@JsonTest`) | MockMvcTester / WebTestClient, `@MockitoBean` |
| HTTP client | `*Test` or `*IT` (C-16.1) | Surefire / Failsafe | none, slice or full | WireMock |
| Integration | `*IT` | Failsafe (`./mvnw verify`) | full (`@SpringBootTest`) | Testcontainers / WireMock |

- [ ] **A: Surefire runs `*Test`, Failsafe runs `*IT`** *(recommended)*.
- [ ] **B: everything is `*Test` and runs in Surefire**.

**Decision:** ____

### C-15.3 Unit test setup

Fixed:

- Unit tests use no Spring context: `@ExtendWith(MockitoExtension.class)` and plain constructors.
- Mock only collaborators you own or that are slow/external (repositories, clients, publishers). Do not mock value
  objects, DTOs, mappers that are pure functions, `List`, `Optional`, or the class under test.
- Never mock static methods or constructors (`mockStatic`, `mockConstruction`) for new code; inject a `Clock`,
  `Supplier`, `IdGenerator` instead.
- Mockito strict stubs stay on (default with `MockitoExtension`): unused stubs fail the test. No `lenient()` unless
  the stub is shared and you explain why.

### C-15.4 Creating the class under test

```java
// A
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {
    @Mock
    private OrderRepository orderRepository;
    @InjectMocks
    private OrderService orderService;
}

// B
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {
    @Mock
    private OrderRepository orderRepository;
    private final Clock clock = Clock.fixed(Instant.parse("2026-01-15T10:00:00Z"), ZoneOffset.UTC);
    private OrderService orderService;

    @BeforeEach
    void setUp() {
        orderService = new OrderService(orderRepository, clock);
    }
}
```

- [ ] **A: `@Mock` + `@InjectMocks`**.
- [ ] **B: `@Mock` fields, class under test built with its constructor in `@BeforeEach`** *(recommended)*:
  `@InjectMocks` silently leaves `null` when it cannot match a dependency; constructors fail at compile time.

**Decision:** ____

### C-15.5 Mockito style

```java
// A: classic
when(orderRepository.findById(42L)).thenReturn(Optional.of(order));
verify(paymentClient).charge(order.id(), amount);

// B: BDD
given(orderRepository.findById(42L)).willReturn(Optional.of(order));
then(paymentClient).should().charge(order.id(), amount);
```

- [ ] **A: `when`/`thenReturn`, `verify`** *(recommended)*.
- [ ] **B: BDDMockito `given`/`willReturn`, `then(...).should()`**: reads with given/when/then.

Fixed: stub with concrete arguments, not `any()`, unless the argument does not matter for the test. Prefer asserting
on returned values over verifying calls; verify only calls that are the behaviour (sent an email, published an event,
charged a card).

**Decision:** ____

### C-15.6 `verifyNoMoreInteractions`

- [ ] **A: not used by default; only when "nothing else happened" is the point of the test** *(recommended)*: it
  makes tests break on harmless refactors.
- [ ] **B: `verifyNoMoreInteractions` on every mock in `@AfterEach`**.

**Decision:** ____

### C-15.7 Capturing arguments

- [ ] **A: `ArgumentCaptor` (`@Captor`) + AssertJ on the captured value when you need to check an object passed to
  a mock** *(recommended)*.
- [ ] **B: `argThat(order -> ...)` matchers in `verify`**.

**Decision:** ____

### C-15.8 Test structure

```java
@Test
void appliesVipDiscount() {
    // given
    var customer = aCustomer().vip(true).build();

    // when
    var discount = discountService.discountFor(customer);

    // then
    assertThat(discount).isEqualTo(Discount.VIP);
}
```

- [ ] **A: `// given` / `// when` / `// then` comments** *(recommended)*.
- [ ] **B: `// arrange` / `// act` / `// assert`**.
- [ ] **C: blank lines between the three parts, no comments**.

Fixed: one behaviour per test; the "when" part is one call; no logic (`if`, loops) in tests; no test depends on
another test or on the run order.

**Decision:** ____

### C-15.9 Assertions (AssertJ)

Fixed:

- `assertThat(actual).isEqualTo(expected)`: actual first.
- Use the specific assertion, not a boolean: `assertThat(list).hasSize(2)`, not `assertThat(list.size() ==
  2).isTrue()`; `assertThat(optional).contains(order)` / `isEmpty()`; `assertThat(text).contains("x")`.
- Collections: `containsExactly` (order matters), `containsExactlyInAnyOrder`, `extracting(Order::id)`,
  `singleElement()`, `allSatisfy`.
- Objects without `equals`: `usingRecursiveComparison()` (`.ignoringFields("id", "createdAt")` only when needed).
- `BigDecimal`: `isEqualByComparingTo("10.00")`.
- Exceptions:

```java
assertThatThrownBy(() -> orderService.cancel(42L))
        .isInstanceOf(OrderNotFoundException.class)
        .hasMessageContaining("42");

// or
assertThatExceptionOfType(OrderNotFoundException.class)
        .isThrownBy(() -> orderService.cancel(42L));
```

- [ ] **A: `assertThatThrownBy`** *(recommended)*.
- [ ] **B: `assertThatExceptionOfType(...).isThrownBy(...)`**.

**Decision:** ____

### C-15.10 Several assertions in one test

- [ ] **A: several `assertThat` on the same result are fine; `SoftAssertions.assertSoftly` when you want all
  failures reported at once** *(recommended)*.
- [ ] **B: one `assertThat` per test**.
- [ ] **C: always soft assertions for 3+ checks**.

**Decision:** ____

### C-15.11 Test data

```java
// A: test data builders / object mothers
var order = OrderFixtures.paidOrder().withTotal("99.90").build();

// B: inline construction in every test
var order = new Order(42L, CustomerId.of(7), List.of(line), OrderStatus.PAID);
```

- [ ] **A: shared fixtures/builders per aggregate in `src/test/java/.../fixtures`, with sensible defaults; tests only
  set the fields that matter** *(recommended)*.
- [ ] **B: inline construction in each test**.
- [ ] **C: JSON files under `src/test/resources` loaded with a helper**.

Fixed: test data is fake (`customer@example.com`, `Jane Doe`), never copied from production.

**Decision:** ____

### C-15.12 Parameterized and nested tests

- [ ] **A: `@ParameterizedTest` (`@ValueSource`, `@CsvSource`, `@EnumSource`, `@MethodSource`) for the same
  behaviour with different inputs; `@Nested` classes to group tests per method or scenario** *(recommended)*.
- [ ] **B: parameterized yes, `@Nested` no**.
- [ ] **C: plain tests only**.

**Decision:** ____

### C-15.13 Spring test context reuse

Fixed: every `@SpringBootTest` with a different configuration (different `@MockitoBean`s, properties, profiles)
starts a new context and slows the build.

- [ ] **A: one abstract base class per test type (`AbstractIT` with the shared containers, WireMock and properties);
  no `@MockitoBean` in integration tests unless unavoidable** *(recommended)*.
- [ ] **B: each test class configures itself**.

Fixed: never `@DirtiesContext` to fix test pollution; clean up the data instead.

**Decision:** ____

### C-15.14 Mocking beans in Spring tests

Fixed: `@MockitoBean` / `@MockitoSpyBean` (Spring Framework). The Spring Boot `@MockBean` / `@SpyBean` are removed
in Spring Boot 4; never use them.

### C-15.15 Databases in tests

- [ ] **A: Testcontainers with the same database as production (PostgreSQL/MySQL/…), `@ServiceConnection`; one
  container per test JVM** *(recommended)*.
- [ ] **B: H2 / in-memory for repository tests, Testcontainers only in `*IT`**: faster, but SQL dialect differences
  hide bugs.
- [ ] **C: H2 only**.

**Decision:** ____

### C-15.16 Waiting in tests

Fixed: no `Thread.sleep`. Use Awaitility (`await().atMost(Duration.ofSeconds(5)).untilAsserted(() ->
assertThat(...)...)`) for asynchronous results, or the stack's virtual time (see `W-`).

### C-15.17 Coverage

- [ ] **A: JaCoCo report, no hard gate; review new code** *(recommended)*.
- [ ] **B: JaCoCo gate on new code (e.g. 80% lines) in CI / Sonar quality gate**.
- [ ] **C: no coverage measurement**.

**Decision:** ____

### C-15.18 What must have a unit test

- [ ] **A: every service method with logic (branches, calculations, mapping rules, error handling); not trivial
  getters, pure delegation or configuration** *(recommended)*.
- [ ] **B: every public method**.

Fixed: a bug fix starts with a test that fails without the fix.

**Decision:** ____

---

## C-16 Tests: WireMock (HTTP clients)

WireMock is used to test our HTTP clients (`RestClient` / `WebClient` / HTTP interfaces) against a real HTTP server
with stubbed responses. It tests the real serialisation, headers, timeouts and error mapping, which a Mockito mock of
the client cannot.

### C-16.1 What a WireMock test covers

- [ ] **A: one client test class per external service (`PaymentClientTest`), testing the client class directly
  against WireMock; services that use the client are unit-tested with a Mockito mock of the client**
  *(recommended)*.
- [ ] **B: WireMock in `@SpringBootTest` integration tests only (the whole flow, client included)**.
- [ ] **C: both A and B**.

**Decision:** ____

### C-16.2 How WireMock is started

```java
// A: JUnit Jupiter extension, client built by hand, no Spring
class PaymentClientTest {

    @RegisterExtension
    static WireMockExtension wireMock = WireMockExtension.newInstance()
            .options(wireMockConfig().dynamicPort())
            .build();

    private PaymentClient paymentClient;

    @BeforeEach
    void setUp() {
        // build the client exactly like the production configuration does, but with wireMock.baseUrl()
        paymentClient = PaymentClientFactory.create(wireMock.baseUrl());
    }
}

// B: @WireMockTest, simplest form
@WireMockTest
class PaymentClientTest {

    @BeforeEach
    void setUp(WireMockRuntimeInfo wireMockInfo) {
        paymentClient = new PaymentClient(wireMockInfo.getHttpBaseUrl());
    }
}

// C: Spring context, property points the client at WireMock
@SpringBootTest
class PaymentFlowIT {

    @RegisterExtension
    static WireMockExtension wireMock = WireMockExtension.newInstance()
            .options(wireMockConfig().dynamicPort())
            .build();

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("clients.payment.base-url", wireMock::baseUrl);
    }
}

// D: WireMock Spring Boot integration (org.wiremock.integrations:wiremock-spring-boot)
@SpringBootTest
@EnableWireMock(@ConfigureWireMock(name = "payment-service", baseUrlProperties = "clients.payment.base-url"))
class PaymentFlowIT {

    @InjectWireMock("payment-service")
    private WireMockServer paymentService;
}
```

- [ ] **A: `WireMockExtension` for client tests without Spring** *(recommended for C-16.1 A)*.
- [ ] **B: `@WireMockTest`** (one server per class, less control).
- [ ] **C: `WireMockExtension` + `@DynamicPropertySource` in Spring tests** *(recommended for Spring tests)*.
- [ ] **D: `wiremock-spring-boot` (`@EnableWireMock`)**: one named server per external service.

Fixed: always a dynamic port, never a fixed one. Never use Spring Cloud Contract's `@AutoConfigureWireMock` in new
tests. Use the WireMock artifact the pom already has; if WireMock's Jetty or Jackson clashes with Spring Boot's,
switch to `wiremock-standalone` (ask first, see C-0.2).

**Decision:** ____

### C-16.3 Where stubs live

```java
// A: Java DSL in the test
wireMock.stubFor(get(urlPathEqualTo("/payments/p-1"))
        .willReturn(okJson("""
                {"id": "p-1", "status": "CAPTURED", "amount": "49.90"}
                """)));

// B: JSON response bodies in files, stub in Java
wireMock.stubFor(get(urlPathEqualTo("/payments/p-1"))
        .willReturn(aResponse()
                .withHeader("Content-Type", "application/json")
                .withBodyFile("payment-service/payment-captured.json")));   // src/test/resources/__files/...

// C: full stub mappings as JSON files (src/test/resources/wiremock/mappings/*.json)
```

- [ ] **A: Java DSL with inline text-block bodies for small payloads** *(recommended)*: the test shows everything.
- [ ] **B: Java DSL + body files for large payloads (> ~20 lines) or payloads copied from the provider's docs**
  *(recommended together with A)*.
- [ ] **C: JSON mapping files for everything**: shareable with other tools, but the test hides the stub.

Fixed: file names describe the scenario (`payment-captured.json`, `payment-declined.json`), grouped per external
service.

**Decision:** ____

### C-16.4 Request matching

Fixed:

- Match the method and the path exactly (`urlPathEqualTo`), plus the query parameters, headers and body that
  matter: `withQueryParam("page", equalTo("1"))`, `withHeader("Authorization", equalTo("Bearer test-token"))`,
  `withRequestBody(equalToJson(expectedJson, true, true))` (ignore array order, ignore extra fields) when only some
  fields matter.
- No `urlMatching(".*")` / `any(anyUrl())` catch-all stubs: a wrong path must fail the test.
- An unmatched request returns 404 from WireMock: the client test sees it as a failure. Do not hide it.

### C-16.5 Verifying requests

- [ ] **A: verify (`wireMock.verify(postRequestedFor(urlPathEqualTo("/payments")).withRequestBody(...))`) for
  requests that change state (POST/PUT/PATCH/DELETE) and for the number of calls in retry tests; rely on stub
  matching for GETs** *(recommended)*.
- [ ] **B: verify every expected request**.
- [ ] **C: no verify; strict stub matching is enough**.

**Decision:** ____

### C-16.6 Scenarios every client test class covers

Fixed, for each external call:

- the success response, deserialised into our model (assert every mapped field once);
- each documented error status the provider returns (`400`, `404`, `409`, `5xx`) and what our client turns it into
  (exception type, empty result);
- a timeout: `withFixedDelay(...)` longer than the configured read timeout, with a short timeout in the test config;
- a connection fault: `withFault(Fault.CONNECTION_RESET_BY_PEER)` or `Fault.EMPTY_RESPONSE`;
- an unexpected body (missing fields, extra fields, wrong content type) when the client must tolerate it;
- retries, if the client retries: WireMock scenarios
  (`inScenario("retry").whenScenarioStateIs(STARTED).willReturn(serverError()).willSetStateTo("recovered")`) and a
  verify of the call count.

### C-16.7 Resetting between tests

Fixed: every test starts with no stubs and an empty request journal. `WireMockExtension` and `@WireMockTest` reset
after each test. With a manually managed `WireMockServer`, call `resetAll()` in `@AfterEach`. Stubs needed by every
test go in `@BeforeEach`, not in a static block.

### C-16.8 Authentication against stubs

- [ ] **A: stub the token endpoint too (OAuth2 client credentials) and assert the `Authorization` header on the
  business call** *(recommended)*.
- [ ] **B: disable authentication in the test profile**.

**Decision:** ____

---

## C-17 Security basics

Fixed:

- Never build SQL / JPQL / queries by string concatenation with input; use parameters.
- Validate all input at the API boundary (C-12). Limit sizes (strings, lists, page size, upload size).
- No secrets in code, tests, logs, or committed config. Test credentials are obviously fake.
- Authorisation checks in the service layer or with method security (`@PreAuthorize`), not only in the UI or gateway.
- Do not disable TLS verification, CSRF (for browser clients) or security filters to make something work.
- Do not deserialise untrusted data into polymorphic types (Jackson default typing).

---

## C-18 Concurrency and resources

Fixed:

- Close resources with try-with-resources.
- No `new Thread(...)`; use Spring-managed executors (`@Async` with a configured executor, `TaskExecutor`) or the
  stack's model.
- Shared mutable state needs a reason; prefer immutable objects and `ConcurrentHashMap` / atomic types when needed.
- Every outgoing call (HTTP, DB, broker) has a timeout.
