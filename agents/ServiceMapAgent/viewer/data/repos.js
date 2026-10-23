// The map's index: system description, layers and the mapped repositories, in mapping order.
// Each repository has its own data/<repo>.js, written by the Service Mapper agent.
SERVICE_MAP.system({
  name: "Shop",
  summary: "Customers browse products, check out a basket and get emails about their order. Five repositories of code (an API gateway, three domain services and a notification worker), deployed on AWS by a Terraform repository and GitHub Actions.",
  demo: true,
  // Optional: turns code references into links. {path} is relative to the folder holding all repositories.
  codeLink: "vscode://file/Users/me/code/{path}:{line}",
  layers: [
    { id: "Edge", about: "Public entry points: authentication and routing, no business logic." },
    { id: "Domain", about: "Business services, each owning its own database." },
    { id: "Workers", about: "Event consumers with no HTTP API." },
  ],
  repos: ["platform-infra", "inventory-service", "billing-service", "orders-service", "notification-worker", "api-gateway"],
});
