import { test } from "node:test";
import assert from "node:assert/strict";
import { parseNote, endpointAt, endpointRelations, resolveLinks, type ParsedNote } from "./relations.ts";

// Cases ported from constellation/core/tests/parser.rs and graph.rs.
const CART =
  "---\ntype: endpoint\nowner: team-a\n---\n# Cart endpoints\n\n## GET /cart\nCalls:\n- [[shop-orders/endpoints#POST /orders]]\n- [[shop-orders/endpoints#GET /stock]]\n\nStatus:\n- implemented: true\n- last_changed: 2026-01-02\n\n## DELETE /cart\nCalls:\n- [[shop-orders/endpoints#POST /orders]]";

test("Calls are grouped by Endpoint heading, with the Link heading", () => {
  const p = parseNote(CART);
  assert.deepEqual(p.calls.map((c) => c.heading), ["GET /cart", "DELETE /cart"]);
  assert.deepEqual(p.calls[0].links, [
    { target: "shop-orders/endpoints", heading: "POST /orders" },
    { target: "shop-orders/endpoints", heading: "GET /stock" },
  ]);
});

test("only the bullet list right after an exact Calls: line counts; Links in code never", () => {
  const p = parseNote(
    "## GET /a\nSee [[x#GET /x]].\nCalls:\n- [[b#GET /b]] and `[[code#GET /c]]`\n```\n- [[fenced#GET /f]]\n```\n\n- [[after-gap#GET /g]]\nMy Calls:\n- [[no#GET /n]]",
  );
  assert.deepEqual(p.calls, [{ heading: "GET /a", links: [{ target: "b", heading: "GET /b" }] }]);
});

test("a Calls: list outside an Endpoint heading is a plain list", () => {
  const p = parseNote("# Misc\nCalls:\n- [[a]]\n## GET /x\nCalls:\n- [[b#GET /y]]");
  assert.deepEqual(p.calls.map((c) => c.heading), ["GET /x"]);
});

test("Calls belong to the enclosing Endpoint across sub-headings, not past a sibling", () => {
  const p = parseNote("## GET /a\n### Request\nCalls:\n- [[b#GET /b]]\n## Notes\nCalls:\n- [[c#GET /c]]\n");
  assert.deepEqual(p.calls, [{ heading: "GET /a", links: [{ target: "b", heading: "GET /b" }] }]);
});

test("Calls accept trailing spaces, indented and * bullets, backticked methods", () => {
  const p = parseNote("## `GET /a`\nCalls: \t\n  - [[b#GET /b]]\n\t* [[c|C]]\nStatus:\n  - implemented: true\n");
  assert.deepEqual(p.calls, [
    { heading: "GET /a", links: [{ target: "b", heading: "GET /b" }, { target: "c", heading: null }] },
  ]);
});

test("the Endpoint under the cursor line", () => {
  const lines = CART.split("\n");
  const p = parseNote(CART);
  assert.equal(endpointAt(p, lines.indexOf("- [[shop-orders/endpoints#GET /stock]]")), "GET /cart");
  assert.equal(endpointAt(p, lines.indexOf("## DELETE /cart")), "DELETE /cart");
  assert.equal(endpointAt(p, 0), null);
  assert.equal(endpointAt(p, lines.indexOf("# Cart endpoints")), null);
  const q = parseNote("## `GET /a`\n### Request\nbody\n## Notes\nmore");
  assert.equal(endpointAt(q, 2), "GET /a");
  assert.equal(endpointAt(q, 4), null);
});

test("Uses: counts only in Client Notes", () => {
  const web = "---\ntype: client\n---\n# Web\nUses:\n- [[shop-cart/endpoints#GET /cart]]\n\nSee [[other]]\n";
  assert.deepEqual(parseNote(web).uses, [{ target: "shop-cart/endpoints", heading: "GET /cart" }]);
  assert.deepEqual(parseNote("# W\nUses:\n- [[a#GET /x]]").uses, []);
  assert.deepEqual(parseNote("---\ntype: endpoint\n---\n## GET /a\nUses:\n- [[a#GET /x]]").uses, []);
});

