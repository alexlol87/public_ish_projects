// Business flows across services, written by the agent's "journey" command.
SERVICE_MAP.journey({
  id: "place-order", title: "A customer places an order",
  story: "The customer presses Buy in the app. The gateway checks who they are, orders-service holds the stock, billing-service charges the card, and the order is saved. A Kafka event then lets inventory confirm the hold and the worker send the confirmation email. If the payment fails, the stock is released and nothing is saved.",
  start: { service: "orders-service", endpoint: "POST /orders" },
  diagram: `sequenceDiagram
  autonumber
  actor U as Customer app
  participant G as api-gateway
  participant O as orders-service
  participant I as inventory-service
  participant B as billing-service
  participant P as payment provider
  participant K as order-events
  participant N as notification-worker
  U->>G: POST /api/orders
  G->>O: POST /orders
  O->>I: POST /stock/reservations
  I-->>O: 201 reservationId
  O->>B: POST /payments
  B->>P: POST /v2/charges
  alt payment refused
    P-->>B: declined
    B-->>O: 402
    O->>I: DELETE /stock/reservations/{id}
    O-->>G: 402 Payment Required
  else paid
    P-->>B: ok
    B-->>O: 201 paymentId
    O->>O: INSERT orders, order_lines
    O-)K: OrderPlaced
    O-->>G: 201 Created
    K-)I: confirm the hold
    K-)N: send the confirmation email
  end
  G-->>U: response`,
  failures: [
    "Payment declined: 402, and the stock hold is released.",
    "billing-service down: the circuit breaker opens, 503, and the hold is released.",
    "The provider is slow: the gateway gives up after 10 s while billing waits 30 s, so the customer sees an error but may still be charged.",
  ],
  changes: "One row in orders and its order_lines, one payment, the hold becomes confirmed and stock goes down, and the customer gets one email.",
});
