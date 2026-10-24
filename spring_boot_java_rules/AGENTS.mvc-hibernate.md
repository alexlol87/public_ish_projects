# AGENTS.md: Spring Boot (Spring MVC + Hibernate / JPA) service

<!-- Delete this block if AGENTS.common.md was merged into this file. -->
> **Read and follow `AGENTS.common.md` in this directory first.** It holds the Java style, coding, unit test and
> WireMock rules shared with the reactive services. This file adds the rules for the blocking stack; when the two
> disagree, this file wins.

Rule IDs start with `M-`. Rules with checkboxes are not decided yet: follow the option marked *(recommended)*.

---

## M-0 Stack

- Java **25**, Spring Boot **4.x** (Spring Framework 7, Jakarta EE 11: `jakarta.*` imports only, never `javax.*`
  for persistence, validation or servlet).
- Spring MVC on Tomcat (`spring-boot-starter-web`), blocking I/O, one thread per request.
- Spring Data JPA with Hibernate ORM 7 (Jakarta Persistence 3.2).
- Maven (wrapper `./mvnw`), Lombok, MapStruct. Formatter: IntelliJ IDEA default (C-1).
- Tests: JUnit Jupiter, AssertJ, Mockito, WireMock, Testcontainers / H2 (C-15.15).

Fixed:

- Never add `spring-boot-starter-webflux` or Reactor types (`Mono`, `Flux`) to this service. If a library forces
  `WebClient`, ask first.
- Since JDK 23 `javac` no longer runs annotation processors found on the classpath by default. Lombok and MapStruct
  must stay declared in `maven-compiler-plugin` `annotationProcessorPaths`; do not remove that block.
- No preview features (`--enable-preview`): structured concurrency and primitive patterns are still preview in
  Java 25.

---

## M-1 Java 25 language features

Records, sealed types, pattern matching `switch`, record patterns, text blocks and sequenced collections follow C-3
and C-4. The rules below are for features newer than Java 21.

### M-1.1 Unnamed variables `_` (Java 22)

```java
try {
    return Integer.parseInt(value);
} catch (NumberFormatException _) {
    return DEFAULT_PAGE_SIZE;
}

ordersById.forEach((_, order) -> publisher.publish(order));
if (event instanceof OrderPaid(var orderId, _)) { ... }
```

- [ ] **A: use `_` for unused catch parameters, lambda parameters and record pattern components** *(recommended)*.
- [ ] **B: allowed only in record patterns**.
- [ ] **C: do not use `_`; name every variable (`ignored`)**.

**Decision:** ____

### M-1.2 Flexible constructor bodies (Java 25)

```java
public class PremiumAccount extends Account {
    public PremiumAccount(BigDecimal limit) {
        if (limit.signum() < 0) {
            throw new IllegalArgumentException("limit must be positive");
        }
        super(limit);
    }
}
```

- [ ] **A: allowed for validating arguments before `super(...)` / `this(...)`** *(recommended)*.
- [ ] **B: not used; validate in a static factory method**.

**Decision:** ____

### M-1.3 Module import declarations (`import module java.base;`, Java 25)

- [ ] **A: forbidden: explicit single-type imports only** *(recommended)*: same reason as C-1.2.
- [ ] **B: allowed in tests and scripts**.

**Decision:** ____

### M-1.4 Stream gatherers (`Stream.gather`, Java 24)

- [ ] **A: allowed for windowing / folding (`Gatherers.windowFixed`, `windowSliding`, `fold`, `scan`) when a loop
  would be harder to read** *(recommended)*.
- [ ] **B: not used; write a loop**.

**Decision:** ____

### M-1.5 Scoped values vs `ThreadLocal` (Java 25)

- [ ] **A: `ScopedValue` for new per-request context we own; `ThreadLocal` only where a library requires it**
  *(recommended when virtual threads are on)*.
- [ ] **B: keep `ThreadLocal` / MDC; no scoped values**.

