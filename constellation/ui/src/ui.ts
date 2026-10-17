/** Tiny DOM helpers: element builder, modal prompt, context menu, toast. */
export function h<K extends keyof HTMLElementTagNameMap>(
  tag: K, props: Partial<Record<string, unknown>> = {}, ...kids: (Node | string | null | undefined | false)[]
): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v === undefined || v === null || v === false) continue;
    if (k === "class") el.className = String(v);
    else if (k.startsWith("on")) el.addEventListener(k.slice(2), v as EventListener);
    else if (k in el) (el as unknown as Record<string, unknown>)[k] = v;
    else el.setAttribute(k, String(v));
  }
  for (const kid of kids) if (kid) el.append(kid);
  return el;
}

export function toast(msg: string, bad = false) {
  const t = h("div", { class: "toast" + (bad ? " bad" : "") }, msg);
  document.body.append(t);
  setTimeout(() => t.remove(), bad ? 6000 : 2500);
}

/** Modal with arbitrary body; resolves when closed. `build` gets a `close` callback. */
export function modal(title: string, build: (close: () => void) => HTMLElement): Promise<void> {
  return new Promise((resolve) => {
    const back = h("div", { class: "modal-back" });
    const close = () => { back.remove(); resolve(); };
    back.addEventListener("mousedown", (e) => e.target === back && close());
    back.addEventListener("keydown", (e) => e.key === "Escape" && close());
    back.append(h("div", { class: "modal" }, h("h3", {}, title), build(close)));
    document.body.append(back);
    (back.querySelector("input,select,button") as HTMLElement | null)?.focus();
  });
}

export async function ask(title: string, value = "", label = ""): Promise<string | null> {
  let out: string | null = null;
  await modal(title, (close) => {
    const input = h("input", { type: "text", value, class: "wide" });
    const ok = () => { out = input.value.trim(); close(); };
    input.addEventListener("keydown", (e) => e.key === "Enter" && ok());
    queueMicrotask(() => { input.focus(); input.select(); });
    return h("div", {}, label && h("p", { class: "muted" }, label), input,
      h("div", { class: "row end" }, h("button", { onclick: close }, "Cancel"), h("button", { class: "primary", onclick: ok }, "OK")));
  });
  return out || null;
}

export function contextMenu(e: MouseEvent, items: [string, () => void][]) {
  e.preventDefault();
  document.querySelector(".ctx")?.remove();
  const m = h("div", { class: "ctx", style: `left:${e.clientX}px;top:${e.clientY}px` },
    ...items.map(([label, run]) => h("div", { class: "ctx-item", onclick: () => { m.remove(); run(); } }, label)));
  document.body.append(m);
  // A press on the menu itself must not remove it before the click lands.
  const off = (ev: Event) => { if (m.contains(ev.target as Node)) return; m.remove(); removeEventListener("mousedown", off, true); };
  setTimeout(() => addEventListener("mousedown", off, true));
}
