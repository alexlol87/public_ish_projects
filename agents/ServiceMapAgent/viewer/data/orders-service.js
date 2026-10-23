SERVICE_MAP.repo({
  repo: "orders-service", commit: "3f2a9c1", mapped: "2026-10-23",
  services: [{
    id: "orders-service", layer: "Domain",
    purpose: "Owns orders, from the basket being checked out to delivery or cancellation.",
    tech: "Java 21, Spring Boot 3.4, Spring Data JPA, OpenFeign, Spring Kafka, Resilience4j",
    runtime: "ECS Fargate, 2 to 4 tasks", terraform: "platform-infra/services/orders.tf:1",
    pipeline: { workflow: "deploy-orders.yml", pr: "build, tests, Testcontainers", merge: "deploy to dev, then test", prod: "manual approval" },
    database: "orders-db",
    notes: [
      { level: "risk", text: "Cancelling calls billing inside the database transaction, so a slow refund holds the order's row lock.", ref: "orders-service/src/main/java/shop/orders/OrderService.java:88" },
      { level: "warn", text: "Releasing the reservation on cancel only logs a failure; the stock stays held until the reservation expires (15 minutes).", ref: "orders-service/src/main/java/shop/orders/OrderService.java:97" },
      { level: "info", text: "Events go out through an outbox table, so an event is sent only if the order was saved.", ref: "orders-service/src/main/java/shop/orders/OutboxRelay.java:27" },
    ],
    endpoints: [
      {
        method: "POST", path: "/orders", purpose: "Check out a basket",
        use_when: "A customer checks out a basket. In one call it holds the stock, takes the payment and creates the order.",
        dont_confuse: "POST /stock/reservations in inventory-service, which only holds stock and creates no order.",
        auth: "ROLE_CUSTOMER", ref: "orders-service/src/main/java/shop/orders/OrderController.java:52",
        flow: {
          diagram: `sequenceDiagram
  participant C as api-gateway
  participant OC as OrderController
  participant OS as OrderService
  participant I as inventory-service
  participant B as billing-service
  participant DB as orders-db
  participant K as order-events
  C->>OC: POST /orders {customerId, lines[]}
  OC->>OS: place(request)
  OS->>I: POST /stock/reservations
  alt out of stock
    I-->>OS: 409
    OC-->>C: 409 OUT_OF_STOCK
  end
  OS->>B: POST /payments {orderId, amount}
  alt declined or billing down
    B-->>OS: 402 / circuit open
    OS->>I: DELETE /stock/reservations/{id}
    OC-->>C: 402 / 503
  end
  rect rgb(239,238,229)
  note over OS,DB: @Transactional
  OS->>DB: INSERT orders, order_lines
  OS->>DB: INSERT outbox (OrderPlaced)
  end
  OS-)K: OrderPlaced (outbox relay)
  OC-->>C: 201 Created {orderId}`,
          steps: [
            { text: "OrderController.create validates the body (@Valid CreateOrderRequest)", ref: "orders-service/src/main/java/shop/orders/OrderController.java:52" },
            { text: "OrderService.place starts the checkout", ref: "orders-service/src/main/java/shop/orders/OrderService.java:40" },
            { text: "Hold the stock: InventoryClient.reserve calls inventory-service POST /stock/reservations", ref: "orders-service/src/main/java/shop/orders/InventoryClient.java:18" },
            { text: "Charge: BillingClient.charge calls billing-service POST /payments, behind the Resilience4j 'billing' circuit breaker", ref: "orders-service/src/main/java/shop/orders/OrderService.java:51" },
            { text: "Save the order, its lines and the outbox row in one transaction", ref: "orders-service/src/main/java/shop/orders/OrderService.java:60" },
            { text: "OutboxRelay publishes OrderPlaced to order-events", ref: "orders-service/src/main/java/shop/orders/OutboxRelay.java:27" },
          ],
          errors: [
            { when: "No lines, or a quantity below 1", status: 400, code: "VALIDATION_FAILED" },
            { when: "A SKU is out of stock", status: 409, code: "OUT_OF_STOCK" },
            { when: "Payment declined", status: 402, code: "PAYMENT_DECLINED" },
            { when: "billing-service unavailable", status: 503, code: "BILLING_UNAVAILABLE" },
          ],
          changes: "Rows in orders, order_lines and outbox; a reservation in inventory; a payment in billing; the OrderPlaced event, which sends the confirmation email.",
        },
      },
      { method: "GET", path: "/orders/{id}", purpose: "One order", use_when: "Showing one order with its lines and status.", auth: "owner or ROLE_SUPPORT", ref: "orders-service/src/main/java/shop/orders/OrderController.java:41" },
      { method: "GET", path: "/orders", purpose: "A customer's orders", use_when: "Listing a customer's orders, newest first, paged.", auth: "ROLE_CUSTOMER", ref: "orders-service/src/main/java/shop/orders/OrderController.java:35" },
      {
        method: "POST", path: "/orders/{id}/cancel", purpose: "Cancel an order",
        use_when: "A customer or support cancels an order that hasn't shipped yet. Refunds the full amount and frees the stock.",
        dont_confuse: "Returns after delivery, which go through billing-service POST /refunds/partial.",
        auth: "owner or ROLE_SUPPORT", ref: "orders-service/src/main/java/shop/orders/OrderController.java:58",
        flow: {
          diagram: `sequenceDiagram
  participant C as api-gateway
  participant OS as OrderService
  participant DB as orders-db
  participant B as billing-service
  participant I as inventory-service
  participant K as order-events
  C->>OS: POST /orders/{id}/cancel
  rect rgb(239,238,229)
  note over OS,DB: @Transactional
  OS->>DB: SELECT orders WHERE id = ? FOR UPDATE
  alt not the owner and not support
    OS-->>C: 403
  else shipped or delivered
    OS-->>C: 409 ORDER_ALREADY_SHIPPED
  else
    OS->>B: POST /refunds
    alt refund failed
      OS->>DB: UPDATE orders SET status = CANCEL_PENDING
    else
      OS->>DB: UPDATE orders SET status = CANCELLED
    end
    OS->>DB: INSERT outbox (OrderCancelled)
  end
  end
  OS->>I: DELETE /stock/reservations/{id}
  OS-)K: OrderCancelled
  OS-->>C: 200 {status}`,
          steps: [
            { text: "OrderController.cancel", ref: "orders-service/src/main/java/shop/orders/OrderController.java:58" },
            { text: "Load and lock the order; check owner or ROLE_SUPPORT", ref: "orders-service/src/main/java/shop/orders/OrderService.java:80" },
            { text: "Refuse when shipped or delivered", ref: "orders-service/src/main/java/shop/orders/OrderService.java:84" },
            { text: "Refund through billing, inside the transaction", ref: "orders-service/src/main/java/shop/orders/OrderService.java:88" },
            { text: "Free the stock; a failure is only logged", ref: "orders-service/src/main/java/shop/orders/OrderService.java:97" },
          ],
          errors: [
            { when: "Not the owner and not support", status: 403, code: "FORBIDDEN" },
            { when: "Unknown id", status: 404, code: "ORDER_NOT_FOUND" },
            { when: "Already shipped or delivered", status: 409, code: "ORDER_ALREADY_SHIPPED" },
          ],
          changes: "orders.status becomes CANCELLED (or CANCEL_PENDING when the refund failed; RefundRetryJob retries it), a refund in billing, the reservation is freed, and the OrderCancelled event sends the cancellation email.",
        },
      },
    ],
    entry_points: [
      { kind: "Kafka listener", name: "ShipmentListener", does: "Sets the order DELIVERED on ShipmentDelivered.", ref: "orders-service/src/main/java/shop/orders/ShipmentListener.java:17" },
      { kind: "Scheduled", name: "RefundRetryJob", does: "Every 5 minutes, retries the refunds of CANCEL_PENDING orders.", ref: "orders-service/src/main/java/shop/orders/RefundRetryJob.java:14" },
    ],
    calls: [
      { from: "POST /orders", to: "inventory-service", endpoint: "POST /stock/reservations", kind: "HTTP (Feign)", on_failure: "2 retries, then 503" },
      { from: "POST /orders", to: "billing-service", endpoint: "POST /payments", kind: "HTTP (Feign)", on_failure: "Circuit breaker; the reservation is released" },
      { from: "POST /orders/{id}/cancel", to: "billing-service", endpoint: "POST /refunds", kind: "HTTP (Feign)", on_failure: "Order stays CANCEL_PENDING, RefundRetryJob retries" },
      { from: "POST /orders/{id}/cancel", to: "inventory-service", endpoint: "DELETE /stock/reservations/{id}", kind: "HTTP (Feign)", on_failure: "Logged only; stock held until expiry" },
    ],
    produces: [{ topic: "order-events", events: ["OrderPlaced"], from: ["POST /orders"] }, { topic: "order-events", events: ["OrderCancelled"], from: ["POST /orders/{id}/cancel"] }],
    consumes: [{ topic: "shipment-events", events: ["ShipmentDelivered"], handler: "ShipmentListener", question: "No producer in the mapped repositories; probably the external warehouse." }],
    tables: [
      { name: "orders", written_by: ["POST /orders", "POST /orders/{id}/cancel", "ShipmentListener"], read_by: ["GET /orders", "GET /orders/{id}"] },
      { name: "order_lines", written_by: ["POST /orders"], read_by: ["GET /orders/{id}"] },
      { name: "outbox", written_by: ["POST /orders", "POST /orders/{id}/cancel"], read_by: ["OutboxRelay"] },
      { name: "refund_retries", written_by: ["RefundRetryJob"], read_by: [] },
    ],
    er: `erDiagram
  orders ||--o{ order_lines : has
  orders {
    uuid id PK
    uuid customer_id
    string status
    uuid payment_id
    uuid reservation_id
  }
  order_lines {
    uuid id PK
    uuid order_id FK
    string sku
    int quantity
  }`,
    lifecycle: `stateDiagram-v2
  [*] --> PLACED: POST /orders
  PLACED --> SHIPPED: OrderShipped
  SHIPPED --> DELIVERED: ShipmentDelivered
  PLACED --> CANCELLED: POST /orders/{id}/cancel
  PLACED --> CANCEL_PENDING: cancel, refund failed
  CANCEL_PENDING --> CANCELLED: RefundRetryJob`,
  }],
  glossary: [
    { term: "Reservation", meaning: "Stock held for an order being placed; expires after 15 minutes unless the order confirms it." },
    { term: "CANCEL_PENDING", meaning: "Order status while a refund is being retried after billing-service failed." },
    { term: "Outbox", meaning: "Table where events are saved in the same transaction as the order, then published by OutboxRelay." },
  ],
});
