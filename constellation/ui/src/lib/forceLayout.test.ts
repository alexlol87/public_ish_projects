import { expect, test } from "vitest";
import { ForceLayout } from "./forceLayout";

test("connected nodes end closer than unconnected", () => {
  const l = new ForceLayout(["a", "b", "c"], [["a", "b"]]);
  for (let i = 0; i < 300; i++) l.step();
  const d = (x: string, y: string) => Math.hypot(l.get(x)!.x - l.get(y)!.x, l.get(x)!.y - l.get(y)!.y);
  expect(d("a", "b")).toBeLessThan(d("a", "c"));
  expect([...l.x, ...l.y].every(Number.isFinite)).toBe(true);
});

test("keeps existing positions when ids change", () => {
  const l = new ForceLayout(["a", "b"], []);
  for (let i = 0; i < 20; i++) l.step();
  const a = l.get("a")!;
  l.update(["a", "b", "c"], []);
  expect(l.get("a")).toEqual(a);
  expect(l.get("c")).toBeDefined();
  l.update(["a"], []);
  expect(l.get("b")).toBeUndefined();
});

test("pinned node stays put while others move; unpin releases it", () => {
  const l = new ForceLayout(["a", "b"], [["a", "b"]]);
  l.pin("a", { x: 500, y: 500 });
  const b0 = l.get("b")!;
  for (let i = 0; i < 10; i++) l.step();
  expect(l.get("a")).toEqual({ x: 500, y: 500 });
  expect(l.get("b")).not.toEqual(b0);
  l.unpin("a");
  l.step();
  expect(l.get("a")).not.toEqual({ x: 500, y: 500 });
});

test("pin survives update; unknown ids are ignored", () => {
  const l = new ForceLayout(["a", "b"], []);
  l.pin("a", { x: 9, y: 9 });
  l.update(["b", "a", "c"], [["a", "zzz"]]);
  l.step();
  expect(l.get("a")).toEqual({ x: 9, y: 9 });
  l.pin("nope", { x: 1, y: 1 });
});

test("Barnes-Hut handles coincident bodies and large graphs", () => {
  const ids = Array.from({ length: 2000 }, (_, i) => `n${i}`);
  const l = new ForceLayout(ids, ids.slice(1).map((id, i) => [ids[i >> 1], id]));
  l.x.fill(1); l.y.fill(1); // all coincident
  for (let i = 0; i < 3; i++) l.step();
  expect([...l.x, ...l.y].every(Number.isFinite)).toBe(true);
});