Fixed: never store large objects in a `ThreadLocal` with virtual threads (one copy per thread, millions of threads).

**Decision:** ____

### M-1.6 Virtual threads

```yaml
spring:
  threads:
    virtual:
      enabled: true
```

- [ ] **A: enabled**: Tomcat, `@Async`, `@Scheduled` and the task executors run on virtual threads *(recommended
  for I/O-bound services)*.
- [ ] **B: disabled (platform thread pool)**.

Fixed when enabled:

- The database is still limited by the HikariCP pool size; virtual threads do not give more connections. Do not
  raise the pool size to "match" threads.
- Never pool virtual threads, never create an executor that caps them with a fixed pool. Limit concurrency to an
  external system with a `Semaphore` or Spring Framework 7 `@ConcurrencyLimit`.
- `synchronized` no longer pins the carrier thread since Java 24, but long blocking work inside `synchronized`
  still blocks the other callers; use `ReentrantLock` for long critical sections.

**Decision:** ____

---

## M-2 Web layer (Spring MVC)

Fixed:

- `@RestController` with a class-level `@RequestMapping("/api/v1/orders")`; methods use `@GetMapping`,
  `@PostMapping`, `@PutMapping`, `@PatchMapping`, `@DeleteMapping`.
- Controllers do not use `HttpServletRequest` / `HttpServletResponse` unless they must read something not available
  through `@RequestHeader`, `@CookieValue`, `@RequestParam`, `@PathVariable`. Never pass them to services.
- `@Valid` on `@RequestBody`; `@Validated` on the controller class to validate `@PathVariable` / `@RequestParam`
  constraints (`@Positive Long id`).
- One `@RestControllerAdvice` (extending `ResponseEntityExceptionHandler` when using Problem Details, C-9.3).
- Cross-cutting HTTP concerns (logging, correlation ID, auth headers) in a `OncePerRequestFilter` or
  `HandlerInterceptor`, not in controllers.
- Upload limits set in config (`spring.servlet.multipart.max-file-size`, `max-request-size`).

### M-2.1 Parameter names in annotations

```java
// A
public OrderResponse get(@PathVariable Long orderId) { ... }

// B
public OrderResponse get(@PathVariable("orderId") Long orderId) { ... }
```

- [ ] **A: rely on the `-parameters` compiler flag (set by `spring-boot-starter-parent`)** *(recommended)*.
- [ ] **B: always name the parameter explicitly**.

**Decision:** ____

### M-2.2 Long-running requests

- [ ] **A: no async controller types (`DeferredResult`, `Callable`, `CompletableFuture`); with virtual threads plain
  blocking code is enough** *(recommended)*.
- [ ] **B: `CompletableFuture` return types allowed for fan-out calls**.

Fixed: work that takes longer than the client timeout becomes an asynchronous job: `202 Accepted` + a status
resource.

**Decision:** ____

---

## M-3 Outgoing HTTP calls

### M-3.1 HTTP client technology

```java
// A: HTTP interface client (declarative), backed by RestClient
@HttpExchange("/payments")
public interface PaymentApi {
    @GetExchange("/{paymentId}")
    PaymentProviderResponse get(@PathVariable String paymentId);

    @PostExchange
    PaymentProviderResponse create(@RequestBody CreatePaymentProviderRequest request);
}

// B: RestClient in a client class
@Component
public class PaymentClient {
    private final RestClient restClient;

    public PaymentProviderResponse get(String paymentId) {
        return restClient.get()
                .uri("/payments/{paymentId}", paymentId)
                .retrieve()
                .body(PaymentProviderResponse.class);
    }
}
```

- [ ] **A: HTTP interfaces (`@HttpExchange`) registered with Spring Boot 4's HTTP service client support
  (`@ImportHttpServices`), wrapped by our client class when error mapping is needed** *(recommended)*.
- [ ] **B: `RestClient` built from the auto-configured `RestClient.Builder`, one client class per external service**.
- [ ] **C: Spring Cloud OpenFeign**.

