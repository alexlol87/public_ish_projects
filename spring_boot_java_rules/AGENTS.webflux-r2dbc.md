# AGENTS.md: Spring Boot Reactive (WebFlux + R2DBC) service

<!-- Delete this block if AGENTS.common.md was merged into this file. -->
> **Read and follow `AGENTS.common.md` in this directory first.** It holds the Java style, coding, unit test and
> WireMock rules shared with the blocking services. This file adds the rules for the reactive stack; when the two
> disagree, this file wins.

Rule IDs start with `W-`. Rules with checkboxes are not decided yet: follow the option marked *(recommended)*.

---

## W-0 Stack

- Java **21**, Spring Boot **4.x** (Spring Framework 7, Jakarta EE 11 `jakarta.*` imports).
- Spring WebFlux on Reactor Netty (`spring-boot-starter-webflux`), non-blocking I/O, a few event-loop threads serve
  every request. Project Reactor `Mono` / `Flux` everywhere in the request path.
- Spring Data R2DBC (`spring-boot-starter-data-r2dbc`) with the database's R2DBC driver and `r2dbc-pool`.
- Maven (wrapper `./mvnw`), Lombok, MapStruct. Formatter: IntelliJ IDEA default (C-1).
- Tests: JUnit Jupiter, AssertJ, Mockito, Reactor `StepVerifier`, `WebTestClient`, WireMock, Testcontainers.

Fixed:

- Never add `spring-boot-starter-web` (servlet): when both are on the classpath Spring Boot starts Spring MVC on
  Tomcat, not WebFlux.
- Never add JPA, Hibernate, `spring-boot-starter-jdbc` or `JdbcTemplate` for application queries. The only JDBC
  driver on the classpath is the one Flyway / Liquibase need for migrations (W-6).
- No preview features (`--enable-preview`). In Java 21 unnamed variables (`_`), string templates and unnamed
  classes are preview: do not use them.
- Do not enable virtual threads (`spring.threads.virtual.enabled`): the event loop must never block, so they add
  nothing here and hide blocking calls.

---

## W-1 Non-blocking rules (fixed)

These are not style choices: breaking them stalls the event loop and the whole service.

- Never block in application code: no `.block()`, `.blockFirst()`, `.blockLast()`, `.toFuture().get()`,
  `CompletableFuture.join()`, `Thread.sleep`, `CountDownLatch.await`, JDBC, `RestClient` / `RestTemplate`, blocking
  file or socket I/O, or blocking SDKs (old AWS SDK v1, SMTP clients…).
- An unavoidable blocking call is isolated and commented:

```java
// legacy SDK has no async API
Mono<Report> report = Mono.fromCallable(() -> legacyReportSdk.generate(request))
        .subscribeOn(Schedulers.boundedElastic());
```

- Never call `subscribe()` in controllers, services or clients: return the `Mono` / `Flux` and let WebFlux (or the
  caller) subscribe. Never subscribe inside an operator (nested subscribe). Exception: W-2.12.
- Never return `null` from a method returning `Mono` / `Flux`, and never `Mono.just(null)`. Use `Mono.empty()`,
  `Mono.justOrEmpty(value)`, `Flux.empty()`.
- No `Mono<Optional<T>>`: an empty `Mono` already means "absent".
- Nothing runs until subscription, but the code that **builds** the pipeline runs immediately:
  - `Mono.just(expensiveCall())` calls `expensiveCall()` at assembly time, even if nobody subscribes. Use
    `Mono.fromCallable(...)` / `Mono.defer(...)`.
  - `switchIfEmpty(Mono.error(new OrderNotFoundException(id)))` builds the exception (stack trace included) every
    time. Use the supplier: `switchIfEmpty(Mono.error(() -> new OrderNotFoundException(id)))`.
  - `switchIfEmpty(createOrder())` calls `createOrder()` eagerly; wrap it: `switchIfEmpty(Mono.defer(() ->
    createOrder()))`.
- `map` for synchronous transformations, `flatMap` (or `concatMap`) when the function returns a publisher. A
  `Mono<Mono<T>>` or `Flux<Mono<T>>` type is always a bug.
- `doOnNext` / `doOnSuccess` / `doOnError` / `doFinally` are for side effects that cannot fail and need no waiting:
  logging, metrics. Work that returns a publisher (save, publish, call) goes in `flatMap` / `then`.
- Results you do not need: `then()`, `thenReturn(value)`, `then(otherMono)`; methods with no result return
  `Mono<Void>`.
- Do not swallow errors: no `onErrorResume(e -> Mono.empty())` / `onErrorComplete()` without a comment saying why
  absence is correct. Log **or** propagate (C-9).
- No `ThreadLocal`s in reactive code (the thread changes between operators); use the Reactor `Context` (W-2.10).
- No shared mutable state captured in lambdas (`List` filled inside `doOnNext`); collect with operators
  (`collectList`, `reduce`).

