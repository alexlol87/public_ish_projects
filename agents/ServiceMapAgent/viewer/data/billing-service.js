SERVICE_MAP.repo({
  repo: "billing-service", commit: "c72be90", mapped: "2026-10-23",
  services: [{
    id: "billing-service", layer: "Domain",
    purpose: "Takes payments and refunds through the external payment provider.",
    tech: "Java 21, Spring Boot 3.4, RestClient",
    runtime: "ECS Fargate, 2 tasks, internal only", terraform: "platform-infra/services/billing.tf:1",
    pipeline: { workflow: "deploy-billing.yml", pr: "build, tests", merge: "deploy to dev, then test", prod: "manual approval" },
    database: "billing-db",
    notes: [
      { level: "risk", text: "The payment provider timeout is 30 s, longer than the gateway's 10 s: a slow payment shows the customer an error while the charge may still succeed.", ref: "billing-service/src/main/resources/application.yml:22" },
    ],
    endpoints: [
      { method: "POST", path: "/payments", purpose: "Charge for an order", use_when: "Charging a customer for an order. Idempotent per orderId, so it is safe to call again after a timeout.", auth: "service token", ref: "billing-service/src/main/java/shop/billing/PaymentController.java:29" },
      { method: "POST", path: "/refunds", purpose: "Full refund", use_when: "Giving all the money back for a cancelled order.", dont_confuse: "POST /refunds/partial, for returns of some order lines.", auth: "service token", ref: "billing-service/src/main/java/shop/billing/RefundController.java:25" },
      { method: "POST", path: "/refunds/partial", purpose: "Partial refund", use_when: "Refunding some order lines after a return.", auth: "service token", ref: "billing-service/src/main/java/shop/billing/RefundController.java:44", question: "No caller found in the mapped repositories." },
      { method: "GET", path: "/payments/{id}", purpose: "Payment status", use_when: "Support checking a payment's status at the provider.", auth: "ROLE_SUPPORT", ref: "billing-service/src/main/java/shop/billing/PaymentController.java:51", question: "No caller found; probably the support tool." },
    ],
    calls: [
      { from: "POST /payments", to: "payment-provider", endpoint: "POST /v2/charges", kind: "HTTP (RestClient)", on_failure: "30 s timeout", external: true },
      { from: "POST /refunds", to: "payment-provider", endpoint: "POST /v2/refunds", kind: "HTTP (RestClient)", on_failure: "30 s timeout", external: true },
    ],
    produces: [{ topic: "payment-events", events: ["PaymentFailed", "RefundCompleted"] }],
    tables: [
      { name: "payments", written_by: ["POST /payments"], read_by: ["GET /payments/{id}"] },
      { name: "refunds", written_by: ["POST /refunds", "POST /refunds/partial"], read_by: [] },
    ],
  }],
});