Fixed: no new `RestTemplate` code (maintenance mode, Spring plans to deprecate it); existing code may keep it until
it is touched for other reasons. Never create a client with `RestClient.create()` in a business method; build it
once in a `@Configuration` with the base URL and timeouts from `@ConfigurationProperties` (C-13.1).

**Decision:** ____

### M-3.2 Timeouts

Fixed: every client has a connect timeout and a read timeout, configured per external service, never the infinite
JDK default. Tests check the read timeout with WireMock `withFixedDelay` (C-16.6).

### M-3.3 Error mapping

```java
.retrieve()
.onStatus(status -> status.value() == 404, (request, response) -> {
    throw new PaymentNotFoundException(paymentId);
})
.onStatus(HttpStatusCode::is5xxServerError, (request, response) -> {
    throw new PaymentProviderUnavailableException(response.getStatusCode());
})
.body(PaymentProviderResponse.class);
```

- [ ] **A: map provider errors to our exceptions in the client class (`onStatus` / `defaultStatusHandler`); services
  never see `RestClientResponseException`** *(recommended)*.
- [ ] **B: let `HttpClientErrorException` / `HttpServerErrorException` propagate and handle them in services**.

**Decision:** ____

### M-3.4 Retries and resilience

- [ ] **A: Spring Framework 7 `@Retryable` / `@ConcurrencyLimit` (`@EnableResilientMethods`) for simple retries**
  *(recommended when no circuit breaker is needed)*.
- [ ] **B: Resilience4j (retry, circuit breaker, bulkhead, rate limiter)** with Spring Boot integration.
- [ ] **C: Spring Retry** (only where it is already used).
- [ ] **D: no automatic retries**.

Fixed: retry only idempotent calls (GET, or POST with an idempotency key), with backoff and a max attempts limit,
and only on 5xx / timeouts / connection errors, never on 4xx.

**Decision:** ____

---

## M-4 JPA entities

Fixed:

- Entities are classes, not records, not `final`, with a `protected` no-args constructor (Hibernate proxies and
  instantiation): `@NoArgsConstructor(access = AccessLevel.PROTECTED)`.
- Lombok on entities: `@Getter` and, where allowed (M-4.2), `@Setter` on fields. Never `@Data`, `@Value`,
  `@EqualsAndHashCode`, `@ToString` without excludes, or `@Builder` on the class (use a builder on a constructor or
  a static factory if needed).
- `@Enumerated(EnumType.STRING)` on every enum column; never `ORDINAL` (the default).
- Every `@ManyToOne` and `@OneToOne` has `fetch = FetchType.LAZY` (their default is `EAGER`). Collections stay
  `LAZY` (default).
- Bidirectional associations: the `@ManyToOne` side owns the relation; the parent has `mappedBy` and helper methods
  that keep both sides in sync (`addLine(line)` sets `line.order = this` and adds it to the list). Collections are
  initialised (`= new ArrayList<>()`) and never replaced by a setter.
- Cascade only from an aggregate root to the children it owns (`cascade = CascadeType.ALL, orphanRemoval = true`).
  Never cascade on `@ManyToOne` or to entities that other aggregates also reference.
- `java.time` types for dates (`Instant`, `LocalDate`, `OffsetDateTime`), `BigDecimal` with `precision`/`scale` for
  money.
- `toString` (if any) never includes lazy associations or personal data.
- Entities never leave the service layer: map to DTOs (C-8.3).

### M-4.1 IDs

```java
// A: sequence
@Id
@GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "order_seq")
@SequenceGenerator(name = "order_seq", sequenceName = "order_seq", allocationSize = 50)
private Long id;

// B: identity column
@Id
@GeneratedValue(strategy = GenerationType.IDENTITY)
private Long id;

// C: UUID (time-ordered v7, Hibernate 7)
@Id
@UuidGenerator(style = UuidGenerator.Style.VERSION_7)
private UUID id;
```

- [ ] **A: `Long` + `SEQUENCE` with `allocationSize` matching the DB sequence increment** *(recommended for
  PostgreSQL / Oracle)*: Hibernate can batch inserts.