---

## W-2 Reactor style

### W-2.1 Formatting pipelines

Fixed: one operator per line (C-1.5 A applies to every Reactor chain), the source on the first line.

```java
return orderRepository.findById(orderId)
        .switchIfEmpty(Mono.error(() -> new OrderNotFoundException(orderId)))
        .flatMap(this::reserveStock)
        .flatMap(orderRepository::save)
        .map(orderMapper::toResponse);
```

### W-2.2 Long lambdas inside operators

```java
// A: named private methods
return orderRepository.findById(orderId)
        .flatMap(this::reserveStock)
        .flatMap(this::chargeCustomer);

private Mono<Order> reserveStock(Order order) { ... }

// B: inline lambdas
return orderRepository.findById(orderId)
        .flatMap(order -> inventoryClient.reserve(order.lines())
                .thenReturn(order.withStatus(RESERVED)))
        .flatMap(order -> paymentClient.charge(order.customerId(), order.total())
                .map(payment -> order.withPaymentId(payment.id())));
```

- [ ] **A: lambdas longer than one or two lines become private methods returning `Mono` / `Flux`; the main method
  reads like a list of steps** *(recommended)*.
- [ ] **B: inline lambdas allowed up to ~5 lines**.

**Decision:** ____

### W-2.3 `flatMap`, `concatMap`, `flatMapSequential`

- [ ] **A: `flatMap` when order does not matter, `concatMap` when it must be sequential or ordered,
  `flatMapSequential` for concurrent work with ordered results; always pass a concurrency limit when the inner
  publisher calls a database or another service (`flatMap(this::enrich, 8)`)** *(recommended)*.
- [ ] **B: `concatMap` by default; `flatMap` only when measured to be needed**.

Fixed: the concurrency limit for database calls stays below the R2DBC pool size (`spring.r2dbc.pool.max-size`).

**Decision:** ____

### W-2.4 Carrying several values through a pipeline

```java
// A: zip into a record immediately
return Mono.zip(customerClient.get(customerId), cartRepository.findByCustomerId(customerId), Checkout::new)
        .flatMap(this::placeOrder);

// B: nested flatMap closures
return customerClient.get(customerId)
        .flatMap(customer -> cartRepository.findByCustomerId(customerId)
                .flatMap(cart -> placeOrder(customer, cart)));
```

- [ ] **A: `Mono.zip` / `zipWith` for independent values, mapped straight away to a small record; no `getT1()`
  / `getT2()` passed further down the pipeline** *(recommended)*.
- [ ] **B: nested `flatMap` closures (max 2 levels), sequential calls**.
- [ ] **C: `Tuple2` allowed through the pipeline**.

Fixed: independent calls run in parallel with `Mono.zip`, not one after the other with `flatMap`. Note: `zip`
completes empty as soon as one source is empty; handle emptiness before zipping (`switchIfEmpty`).

**Decision:** ____

### W-2.5 Empty results

Fixed: decide explicitly what empty means at the boundary:

- missing resource → `switchIfEmpty(Mono.error(() -> new XNotFoundException(id)))`;
- default value → `defaultIfEmpty(value)` / `switchIfEmpty(Mono.defer(...))`;
- empty is fine → leave it, and document it in the method name (`findBy...` returns empty, `getBy...` errors,
  C-2.4).

### W-2.6 Service return types for lists

- [ ] **A: `Flux<T>` from repositories and services; WebFlux writes a JSON array for `application/json`**
  *(recommended)*.
- [ ] **B: `Mono<List<T>>` (`collectList()`) for small bounded lists the caller needs as a whole (e.g. for a page
  response, validation of the whole set)**.
- [ ] **C: always `Mono<List<T>>` in the web layer, `Flux<T>` inside**.

Fixed: never `collectList()` an unbounded `Flux` (whole table in memory).

**Decision:** ____

### W-2.7 Errors in pipelines

Fixed:

- Map technical errors to domain exceptions at the boundary that knows them (`onErrorMap(WebClientResponseException.
  NotFound.class, e -> new PaymentNotFoundException(id))`), not in every service.
- `onErrorResume` only for a real fallback (cache, default) and only for a specific exception type.
- Throwing inside `map` / `flatMap` lambdas turns into an error signal; prefer returning `Mono.error(...)` from
  `flatMap` and throwing only in `map` / `handle`.
- The `@RestControllerAdvice` (C-9) handles exceptions from reactive controllers the same way.

### W-2.8 Timeouts

Fixed: every outgoing call has a timeout at the client level (W-4.2). Add `.timeout(Duration)` in the pipeline only
for an overall deadline across several calls, followed by `onErrorMap(TimeoutException.class, ...)`.

### W-2.9 Retries

```java
.retryWhen(Retry.backoff(3, Duration.ofMillis(200))
        .maxBackoff(Duration.ofSeconds(2))
        .filter(this::isTransient)
        .onRetryExhaustedThrow((spec, signal) -> new PaymentProviderUnavailableException(signal.failure())))
```

