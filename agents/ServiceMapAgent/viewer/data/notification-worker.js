SERVICE_MAP.repo({
  repo: "notification-worker", commit: "e09a4b2", mapped: "2026-10-23",
  services: [{
    id: "notification-worker", layer: "Workers",
    purpose: "Sends customer emails when orders and payments change. No HTTP endpoints.",
    tech: "Java 21, Spring Cloud Function",
    runtime: "AWS Lambda with an MSK trigger", terraform: "platform-infra/services/notifications.tf:1",
    pipeline: { workflow: "deploy-notifications.yml", pr: "build, tests", merge: "deploy to dev, then test", prod: "manual approval" },
    endpoints: [],
    entry_points: [
      { kind: "Kafka listener", name: "order-events", does: "OrderPlaced sends the confirmation; OrderCancelled sends the cancellation and refund notice.", ref: "notification-worker/src/main/java/shop/notify/OrderMails.java:20" },
      { kind: "Kafka listener", name: "payment-events", does: "PaymentFailed asks the customer to update their card.", ref: "notification-worker/src/main/java/shop/notify/PaymentMails.java:18" },
    ],
    calls: [
      { from: "order-events listener", to: "email-provider", endpoint: "POST /v3/mail/send", kind: "HTTP", on_failure: "3 retries, then the notifications-dlt topic", external: true },
    ],
    consumes: [{ topic: "order-events", events: ["OrderPlaced", "OrderCancelled"] }, { topic: "payment-events", events: ["PaymentFailed"] }],
    tables: [],
  }],
});
