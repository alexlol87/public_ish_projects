// Scale test (not part of `npm run e2e`): generates a ~5,000-Note Vault, opens it in the release app and measures
// launch, tree, typing, search, tags, inspector, graph and a 200-file agent rewrite. Fails if search is slow.
// Run: `npm run e2e:perf` (after building the release binary, as for `npm run e2e`).
import fs from "node:fs";
import path from "node:path";
import { genVault } from "./genvault.mjs";
import { launch, sleep, tmp } from "./lib.mjs";

const vault = tmp("scale");
const files = genVault(vault);
console.log(`vault: ${vault} (${files} files)`);
const note = (k, v) => { console.log(k.padEnd(40), typeof v === "number" ? v.toFixed(0) + (k.includes("fps") ? "" : " ms") : v); };
const failures = [];
const app = await launch({ vault, config: tmp("cfg-scale") });
const inv = (cmd, args) => app.eval(`const t = performance.now(); await window.__TAURI_INTERNALS__.invoke(A[0], A[1]); return performance.now() - t;`, cmd, args);
/** Main-thread stalls: largest gap between animation frames over `ms`, while `during` runs (in node). */
const frameGaps = async (ms, during = async () => {}) => {
  await app.eval(() => { const s = (window.__gaps = { max: 0, n: 0, last: performance.now(), on: true }); const f = () => { const t = performance.now(); s.max = Math.max(s.max, t - s.last); s.n++; s.last = t; if (s.on) requestAnimationFrame(f); }; requestAnimationFrame(f); });
  const t0 = Date.now();
  await during();
  await sleep(Math.max(0, ms - (Date.now() - t0)));
  return app.eval((ms) => { const s = window.__gaps; s.on = false; return { maxGap: s.max, fps: (s.n * 1000) / ms }; }, ms);
};