- [ ] **A: Reactor `retryWhen(Retry.backoff(...).filter(...))` in the client class** *(recommended)*.
- [ ] **B: Resilience4j Reactor operators (`RetryOperator`, `CircuitBreakerOperator`) or annotations**.
- [ ] **C: Spring Framework 7 `@Retryable` on the client method (supports reactive return types)**.

Fixed: retry only idempotent calls, on 5xx / timeouts / connection errors, never on 4xx; `retryWhen` re-subscribes,
so the call is made again only if it is built lazily (W-1).

**Decision:** ____

### W-2.10 Context propagation (trace IDs, MDC, security)

- [ ] **A: automatic context propagation: `spring.reactor.context-propagation=auto` (Micrometer
  `context-propagation` on the classpath); logs inside operators get the trace ID** *(recommended)*.
- [ ] **B: read values from the Reactor `Context` explicitly (`Mono.deferContextual(ctx -> ...)`); no MDC inside
  operators**.

Fixed: the current user comes from `ReactiveSecurityContextHolder.getContext()`, never from a thread-bound holder.

**Decision:** ____

### W-2.11 Schedulers

Fixed: no `publishOn` / `subscribeOn` except `subscribeOn(Schedulers.boundedElastic())` around a blocking call
(W-1). No `Schedulers.parallel()` / `ParallelFlux` without measured CPU-bound work. Never create schedulers per
request (`Schedulers.newBoundedElastic` inside a method).

### W-2.12 Fire-and-forget

- [ ] **A: not allowed: every side effect is part of the returned pipeline (`then(audit.save(...))`), or goes through
  a message broker** *(recommended)*.
- [ ] **B: allowed for non-critical side effects (metrics, cache warm-up) with `subscribe(null, e -> log.warn(...))`
  and a comment**: errors and backpressure are lost, the request context is gone.

**Decision:** ____

### W-2.13 Debugging aids

- [ ] **A: `ReactorDebugAgent` (`reactor-tools`) enabled at startup for readable assembly stack traces; named
  `checkpoint("...")` only where hard to trace** *(recommended)*.
- [ ] **B: `checkpoint` only, no agent**.
- [ ] **C: nothing**.

Fixed: never `Hooks.onOperatorDebug()` in production (large overhead).

**Decision:** ____

### W-2.14 `Mono.fromCallable` vs `Mono.fromSupplier` vs `Mono.defer`

Fixed: `fromCallable` for a synchronous value that may throw (turns the exception into an error signal),
`fromSupplier` for one that cannot throw, `defer` when the lambda returns a publisher, `fromRunnable` for
synchronous side effects with no value.

---

## W-3 Web layer (WebFlux)

Fixed:

- Controllers return `Mono<T>`, `Flux<T>` or `Mono<Void>`; never block to return `T`.
- No `ServerWebExchange` / `ServerHttpRequest` in services; read headers in the controller (`@RequestHeader`) or a
  `WebFilter`.
- Cross-cutting HTTP concerns (logging, correlation ID, auth headers) in a `WebFilter`.
- Request body size limit: `spring.codec.max-in-memory-size` set deliberately (default 256 KB).
- Problem Details: extend `org.springframework.web.reactive.result.method.annotation.ResponseEntityExceptionHandler`
  (the reactive one, not the MVC class) in the `@RestControllerAdvice`.

### W-3.1 Annotated controllers vs functional endpoints

```java
// A: annotated
@RestController
@RequestMapping("/api/v1/orders")
@RequiredArgsConstructor
public class OrderController {
    private final OrderService orderService;

    @GetMapping("/{orderId}")
    public Mono<OrderResponse> get(@PathVariable Long orderId) {
        return orderService.get(orderId);
    }
}

// B: functional
@Bean
RouterFunction<ServerResponse> orderRoutes(OrderHandler handler) {
    return route()
            .GET("/api/v1/orders/{orderId}", handler::get)
            .build();
}
```

- [ ] **A: annotated controllers** *(recommended)*: same model as the MVC services, `@Valid`, springdoc and
  `@RestControllerAdvice` work out of the box.
- [ ] **B: functional `RouterFunction` + handler classes**.
- [ ] **C: annotated by default, functional only for small internal endpoints**.

**Decision:** ____

### W-3.2 Request body type

```java
// A
@PostMapping
@ResponseStatus(HttpStatus.CREATED)
public Mono<OrderResponse> create(@Valid @RequestBody CreateOrderRequest request) { ... }

// B
@PostMapping
@ResponseStatus(HttpStatus.CREATED)
public Mono<OrderResponse> create(@Valid @RequestBody Mono<CreateOrderRequest> request) { ... }
```

- [ ] **A: plain DTO parameter: WebFlux reads and validates the body before calling the method** *(recommended)*.
- [ ] **B: `Mono<DTO>` parameter**: validation errors become an error signal in the pipeline.

