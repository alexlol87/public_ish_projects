// Tiny WebDriver client for tauri-driver (Linux only). No dependencies: plain fetch + child_process.
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const BIN = path.join(process.env.CARGO_TARGET_DIR || path.resolve(import.meta.dirname, "../target"), "release/constellation");
const BASE = "http://127.0.0.1:4444";

let xvfb;
/** A private X display when Xvfb is installed (a real display may be locked or blanked, which stops WebKit painting
 *  and makes screenshots hang); otherwise the current DISPLAY is used. Set E2E_REAL_DISPLAY=1 to force that. */
function display() {
  if (xvfb || process.env.E2E_REAL_DISPLAY || spawnSync("which", ["Xvfb"]).status !== 0) return process.env.DISPLAY;
  const num = 90 + (process.pid % 9);
  xvfb = spawn("Xvfb", [":" + num, "-screen", "0", "1600x1000x24", "-nolisten", "tcp"], { stdio: "ignore" });
  xvfb.unref();
  process.on("exit", () => xvfb.kill());
  process.env.DISPLAY = ":" + num;
  return process.env.DISPLAY;
}

/** Closes or focuses (`action`) the top-level X window titled `title` (see xwin.py). */
export function xwin(action, title) {
  const r = spawnSync("python3", ["-I", path.join(import.meta.dirname, "xwin.py"), action, title], { env: process.env });
  return r.status === 0;
}

export const KEYS = { Control: "", Shift: "", Alt: "", Enter: "", Escape: "", Backspace: "", ArrowDown: "", ArrowUp: "", ArrowLeft: "", ArrowRight: "", Tab: "", Home: "", End: "", Delete: "" };

