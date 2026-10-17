// Builds the e2e Vault: a copy of fixtures/vault (without the user's local .constellation) plus richer fictional notes.
import fs from "node:fs";
import path from "node:path";
import { tmp } from "./lib.mjs";

const fixtures = path.resolve(import.meta.dirname, "../fixtures/vault");
const daysAgo = (n) => new Date(Date.now() - n * 864e5).toISOString().slice(0, 10);

export const FILES = {
  "README.md": "---\ntype: note\n---\n# Test vault\n\nWelcome. See [[acme-shop/README]] and [[acme-shop/cart-service/README]].\n",
  "repos.txt": "cart-service\norders-service\n",
  "tags.md": "- #payments: payment flows\n- #team/payments: the payments team\n",
  "AGENTS.md": "# Agents\n\nRules.\n",
  "templates/note.md": "---\ntype: note\n---\n# Title\n",
  "external/stripe.md": "---\ntype: external-api\n---\n# Stripe\n\n## POST /v1/payment_intents\n\nCreates a payment intent. #payments\n",
  "clients/portal.md": "---\ntype: client\n---\n# Portal\n\nWho: the storefront.\n\nUses:\n- [[acme-shop/cart-service/endpoints#GET /carts/{id}]]\n",
  "acme-shop/README.md": "---\ntype: project\n---\n# Acme Shop\n\nA fictional online shop. Owned by #team/payments.\n",
  "acme-shop/overview.md": "# Acme Shop\n\nA fictional online shop. #alpha\n",
  "acme-shop/cart-service/README.md": `---\ntype: repo\nrepo_url: https://github.com/acme/cart-service\nverified_commit: abc1234\nverified_on: ${daysAgo(100)}\n---\n# Cart service\n\nHolds **shopping** carts, see [[acme-shop/cart-service/endpoints]]. Plain *italic* text and a [[nowhere-note]] link.\n`,
  "acme-shop/cart-service/endpoints.md": "---\ntype: endpoint\n---\n# Endpoints\n\n## POST /carts\n\nSummary: creates a cart.\n\nCalls:\n- [[acme-shop/orders-service/endpoints#POST /orders]]\n\n## GET /carts/{id}\n\nSummary: reads a cart. Café résumé.\n",
  "acme-shop/cart-service/bugs.md": "---\ntype: bugs\n---\n# Bugs\n\n- [ ] Total ignores discounts → [[acme-shop/cart-service/endpoints#POST /carts]]\n  Applied after tax.\n- [ ] Second bug\n",
  "acme-shop/orders-service/README.md": `---\ntype: repo\nverified_on: ${daysAgo(3)}\n---\n# Orders service\n\nTakes orders. #payments Handles refund flow.\n`,
  "acme-shop/orders-service/endpoints.md": "---\ntype: endpoint\n---\n# Endpoints\n\n## POST /orders\n\nSummary: places an order.\n\nCalls:\n- [[external/stripe#POST /v1/payment_intents]]\n",
  "acme-shop/cart-notes.md": "# Cart notes\n\nNothing here.\n",
  "acme-shop/archive/fixed-bugs.md": "---\ntype: archive\n---\n# Fixed bugs\n\n### Old legacy bug\n- closed: 2026-01-01\n",
  "acme-shop/archive/done-todos.md": "---\ntype: archive\n---\n# Done todos\n",
};

export function makeVault() {
  const dir = tmp("vault");
  fs.cpSync(fixtures, dir, { recursive: true, filter: (s) => !s.includes(".constellation") });
  for (const [p, t] of Object.entries(FILES)) {
    fs.mkdirSync(path.dirname(path.join(dir, p)), { recursive: true });
    fs.writeFileSync(path.join(dir, p), t);
  }
  return dir;
}