**Decision:** ____

### W-3.3 Response type and 404

```java
// A: empty → exception → advice maps to 404
public Mono<OrderResponse> get(@PathVariable Long orderId) {
    return orderService.get(orderId);   // service: switchIfEmpty(Mono.error(() -> new OrderNotFoundException(orderId)))
}

// B: ResponseEntity in the controller
public Mono<ResponseEntity<OrderResponse>> get(@PathVariable Long orderId) {
    return orderService.find(orderId)
            .map(ResponseEntity::ok)
            .defaultIfEmpty(ResponseEntity.notFound().build());
}
```

- [ ] **A: `Mono<T>` + `@ResponseStatus`; not found is an exception mapped by the advice** *(recommended)*: same
  error body everywhere (C-9.3). Note: an empty `Mono<T>` without this returns `200` with no body.
- [ ] **B: `Mono<ResponseEntity<T>>`**.

**Decision:** ____

### W-3.4 Streaming responses

- [ ] **A: `Flux<T>` as a JSON array by default; `application/x-ndjson` or `text/event-stream` (SSE) only for
  endpoints agreed to stream** *(recommended)*.
- [ ] **B: no streaming endpoints**.

**Decision:** ____

---

## W-4 Outgoing HTTP calls (WebClient)

### W-4.1 Client technology

```java
// A: HTTP interface client backed by WebClient
@HttpExchange("/payments")
public interface PaymentApi {
    @GetExchange("/{paymentId}")
    Mono<PaymentProviderResponse> get(@PathVariable String paymentId);
}

// B: WebClient in a client class
@Component
public class PaymentClient {
    private final WebClient webClient;

    public Mono<PaymentProviderResponse> get(String paymentId) {
        return webClient.get()
                .uri("/payments/{paymentId}", paymentId)
                .retrieve()
                .onStatus(status -> status.value() == 404,
                        response -> Mono.error(new PaymentNotFoundException(paymentId)))
                .bodyToMono(PaymentProviderResponse.class);
    }
}
```

- [ ] **A: HTTP interfaces (`@HttpExchange`) with reactive return types, registered with Spring Boot 4's HTTP service
  client support and backed by `WebClient`; wrapped by our client class when error mapping is needed**
  *(recommended)*.
- [ ] **B: `WebClient` built from the auto-configured `WebClient.Builder`, one client class per external service**.

Fixed:

- Build clients once in a `@Configuration` from the injected `WebClient.Builder` (keeps codecs, tracing and metrics),
  base URL and timeouts from `@ConfigurationProperties`. Never `WebClient.create()` inside a business method.
- `retrieve()` by default. `exchangeToMono` / `exchangeToFlux` only when the status decides the body type; always
  consume or release the body. Never `exchange()`.
- Map errors in the client class (`onStatus`, `onErrorMap`); services never see `WebClientResponseException` /
  `WebClientRequestException`.

**Decision:** ____

### W-4.2 Timeouts and connection pool

```java
HttpClient httpClient = HttpClient.create(ConnectionProvider.builder("payment")
                .maxConnections(50)
                .pendingAcquireTimeout(Duration.ofSeconds(2))
                .build())
        .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, (int) properties.connectTimeout().toMillis())
        .responseTimeout(properties.readTimeout());

WebClient webClient = builder
        .baseUrl(properties.baseUrl().toString())
        .clientConnector(new ReactorClientHttpConnector(httpClient))
        .build();
```

Fixed: connect timeout and response timeout per external service; a named connection pool per external service
with a pending-acquire timeout.

---

## W-5 Spring Data R2DBC

Fixed:

- R2DBC is not JPA: no lazy loading, no `@OneToMany` / `@ManyToOne`, no cascades, no persistence context and no
  dirty checking. One entity maps one table. Children are loaded and saved explicitly (W-5.5), in one transaction.
- Mapping annotations come from Spring Data: `org.springframework.data.annotation.Id`, `@Version`, `@CreatedDate`,
  `org.springframework.data.relational.core.mapping.Table` / `Column`. Never `jakarta.persistence.*`.
- `save(entity)` inserts when the `@Id` is `null` (or `@Version` is `null`) and updates otherwise. An entity whose ID
  is set by our code (e.g. a UUID) is treated as existing: the `UPDATE` matches no row and fails. For app-assigned
  IDs implement `Persistable<ID>` (`isNew()`) or use `R2dbcEntityTemplate.insert(...)`.
- Every call to `save` writes; there is no automatic flush of changed objects. Save what you changed and use the
  returned instance (it carries the generated ID and the new version).
- Enums are stored as their `name()` string by default. Database enum types (PostgreSQL `CREATE TYPE`) need an
  explicit converter / codec.
- Custom types (value objects, JSON columns) through `R2dbcCustomConversions` (`@ReadingConverter` /
  `@WritingConverter`).
