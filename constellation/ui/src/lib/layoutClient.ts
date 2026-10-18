import { ForceLayout, type Point } from "./forceLayout";

/**
 * A ForceLayout stepped in a Web Worker. `local` holds the positions the UI reads (and the pins); the worker's
 * snapshots overwrite them. `heat` is the number of steps still to run.
 */
export class WorkerLayout {
  heat = 0;
  private local = new ForceLayout([], []);
  private gen = 0;
  private worker = new Worker(new URL("./layoutWorker.ts", import.meta.url), { type: "module" });

  constructor(onFrame: () => void) {
    this.worker.onmessage = (e: MessageEvent<{ gen: number; heat: number; x: Float64Array; y: Float64Array }>) => {
      const m = e.data;
      if (m.gen !== this.gen) return; // from before the last update()
      this.local.setPositions(m.x, m.y);
      this.heat = m.heat;
      onFrame();
    };
  }

  update(ids: string[], edges: [string, string][]) {
    this.local.update(ids, edges);
    this.worker.postMessage({ t: "update", ids, edges, gen: ++this.gen });
  }
  setHeat(n: number) { this.heat = n; this.worker.postMessage({ t: "heat", n }); }
  get(id: string): Point | undefined { return this.local.get(id); }
  pin(id: string, p: Point) { this.local.pin(id, p); this.worker.postMessage({ t: "pin", id, p }); }
}