- [ ] **B: `Long` + `IDENTITY`** (MySQL / MariaDB): disables JDBC insert batching.
- [ ] **C: `UUID` v7**: IDs can be created before persisting and are safe to expose; bigger indexes.

**Decision:** ____

### M-4.2 Changing entity state

```java
// A: domain methods, no public setters
public void cancel(Instant now) {
    if (status == OrderStatus.SHIPPED) {
        throw new OrderAlreadyShippedException(id);
    }
    status = OrderStatus.CANCELLED;
    cancelledAt = now;
}

// B: setters, logic in the service
order.setStatus(OrderStatus.CANCELLED);
order.setCancelledAt(now);
```

- [ ] **A: domain methods on the entity for state changes; no class-level `@Setter`** *(recommended)*: invariants
  live in one place.
- [ ] **B: setters; business rules in services**.

**Decision:** ____

### M-4.3 `equals` and `hashCode`

```java
// A: ID based, proxy safe, stable hash
@Override
public boolean equals(Object o) {
    if (this == o) {
        return true;
    }
    if (!(o instanceof Order other)) {
        return false;
    }
    return id != null && id.equals(other.getId());
}

@Override
public int hashCode() {
    return Order.class.hashCode();
}
```

- [ ] **A: ID-based `equals` as above, constant `hashCode`** *(recommended)*: correct before and after persisting,
  and with Hibernate proxies (use `other.getId()`, not `other.id`).
- [ ] **B: business key (`@NaturalId`, e.g. order number) in `equals`/`hashCode`**.
- [ ] **C: no override (object identity)**: fine while entities are never put in `Set`s across sessions.

**Decision:** ____

### M-4.4 Collection type for `@OneToMany` / `@ManyToMany`

- [ ] **A: `List` (with `@OrderBy` / `@OrderColumn` when order matters); never fetch-join two `List`s in one query
  (`MultipleBagFetchException`)** *(recommended)*.
- [ ] **B: `Set` for every collection** (needs M-4.3 A or B).

Fixed: no `@ManyToMany` with extra columns: map the join table as its own entity.

**Decision:** ____

### M-4.5 Optimistic locking

- [ ] **A: `@Version` (`Long version`) on every aggregate root; `ObjectOptimisticLockingFailureException` → `409
  Conflict`** *(recommended)*.
- [ ] **B: `@Version` only on entities with concurrent updates**.
- [ ] **C: none**.

Fixed: no pessimistic locks (`@Lock(PESSIMISTIC_WRITE)`) without a lock timeout and a reason.

**Decision:** ____

### M-4.6 Audit columns

- [ ] **A: Spring Data auditing (`@EnableJpaAuditing`, `@CreatedDate`, `@LastModifiedDate`, `@CreatedBy`) in a
  `@MappedSuperclass` `AuditableEntity`** *(recommended)*.
- [ ] **B: Hibernate `@CreationTimestamp` / `@UpdateTimestamp`**.
- [ ] **C: set by the service from the injected `Clock`** (C-4.8).

**Decision:** ____

### M-4.7 Table and column names

- [ ] **A: rely on Spring Boot's snake_case naming strategy; `@Table` / `@Column(name = ...)` only when the DB name
  differs** *(recommended)*.
- [ ] **B: always explicit `@Table(name = ...)` and `@Column(name = ...)`**: renaming a field never renames a column.

Fixed: `@Column(nullable = false, length = ...)` mirrors the migration, but the migration (M-6) is the source of
truth; `ddl-auto` never creates the schema outside tests.

**Decision:** ____

---

## M-5 Repositories and queries

Fixed:

- Repositories are Spring Data interfaces in the feature package, one per aggregate root (no repositories for child
  entities that are only reached through their root).
- `spring.jpa.open-in-view=false` always. Fetch what the use case needs in the query; never fix a
  `LazyInitializationException` with open-in-view, `hibernate.enable_lazy_load_no_trans`, `EAGER`, or
  `Hibernate.initialize` loops.