- N+1: loading children with a `flatMap` per parent runs one query per parent. Load the children of all parents in one
  query (`WHERE order_id IN (:orderIds)`) and group them in memory.
- `saveAll` sends one statement per row. For large imports use `DatabaseClient` batches or the database's bulk
  load (`COPY`) and ask first.
- Concurrency to the database stays below `spring.r2dbc.pool.max-size` (W-2.3).

### W-5.1 Entity style

```java
// A: record + Lombok @With for generated values
@Table("orders")
public record Order(
        @Id @With Long id,
        String number,
        Long customerId,
        OrderStatus status,
        BigDecimal total,
        @Version @With Long version,
        @CreatedDate Instant createdAt) {
}

// B: mutable class
@Table("orders")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class Order {
    @Id
    private Long id;
    ...
}
```

- [ ] **A: immutable records, `@With` on fields set by Spring Data (`id`, `version`, audit fields)** *(recommended)*:
  matches the functional style of Reactor pipelines.
- [ ] **B: mutable classes with Lombok getters/setters**.

**Decision:** ____

### W-5.2 IDs

- [ ] **A: database-generated `Long` (`BIGINT GENERATED ALWAYS AS IDENTITY` / `BIGSERIAL`)** *(recommended)*:
  `save` decides insert vs update correctly with no extra code.
- [ ] **B: `UUID` generated by the database default (`DEFAULT gen_random_uuid()` or `uuidv7()` on PostgreSQL 18)**:
  ID stays `null` until insert, same simplicity as A.
- [ ] **C: `UUID` generated by our code + `Persistable<UUID>`**: the ID exists before saving (useful for events and
  idempotency keys).

**Decision:** ____

### W-5.3 Repository base interface

- [ ] **A: `R2dbcRepository<T, ID>`** *(recommended)*.
- [ ] **B: `ReactiveCrudRepository<T, ID>` (+ `ReactiveSortingRepository`)**.

**Decision:** ____

### W-5.4 Query style

```java
// derived
Flux<Order> findAllByCustomerIdAndStatus(Long customerId, OrderStatus status);

// @Query: native SQL (R2DBC has no JPQL)
@Query("""
        SELECT * FROM orders
        WHERE customer_id = :customerId AND status IN (:statuses)
        ORDER BY created_at DESC
        """)
Flux<Order> findRecent(Long customerId, Collection<OrderStatus> statuses);

// dynamic criteria
template.select(Order.class)
        .matching(query(where("customer_id").is(customerId).and("status").in(statuses)).limit(50))
        .all();

// joins / custom mapping
databaseClient.sql("SELECT o.id, o.number, c.name FROM orders o JOIN customers c ON c.id = o.customer_id WHERE o.id = :id")
        .bind("id", orderId)
        .map((row, metadata) -> new OrderWithCustomer(row.get("id", Long.class), row.get("number", String.class),
                row.get("name", String.class)))
        .one();
```

- [ ] **A: derived queries up to 2 conditions; `@Query` SQL for the rest; `R2dbcEntityTemplate` criteria for dynamic
  filters; `DatabaseClient` for joins and custom mapping** *(recommended)*.
- [ ] **B: `@Query` for everything except `findById`**.
- [ ] **C: jOOQ with R2DBC for complex / dynamic queries**.

Fixed: named parameters (`:customerId`) always, never string concatenation; `SELECT *` only when mapping to the
entity, explicit columns for projections.

**Decision:** ____

### W-5.5 Aggregates with child rows (order + lines)

```java
// A: two queries, assembled in the service
public Mono<OrderWithLines> get(Long orderId) {
    return orderRepository.findById(orderId)
            .switchIfEmpty(Mono.error(() -> new OrderNotFoundException(orderId)))
            .zipWith(orderLineRepository.findAllByOrderId(orderId).collectList(), OrderWithLines::new);
}

@Transactional
public Mono<OrderWithLines> create(CreateOrderRequest request) {
    return orderRepository.save(orderMapper.toEntity(request))
            .flatMap(order -> orderLineRepository.saveAll(orderMapper.toLines(request.lines(), order.id()))
                    .collectList()
                    .map(lines -> new OrderWithLines(order, lines)));
}
```

- [ ] **A: one repository per table; the service loads/saves the parent and the children explicitly and assembles a
  record** *(recommended)*.
- [ ] **B: one `DatabaseClient` join query, rows grouped into the aggregate in a custom repository**.
- [ ] **C: keep children in a JSON column (`jsonb`) of the parent when they are never queried on their own**.

**Decision:** ____

### W-5.6 Transactions

```java
// A
@Transactional
public Mono<OrderResponse> create(CreateOrderRequest request) { ... }

// B
public Mono<OrderResponse> create(CreateOrderRequest request) {
    return doCreate(request).as(transactionalOperator::transactional);
}
```

