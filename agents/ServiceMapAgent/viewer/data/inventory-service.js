SERVICE_MAP.repo({
  repo: "inventory-service", commit: "51d0e3a", mapped: "2026-10-23",
  services: [{
    id: "inventory-service", layer: "Domain",
    purpose: "Knows how much of each product is in stock and holds reservations for orders being placed.",
    tech: "Java 21, Spring Boot 3.4, Spring Data JPA, Spring Kafka",
    runtime: "ECS Fargate, 2 tasks", terraform: "platform-infra/services/inventory.tf:1",
    pipeline: { workflow: "deploy-inventory.yml", pr: "build, tests", merge: "deploy to dev", prod: "tag v*" },
    database: "inventory-db",
    endpoints: [
      { method: "GET", path: "/stock/{sku}", purpose: "Stock level of one product", use_when: "Showing availability on a product page.", auth: "public", ref: "inventory-service/src/main/java/shop/inventory/StockController.java:24" },
      { method: "POST", path: "/stock/reservations", purpose: "Hold stock for an order", use_when: "Holding stock while an order is being placed. The hold expires after 15 minutes unless the order confirms it.", dont_confuse: "POST /orders, which also takes the payment and creates the order.", auth: "service token", ref: "inventory-service/src/main/java/shop/inventory/ReservationController.java:31" },
      { method: "DELETE", path: "/stock/reservations/{id}", purpose: "Release a hold", use_when: "Releasing the stock of a cancelled or failed order.", auth: "service token", ref: "inventory-service/src/main/java/shop/inventory/ReservationController.java:48" },
    ],
    entry_points: [
      { kind: "Kafka listener", name: "OrderEventsListener", does: "Confirms the reservation on OrderPlaced and frees it on OrderCancelled.", ref: "inventory-service/src/main/java/shop/inventory/OrderEventsListener.java:19" },
      { kind: "Scheduled", name: "ReservationExpiryJob", does: "Every minute, frees reservations older than 15 minutes.", ref: "inventory-service/src/main/java/shop/inventory/ReservationExpiryJob.java:15" },
    ],
    calls: [],
    consumes: [{ topic: "order-events", events: ["OrderPlaced", "OrderCancelled"], handler: "OrderEventsListener" }],
    tables: [
      { name: "stock", written_by: ["OrderEventsListener"], read_by: ["GET /stock/{sku}", "POST /stock/reservations"] },
      { name: "reservations", written_by: ["POST /stock/reservations", "DELETE /stock/reservations/{id}", "OrderEventsListener"], read_by: ["ReservationExpiryJob"] },
    ],
  }],
});
