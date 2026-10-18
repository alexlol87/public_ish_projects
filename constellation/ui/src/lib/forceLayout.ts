export interface Point { x: number; y: number }

const SPRING = 60, REPULSION = 2000, DAMPING = 0.85, THETA = 0.8, MAX_STEP = 30;

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

  /** Takes positions computed elsewhere (same ids, same order); pinned Nodes keep theirs. */
  setPositions(x: Float64Array, y: Float64Array) {
    for (let i = 0; i < this.ids.length; i++) if (!this.pinned.has(i)) { this.x[i] = x[i]; this.y[i] = y[i]; }
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

  // Quadtree storage, reused between steps: cell c has centre (cx,cy), half-size ch, mass, centre-of-mass sums
  // (sx,sy), the one body it holds (-1: none) and four child slots at kids[4c..4c+3] (-1: none).
  private cap = 0;
  private cx = new Float64Array(0); private cy = new Float64Array(0); private ch = new Float64Array(0);
  private cm = new Int32Array(0); private sx = new Float64Array(0); private sy = new Float64Array(0);
  private body = new Int32Array(0); private kids = new Int32Array(0);
  private grow(cap: number) {
    const f = <T extends Float64Array | Int32Array>(a: T, k = 1): T => { const b = new (a.constructor as new (n: number) => T)(cap * k); b.set(a); return b; };
    this.cx = f(this.cx); this.cy = f(this.cy); this.ch = f(this.ch); this.cm = f(this.cm);
    this.sx = f(this.sx); this.sy = f(this.sy); this.body = f(this.body); this.kids = f(this.kids, 4);
    this.cap = cap;
  }

  step() {
    const { x: px, y: py, vx, vy } = this;
    const n = this.ids.length;
    if (n === 0) return;
    // Build the quadtree.
    let side = 1;
    for (let i = 0; i < n; i++) side = Math.max(side, Math.abs(px[i]), Math.abs(py[i]));
    if (this.cap < 4 * n + 16) this.grow(4 * n + 16);
    let used = 0;
    const newCell = (x: number, y: number, half: number) => {
      if (used === this.cap) this.grow(this.cap * 2);
      const c = used++;
      this.cx[c] = x; this.cy[c] = y; this.ch[c] = half; this.cm[c] = 0; this.sx[c] = 0; this.sy[c] = 0; this.body[c] = -1;
      this.kids.fill(-1, 4 * c, 4 * c + 4);
      return c;
    };
    newCell(0, 0, side + 1);
    const child = (c: number, q: number) => {
      const k = 4 * c + q;
      if (this.kids[k] >= 0) return this.kids[k];
      const h = this.ch[c] / 2;
      const kid = newCell(this.cx[c] + (q & 1 ? h : -h), this.cy[c] + (q & 2 ? h : -h), h);
      return (this.kids[k] = kid);
    };
    const quadrant = (c: number, x: number, y: number) => (x >= this.cx[c] ? 1 : 0) + (y >= this.cy[c] ? 2 : 0);
    for (let i = 0; i < n; i++) {
      let c = 0, depth = 0;
      for (;;) {
        this.cm[c]++; this.sx[c] += px[i]; this.sy[c] += py[i];
        if (this.cm[c] === 1) { this.body[c] = i; break; }
        const b = this.body[c];
        if (b >= 0) {
          if (depth >= 32) break; // coincident bodies: counted in mass, not split further
          this.body[c] = -1;
          const kid = child(c, quadrant(c, px[b], py[b]));
          this.cm[kid] = 1; this.sx[kid] = px[b]; this.sy[kid] = py[b]; this.body[kid] = b;
        }
        c = child(c, quadrant(c, px[i], py[i])); depth++;
      }
    }
    const { cm, sx, sy, ch, body, kids } = this;
    const fx = new Float64Array(n), fy = new Float64Array(n);
    const stack = new Int32Array(4 * 40 + 8);
    const t2 = THETA * THETA;
    for (let i = 0; i < n; i++) {
      fx[i] -= px[i] * 0.01; fy[i] -= py[i] * 0.01;
      let sp = 0;
      stack[sp++] = 0;
      while (sp > 0) {
        const c = stack[--sp];
        if (body[c] === i) continue;
        let dx = px[i] - sx[c] / cm[c];
        const dy = py[i] - sy[c] / cm[c];
        if (dx === 0 && dy === 0) dx = 0.1;
        const d2 = Math.max(dx * dx + dy * dy, 1);
        if (body[c] >= 0 || 4 * ch[c] * ch[c] < t2 * d2) {
          const d = Math.sqrt(d2), f = (cm[c] * REPULSION) / d2;
          fx[i] += (f * dx) / d; fy[i] += (f * dy) / d;
        } else for (let q = 4 * c; q < 4 * c + 4; q++) if (kids[q] >= 0) stack[sp++] = kids[q];
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
