import { expect, test } from "vitest";
import { graphLabels } from "./graphLabels";

test("graph labels: no .md, README by folder, generic and repeated names prefixed", () => {
  const note = (id: string) => ({ id, name: id.split("/").pop()!, kind: "note" as const });
  const nodes = [
    { id: "acme/cart", name: "cart", kind: "folder" as const },
    note("README.md"),
    note("acme/cart/README.md"),
    note("acme/cart/endpoints.md"),
    note("acme/orders/endpoints.md"),
    note("acme/cart/sync.md"),
    note("x/a/notes-1.md"),
    note("y/a/notes-1.md"),
    note("acme/orders/README.md"),
    note("other/orders/README.md"),
    { id: "ghost:phantom", name: "phantom", kind: "ghost" as const },
  ];
  expect([...graphLabels(nodes).values()]).toEqual([
    "cart", "README", "cart", "cart/endpoints", "orders/endpoints", "sync",
    "x/a/notes-1", "y/a/notes-1", "acme/orders", "other/orders", "phantom",
  ]);
});
