"""python3 -m unittest discover -s agents/ServiceMapAgent/scripts"""
import pathlib
import tempfile
import textwrap
import unittest

from scan_repo import scan

FILES = {
    "src/main/java/shop/OrderController.java": """
        @RestController
        @RequestMapping("/orders")
        public class OrderController {
          @PostMapping
          public ResponseEntity<OrderResponse> create(@Valid @RequestBody CreateOrder body) {
            return service.place(body);
          }
          @GetMapping(value = {"/{id}", "/by-id/{id}"})
          public OrderResponse get(@PathVariable long id) { return service.get(id); }
          @RequestMapping(path = "/{id}/cancel", method = RequestMethod.POST)
          public OrderResponse cancel(@PathVariable long id) { return service.cancel(id); }
        }
        """,
    "src/main/java/shop/BillingClient.java": """
        @FeignClient(name = "billing-service", path = "/api")
        public interface BillingClient {
          @PostMapping("/payments")
          PaymentResponse charge(@RequestBody PaymentRequest request);
        }
        """,
    "src/main/java/shop/StockApi.java": """
        @HttpExchange("/stock")
        public interface StockApi {
          @PostExchange("/reservations")
          Reservation reserve(@RequestBody ReserveRequest request);
        }
        """,
    "src/main/java/shop/OrderService.java": """
        @Service
        public class OrderService {
          public OrderResponse place(CreateOrder body) {
            stockApi.reserve(new ReserveRequest(body.lines()));
            billingClient.charge(new PaymentRequest(body.total()));
            kafkaTemplate.send("order-events", event);
            return OrderResponse.of(order);
          }
          @Scheduled(fixedDelay = 300000)
          public void retryRefunds() { }
          @KafkaListener(topics = {"shipment-events"}, groupId = "orders")
          public void onShipment(ShipmentEvent event) { }
        }
        """,
    "src/main/java/shop/Order.java": """
        @Entity
        @Table(name = "orders")
        public class Order { }
        """,
    "src/main/java/shop/OrderLine.java": """
        @Entity
        public class OrderLine { }
        """,
    "src/main/java/shop/OrderRepository.java": """
        public interface OrderRepository extends JpaRepository<Order, UUID> {
          @Query("select o from Order o where o.status = :s")
          List<Order> byStatus(String s);
        }
        """,
    "src/main/resources/application.yml": """
        server:
          servlet:
            context-path: /api
        services:
          billing:
            base-url: http://user:pw@billing-service:8080
        spring:
          datasource:
            password: hunter2
        """,
    "app/routes.py": """
        router = APIRouter(prefix="/reports")

        @router.get("/daily")
        async def daily():
            return []
        """,
    "infra/main.tf": """
        resource "aws_sqs_queue" "orders" {
        }
        """,
    "src/test/java/shop/IgnoredTest.java": """
        @RestController
        public class IgnoredTest { @GetMapping("/x") public void x() { } }
        """,
}


class ScanTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(cls.tmp.name)
        for rel, text in FILES.items():
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(textwrap.dedent(text).lstrip(), encoding="utf-8")
        cls.facts = scan(root, "orders-service")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_spring_and_fastapi_endpoints(self):
        found = {(e["method"], e["path"], e.get("handler")) for e in self.facts["endpoints"]}
        self.assertEqual(found, {
            ("POST", "/orders", "OrderController.create"),
            ("GET", "/orders/{id}", "OrderController.get"),
            ("GET", "/orders/by-id/{id}", "OrderController.get"),
            ("POST", "/orders/{id}/cancel", "OrderController.cancel"),
            ("GET", "/reports/daily", "daily"),
        })
        self.assertTrue(all(":" in e["ref"] for e in self.facts["endpoints"]))

    def test_clients_with_their_call_sites(self):
        clients = {c["interface"]: c for c in self.facts["clients"]}
        feign = clients["BillingClient"]
        self.assertEqual((feign["name"], feign["methods"][0]["method"], feign["methods"][0]["path"]), ("billing-service", "POST", "/api/payments"))
        self.assertEqual([c["in"] for c in feign["methods"][0]["called_from"]], ["OrderService.place"])
        stock = clients["StockApi"]["methods"][0]
        self.assertEqual((stock["method"], stock["path"], stock["called_from"][0]["in"]), ("POST", "/stock/reservations", "OrderService.place"))

    def test_events_jobs_and_data(self):
        self.assertEqual(self.facts["listeners"][0]["topics"], ["shipment-events"])
        self.assertEqual(self.facts["listeners"][0]["handler"], "OrderService.onShipment")
        self.assertEqual(self.facts["producers"][0]["in"], "OrderService.place")
        self.assertEqual(self.facts["scheduled"][0]["handler"], "OrderService.retryRefunds")
        self.assertEqual({e["table"] for e in self.facts["entities"]}, {"orders", "order_line"})
        self.assertEqual(self.facts["repositories"][0]["queries"], 1)
        self.assertEqual(self.facts["terraform"][0]["kind"], "aws_sqs_queue")

    def test_config_keeps_urls_and_drops_secrets(self):
        config = {c["key"]: c["value"] for c in self.facts["config"]}
        self.assertEqual(config["server.servlet.context-path"], "/api")
        self.assertEqual(config["services.billing.base-url"], "http://billing-service:8080")
        self.assertNotIn("spring.datasource.password", config)
        self.assertNotIn("hunter2", str(self.facts))


if __name__ == "__main__":
    unittest.main()