const ORDERS = "---\ntype: endpoint\n---\n## POST /orders\n## GET /stock\nCalls:\n- [[shop-cart/endpoints#GET /cart]]\n";
const WEB = "---\ntype: client\n---\n# Web\nUses:\n- [[shop-cart/endpoints#GET /cart]]\n";

/** Notes by path plus a resolver by path or unique name (case-insensitive, `.md` optional), like Obsidian's. */
function vault(files: Record<string, string>) {
  const notes = new Map<string, ParsedNote>(Object.entries(files).map(([p, t]) => [p, parseNote(t)]));
  const resolve = (target: string) => {
    const t = target.toLowerCase().replace(/\.md$/, "");
    const hits = [...notes.keys()].filter((p) => {
      const q = p.toLowerCase().replace(/\.md$/, "");
      return q === t || (!t.includes("/") && q.split("/").pop() === t);
    });
    return hits.length === 1 ? hits[0] : null;
  };
  return { notes, resolve };
}

const SHOP = {
  "shop-cart/endpoints.md": CART,
  "shop-orders/endpoints.md": ORDERS,
  "web.md": WEB,
  "plain.md": "no frontmatter",
};

test("an Endpoint's Calls, Called by and Used by clients", () => {
  const { notes, resolve } = vault(SHOP);
  const r = endpointRelations(notes, resolve, "shop-cart/endpoints.md", "GET /cart");
  assert.deepEqual(r.calls, [
    { path: "shop-orders/endpoints.md", target: "shop-orders/endpoints", heading: "POST /orders", broken: false },
    { path: "shop-orders/endpoints.md", target: "shop-orders/endpoints", heading: "GET /stock", broken: false },
  ]);
  assert.deepEqual(r.calledBy, [{ path: "shop-orders/endpoints.md", heading: "GET /stock" }]);
  assert.deepEqual(r.usedBy, [{ path: "web.md", heading: null }]);
  const o = endpointRelations(notes, resolve, "shop-orders/endpoints.md", "POST /orders");
  assert.deepEqual(o.calledBy.map((e) => e.heading), ["GET /cart", "DELETE /cart"]);
  assert.deepEqual([o.calls, o.usedBy], [[], []]);
});

test("broken Call targets: a missing Note or a missing heading", () => {
  const { notes, resolve } = vault({
    "a.md": "## GET /a\nCalls:\n- [[gone#GET /x]]\n- [[b#GET /nope]]\n- [[b#get /b]]\n- [[b]]\n",
    "b.md": "## `GET /b`\n",
  });
  const r = endpointRelations(notes, resolve, "a.md", "GET /a");
  assert.deepEqual(r.calls.map((c) => [c.path, c.broken]), [[null, true], ["b.md", true], ["b.md", false], ["b.md", false]]);
});

test("backticked Endpoint headings fold into plain names", () => {
  const { notes, resolve } = vault({ "a.md": "## `GET /a`\nCalls:\n- [[b#GET /b]]\n", "b.md": "## `GET /b`\n" });
  assert.deepEqual(endpointRelations(notes, resolve, "b.md", "GET /b").calledBy, [{ path: "a.md", heading: "GET /a" }]);
});

test("a Client's Uses resolve by unique name, broken ones marked", () => {
  const { notes, resolve } = vault({ ...SHOP, "clients/app.md": "---\ntype: client\n---\nUses:\n- [[endpoints#GET /cart]]\n- [[web]]\n" });
  const uses = resolveLinks(notes, resolve, "clients/app.md", notes.get("clients/app.md")!.uses);
  assert.deepEqual(uses.map((u) => [u.path, u.broken]), [[null, true], ["web.md", false]]);
});
