# Map progress

The agent's work list. One repository per session, infrastructure first, then domain services, then edge.

| # | Repository | Services | Layer | Status | Mapped at | Date | Open questions |
|---|------------|----------|-------|--------|-----------|------|----------------|
| 1 | platform-infra | — (Terraform) | Infra | mapped | `a1b2c3d` | 2026-10-23 | |
| 2 | inventory-service | inventory-service | Domain | mapped | `51d0e3a` | 2026-10-23 | |
| 3 | billing-service | billing-service | Domain | mapped | `c72be90` | 2026-10-23 | `/refunds/partial` has no caller |
| 4 | orders-service | orders-service | Domain | mapped | `3f2a9c1` | 2026-10-23 | `shipment-events` producer unknown |
| 5 | notification-worker | notification-worker | Workers | mapped | `e09a4b2` | 2026-10-23 | |
| 6 | api-gateway | api-gateway | Edge | mapped | `8d41e07` | 2026-10-23 | |
