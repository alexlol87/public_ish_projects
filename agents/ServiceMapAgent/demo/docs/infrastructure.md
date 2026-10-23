# Infrastructure and CI/CD

From the `platform-infra` Terraform repository and each repository's GitHub Actions workflows.

## Where each service runs

| Service | Runtime | Database | Kafka topics | Public route | Terraform |
|---------|---------|----------|--------------|--------------|-----------|
| api-gateway | ECS Fargate, 2–6 tasks | — | — | `shop.example.com/api/**` | `services/gateway.tf` |
| orders-service | ECS Fargate, 2–4 tasks | RDS PostgreSQL `orders-db` | produces `order-events`, consumes `shipment-events` | via gateway | `services/orders.tf` |
| billing-service | ECS Fargate, 2 tasks | RDS PostgreSQL `billing-db` | produces `payment-events` | via gateway (internal only) | `services/billing.tf` |
| inventory-service | ECS Fargate, 2 tasks | RDS PostgreSQL `inventory-db` | consumes `order-events` | via gateway | `services/inventory.tf` |
| notification-worker | AWS Lambda (MSK trigger) | — | consumes `order-events`, `payment-events` | — | `services/notifications.tf` |

## How it ships

| Service | Workflow | On pull request | On merge to main | To production |
|---------|----------|-----------------|------------------|---------------|
| api-gateway | `.github/workflows/deploy-gateway.yml` | build, tests | deploy to dev, then test | manual approval (`prod` environment) |
| orders-service | `.github/workflows/deploy-orders.yml` | build, tests, Testcontainers | deploy to dev, then test | manual approval |
| billing-service | `.github/workflows/deploy-billing.yml` | build, tests | deploy to dev, then test | manual approval |
| inventory-service | `.github/workflows/deploy-inventory.yml` | build, tests | deploy to dev | tag `v*` ❓ no approval step |
| notification-worker | `.github/workflows/deploy-notifications.yml` | build, tests | deploy to dev, then test | manual approval |

## Shared infrastructure

Not tied to one service, listed only: `shop-vpc` (VPC, `modules/network`), `shop-msk` (Kafka cluster, `modules/kafka`),
`shop.example.com` (Route 53 zone, `dns.tf`).