async function wd(method, p, body) {
  const r = await fetch(BASE + p, { method, headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const j = await r.json();
  if (j.value && j.value.error) throw new Error(`${j.value.error}: ${j.value.message}`);
  return j.value;
}

/** Starts tauri-driver (it passes its environment on to the app) and a session. */
export async function launch({ vault, config, env = {} }) {
  if (!process.env.E2E_EXTERNAL) for (const n of ["tauri-driver", "WebKitWebDriver", "constellation"]) spawnSync("pkill", ["-x", n]); // leftovers of a killed run
  await sleep(300);
  display();
  await sleep(xvfb && !xvfb.ready ? 1500 : 0); if (xvfb) xvfb.ready = true;
  const e = { ...process.env, WEBKIT_DISABLE_DMABUF_RENDERER: "1", XDG_CONFIG_HOME: config, ...env };
  delete e.CONSTELLATION_VAULT;
  if (vault) e.CONSTELLATION_VAULT = vault;
  const driver = process.env.E2E_EXTERNAL ? { pid: 0 } : spawn("tauri-driver", [], { env: e, stdio: process.env.E2E_STDIO ? "inherit" : "ignore", detached: !process.env.E2E_NODETACH });
  for (let i = 0; i < 50; i++) { try { await fetch(BASE + "/status"); break; } catch { await sleep(100); } }
  const s = await wd("POST", "/session", { capabilities: { alwaysMatch: { "tauri:options": { application: BIN } } } });
  await sleep(500);
  xwin("focus", "Constellation");
  return new App(driver, "/session/" + s.sessionId);
}

export class App {
  constructor(driver, id) { this.driver = driver; this.id = id; }
  req(method, p, body) { return wd(method, this.id + p, body); }
  /** Runs `body` (a function body string or function) in the page; returns its value. Async bodies may `await`. */
  async eval(fn, ...args) {
    // String bodies see their arguments as `A`.
    const src = typeof fn === "function" ? `return (${fn})(...A)` : fn;
    const script = `const A = arguments[0]; const done = arguments[1]; (async () => { ${src} })().then(done, (e) => done({__err: String(e && (e.message || e.stack) || e)}));`;
    const v = await this.req("POST", "/execute/async", { script, args: [args] });
    if (v && v.__err) throw new Error("page: " + v.__err);
    return v;
  }
  async el(css) { const r = await this.req("POST", "/element", { using: "css selector", value: css }); return Object.values(r)[0]; }
  async has(css) { return this.eval((c) => !!document.querySelector(c), css); }
  /** Waits until `fn` (run in the page) returns truthy. */
  async until(fn, what = "condition", ms = 8000, ...args) {
    const end = Date.now() + ms;
    let last;
    while (Date.now() < end) { try { last = await this.eval(fn, ...args); if (last) return last; } catch (e) { last = e.message; } await sleep(100); }
    throw new Error(`timeout waiting for ${what} (last: ${JSON.stringify(last)})`);
  }
  /** Real click (pointer events) on the first element matching `css`; `text` picks the first one containing it. */
  async click(css, text) {
    for (let i = 0; ; i++) {
      try { await this.req("POST", `/element/${await this.el(await this.mark(css, text))}/click`, {}); return; }
      catch (e) { if (i >= 5 || !/stale|not interactable|no such element|intercepted/.test(e.message)) throw e; await sleep(300); } // the UI re-renders after file events
    }
  }
  /** Marks the first element matching `css` (containing `text`) with data-e2e and returns a selector for it. */
  async mark(css, text) {
    await this.eval((c, t) => { document.querySelectorAll("[data-e2e]").forEach((x) => x.removeAttribute("data-e2e")); const el = [...document.querySelectorAll(c)].find((x) => t == null || x.textContent.includes(t)); if (!el) throw new Error(`no ${c}${t ? " with text " + t : ""}`); el.setAttribute("data-e2e", "1"); }, css, text);
    return "[data-e2e='1']";
  }
  /**
   * Mouse sequence relative to the centre of an element: steps are ["move", dx, dy] | ["down", button] | ["up", button];
   * `ctrl` holds Control throughout.
   */
  async pointer(css, steps, { ctrl = false, text } = {}) {
    const id = await this.el(await this.mark(css, text));
    const origin = { "element-6066-11e4-a52e-4f735466cecf": id };
    const pt = [], key = [];
    const tick = (p, k) => { pt.push(p); key.push(k ?? { type: "pause", duration: 0 }); };
    if (ctrl) tick({ type: "pause", duration: 0 }, { type: "keyDown", value: KEYS.Control });
    for (const [kind, a, b] of steps) {
      if (kind === "move") tick({ type: "pointerMove", duration: 50, origin, x: Math.round(a), y: Math.round(b) });
      else tick({ type: kind === "down" ? "pointerDown" : "pointerUp", button: a ?? 0 });
    }
    if (ctrl) tick({ type: "pause", duration: 0 }, { type: "keyUp", value: KEYS.Control });
    await this.req("POST", "/actions", { actions: [{ type: "pointer", id: "m", parameters: { pointerType: "mouse" }, actions: pt }, { type: "key", id: "kb", actions: key }] });
    await this.req("DELETE", "/actions");
  }
  rightClick(css, text) { return this.pointer(css, [["move", 0, 0], ["down", 2], ["up", 2]], { text }); }
  ctrlClick(css, text) { return this.pointer(css, [["move", 0, 0], ["down", 0], ["up", 0]], { ctrl: true, text }); }
  async actions(seq) { await this.req("POST", "/actions", { actions: [{ type: "key", id: "kb", actions: seq }] }); await this.req("DELETE", "/actions"); }
  /** Types text into whatever has focus. */
  async type(text) { await this.actions([...text].flatMap((c) => [{ type: "keyDown", value: c }, { type: "keyUp", value: c }])); }
  /** `press("Control", "z")`: chord of keys (names from KEYS or single characters). */
  async press(...keys) {
    const k = keys.map((x) => KEYS[x] ?? x);
    await this.actions([...k.map((value) => ({ type: "keyDown", value })), ...[...k].reverse().map((value) => ({ type: "keyUp", value }))]);
  }
  async screenshot(file) { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, Buffer.from(await this.req("GET", "/screenshot"), "base64")); return file; }
  async windows() { return this.req("GET", "/window/handles"); }
  async switchTo(handle) { await this.req("POST", "/window", { handle }); }
  /** Switches to the window whose URL contains `part` ("view=graph") or the one without it when `part` is null. */
  async focusWindow(part) {
    for (let i = 0; i < 50; i++) {
      for (const h of await this.windows()) {
        await this.switchTo(h);
        const u = await this.req("GET", "/url");
        if (part === null ? !u.includes("view=") : u.includes(part)) return h;
      }
      await sleep(200);
    }
    throw new Error("no window " + part);
  }
  async close() {
    try { await wd("DELETE", this.id); } catch {}
    try { process.kill(-this.driver.pid, "SIGKILL"); } catch {}
    await sleep(500);
    for (const n of ["constellation", "WebKitWebDriver"]) spawnSync("pkill", ["-x", n]);
    await sleep(300);
  }
}

export const tmp = (name) => fs.mkdtempSync(path.join(os.tmpdir(), `constellation-e2e-${name}-`));
