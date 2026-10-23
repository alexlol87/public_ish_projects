# api-gateway

Single public entry point (Spring Cloud Gateway). Checks the customer's JWT and routes requests; no business logic.
**Layer:** Edge.

| Public route | Goes to | Filters |
|--------------|---------|---------|
| `/api/orders/**` | `orders-service /orders/**` | JWT, strip `/api`, 10 s timeout |
| `/api/stock/**` | `inventory-service /stock/**` | strip `/api`, 10 s timeout; `GET /stock/{sku}` is public |

<small>Mapped from `api-gateway@8d41e07` on 2026-10-23.</small>