- Watch for N+1: a loop that touches a lazy association runs one query per element. Use `@EntityGraph(attributePaths
  = "lines")`, `join fetch`, or `hibernate.default_batch_fetch_size`.
- Pagination with a fetch-joined collection paginates in memory. Set
  `spring.jpa.properties.hibernate.query.fail_on_pagination_over_collection_fetch=true`; page the IDs first, then
  fetch the entities with their collections.
- Use `getReferenceById(id)` to set a `@ManyToOne` when you only have the ID (no extra select).
- Bulk `@Modifying` queries bypass the persistence context: `@Modifying(clearAutomatically = true,
  flushAutomatically = true)`; they also bypass `@Version` and auditing.
- Large exports: `Stream<T>` in a read-only transaction (closed with try-with-resources) or Spring Data scrolling
  (`Window`, `ScrollPosition.keyset()`); never `findAll()` into memory.
- Insert batching: `spring.jpa.properties.hibernate.jdbc.batch_size`, `order_inserts`, `order_updates` set together
  with M-4.1 A.

### M-5.1 Base repository interface

- [ ] **A: `JpaRepository<T, ID>`** *(recommended)*.
- [ ] **B: `ListCrudRepository<T, ID>` + `ListPagingAndSortingRepository`**: smaller API, no `flush`/`saveAndFlush`
  /`deleteAllInBatch` unless needed.
- [ ] **C: `Repository<T, ID>` and declare only the methods used**.

**Decision:** ____

### M-5.2 Query style

```java
// derived
List<Order> findAllByCustomerIdAndStatus(Long customerId, OrderStatus status);

// JPQL
@Query("""
        select o from Order o
        join fetch o.lines
        where o.customerId = :customerId and o.status in :statuses
        """)
List<Order> findWithLines(Long customerId, Collection<OrderStatus> statuses);
```

- [ ] **A: derived queries up to 2 conditions; above that, or with joins / fetches, `@Query` JPQL in a text block**
  *(recommended)*.
- [ ] **B: derived queries whenever Spring Data supports them**.
- [ ] **C: always `@Query`**.

Fixed: native queries (`nativeQuery = true`) only for database features JPQL cannot express; named parameters
(`:customerId`), never positional (`?1`).

**Decision:** ____

### M-5.3 Dynamic filters (search endpoints)

- [ ] **A: Spring Data JPA `Specification`s** *(recommended)*.
- [ ] **B: Querydsl** (needs the Querydsl annotation processor).
- [ ] **C: Criteria API in a custom repository fragment (`OrderRepositoryCustom` + `Impl`)**.
- [ ] **D: jOOQ for read-heavy / reporting queries**.

**Decision:** ____

### M-5.4 Read models / projections

```java
public record OrderSummary(Long id, String number, BigDecimal total) {
}

// A: DTO projection with a JPQL constructor expression
@Query("select new com.example.shop.order.OrderSummary(o.id, o.number, o.total) from Order o where o.customerId = :customerId")
List<OrderSummary> findSummaries(Long customerId);

// B: Spring Data class-based projection (derived from the record's constructor)
List<OrderSummary> findAllByCustomerId(Long customerId);

// C: interface projection
public interface OrderSummaryView {
    Long getId();
    String getNumber();
}
```

- [ ] **A or B: record projections for read-only lists** *(recommended)*: no dirty checking, fewer columns.
- [ ] **C: interface projections**.
- [ ] **D: load entities and map with MapStruct**.

**Decision:** ____

### M-5.5 Saving managed entities

```java
// A: dirty checking
@Transactional
public void cancel(Long orderId) {
    Order order = orderRepository.findById(orderId).orElseThrow(() -> new OrderNotFoundException(orderId));
    order.cancel(Instant.now(clock));
}

// B: explicit save
@Transactional
public void cancel(Long orderId) {
    Order order = orderRepository.findById(orderId).orElseThrow(() -> new OrderNotFoundException(orderId));
    order.cancel(Instant.now(clock));
    orderRepository.save(order);
}
```

