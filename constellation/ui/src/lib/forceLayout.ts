export interface Point { x: number; y: number }

const SPRING = 60, REPULSION = 2000, DAMPING = 0.85, THETA = 0.8, MAX_STEP = 30;

interface Cell { x: number; y: number; half: number; mass: number; sx: number; sy: number; body: number; kids: number[] }
const cell = (x: number, y: number, half: number): Cell => ({ x, y, half, mass: 0, sx: 0, sy: 0, body: -1, kids: [-1, -1, -1, -1] });

/**
 * Force-directed layout (repulsion, springs, centring), stepped from requestAnimationFrame.
 * Repulsion uses a Barnes-Hut quadtree (O(n log n)), so 5,000 Nodes stay interactive.
 * Read `x`/`y` (parallel to `ids`) to draw. Positions are not persisted.
 */
export class ForceLayout {
  ids: string[] = [];
  x = new Float64Array(0);
  y = new Float64Array(0);
  private vx = new Float64Array(0);
  private vy = new Float64Array(0);
  private index = new Map<string, number>();
  private edges: [number, number][] = [];
  private pinned = new Set<number>();

  constructor(ids: string[], edges: [string, string][]) { this.update(ids, edges); }

  /** Keeps positions of surviving ids; new ids start on a deterministic spiral. */
  update(ids: string[], edges: [string, string][]) {
    const old = { ids: this.ids, x: this.x, y: this.y, index: this.index, pinned: this.pinned };
    this.ids = ids;
    this.index = new Map(ids.map((id, i) => [id, i]));
    this.x = new Float64Array(ids.length); this.y = new Float64Array(ids.length);
    this.vx = new Float64Array(ids.length); this.vy = new Float64Array(ids.length);
    this.pinned = new Set();
    ids.forEach((id, i) => {
      const o = old.index.get(id);
      if (o !== undefined) {
        this.x[i] = old.x[o]; this.y[i] = old.y[o];
        if (old.pinned.has(o)) this.pinned.add(i);
      } else {
        const a = i * 2.4, r = 20 * Math.sqrt(i + 1);
        this.x[i] = r * Math.cos(a); this.y[i] = r * Math.sin(a);
      }
    });
    this.edges = edges.flatMap(([a, b]) => {
      const i = this.index.get(a), j = this.index.get(b);
      return i === undefined || j === undefined ? [] : [[i, j] as [number, number]];
    });
  }

  get(id: string): Point | undefined {
    const i = this.index.get(id);
    return i === undefined ? undefined : { x: this.x[i], y: this.y[i] };
  }

  /** Pins a Node at `p` while the user drags it; it still repels the others. */
  pin(id: string, p: Point) {
    const i = this.index.get(id);
    if (i === undefined) return;
    this.x[i] = p.x; this.y[i] = p.y; this.vx[i] = 0; this.vy[i] = 0;
    this.pinned.add(i);
  }

  unpin(id: string) {
    const i = this.index.get(id);
    if (i !== undefined) this.pinned.delete(i);
  }

  step() {
    const { x: px, y: py, vx, vy } = this;
    const n = this.ids.length;
    if (n === 0) return;
    // Build the quadtree.
    let side = 1;
    for (let i = 0; i < n; i++) side = Math.max(side, Math.abs(px[i]), Math.abs(py[i]));
    const cells = [cell(0, 0, side + 1)];
    const quadrant = (c: Cell, x: number, y: number) => (x >= c.x ? 1 : 0) + (y >= c.y ? 2 : 0);
    const child = (c: number, q: number) => {
      if (cells[c].kids[q] >= 0) return cells[c].kids[q];
      const p = cells[c], h = p.half / 2;
      cells.push(cell(p.x + (q & 1 ? h : -h), p.y + (q & 2 ? h : -h), h));
      return (p.kids[q] = cells.length - 1);
    };
    for (let i = 0; i < n; i++) {
      let c = 0, depth = 0;
      for (;;) {
        const k = cells[c];
        k.mass++; k.sx += px[i]; k.sy += py[i];
        if (k.mass === 1) { k.body = i; break; }
        if (k.body >= 0) {
          if (depth >= 32) break; // coincident bodies: counted in mass, not split further
          const b = k.body;
          k.body = -1;
          const kid = cells[child(c, quadrant(k, px[b], py[b]))];
          kid.mass = 1; kid.sx = px[b]; kid.sy = py[b]; kid.body = b;
        }
        c = child(c, quadrant(cells[c], px[i], py[i])); depth++;
      }
    }
    const fx = new Float64Array(n), fy = new Float64Array(n);
    const stack: number[] = [];
    const t2 = THETA * THETA;
    for (let i = 0; i < n; i++) {
      fx[i] -= px[i] * 0.01; fy[i] -= py[i] * 0.01;
      stack.push(0);
      for (let c; (c = stack.pop()) !== undefined; ) {
        const k = cells[c];
        if (k.body === i) continue;
        let dx = px[i] - k.sx / k.mass;
        const dy = py[i] - k.sy / k.mass;
        if (dx === 0 && dy === 0) dx = 0.1;
        const d2 = Math.max(dx * dx + dy * dy, 1);
        if (k.body >= 0 || 4 * k.half * k.half < t2 * d2) {
          const d = Math.sqrt(d2), f = (k.mass * REPULSION) / d2;
          fx[i] += (f * dx) / d; fy[i] += (f * dy) / d;
        } else for (const kid of k.kids) if (kid >= 0) stack.push(kid);
      }
    }
    for (const [i, j] of this.edges) {
      const dx = px[j] - px[i], dy = py[j] - py[i], d = Math.max(Math.hypot(dx, dy), 0.01);
      const k = (0.05 * (d - SPRING)) / d;
      fx[i] += k * dx; fy[i] += k * dy;
      fx[j] -= k * dx; fy[j] -= k * dy;
    }
    for (let i = 0; i < n; i++) {
      if (this.pinned.has(i)) continue;
      let ux = (vx[i] + fx[i]) * DAMPING, uy = (vy[i] + fy[i]) * DAMPING;
      const m = Math.hypot(ux, uy);
      if (m > MAX_STEP) { ux *= MAX_STEP / m; uy *= MAX_STEP / m; }
      vx[i] = ux; vy[i] = uy;
      px[i] += ux; py[i] += uy;
    }
  }
}