- [ ] **A: `@Transactional` on service methods returning `Mono` / `Flux`** *(recommended)*: same as the MVC services.
- [ ] **B: `TransactionalOperator`** when the transaction must cover only part of a pipeline.

Fixed:

- The transaction lives in the Reactor `Context` of the subscription, not on a thread. It covers only the publisher
  returned by the method; work started outside it (a separate `subscribe()`, W-2.12) is not part of it.
- Same proxy rules as Spring MVC: public methods called from another bean; no self-invocation.
- No HTTP calls or message sends inside a transaction (they hold a pooled connection and cannot roll back); do them
  before, or after the transactional publisher completes.
- Rollback happens on an error signal; an error turned into a value with `onErrorResume` inside the transaction
  commits.

**Decision:** ____

### W-5.7 Optimistic locking and auditing

- [ ] **A: `@Version` on every aggregate root; `OptimisticLockingFailureException` → `409`; `@EnableR2dbcAuditing`
  with `@CreatedDate` / `@LastModifiedDate` (and a `ReactiveAuditorAware` for `@CreatedBy`)** *(recommended)*.
- [ ] **B: `@Version` only where concurrent updates happen; audit columns set by the service from the `Clock`**.

**Decision:** ____

### W-5.8 Pagination

```java
Flux<Order> findAllByCustomerId(Long customerId, Pageable pageable);
Mono<Long> countByCustomerId(Long customerId);

// service
public Mono<PagedModel<OrderResponse>> page(Long customerId, Pageable pageable) {
    return orderRepository.findAllByCustomerId(customerId, pageable)
            .map(orderMapper::toResponse)
            .collectList()
            .zipWith(orderRepository.countByCustomerId(customerId),
                    (content, total) -> new PagedModel<>(new PageImpl<>(content, pageable, total)));
}

// controller: Spring Boot does not resolve Pageable parameters in WebFlux
@GetMapping
public Mono<PagedModel<OrderResponse>> list(
        @RequestParam Long customerId,
        @RequestParam(defaultValue = "0") @PositiveOrZero int page,
        @RequestParam(defaultValue = "20") @Positive @Max(100) int size) {
    return orderService.page(customerId, PageRequest.of(page, size, Sort.by("createdAt").descending()));
}
```

- [ ] **A: offset pagination as above (derived query with `Pageable` + count query), `PagedModel` response with the
  same JSON as C-12.3 A; `page` / `size` read as `@RequestParam` and turned into a `PageRequest`** *(recommended)*.
- [ ] **B: keyset pagination (`WHERE id > :after ORDER BY id LIMIT :size`)** for large tables / infinite scroll.

**Decision:** ____

---

## W-6 Schema migrations

Fixed:

- Flyway and Liquibase use JDBC. The service has the JDBC driver at runtime **only** for migrations, and the
  migration tool gets its own connection settings (`spring.flyway.url`, `user`, `password`, or the Liquibase
  equivalents), because Spring Boot does not derive them from `spring.r2dbc.url`.
- Every schema change is a migration in the repo. Never edit or delete a migration that ran in any shared
  environment; add a new one.
- Migrations are backward compatible with the previous app version (expand, deploy, contract).

### W-6.1 Migration tool

- [ ] **A: Flyway, plain SQL** *(recommended)*.
- [ ] **B: Liquibase**.

**Decision:** ____

### W-6.2 Flyway file names

- [ ] **A: timestamp version `V2026_10_24_1030__add_order_status.sql`** *(recommended)*.
- [ ] **B: sequential `V12__add_order_status.sql`**.

**Decision:** ____

---

## W-7 JSON (Jackson)

Fixed:

- Spring Boot 4 uses Jackson 3 by default (`tools.jackson.*`, annotations still `com.fasterxml.jackson.annotation`).
  Match what the repo imports; do not mix Jackson 2 and 3 mapper types.
- Customise the auto-configured mapper (`spring.jackson.*`, builder customizer) and the WebFlux codecs
  (`CodecCustomizer`); never a second mapper with `new` in production code.

### W-7.1 `null` fields in responses

- [ ] **A: omit nulls (`spring.jackson.default-property-inclusion=non_null`)** *(recommended)*.
- [ ] **B: always write every field, `null` included**.

**Decision:** ____

---

## W-8 Tests for this stack

The general test and WireMock rules are in C-15 and C-16. This section adds the reactive specifics.

Fixed:

- Spring Boot 4 split test slices into modules (`spring-boot-webflux-test`, `spring-boot-data-r2dbc-test`, …) and
  moved the annotations to new packages. Copy imports from the existing tests in the repo.
- Mock beans with `@MockitoBean` (C-15.14).

### W-8.1 Asserting `Mono` / `Flux`: StepVerifier