- [ ] **A: rely on dirty checking for entities loaded in the same transaction; `save` only for new entities**
  *(recommended)*.
- [ ] **B: always call `save`** (more explicit, a no-op `merge` for managed entities).

**Decision:** ____

---

## M-6 Schema migrations

Fixed:

- Every schema change is a migration in the repo; `spring.jpa.hibernate.ddl-auto=validate` (or `none`) outside
  tests.
- Never edit or delete a migration that ran in any shared environment; add a new one.
- Migrations are backward compatible with the previous app version (expand, deploy, then contract): add nullable
  column → backfill → add constraint in a later release; never rename/drop a column the running version uses.
- Large tables: create indexes concurrently (PostgreSQL `CREATE INDEX CONCURRENTLY`, outside a transaction).

### M-6.1 Migration tool

- [ ] **A: Flyway, plain SQL** *(recommended)*.
- [ ] **B: Liquibase (YAML / XML changelogs)**.

**Decision:** ____

### M-6.2 Flyway file names

- [ ] **A: timestamp version `V2026_10_24_1030__add_order_status.sql`**: no conflicts between branches
  *(recommended)*.
- [ ] **B: sequential `V12__add_order_status.sql`**.

**Decision:** ____

---

## M-7 Transactions

Fixed:

- `@Transactional` from `org.springframework.transaction.annotation`, never `jakarta.transaction.Transactional`.
- Transactions start in the service layer. Not on controllers, not on repositories (Spring Data already has them),
  not on private methods.
- Self-invocation does not start a transaction (`this.otherMethod()` bypasses the proxy). Move the method to another
  bean.
- No remote HTTP calls, message sends or long computations inside a transaction: they hold a DB connection and
  cannot be rolled back. Do the call before, or publish after commit (M-7.2).
- Spring rolls back on unchecked exceptions only. With checked exceptions (if C-9.1 B) add `rollbackFor`.
- `Propagation.REQUIRES_NEW` only with a comment explaining why (it takes a second connection).
- A `@Transactional` method that catches an exception from an inner transactional call still rolls back if the inner
  call marked the transaction rollback-only (`UnexpectedRollbackException`).

### M-7.1 Read-only transactions

```java
// A
@Service
@Transactional(readOnly = true)
public class OrderService {

    public OrderResponse get(Long id) { ... }

    @Transactional
    public OrderResponse create(CreateOrderRequest request) { ... }
}

// B
@Service
public class OrderService {

    @Transactional(readOnly = true)
    public OrderResponse get(Long id) { ... }

    @Transactional
    public OrderResponse create(CreateOrderRequest request) { ... }
}
```

- [ ] **A: class-level `@Transactional(readOnly = true)`, `@Transactional` on write methods** *(recommended)*.
- [ ] **B: annotate every public method explicitly**.
- [ ] **C: no transaction for reads; `@Transactional` on writes only**.

**Decision:** ____

### M-7.2 Side effects after commit

- [ ] **A: publish a Spring application event and handle it with `@TransactionalEventListener(phase =
  AFTER_COMMIT)`** *(recommended for in-process side effects)*.
- [ ] **B: transactional outbox table + relay** (guaranteed delivery to a broker).
- [ ] **C: call the external system after the transactional method returns**.

**Decision:** ____

---

## M-8 JSON (Jackson)

Fixed:

- Spring Boot 4 uses Jackson 3 by default: `tools.jackson.*` packages (`JsonMapper`), while annotations stay in
  `com.fasterxml.jackson.annotation`. Match what the repo already imports; do not mix Jackson 2 and 3 `ObjectMapper`
  types in one service.
- Customise the auto-configured mapper (`JsonMapperBuilderCustomizer` / `spring.jackson.*`); never create a second
  mapper with `new JsonMapper()` / `new ObjectMapper()` in production code.
- DTOs only; no Jackson annotations on entities.

