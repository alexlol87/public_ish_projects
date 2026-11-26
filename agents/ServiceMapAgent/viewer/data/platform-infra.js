SERVICE_MAP.repo({
  repo: "platform-infra", kind: "terraform", commit: "a1b2c3d", mapped: "2026-10-23",
  shared: [
    { name: "shop-vpc", kind: "VPC", ref: "platform-infra/modules/network/main.tf:1" },
    { name: "shop-msk", kind: "Kafka cluster (MSK)", ref: "platform-infra/modules/kafka/main.tf:1" },
    { name: "shop.example.com", kind: "Route 53 zone", ref: "platform-infra/dns.tf:1" },
  ],
});
