# POST /orders/{id}/cancel

**Use it when** a customer or support cancels an order that hasn't shipped yet. It refunds the full amount and frees
the stock. **Called by** api-gateway. **Not for** returns after delivery (those go through billing
`POST /refunds/partial`).

```mermaid
sequenceDiagram
  participant C as api-gateway
  participant OC as OrderController
  participant OS as OrderService
  participant DB as orders-db
  participant BC as BillingClient
  participant IC as InventoryClient
  participant K as order-events
  C->>OC: POST /orders/{id}/cancel
  OC->>OS: cancel(id, user)
  rect rgba(128,128,128,0.12)
  note over OS,DB: @Transactional
  OS->>DB: SELECT orders WHERE id = ? FOR UPDATE
  alt not owner and not ROLE_SUPPORT
    OC-->>C: 403
  else status is SHIPPED or DELIVERED
    OC-->>C: 409 ORDER_ALREADY_SHIPPED
  else
    OS->>BC: POST /refunds
    alt refund failed
      OS->>DB: UPDATE orders SET status = CANCEL_PENDING
    else
      OS->>DB: UPDATE orders SET status = CANCELLED
    end
    OS->>DB: INSERT outbox (OrderCancelled)
  end
  end
  OS->>IC: DELETE /stock/reservations/{id}
  OS-)K: OrderCancelled
  OC-->>C: 200 {status}
```

## Steps

1. `OrderController.cancel` — `OrderController.java:58`
2. Load and lock the order, check owner or `ROLE_SUPPORT` — `OrderService.java:80`
3. Refuse when shipped — `OrderService.java:84`
4. Refund through billing **inside the transaction** — `OrderService.java:88`
5. Free the stock (failure only logged) — `OrderService.java:97`

| Condition | Status | Error |
|-----------|--------|-------|
| Not the owner or support | 403 | `FORBIDDEN` |
| Unknown id | 404 | `ORDER_NOT_FOUND` |
| Already shipped | 409 | `ORDER_ALREADY_SHIPPED` |