```java
@Test
void returnsOrder() {
    when(orderRepository.findById(42L)).thenReturn(Mono.just(OrderFixtures.paidOrder().id(42L).build()));

    StepVerifier.create(orderService.get(42L))
            .assertNext(order -> assertThat(order.number()).isEqualTo("ORD-42"))
            .verifyComplete();
}

@Test
void failsWhenOrderDoesNotExist() {
    when(orderRepository.findById(42L)).thenReturn(Mono.empty());

    StepVerifier.create(orderService.get(42L))
            .expectErrorSatisfies(error -> assertThat(error)
                    .isInstanceOf(OrderNotFoundException.class)
                    .hasMessageContaining("42"))
            .verify();
}

@Test
void returnsNothingForCustomerWithoutOrders() {
    when(orderRepository.findAllByCustomerId(7L)).thenReturn(Flux.empty());

    StepVerifier.create(orderService.findByCustomer(7L))
            .verifyComplete();
}
```

Fixed:

- Every reactive result is asserted with `StepVerifier`.
- A `StepVerifier` does nothing until a `verify...()` call: every chain ends with `verify()`, `verifyComplete()`,
  `verifyError(...)` or `verifyErrorSatisfies(...)`. A chain without it passes without running the code.
- Assert the terminal signal too: `verifyComplete()` for success, an error expectation for failures. Check emptiness
  with `StepVerifier.create(mono).verifyComplete()`, not `expectNextCount(0)` alone.
- Use AssertJ inside `assertNext` / `expectErrorSatisfies` / `consumeNextWith` (C-15.9).

- [ ] **A: `assertNext(x -> assertThat(...))` for objects; `expectNext(value)` only for simple values and records
  with meaningful `equals`** *(recommended)*.
- [ ] **B: always `assertNext` + AssertJ**.
- [ ] **C: `expectNext(expected)` with full expected objects**.

**Decision:** ____

### W-8.2 `.block()` in tests

- [ ] **A: never in assertions; allowed in test setup and cleanup only (`repository.saveAll(fixtures).blockLast()`,
  `deleteAll().block()`)** *(recommended)*.
- [ ] **B: never, also not in setup: chain setup into the verified publisher or use `StepVerifier` for setup
  too**.
- [ ] **C: `.block()` allowed in assertions for simple single-value cases**.

**Decision:** ____

### W-8.3 Time-based behaviour (delays, retries with backoff, timeouts)

```java
@Test
void retriesThreeTimesWithBackoff() {
    when(paymentApi.get("p-1"))
            .thenReturn(Mono.error(new PaymentProviderUnavailableException()));

    StepVerifier.withVirtualTime(() -> paymentClient.get("p-1"))
            .thenAwait(Duration.ofSeconds(10))
            .verifyError(PaymentProviderUnavailableException.class);
}
```

Fixed:

- Use `StepVerifier.withVirtualTime(() -> ...)` for unit tests of delays, `interval`, backoff and `timeout`. The
  publisher must be **created inside** the supplier, otherwise virtual time is not used.
- Virtual time does not work with real I/O: in WireMock tests (W-8.7) use short real timeouts / backoffs from the
  test configuration instead.
- Add a default timeout so a hanging publisher fails instead of blocking the build: `.verify(Duration.ofSeconds(5))`
  or `StepVerifier.setDefaultTimeout(...)` in a shared extension.

### W-8.4 Mockito with reactive types

Fixed:

- Stub every reactive method the code under test calls: an unstubbed method returning `Mono` / `Flux` returns `null`
  and the test fails with a `NullPointerException` far from the cause. Return `Mono.empty()` / `Flux.empty()`
  explicitly for "nothing".
- `verify(mock).method()` only proves the method was **called**, not that the returned `Mono` was subscribed (the
  work never happens if nobody subscribes). To prove the side effect, use a `PublisherProbe`:

```java
PublisherProbe<Void> published = PublisherProbe.empty();
when(eventPublisher.publish(any(OrderPaid.class))).thenReturn(published.mono());

StepVerifier.create(orderService.markPaid(42L)).expectNextCount(1).verifyComplete();

published.assertWasSubscribed();
```

- Stubs return fresh, lazy publishers (`Mono.just(x)`, `Mono.fromCallable(...)`); for "called twice returns
  different values" use `thenReturn(first, second)`.

### W-8.5 Controller tests

```java
@WebFluxTest(OrderController.class)
class OrderControllerTest {

    @Autowired
    private WebTestClient webTestClient;

    @MockitoBean
    private OrderService orderService;

    @Test
    void returnsOrder() {
        when(orderService.get(42L)).thenReturn(Mono.just(new OrderResponse(42L, "ORD-42", new BigDecimal("49.90"))));

        webTestClient.get().uri("/api/v1/orders/{id}", 42)
                .exchange()
                .expectStatus().isOk()
                .expectBody(OrderResponse.class)
                .value(order -> assertThat(order.number()).isEqualTo("ORD-42"));
    }

    @Test
    void returns404WhenOrderDoesNotExist() {
        when(orderService.get(42L)).thenReturn(Mono.error(new OrderNotFoundException(42L)));

        webTestClient.get().uri("/api/v1/orders/{id}", 42)
                .exchange()
                .expectStatus().isNotFound()
                .expectBody()
                .jsonPath("$.code").isEqualTo("ORDER_NOT_FOUND");
    }
}
```

