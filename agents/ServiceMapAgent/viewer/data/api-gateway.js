SERVICE_MAP.repo({
  repo: "api-gateway", commit: "8d41e07", mapped: "2026-10-23",
  services: [{
    id: "api-gateway", layer: "Edge",
    purpose: "Single public entry point (Spring Cloud Gateway). Checks the customer's JWT and routes /api/** to the domain services.",
    tech: "Java 21, Spring Cloud Gateway",
    runtime: "ECS Fargate, 2 to 6 tasks", terraform: "platform-infra/services/gateway.tf:1",
    pipeline: { workflow: "deploy-gateway.yml", pr: "build, tests", merge: "deploy to dev, then test", prod: "manual approval" },
    endpoints: [
      { method: "ANY", path: "/api/orders/**", purpose: "Route to orders-service", use_when: "Any client call about orders. Strips /api and forwards to orders-service /orders/**.", auth: "JWT", ref: "api-gateway/src/main/resources/application.yml:14" },
      { method: "ANY", path: "/api/stock/**", purpose: "Route to inventory-service", use_when: "Any client call about stock. GET /api/stock/{sku} is public.", auth: "JWT (except GET)", ref: "api-gateway/src/main/resources/application.yml:23" },
    ],
    calls: [
      { from: "ANY /api/orders/**", to: "orders-service", endpoint: "ANY /orders/**", kind: "HTTP", on_failure: "10 s timeout, 504 to the client" },
      { from: "ANY /api/stock/**", to: "inventory-service", endpoint: "ANY /stock/**", kind: "HTTP", on_failure: "10 s timeout, 504 to the client" },
    ],
    tables: [],
  }],
});