### M-8.1 Unknown properties in incoming JSON

- [ ] **A: ignore unknown properties (Spring Boot default)** *(recommended)*: tolerant to providers adding fields.
- [ ] **B: fail on unknown properties for our own API requests**.

**Decision:** ____

### M-8.2 `null` fields in responses

- [ ] **A: omit nulls (`spring.jackson.default-property-inclusion=non_null`)** *(recommended)*.
- [ ] **B: always write every field, `null` included**.

**Decision:** ____

---

## M-9 Background work

### M-9.1 Scheduled jobs with several instances

- [ ] **A: ShedLock (JDBC lock table) on every `@Scheduled` job that must run once per cluster** *(recommended)*.
- [ ] **B: an external scheduler (Kubernetes CronJob) calls an endpoint / runs a job**.
- [ ] **C: single instance; no locking**.

Fixed: jobs are idempotent and process in batches with their own transactions (not one transaction for the whole
run).

**Decision:** ____

### M-9.2 `@Async`

- [ ] **A: avoid `@Async`; use explicit executors or events** *(recommended)*.
- [ ] **B: `@Async` with a named, configured executor; never the default `SimpleAsyncTaskExecutor` without limits**.

**Decision:** ____

---

## M-10 Tests for this stack

The general test and WireMock rules are in C-15 and C-16. This section adds the Spring MVC / JPA specifics.

Fixed:

- Spring Boot 4 split test slices into modules (`spring-boot-webmvc-test`, `spring-boot-data-jpa-test`, …) and moved
  the annotations to new packages. Copy imports from the existing tests in the repo; do not use the Spring Boot 3
  `org.springframework.boot.test.autoconfigure.*` packages.
- Mock beans with `@MockitoBean` (C-15.14).

### M-10.1 Controller tests

```java
// A: MockMvcTester (AssertJ)
@WebMvcTest(OrderController.class)
class OrderControllerTest {

    @Autowired
    private MockMvcTester mvc;

    @MockitoBean
    private OrderService orderService;

    @Test
    void returnsOrder() {
        when(orderService.get(42L)).thenReturn(new OrderResponse(42L, "ORD-42", new BigDecimal("49.90")));

        assertThat(mvc.get().uri("/api/v1/orders/{id}", 42))
                .hasStatusOk()
                .bodyJson()
                .extractingPath("$.number").isEqualTo("ORD-42");
    }
}

// B: classic MockMvc with matchers
mockMvc.perform(get("/api/v1/orders/{id}", 42))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.number").value("ORD-42"));
```

- [ ] **A: `@WebMvcTest` + `MockMvcTester`** *(recommended)*: AssertJ style, matches C-15.1.
- [ ] **B: `@WebMvcTest` + `MockMvc` with `andExpect`**.
- [ ] **C: `RestTestClient` (Spring Framework 7) bound to the controller or the context**.

Fixed: controller tests cover request mapping, validation (400 with field errors), status codes, the JSON shape and
exception mapping from the `@RestControllerAdvice`. Business logic is tested in service unit tests.

**Decision:** ____

### M-10.2 JSON contract assertions

- [ ] **A: compare the full response body with an expected JSON text block (`bodyJson().isLenientlyEqualTo(...)`,
  or `isStrictlyEqualTo` when field order and extra fields matter)** *(recommended)*.
- [ ] **B: assert selected fields with JSON paths**.
- [ ] **C: `@JsonTest` + `JacksonTester` for DTO serialisation, paths in controller tests**.

**Decision:** ____

### M-10.3 Repository tests

```java
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Import(TestcontainersConfiguration.class)   // @ServiceConnection PostgreSQLContainer
class OrderRepositoryTest {

    @Autowired
    private OrderRepository orderRepository;

    @Autowired
    private TestEntityManager entityManager;

    @Test
    void findsOrdersWithLines() {
        entityManager.persist(OrderFixtures.paidOrder().build());
        entityManager.flush();
        entityManager.clear();

        var orders = orderRepository.findWithLines(7L, List.of(OrderStatus.PAID));

        assertThat(orders).singleElement()
                .satisfies(order -> assertThat(order.getLines()).hasSize(2));
    }
}
```