- [ ] **A: `@WebFluxTest` + `WebTestClient`; assertions on bodies with `.value(x -> assertThat(...))` or a full
  JSON comparison (`expectBody().json("""...""")`)** *(recommended)*.
- [ ] **B: `WebTestClient.bindToController(...)` without a Spring context** (faster, but the advice, validation and
  codecs must be wired by hand).

Fixed: controller tests cover mapping, validation, status codes, JSON shape and exception mapping; business logic is
in service unit tests.

**Decision:** ____

### W-8.6 Repository tests

```java
@DataR2dbcTest
@Import(TestcontainersConfiguration.class)   // @ServiceConnection PostgreSQLContainer
class OrderRepositoryTest {

    @Autowired
    private OrderRepository orderRepository;

    @BeforeEach
    void cleanUp() {
        orderRepository.deleteAll().block();
    }

    @Test
    void findsRecentOrdersOfCustomer() {
        orderRepository.saveAll(List.of(OrderFixtures.paidOrder().customerId(7L).build())).blockLast();

        StepVerifier.create(orderRepository.findRecent(7L, List.of(OrderStatus.PAID)))
                .assertNext(order -> assertThat(order.customerId()).isEqualTo(7L))
                .verifyComplete();
    }
}
```

Fixed:

- Test `@Query` SQL, derived queries with non-trivial conditions, custom converters, `Persistable` insert logic and
  `@Version` behaviour. Do not test inherited `save` / `findById`.
- Spring's test framework does not roll back reactive transactions after each test: clean the tables yourself
  (`deleteAll()`, or `DatabaseClient` `TRUNCATE ... CASCADE`) in `@BeforeEach`.
- The schema in tests comes from the real migrations (W-6). Check that the migrations run against the test database
  (with R2DBC they need the JDBC connection too).

- [ ] **A: `@DataR2dbcTest` + Testcontainers with the production database** *(recommended, see C-15.15)*.
- [ ] **B: `@DataR2dbcTest` + H2 via `r2dbc-h2`**: native SQL differences make this risky with `@Query`.

**Decision:** ____

### W-8.7 HTTP client tests (WireMock + WebClient)

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
        paymentClient = new PaymentClientConfiguration().paymentClient(WebClient.builder(), properties);
    }

    @Test
    void returnsCapturedPayment() {
        wireMock.stubFor(get(urlPathEqualTo("/payments/p-1"))
                .willReturn(okJson("""
                        {"id": "p-1", "status": "CAPTURED", "amount": "49.90"}
                        """)));

        StepVerifier.create(paymentClient.get("p-1"))
                .assertNext(payment -> {
                    assertThat(payment.status()).isEqualTo(PaymentStatus.CAPTURED);
                    assertThat(payment.amount()).isEqualByComparingTo("49.90");
                })
                .verifyComplete();
    }

    @Test
    void mapsNotFoundToPaymentNotFoundException() {
        wireMock.stubFor(get(urlPathEqualTo("/payments/p-404")).willReturn(notFound()));

        StepVerifier.create(paymentClient.get("p-404"))
                .verifyError(PaymentNotFoundException.class);
    }

    @Test
    void failsWhenProviderIsSlowerThanResponseTimeout() {
        wireMock.stubFor(get(urlPathEqualTo("/payments/p-1"))
                .willReturn(okJson("{}").withFixedDelay(1_000)));

        StepVerifier.create(paymentClient.get("p-1"))
                .verifyError(PaymentProviderUnavailableException.class);
    }
}
```

Fixed: the client under test is built exactly like production (same configuration class, same `HttpClient`
timeouts), only the base URL points at WireMock. Retries are tested with WireMock scenarios and a `verify` of the
call count (C-16.6), with backoffs of a few milliseconds from the test properties.

### W-8.8 Detecting blocking calls

- [ ] **A: BlockHound in tests (`io.projectreactor.tools:blockhound` + `blockhound-junit-platform`); on Java 21 the
  test JVM needs `-XX:+AllowRedefinitionToAddDeleteMethods` in the Surefire / Failsafe `argLine`)**
  *(recommended)*: fails the test when code blocks on a Reactor thread.
- [ ] **B: no BlockHound; review only**.

**Decision:** ____

### W-8.9 Integration tests

- [ ] **A: `@SpringBootTest(webEnvironment = RANDOM_PORT)` + `WebTestClient`, Testcontainers database, WireMock for
  every external service (C-16.2 C or D)** *(recommended)*.
- [ ] **B: `@SpringBootTest` + `@AutoConfigureWebTestClient` against a mock server (no real port)**.

Fixed: clean the data between tests (no automatic rollback, W-8.6).

**Decision:** ____
