const GENERIC = new Set(["index", "endpoints", "bugs", "todo", "overview", "architecture", "requirements", "future", "notes", "adr", "clients"]);

interface LabelNode { id: string; name: string; kind: "note" | "folder" | "ghost" }

/**
 * Short, unambiguous graph labels. Notes lose `.md`; a README is labelled by its folder; generic or
 * repeated note names get their parent folder (`cart-service/endpoints`), and the full path if still repeated.
 */
export function graphLabels(nodes: LabelNode[]): Map<string, string> {
  const notes = nodes.filter((n) => n.kind === "note");
  // Path segments a note is named by; a non-root README is named by its folder.
  const segs = new Map(notes.map((n) => {
    const p = n.id.replace(/\.md$/i, "").split("/");
    if (p.length > 1 && /^readme$/i.test(p[p.length - 1])) p.pop();
    return [n.id, p];
  }));
  const tail = (id: string, k: number) => segs.get(id)!.slice(-k).join("/");
  const counts = (k: (id: string) => number) => {
    const c = new Map<string, number>();
    for (const n of notes) c.set(tail(n.id, k(n.id)), (c.get(tail(n.id, k(n.id))) ?? 0) + 1);
    return c;
  };
  const c1 = counts(() => 1);
  const depth = new Map(notes.map((n) => {
    const l = tail(n.id, 1);
    return [n.id, GENERIC.has(l.toLowerCase()) || c1.get(l)! > 1 ? 2 : 1];
  }));
  const c2 = counts((id) => depth.get(id)!);
  const out = new Map(nodes.map((n) => [n.id, n.name]));
  for (const n of notes) {
    const d = depth.get(n.id)!;
    out.set(n.id, c2.get(tail(n.id, d))! > 1 ? segs.get(n.id)!.join("/") : tail(n.id, d));
  }
  return out;
}