Fixed:

- Test custom `@Query` methods, non-trivial derived queries, entity mappings (enums, embedded types, converters) and
  constraints. Do not test inherited `save`/`findById`.
- `@DataJpaTest` runs each test in a transaction that is rolled back: call `flush()` and `clear()` before asserting,
  otherwise the query reads from the first-level cache and hides mapping and lazy-loading bugs.
- Migrations run in repository tests (Flyway / Liquibase on the test database), so the schema under test is the real
  one.

- [ ] **A: `@DataJpaTest` + Testcontainers** *(recommended, see C-15.15)*.
- [ ] **B: `@DataJpaTest` + H2 in the production DB's compatibility mode**.

**Decision:** ____

### M-10.4 Integration tests

- [ ] **A: `@SpringBootTest(webEnvironment = RANDOM_PORT)` + `RestTestClient` / `TestRestTemplate`, Testcontainers
  database, WireMock for every external service (C-16.2 C or D)** *(recommended)*.
- [ ] **B: `@SpringBootTest` + `@AutoConfigureMockMvc` (no real HTTP server)**.

Fixed:

- No `@Transactional` on integration tests: it hides commit-time behaviour (constraints, `@TransactionalEventListener`,
  lazy loading outside the transaction). Clean the data between tests instead.

**Decision:** ____

### M-10.5 Cleaning the database between integration tests

- [ ] **A: truncate the tables touched by the test in `@AfterEach` (`JdbcTemplate` / `@Sql(executionPhase =
  AFTER_TEST_METHOD)`)** *(recommended)*.
- [ ] **B: each test creates its own data with unique keys and never cleans up**.
- [ ] **C: a fresh container per test class** (slow).

**Decision:** ____

### M-10.6 HTTP client tests

```java
class PaymentClientTest {

    @RegisterExtension
    static WireMockExtension wireMock = WireMockExtension.newInstance()
            .options(wireMockConfig().dynamicPort())
            .build();

    private PaymentClient paymentClient;

    @BeforeEach
    void setUp() {
        var properties = new PaymentClientProperties(
                URI.create(wireMock.baseUrl()), Duration.ofSeconds(1), Duration.ofMillis(500));
        paymentClient = new PaymentClientConfiguration().paymentClient(RestClient.builder(), properties);
    }

    @Test
    void returnsCapturedPayment() {
        wireMock.stubFor(get(urlPathEqualTo("/payments/p-1"))
                .willReturn(okJson("""
                        {"id": "p-1", "status": "CAPTURED", "amount": "49.90"}
                        """)));

        var payment = paymentClient.get("p-1");

        assertThat(payment.status()).isEqualTo(PaymentStatus.CAPTURED);
        assertThat(payment.amount()).isEqualByComparingTo("49.90");
    }

    @Test
    void mapsNotFoundToPaymentNotFoundException() {
        wireMock.stubFor(get(urlPathEqualTo("/payments/p-404")).willReturn(notFound()));

        assertThatThrownBy(() -> paymentClient.get("p-404"))
                .isInstanceOf(PaymentNotFoundException.class);
    }

    @Test
    void failsWhenProviderIsSlowerThanReadTimeout() {
        wireMock.stubFor(get(urlPathEqualTo("/payments/p-1"))
                .willReturn(okJson("{}").withFixedDelay(1_000)));

        assertThatThrownBy(() -> paymentClient.get("p-1"))
                .isInstanceOf(PaymentProviderUnavailableException.class);
    }
}
```

- [ ] **A: WireMock for every client (C-16)** *(recommended)*.
- [ ] **B: `@RestClientTest` + `MockRestServiceServer` for `RestClient` clients, WireMock only in integration
  tests**: faster, but skips the real HTTP stack and timeouts.

**Decision:** ____
