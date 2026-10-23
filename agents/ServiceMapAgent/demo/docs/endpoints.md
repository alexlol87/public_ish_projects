# All endpoints

Every endpoint of every service in one place. Use the search box, or your browser's find, to filter. "Flow" links to
a step-by-step page for endpoints that do more than read or save one record.

| Service | Method | Path | Use it when | Called by | Auth | Details |
|---------|--------|------|-------------|-----------|------|---------|
| api-gateway | ANY | `/api/orders/**` | Any client call about orders; forwards to `orders-service /orders/**` | web, mobile | JWT | [service](services/api-gateway/index.md) |
| api-gateway | ANY | `/api/stock/**` | Any client call about stock; forwards to `inventory-service /stock/**` | web, mobile | JWT | [service](services/api-gateway/index.md) |
| orders-service | POST | `/orders` | Checking out a basket: reserves stock, takes the payment, creates the order | api-gateway | `ROLE_CUSTOMER` | [flow](services/orders-service/POST-orders.md) |
| orders-service | GET | `/orders/{id}` | Showing one order with its lines and status | api-gateway | owner or `ROLE_SUPPORT` | simple read |
| orders-service | GET | `/orders` | Listing a customer's orders, newest first, paged | api-gateway | `ROLE_CUSTOMER` | simple read |
| orders-service | POST | `/orders/{id}/cancel` | Customer or support cancels an order that hasn't shipped; refunds and frees stock | api-gateway | owner or `ROLE_SUPPORT` | [flow](services/orders-service/POST-orders-id-cancel.md) |
| billing-service | POST | `/payments` | Charging for an order. Idempotent per `orderId`, so safe to retry after a timeout | orders-service | service token | [service](services/billing-service/index.md) |
| billing-service | POST | `/refunds` | Full refund of a cancelled order. **Don't confuse with** `/refunds/partial` for returns of some lines | orders-service | service token | [service](services/billing-service/index.md) |
| billing-service | POST | `/refunds/partial` | Refunding some order lines (returns) | ❓ no caller found | service token | [service](services/billing-service/index.md) |
| billing-service | GET | `/payments/{id}` | Support checking a payment's status at the provider | ❓ no caller found (support tool?) | `ROLE_SUPPORT` | simple read |
| inventory-service | GET | `/stock/{sku}` | Showing availability on a product page | api-gateway | public | simple read |
| inventory-service | POST | `/stock/reservations` | Holding stock while an order is placed; expires after 15 min unless confirmed | orders-service | service token | [service](services/inventory-service/index.md) |
| inventory-service | DELETE | `/stock/reservations/{id}` | Releasing the stock of a cancelled or failed order | orders-service | service token | [service](services/inventory-service/index.md) |

Entry points without HTTP: `inventory-service` and `notification-worker` consume Kafka topics, see
[Calls and events](calls.md#events).
