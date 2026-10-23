# notification-worker

Sends customer emails when orders and payments change. No HTTP endpoints. **Layer:** Workers. **Runs on** AWS Lambda
with an MSK trigger.

| Listens to | Event | Sends |
|------------|-------|-------|
| `order-events` | `OrderPlaced` | order confirmation |
| `order-events` | `OrderCancelled` | cancellation and refund notice |
| `payment-events` | `PaymentFailed` | "update your card" |

Emails go through the email provider (`POST /v3/mail/send`), 3 retries, then the `notifications-dlt` topic.

<small>Mapped from `notification-worker@e09a4b2` on 2026-10-23.</small>