try {
  // ---- launch ----
  const ready = await app.until(() => document.querySelector(".cm-content") && document.querySelector(".row-item") && performance.now(), "main window", 60000);
  note("launch: page load to interactive", ready);

  // ---- tree: expand a project folder and a repo ----
  for (const f of ["project-01", "project-01/svc01-cart"]) {
    note(`tree: expand ${f}`, await app.eval(async (f) => {
      const t = performance.now(), before = document.querySelectorAll(".row-item").length;
      document.querySelector(`.row-item[title='${f}']`).click();
      while (document.querySelectorAll(".row-item").length === before) await new Promise(requestAnimationFrame);
      return performance.now() - t;
    }, f));
  }
  note("tree: invoke tree", await inv("tree"));

  // ---- typing: open endpoints.md and type, timing keydown -> next frame ----
  await app.eval(() => document.querySelector(".row-item[title='project-01/svc01-cart/endpoints.md']").click());
  await app.until(() => document.querySelector(".tab.active")?.title === "project-01/svc01-cart/endpoints.md", "tab");
  await app.eval(() => {
    const v = document.querySelector(".cm-content").cmTile.view; v.focus(); v.dispatch({ selection: { anchor: v.state.doc.toString().indexOf("Summary:") } });
    window.__keys = []; addEventListener("keydown", () => { const t = performance.now(); requestAnimationFrame(() => setTimeout(() => window.__keys.push(performance.now() - t))); }, true);
  });
  const typing = await frameGaps(4000, () => app.type("quick brown fox jumps over the lazy dog "));
  const keys = await app.eval(() => window.__keys);
  note("typing: keydown to frame, median", keys.sort((a, b) => a - b)[keys.length >> 1]);
  note("typing: keydown to frame, max", Math.max(...keys));
  note("typing: max frame gap (incl. autosave)", typing.maxGap);

  // ---- inspector ----
  const text = await app.eval(() => document.querySelector(".cm-content").cmTile.view.state.doc.toString());
  note("inspector: invoke inspect", await inv("inspect", { path: "project-01/svc01-cart/endpoints.md", text, offset: text.indexOf("Calls:") }));
  note("inspector: invoke inspect (README)", await inv("inspect", { path: "project-01/svc01-cart/README.md", text: "# x", offset: 0 }));
  note("broken links: invoke", await inv("broken_targets", { text }));

  // ---- search, per keystroke ----
  let worst = 0;
  for (const q of ["w", "we", "web", "webh", "webho", "webhook", "#payments", "#payments refund"]) {
    const ms = await inv("search", { query: q });
    worst = Math.max(worst, ms);
    note(`search: invoke "${q}"`, ms);
  }
  const ui = await app.eval(async () => {
    const i = document.querySelector("#search"), list = document.querySelectorAll(".side .list")[1];
    const t = performance.now(); const before = list.innerHTML;
    i.value = "refund retry"; i.dispatchEvent(new Event("input"));
    while (list.innerHTML === before) await new Promise(requestAnimationFrame);
    return performance.now() - t;
  });
  note("search: UI incl. 120 ms debounce", ui);
  if (worst > 100) failures.push(`search took ${worst.toFixed(0)} ms (limit 100)`);
  await app.eval(() => { const i = document.querySelector("#search"); i.value = ""; i.dispatchEvent(new Event("input")); });
  await sleep(300);

  // ---- tags tab ----
  note("tags: open tab", await app.eval(async () => {
    const t = performance.now(); document.querySelector("#tab-tags").click();
    while (!document.querySelector("#tag-sort")) await new Promise(requestAnimationFrame);
    return performance.now() - t;
  }));
  note("tags: invoke tag_hits payments", await inv("tag_hits", { tag: "payments" }));
  note("tags: open #payments hits", await app.eval(async () => {
    const t = performance.now(); [...document.querySelectorAll(".row-item")].find((r) => r.textContent.startsWith("#payments")).click();
    while (!document.querySelector(".row-item.match")) await new Promise(requestAnimationFrame);
    return performance.now() - t;
  }));
  await app.eval(() => document.querySelector("#tab-files").click());

  // ---- agent rewrites 200 files ----
  const all = fs.readdirSync(vault, { recursive: true }).filter((p) => p.endsWith(".md")).slice(0, 200);
  const storm = await frameGaps(6000, async () => {
    for (const p of all) fs.appendFileSync(path.join(vault, p), "\nAgent edit.\n");
    fs.appendFileSync(path.join(vault, "project-01/svc01-cart/endpoints.md"), "\nAGENT WAS HERE\n");
  });
  note("rewrite 200: max frame gap", storm.maxGap);
  note("rewrite 200: open tab reloaded", String(await app.eval(() => document.querySelector(".cm-content").cmTile.view.state.doc.toString().includes("AGENT WAS HERE"))));

  // ---- graph window ----
  const t0 = Date.now();
  await app.eval(() => window.__TAURI_INTERNALS__.invoke("open_graph"));
  await app.focusWindow("view=graph");
  await app.until(() => document.querySelector("#graph-canvas")?.e2e?.().nodes.length > 0, "graph nodes", 60000);
  note("graph: open to first nodes", Date.now() - t0);
  const g = await app.eval(() => { const s = document.querySelector("#graph-canvas").e2e(); return { nodes: s.nodes.length, edges: s.edges }; });
  note("graph: nodes / edges", `${g.nodes} / ${g.edges}`);
  const settle = await frameGaps(3000);
  note("graph: fps while laying out", settle.fps); note("graph: max frame gap while laying out", settle.maxGap);
  const st = Date.now();
  await app.until(() => document.querySelector("#graph-canvas").e2e().heat === 0, "layout settled", 120000);
  note("graph: settle (after the 3 s above)", Date.now() - st);
  note("graph: invoke graph", await inv("graph", { filter: await app.eval(() => window.__TAURI_INTERNALS__.invoke("graph_filter")), around: null }));
  const idle = await frameGaps(2000, () => app.pointer("#graph-canvas", [["move", 0, 0], ["move", 40, 30], ["move", 80, 60], ["move", -50, 20], ["move", 10, -40]]));
  note("graph: fps while hovering, settled", idle.fps); note("graph: max frame gap hovering", idle.maxGap);
} catch (e) {
  failures.push(e.message);
} finally {
  await app.close();
  fs.rmSync(vault, { recursive: true, force: true });
}
if (failures.length) { console.log("FAIL", failures.join("; ")); process.exit(1); }
console.log("ok   scale");
