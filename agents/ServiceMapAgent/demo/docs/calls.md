# Calls and events

## Endpoint to endpoint

| Caller | Caller endpoint | Callee | Callee endpoint | Kind | On failure |
|--------|-----------------|--------|-----------------|------|------------|
| api-gateway | `ANY /api/orders/**` | orders-service | `ANY /orders/**` | HTTP | 10 s timeout, 504 to client |
| api-gateway | `ANY /api/stock/**` | inventory-service | `ANY /stock/**` | HTTP | 10 s timeout, 504 to client |
| orders-service | `POST /orders` | inventory-service | `POST /stock/reservations` | HTTP (Feign) | 2 retries, then 503 |
| orders-service | `POST /orders` | billing-service | `POST /payments` | HTTP (Feign) | circuit breaker; reservation released |
| orders-service | `POST /orders/{id}/cancel` | billing-service | `POST /refunds` | HTTP (Feign) | order stays `CANCEL_PENDING`, retried by a job |
| orders-service | `POST /orders/{id}/cancel` | inventory-service | `DELETE /stock/reservations/{id}` | HTTP (Feign) | logged only ❓ stock may stay reserved |
| billing-service | `POST /payments` | payment provider (external) | `POST /v2/charges` | HTTP (RestClient) | 30 s timeout |
| billing-service | `POST /refunds` | payment provider (external) | `POST /v2/refunds` | HTTP (RestClient) | 30 s timeout |
| notification-worker | `@KafkaListener order-events` | email provider (external) | `POST /v3/mail/send` | HTTP | 3 retries, then dead-letter topic |

## Events

| Topic | Event types | Producers | Consumers |
|-------|-------------|-----------|-----------|
| `order-events` | `OrderPlaced`, `OrderCancelled`, `OrderShipped` | orders-service | inventory-service (confirms or frees reservations), notification-worker (emails) |
| `payment-events` | `PaymentFailed`, `RefundCompleted` | billing-service | notification-worker |
| `shipment-events` | `ShipmentDelivered` | ❓ no producer in the mapped repos (external warehouse?) | orders-service |
