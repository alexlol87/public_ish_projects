import { ForceLayout } from "./forceLayout";

// Runs the layout steps off the main thread (big graphs: one step is tens of ms); posts positions after each step.
const layout = new ForceLayout([], []);
let heat = 0, gen = 0, running = false;

function tick() {
  if (heat <= 0) return void (running = false);
  layout.step(); heat--;
  const x = layout.x.slice(), y = layout.y.slice();
  postMessage({ gen, heat, x, y }, { transfer: [x.buffer, y.buffer] });
  setTimeout(tick, 0);
}

onmessage = (e: MessageEvent) => {
  const m = e.data;
  if (m.t === "update") { layout.update(m.ids, m.edges); gen = m.gen; }
  else if (m.t === "pin") layout.pin(m.id, m.p);
  else if (m.t === "heat") heat = m.n;
  if (heat > 0 && !running) { running = true; setTimeout(tick, 0); }
};
