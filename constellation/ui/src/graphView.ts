import { listen } from "@tauri-apps/api/event";
import { api, type EdgeKind, type GraphFilter, type VaultGraph, type TagNode } from "./api";
import { WorkerLayout } from "./lib/layoutClient";
import { graphLabels } from "./lib/graphLabels";
import { applyTheme, palette, THEME_CHOICES, type ThemeChoice } from "./lib/themes";
import { h, toast } from "./ui";

const TYPES = ["project", "repo", "endpoint", "architecture", "adr", "requirements", "future", "external-api", "client", "bugs", "todo", "archive", "note"];
const KINDS: EdgeKind[] = ["containment", "link", "call", "uses"];

export async function graphView(app: HTMLElement) {
  let theme: ThemeChoice = "System";
  const loadTheme = async () => {
    const t = (await api.getSettings()).theme;
    theme = (THEME_CHOICES as readonly string[]).includes(t) ? (t as ThemeChoice) : "System";
    applyTheme(theme);
  };
  await loadTheme();
  let filter: GraphFilter = await api.graphFilter();
  let local = false;
  let current: string | null = await api.getCurrent();
  let g: VaultGraph = { nodes: [], edges: [] };
  const layout = new WorkerLayout(() => redraw());
  let hover: string | null = null;
  let neighbours = new Map<string, Set<string>>();
  let labels = new Map<string, string>();
  let refit = false;
  const view = { x: 0, y: 0, k: 1 };

  const canvas = h("canvas", { id: "graph-canvas" });
  const ctx = canvas.getContext("2d")!;
  const panel = h("div", { class: "gpanel" });
  app.replaceChildren(h("div", { class: "gwrap" }, panel, h("div", { class: "gcanvas" }, canvas)));

  const reloads: string[] = []; // why each reload happened (e2e introspection)
  const save = () => { void api.saveGraphFilter(filter); void reload("filter"); };
  const check = (label: string, on: boolean, set: (v: boolean) => void, id?: string) =>
    h("label", { class: "chk" }, h("input", { type: "checkbox", id, checked: on, onchange: (e: Event) => { set((e.target as HTMLInputElement).checked); save(); } }), label);
  // Empty set means "all" in the filter; the checkboxes show the full list ticked in that case.
  const multi = (title: string, all: string[], sel: string[], set: (v: string[]) => void) =>
    h("div", { class: "gsec" }, h("div", { class: "sec" }, title),
      ...all.map((x) => check(x, sel.length === 0 || sel.includes(x), (on) => {
        const cur = sel.length === 0 ? [...all] : [...sel];
        const next = on ? [...new Set([...cur, x])] : cur.filter((y) => y !== x);
        if (!next.length) return void renderPanel(); // the last one stays ticked ("none" would mean "all")
        set(next.length === all.length ? [] : next);
      })));

  async function renderPanel() {
    const tree = await api.tree();
    const projects = tree.children.filter((c) => c.isFolder && !c.appOnly).map((c) => c.name);
    const flat = (n: TagNode[]): string[] => n.flatMap((t) => [t.tag, ...flat(t.children)]);
    const tags = flat(await api.tagTree("name"));
    panel.replaceChildren(
      h("div", { class: "gsec" }, h("div", { class: "sec" }, "Local graph"),
        check("Around current note", local, (v) => (local = v), "g-local"),
        h("label", {}, "Depth ", h("select", { id: "g-depth", onchange: (e: Event) => { filter.localDepth = Number((e.target as HTMLSelectElement).value); save(); } },
          ...[1, 2, 3].map((d) => h("option", { value: String(d), selected: d === filter.localDepth }, String(d)))))),
      multi("Projects", projects, filter.projects, (v) => (filter.projects = v)),
      multi("Note types", TYPES, filter.types, (v) => (filter.types = v)),
      multi("Edges", KINDS, filter.edgeKinds.length ? filter.edgeKinds : [], (v) => (filter.edgeKinds = (v.length ? v : [...KINDS]) as EdgeKind[])),
      h("div", { class: "gsec" }, check("Show archive", filter.includeArchive, (v) => (filter.includeArchive = v), "g-archive")),
      h("div", { class: "gsec" }, h("div", { class: "sec" }, "Tag"),
        h("select", { id: "g-tag", onchange: (e: Event) => { filter.tag = (e.target as HTMLSelectElement).value || null; save(); } },
          h("option", { value: "" }, "(any)"), ...tags.map((t) => h("option", { value: t, selected: t === filter.tag }, "#" + t)))));
  }

  async function reload(why = "?") {
    reloads.push(why);
    try { g = await api.graph(filter, local ? current : null); } catch (e) { toast(String(e), true); return; }
    neighbours = new Map(g.nodes.map((n) => [n.id, new Set<string>()]));
    labels = graphLabels(g.nodes);
    for (const e of g.edges) { neighbours.get(e.from)?.add(e.to); neighbours.get(e.to)?.add(e.from); }
    layout.update(g.nodes.map((n) => n.id), g.edges.map((e) => [e.from, e.to]));
    layout.setHeat(400);
    refit ||= why === "init" || why === "filter" || why === "current-note"; // a Vault change keeps the user's pan/zoom
    redraw();
  }

  // ---- drawing ----
  const toScreen = (x: number, y: number) => [x * view.k + view.x, y * view.k + view.y] as const;
  const toWorld = (sx: number, sy: number) => [(sx - view.x) / view.k, (sy - view.y) / view.k] as const;
  const radius = (id: string) => 4 + Math.min(10, Math.sqrt(neighbours.get(id)?.size ?? 0) * 1.6);
  let queued = false, fits = 0;
  const ms = { draw: 0 }; // last frame's cost (e2e introspection)

  function draw() {
    const pal = palette(theme);
    const dpr = devicePixelRatio || 1;
    const w = canvas.clientWidth, hgt = canvas.clientHeight;
    if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(hgt * dpr)) { canvas.width = Math.round(w * dpr); canvas.height = Math.round(hgt * dpr); }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = pal.background; ctx.fillRect(0, 0, w, hgt);
    const near = hover ? neighbours.get(hover) : undefined;
    const lit = (id: string) => !hover || id === hover || near?.has(id);
    const stroke: Record<EdgeKind, { c: string; w: number; dash: number[] }> = {
      containment: { c: pal.folderNode, w: 1, dash: [2, 4] },
      link: { c: pal.link, w: 1.2, dash: [] },
      call: { c: pal.heading, w: 2, dash: [] },
      uses: { c: pal.tag, w: 1.6, dash: [7, 4] },
    };
    // One path per edge kind and highlight state (thousands of separate strokes are slow); off-screen edges are skipped.
    const paths = new Map<string, { kind: EdgeKind; on: boolean; line: Path2D; head: Path2D }>();
    // Strokes are the slow part of a big graph; while it is still moving, draw a thin sample of the edges.
    const stride = layout.heat > 0 ? Math.ceil(g.edges.length / 2500) : 1;
    for (let ei = 0; ei < g.edges.length; ei += stride) {
      const e = g.edges[ei];
      const a = layout.get(e.from), b = layout.get(e.to);
      if (!a || !b) continue;
      const [x1, y1] = toScreen(a.x, a.y), [x2, y2] = toScreen(b.x, b.y);
      if ((x1 < 0 && x2 < 0) || (y1 < 0 && y2 < 0) || (x1 > w && x2 > w) || (y1 > hgt && y2 > hgt)) continue;
      const on = !hover || e.from === hover || e.to === hover, key = e.kind + on;
      let p = paths.get(key);
      if (!p) paths.set(key, (p = { kind: e.kind, on, line: new Path2D(), head: new Path2D() }));
      p.line.moveTo(x1, y1); p.line.lineTo(x2, y2);
      if (e.kind === "call" || e.kind === "uses") { // arrow head near the target
        const ang = Math.atan2(y2 - y1, x2 - x1), r = radius(e.to) * view.k + 3;
        const tx = x2 - Math.cos(ang) * r, ty = y2 - Math.sin(ang) * r;
        p.head.moveTo(tx, ty);
        p.head.lineTo(tx - 8 * Math.cos(ang - 0.4), ty - 8 * Math.sin(ang - 0.4));
        p.head.lineTo(tx - 8 * Math.cos(ang + 0.4), ty - 8 * Math.sin(ang + 0.4)); p.head.closePath();
      }
    }
    for (const p of [...paths.values()].sort((a, b) => Number(a.on) - Number(b.on))) {
      const s = stroke[p.kind];
      ctx.globalAlpha = p.on ? 0.85 : 0.1;
      // Lines wider than 1 px are slow to stroke in bulk (WebKitGTK/Cairo), so big graphs draw hairlines.
      ctx.strokeStyle = s.c; ctx.fillStyle = s.c; ctx.lineWidth = g.edges.length > 2000 ? 1 : s.w; ctx.setLineDash(s.dash);
      ctx.stroke(p.line);
      ctx.setLineDash([]); ctx.fill(p.head);
    }
    ctx.setLineDash([]);
    ctx.font = "11px system-ui, sans-serif"; ctx.textAlign = "center";
    // Nodes are batched like edges: one Path2D per fill colour, ghost outline and highlight state.
    const marks: { x: number; y: number; r: number; on: boolean; fade: number; n: (typeof g.nodes)[number] }[] = [];
    const fills = new Map<string, { color: string; on: boolean; ghost: boolean; path: Path2D }>();
    for (const n of g.nodes) {
      const p = layout.get(n.id);
      if (!p) continue;
      const [x, y] = toScreen(p.x, p.y), r = radius(n.id) * Math.max(g.nodes.length > 1000 ? 0.25 : 0.6, Math.min(view.k, 2));
      if (x < -50 || y < -50 || x > w + 50 || y > hgt + 50) continue;
      const on = !!lit(n.id), ghost = n.kind === "ghost", key = (ghost ? "g" : n.kind === "folder" ? "f" : "n") + on;
      let f = fills.get(key);
      if (!f) fills.set(key, (f = { color: n.kind === "folder" ? pal.folderNode : pal.noteNode, on, ghost, path: new Path2D() }));
      if (r < 2 && !ghost) f.path.rect(x - r, y - r, 2 * r, 2 * r); // tiny dots: arcs are slow to fill by the thousand
      else { f.path.moveTo(x + r, y); f.path.arc(x, y, r, 0, 7); }
      // Labels fade out when zoomed out (and for big graphs), except the hovered Node, its neighbours and the current Note.
      const focus = n.id === hover || near?.has(n.id) || n.id === current;
      const fade = focus ? 1 : (g.nodes.length < 120 || view.k > 1.2 ? 1 : 0) * Math.min(1, Math.max(0, (view.k - 0.45) / 0.3));
      if (fade > 0 || n.id === current) marks.push({ x, y, r, on, fade, n });
    }
    for (const f of fills.values()) {
      ctx.globalAlpha = f.on ? 1 : 0.15;
      if (f.ghost) { ctx.strokeStyle = pal.stale; ctx.lineWidth = 1.5; ctx.setLineDash([3, 2]); ctx.stroke(f.path); ctx.setLineDash([]); }
      else { ctx.fillStyle = f.color; ctx.fill(f.path); }
    }
    for (const { x, y, r, on, fade, n } of marks) {
      if (n.id === current) { ctx.globalAlpha = on ? 1 : 0.15; ctx.strokeStyle = pal.text; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(x, y, r + 3, 0, 7); ctx.stroke(); }
      if (fade > 0) { ctx.globalAlpha = (on ? 1 : 0.15) * fade; ctx.fillStyle = pal.text; ctx.fillText(labels.get(n.id) ?? n.name, x, y + r + 12); }
    }
    ctx.globalAlpha = 1;
  }

  /** Zooms and pans so the whole graph is in view (after each reload, once the layout has settled). */
  function fit() {
    const pts = g.nodes.map((n) => layout.get(n.id)).filter((p): p is { x: number; y: number } => !!p);
    const w = canvas.clientWidth, hgt = canvas.clientHeight;
    if (!pts.length || !w || !hgt) return;
    const xs = pts.map((p) => p.x), ys = pts.map((p) => p.y);
    const [x0, x1, y0, y1] = [Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys)];
    view.k = Math.max(0.05, Math.min(2, (w - 120) / Math.max(1, x1 - x0), (hgt - 120) / Math.max(1, y1 - y0)));
    view.x = w / 2 - ((x0 + x1) / 2) * view.k;
    view.y = hgt / 2 - ((y0 + y1) / 2) * view.k;
  }

  function frame() {
    queued = false;
    // The layout runs in a worker and calls redraw() with each new step. Until the user takes over the view, it keeps fitting while it spreads out.
    const heat = layout.heat;
    if (refit && (heat === 0 || ++fits % 10 === 0)) { fit(); if (heat === 0) refit = false; }
    const t1 = performance.now();
    draw();
    ms.draw = performance.now() - t1;
  }
  const redraw = () => { if (!queued) { queued = true; requestAnimationFrame(frame); } };

  // ---- interaction ----
  const nodeAt = (sx: number, sy: number) => {
    const [wx, wy] = toWorld(sx, sy);
    let best: string | null = null, bd = Infinity;
    for (const n of g.nodes) {
      const p = layout.get(n.id);
      if (!p) continue;
      const d = Math.hypot(p.x - wx, p.y - wy), r = radius(n.id) + 3 / view.k;
      if (d < r && d < bd) { best = n.id; bd = d; }
    }
    return best;
  };
  // Read-only introspection for the e2e harness: where each node is drawn (canvas pixels) and the view transform.
  Object.assign(canvas, {
    e2e: () => ({ view: { ...view }, nodes: g.nodes.map((n) => { const p = layout.get(n.id); const [x, y] = p ? toScreen(p.x, p.y) : [NaN, NaN]; return { id: n.id, name: n.name, label: labels.get(n.id), kind: n.kind, x, y }; }), edges: g.edges.length, hover, local, heat: layout.heat, ms: { ...ms }, reloads: [...reloads], drag: drag && { id: drag.id, moved: drag.moved } }),
  });
  const pos = (e: MouseEvent) => { const r = canvas.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top] as const; };
  let drag: { id: string | null; moved: boolean; sx: number; sy: number } | null = null;

  canvas.addEventListener("mousedown", (e) => { refit = false; const [x, y] = pos(e); drag = { id: nodeAt(x, y), moved: false, sx: x, sy: y }; });
  addEventListener("mousemove", (e) => {
    const [x, y] = pos(e);
    if (drag) {
      if (Math.hypot(x - drag.sx, y - drag.sy) > 3) drag.moved = true;
      if (drag.moved) {
        if (drag.id) { const [wx, wy] = toWorld(x, y); layout.pin(drag.id, { x: wx, y: wy }); layout.setHeat(Math.max(layout.heat, 40)); } // gentle reheat: neighbours follow, the rest barely moves
        else { view.x += x - drag.sx; view.y += y - drag.sy; drag.sx = x; drag.sy = y; }
        redraw();
      }
    } else {
      const id = nodeAt(x, y);
      if (id !== hover) { hover = id; canvas.style.cursor = id ? "pointer" : "default"; redraw(); }
    }
  });
  addEventListener("mouseup", () => {
    if (!drag) return;
    const d = drag; drag = null;
    if (d.moved && d.id) layout.setHeat(Math.min(layout.heat, 24)); // cool down quickly after a drop
    if (!d.moved && d.id) void click(d.id);
  });
  canvas.addEventListener("wheel", (e) => {
    e.preventDefault();
    refit = false; // the user took over the view
    const [x, y] = pos(e), k = Math.max(0.05, Math.min(8, view.k * Math.exp(-e.deltaY * 0.0015)));
    view.x = x - ((x - view.x) / view.k) * k; view.y = y - ((y - view.y) / view.k) * k; view.k = k;
    redraw();
  }, { passive: false });
  new ResizeObserver(() => { if (!view.x && !view.y) { view.x = canvas.clientWidth / 2; view.y = canvas.clientHeight / 2; } redraw(); }).observe(canvas);

  async function click(id: string) {
    const n = g.nodes.find((x) => x.id === id);
    if (!n) return;
    try {
      if (n.kind === "note") await api.showNote(id);
      else if (n.kind === "folder") {
        const readme = id ? `${id}/README.md` : "README.md";
        if (g.nodes.some((x) => x.id === readme)) await api.showNote(readme);
      } else {
        const path = await api.createNote(id.replace(/^ghost:/, "").replace(/\.md$/, ""));
        await api.showNote(path);
      }
    } catch (e) { toast(String(e), true); }
  }

  await listen<{ paths: string[] }>("vault-changed", (e) => {
    if (e.payload.paths.every((p) => p.startsWith(".constellation/"))) return; // our own filter save: don't rebuild the panel under the user's mouse
    void reload("vault " + e.payload.paths.join(",")); void renderPanel();
  });
  await listen<string | null>("current-note", (e) => { current = e.payload; if (local) void reload("current-note"); else redraw(); });
  await listen("settings-changed", async () => { await loadTheme(); redraw(); });

  // Wrap `local` toggling so the panel's checkbox triggers a reload through save(); it only persists the filter too.
  await renderPanel();
  await reload("init");
}
