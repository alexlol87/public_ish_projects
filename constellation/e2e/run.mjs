// End-to-end tests: drives the release binary through tauri-driver (Linux only). `npm run e2e` builds first.
import fs from "node:fs";
import path from "node:path";
import { launch, sleep, tmp, xwin } from "./lib.mjs";
import { makeVault } from "./vault.mjs";

const OUT = path.resolve(import.meta.dirname, "out");
const results = [];
let app, vault, current = "";
const only = process.argv[2];

async function test(name, fn) {
  if (only && !name.includes(only)) return;
  current = name;
  try { await fn(); results.push([name, true]); console.log("ok   ", name); }
  catch (e) {
    results.push([name, false, e.message]); console.log("FAIL ", name, "\n      ", e.message.split("\n").slice(0, 8).join("\n       "));
    await app?.screenshot(path.join(OUT, name.replace(/\W+/g, "_") + ".png")).catch(() => {});
  }
}
const eq = (a, b, what) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${what}: expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`); };
const ok = (c, what) => { if (!c) throw new Error("expected " + what); };
const disk = (p) => fs.readFileSync(path.join(vault, p), "utf8");
const write = (p, t) => { fs.mkdirSync(path.dirname(path.join(vault, p)), { recursive: true }); fs.writeFileSync(path.join(vault, p), t); };

const VIEW = "document.querySelector('.cm-content').cmTile.view";
const doc = () => app.eval(`return ${VIEW}.state.doc.toString()`);
const activeTab = () => app.eval(() => document.querySelector(".tab.active")?.title ?? null);
const tabs = () => app.eval(() => [...document.querySelectorAll(".tab")].map((t) => t.title));
/** Puts the caret at `pos` (number) or just after the first occurrence of `text`; focuses the editor. */
const caret = (where) => app.eval(`const v = ${VIEW}; const d = v.state.doc.toString(); const p = typeof A[0] === 'number' ? A[0] : d.indexOf(A[0]) + A[0].length; v.focus(); v.dispatch({ selection: { anchor: p } }); return p;`, where);
const selectText = (text) => app.eval(`const v = ${VIEW}; const i = v.state.doc.toString().indexOf(A[0]); v.focus(); v.dispatch({ selection: { anchor: i, head: i + A[0].length } }); return i;`, text);
const rowExists = (p) => app.eval((p) => [...document.querySelectorAll(".row-item")].some((r) => r.title === p), p);
/** Expands the folders above `p`, waits for its row and opens it. */
const openRow = async (p) => {
  const parts = p.split("/");
  for (let i = 1; i < parts.length; i++) {
    const dir = parts.slice(0, i).join("/");
    await app.until((p) => [...document.querySelectorAll(".row-item")].some((r) => r.title === p), "folder row " + dir, 5000, dir);
    if (!(await app.eval((f) => document.querySelector(`.row-item[title='${f}'] .chev`).textContent === "▾", dir))) await app.eval((f) => document.querySelector(`.row-item[title='${f}']`).click(), dir);
    await sleep(150);
  }
  await app.until((p) => [...document.querySelectorAll(".row-item")].some((r) => r.title === p), "row " + p, 5000, p);
  await app.eval((p) => document.querySelector(`.row-item[title='${p}']`).click(), p);
  await app.until((p) => document.querySelector(".tab.active")?.title === p, "tab " + p, 5000, p);
};
const expand = async (folder) => { if (!(await app.has(`.row-item[title='${folder}']`))) throw new Error("no folder " + folder); if (!(await app.eval((f) => document.querySelector(`.row-item[title='${f}'] .chev`).textContent === "▾", folder))) await app.click(`.row-item[title='${folder}']`); };
const waitDoc = (frag, ms) => app.until(`return ${VIEW}.state.doc.toString().includes(A[0])`, "doc containing " + frag, ms ?? 6000, frag);
const side = (t) => app.click(`#tab-${t}`);
const search = async (q) => { await app.eval((q) => { const i = document.querySelector("#search"); i.value = q; i.dispatchEvent(new Event("input")); }, q); await sleep(450); };
const resultsText = () => app.eval(() => document.querySelector(".side .list:not([hidden])").innerText);
/** Fills the open dialog's text box and confirms with Enter (WebDriver typing drops Shift for capitals in inputs). */
const fillModal = async (text) => {
  await app.until(() => document.querySelector(".modal input"), "dialog");
  await app.eval((t) => { const i = document.querySelector(".modal input"); i.value = t; }, text);
  await app.press("Enter");
};
const shot = (n) => app.screenshot(path.join(OUT, n + ".png"));

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(OUT, { recursive: true });

// ---------- first launch ----------
{
  const full = tmp("nonempty");
  fs.writeFileSync(path.join(full, "keep.txt"), "mine\n");
  app = await launch({ config: tmp("cfg-nonempty"), env: { CONSTELLATION_E2E_PICK: full } });
  await test("create vault refuses a non-empty folder and writes nothing", async () => {
    await app.until(() => document.querySelector("#create-vault"), "welcome");
    await app.click("#create-vault");
    const msg = await app.until(() => document.querySelector(".welcome .bad")?.textContent, "error message");
    ok(/not empty/.test(msg) && /empty folder/.test(msg), "clear error, got: " + msg);
    eq(fs.readdirSync(full), ["keep.txt"], "folder contents");
    ok(await app.has("#create-vault"), "still on the welcome screen");
  });
  await app.close();
}
{
  const cfg = tmp("cfg-first"), target = tmp("newvault");
  app = await launch({ config: cfg, env: { CONSTELLATION_E2E_PICK: target } });
  await test("first launch: welcome offers create/open", async () => {
    await app.until(() => document.querySelector("#create-vault"), "welcome");
    await shot("00-welcome");
  });
  await test("first launch: create writes the scaffold", async () => {
    await app.click("#create-vault");
    await app.until(() => document.querySelector(".cm-content"), "editor after create");
    for (const f of ["README.md", "AGENTS.md", "repos.txt", "tags.md", "templates", "external", "clients"]) ok(fs.existsSync(path.join(target, f)), "scaffold file " + f);
  });
  await app.close();
  app = await launch({ config: cfg });
  await test("last vault is reopened at launch", async () => {
    await app.until(() => document.querySelector(".cm-content"), "editor on relaunch");
    ok((await app.eval(() => document.querySelector(".vault-name").textContent)).startsWith("constellation-e2e-newvault"), "vault name");
  });
  await app.close();
}

// ---------- main window ----------
vault = makeVault();
const cfg = tmp("cfg-main");
app = await launch({ vault, config: cfg });
await app.until(() => document.querySelector(".cm-content"), "editor");

await test("tree: folders, app-only files dimmed, README opened", async () => {
  const names = await app.eval(() => [...document.querySelectorAll(".row-item")].map((r) => [r.title, r.classList.contains("dim")]));
  ok(names.some(([t, d]) => t === "AGENTS.md" && d), "AGENTS.md dimmed");
  ok(names.some(([t, d]) => t === "templates" && d), "templates dimmed");
  ok(names.some(([t, d]) => t === "README.md" && !d), "README.md normal");
  eq(await activeTab(), "README.md", "active tab");
  await shot("01-main");
});

await test("folder click opens its README", async () => {
  await app.click(".row-item[title='acme-shop']");
  await app.until(() => document.querySelector(".tab.active")?.title === "acme-shop/README.md", "acme-shop README");
  await expand("acme-shop");
  await app.click(".row-item[title='acme-shop/cart-service']");
  await app.until(() => document.querySelector(".tab.active")?.title === "acme-shop/cart-service/README.md", "cart README");
});

await test("live preview hides markers off the cursor line", async () => {
  await waitDoc("shopping");
  await caret("Holds");
  const visible = () => app.eval(() => document.querySelector(".cm-content").innerText);
  ok((await visible()).includes("**shopping**"), "markers visible on the cursor line");
  await caret("# Cart service");
  await sleep(150);
  const t = await visible();
  ok(!t.includes("**shopping**") && t.includes("shopping"), "markers hidden elsewhere: " + t);
  const fm = await app.eval(() => document.querySelector(".cm-frontmatter-summary")?.textContent ?? "");
  ok(fm.startsWith("type: repo · repo_url:") && !t.includes("---"), "frontmatter collapsed to a summary: " + fm);
  await shot("02-live-preview");
  await caret("verified_on");
  await app.until(() => !document.querySelector(".cm-frontmatter-summary") && document.querySelectorAll(".cm-frontmatter").length >= 3, "frontmatter raw with the cursor inside");
  await caret("# Cart service");
});

await test("plain click on a link off the cursor line opens it", async () => {
  await caret(0);
  await app.click(".cm-link[data-link='acme-shop/cart-service/endpoints']");
  await app.until(() => document.querySelector(".tab.active")?.title === "acme-shop/cart-service/endpoints.md", "endpoints opened");
});

await test("tabs: several open, switch, close", async () => {
  await openRow("acme-shop/cart-service/README.md");
  ok((await tabs()).length >= 3, "3+ tabs: " + (await tabs()));
  await app.click(".tab", "endpoints");
  eq(await activeTab(), "acme-shop/cart-service/endpoints.md", "switched");
  await app.click(".tab.active .x");
  ok(!(await tabs()).includes("acme-shop/cart-service/endpoints.md"), "closed");
});

const SYNC = "acme-shop/sync.md";
await test("editing autosaves to disk after ~1s", async () => {
  write(SYNC, "# Sync\n\nbody\n");
  await openRow(SYNC);
  await waitDoc("body");
  await caret(await app.eval(`return ${VIEW}.state.doc.length`));
  await app.type(" AUTOSAVED");
  ok(!disk(SYNC).includes("AUTOSAVED"), "not saved instantly");
  await sleep(1700);
  ok(disk(SYNC).includes("AUTOSAVED"), "saved");
});

await test("external edit while clean reloads silently", async () => {
  write(SYNC, disk(SYNC) + "\nEXTERNAL ONE\n");
  await waitDoc("EXTERNAL ONE", 5000);
  ok(await app.eval(() => document.querySelector(".banner").hidden), "no banner");
});

const bannerShown = () => app.until(() => !document.querySelector(".banner").hidden, "conflict banner", 5000);
await test("external edit while dirty shows banner; Keep mine", async () => {
  await caret(await app.eval(`return ${VIEW}.state.doc.length`));
  await app.type(" MINE");
  write(SYNC, "# Theirs\n");
  await bannerShown();
  await shot("03-conflict");
  await app.click("#keep-mine");
  await sleep(700);
  ok(disk(SYNC).includes("MINE"), "mine written");
  ok((await doc()).includes("MINE"), "editor keeps mine");
});

await test("external edit while dirty: Reload from disk", async () => {
  await sleep(700);
  await caret(await app.eval(`return ${VIEW}.state.doc.length`));
  await app.type(" MORE");
  write(SYNC, "# Theirs 2\n");
  await bannerShown();
  await app.click("#reload-disk");
  await waitDoc("# Theirs 2");
  ok(!(await doc()).includes("MORE"), "mine discarded");
  ok(await app.eval(() => document.querySelector(".banner").hidden), "banner gone");
});

await test("toolbar buttons and shortcuts format text", async () => {
  write("acme-shop/scratch.md", "word\n");
  await openRow("acme-shop/scratch.md");
  await waitDoc("word");
  await selectText("word");
  await app.click(".fmt-bold");
  eq((await doc()).split("\n")[0], "**word**", "bold button");
  await app.click(".fmt-bold");
  eq((await doc()).split("\n")[0], "word", "bold toggles off");
  await selectText("word");
  await app.press("Control", "i");
  eq((await doc()).split("\n")[0], "*word*", "Ctrl+I");
  await app.press("Control", "i");
  await app.press("Control", "2");
  eq((await doc()).split("\n")[0], "## word", "Ctrl+2");
  await app.press("Control", "2");
  await selectText("word");
  await app.press("Control", "Shift", "9");
  ok((await doc()).startsWith("- [ ] word"), "task list shortcut: " + (await doc()));
});


await test("per-tab undo history survives tab switches", async () => {
  await openRow(SYNC);
  await caret(await app.eval(`return ${VIEW}.state.doc.length`));
  await app.type("UNDOME");
  await openRow("README.md");
  await openRow(SYNC);
  ok((await doc()).includes("UNDOME"), "text kept");
  await app.eval(`${VIEW}.focus()`);
  await app.press("Control", "z");
  ok(!(await doc()).includes("UNDOME"), "Ctrl+Z undid the typing made before the switch");
});

await test("wikilinks: alias shown, Ctrl-click on the cursor line opens, plain click there does not", async () => {
  await openRow("README.md");
  await caret("Welcome");
  await sleep(150);
  await app.pointer(".cm-link", [["move", 0, 0], ["down", 0], ["up", 0]]);
  await sleep(500);
  eq(await activeTab(), "README.md", "plain click stays");
  await app.ctrlClick(".cm-link");
  await app.until(() => document.querySelector(".tab.active")?.title === "acme-shop/README.md", "Ctrl-click opened the note");
});

await test("broken link is red; click creates the Note", async () => {
  write("acme-shop/links.md", "[[nowhere-note]] and [[acme-shop/README|The Alias]]\n\nsecond line\n");
  await openRow("acme-shop/links.md");
  await waitDoc("nowhere-note");
  await caret("second");
  await app.until(() => document.querySelector(".cm-broken"), "broken link styling");
  const text = await app.eval(() => document.querySelector(".cm-content").innerText);
  ok(text.includes("The Alias") && !text.includes("README|"), "alias shown, target hidden: " + text);
  const [broken, normal] = await app.eval(() => [...document.querySelectorAll(".cm-link")].map((e) => getComputedStyle(e).color));
  ok(broken !== normal, `broken link colour differs (${broken} vs ${normal})`);
  await shot("04-broken-link");
  await app.click(".cm-broken");
  await app.until(() => document.querySelector(".tab.active")?.title.includes("nowhere-note"), "new note opened");
  ok(fs.existsSync(path.join(vault, "nowhere-note.md")) || fs.readdirSync(vault, { recursive: true }).some((f) => f.endsWith("nowhere-note.md")), "file created");
});

await test("link and tag autocomplete", async () => {
  write("acme-shop/typing.md", "start\n");
  await openRow("acme-shop/typing.md");
  await waitDoc("start");
  await caret(await app.eval(`return ${VIEW}.state.doc.length`));
  await app.type("[[cart");
  await app.until(() => document.querySelector(".cm-tooltip-autocomplete li"), "link completions");
  const opts = await app.eval(() => [...document.querySelectorAll(".cm-tooltip-autocomplete li")].map((l) => l.textContent));
  ok(opts.some((o) => o.includes("cart-service")), "cart-service offered: " + opts);
  await sleep(250); // CodeMirror ignores Enter for 75 ms after the list opens
  await app.press("Enter");
  ok(/\[\[acme-shop\/cart-service[^\]]*\]\]/.test(await doc()) || /\[\[[^\]]*cart[^\]]*\]\]/.test(await doc()), "link inserted and closed: " + (await doc()));
  await app.press("End");
  await app.type(" #pay");
  await app.until(() => document.querySelector(".cm-tooltip-autocomplete li"), "tag completions");
  const tagOpts = await app.eval(() => [...document.querySelectorAll(".cm-tooltip-autocomplete li")].map((l) => l.textContent));
  ok(tagOpts.includes("payments"), "payments offered: " + tagOpts);
  await sleep(250);
  await app.press("Enter");
  ok((await doc()).includes("#payments"), "tag inserted: " + (await doc()));
});

await test("Tags tab: counts, nesting, sort, hits", async () => {
  await sleep(1500); // autosave of typing.md
  await side("tags");
  await app.until(() => document.querySelector("#tag-sort"), "tags list");
  const rows = () => app.eval(() => [...document.querySelectorAll(".side .list:not([hidden]) .row-item")].map((r) => [r.textContent, parseInt(r.style.paddingLeft)]));
  let r = await rows();
  const names = r.map((x) => x[0].replace(/\d+$/, ""));
  eq(names.slice(0, 3), ["#alpha", "#payments", "#team"], "sorted by name (top level)");
  ok(r.find((x) => x[0].startsWith("#payments") && x[1] > 8), "nested team/payments indented: " + JSON.stringify(r));
  const count = (n) => Number(r.find((x) => x[0].startsWith(n))[0].match(/(\d+)$/)[1]);
  ok(count("#payments") >= 3, "payments count " + count("#payments"));
  await app.eval(() => { const s = document.querySelector("#tag-sort"); s.value = "count"; s.dispatchEvent(new Event("change")); });
  await sleep(300);
  r = await rows();
  eq(r[0][0].replace(/\d+$/, ""), "#payments", "sorted by count: biggest first");
  await shot("05-tags");
  await app.click(".side .list .row-item", "#payments");
  await app.until(() => document.querySelector(".side .list .match"), "hits");
  const hits = await app.eval(() => [...document.querySelectorAll(".side .list .match")].map((m) => m.innerText));
  ok(hits.some((h) => h.includes("external/stripe.md")) && hits.some((h) => h.includes("orders-service/README.md")), "hits list: " + hits);
  await app.click(".side .list .match", "external/stripe.md");
  await app.until(() => document.querySelector(".tab.active")?.title === "external/stripe.md", "hit opens note");
});

await test("Tags tab: rename tag (right-click) then undo", async () => {
  await app.click("#tab-tags");
  await app.until(() => document.querySelector("#tag-sort"), "tags list");
  await app.rightClick(".side .list .row-item", "#payments");
  await app.click(".ctx-item", "Rename tag");
  await fillModal("billing");
  await sleep(1000);
  ok(disk("external/stripe.md").includes("#billing") && !disk("external/stripe.md").includes("#payments"), "stripe rewritten: " + disk("external/stripe.md"));
  ok(disk("acme-shop/orders-service/README.md").includes("#billing"), "orders README rewritten");
  await app.click("#undo");
  await sleep(1000);
  ok(disk("external/stripe.md").includes("#payments"), "undone");
});

const clearSearch = () => search("");
await test("search: grouping, highlight, diacritics, archived label, #tag filter", async () => {
  await side("files");
  await search("cart");
  let t = await resultsText();
  ok(/FOLDERS \(\d+\)/i.test(t) && /NOTES \(\d+\)/i.test(t) && /TEXT MATCHES \(\d+\)/i.test(t), "three groups: " + t);
  ok(await app.has(".side .list:not([hidden]) mark"), "highlighted hit");
  await shot("06-search");
  await search("CAFE RESUME");
  t = await resultsText();
  ok(t.includes("Café résumé"), "diacritic-insensitive: " + t);
  eq(await app.eval(() => document.querySelector(".side .list:not([hidden]) mark")?.textContent.toLowerCase()), "café résumé", "highlight covers the hit");
  await search("legacy");
  ok((await resultsText()).toLowerCase().includes("archived"), "archived label");
  await search("#payments");
  t = await resultsText();
  ok(t.includes("stripe.md") && t.includes("orders-service/README.md"), "tag filter: " + t);
  await search("#payments refund");
  t = await resultsText();
  ok(t.includes("orders-service/README.md") && !t.includes("stripe.md"), "tag + text: " + t);
});
await test("search: clearing the box shows the tree again", async () => {
  await search("");
  ok(await app.eval(() => document.querySelector(".side .list:not([hidden])").querySelector(".row-item")), "tree back");
});

await test("inspector: endpoint relations, backlinks, outline jump, staleness", async () => {
  const E = "acme-shop/cart-service/endpoints.md";
  await openRow(E);
  await waitDoc("POST /carts");
  await caret("Summary: creates");
  await app.until(() => document.querySelector("#inspector .endpoint")?.textContent.includes("POST /carts"), "endpoint in inspector");
  let t = await app.eval(() => document.querySelector("#inspector").innerText);
  ok(/CALLS/i.test(t) && t.includes("POST /orders"), "Calls out: " + t);
  await shot("07-inspector");
  await caret("Summary: reads");
  await app.until(() => document.querySelector("#inspector .endpoint")?.textContent.includes("GET /carts"), "second endpoint");
  t = await app.eval(() => document.querySelector("#inspector").innerText);
  ok(/USED BY CLIENTS/i.test(t) && /portal/i.test(t), "Uses in: " + t);
  await openRow("acme-shop/orders-service/endpoints.md");
  await caret("Summary: places");
  await app.until(() => document.querySelector("#inspector .endpoint")?.textContent.includes("POST /orders"), "orders endpoint");
  t = await app.eval(() => document.querySelector("#inspector").innerText);
  ok(/CALLED BY/i.test(t) && t.includes("POST /carts"), "Called by: " + t);
  ok(/BACKLINKS \(\d+\)/i.test(t) && !/BACKLINKS \(0\)/i.test(t), "backlinks: " + t);
  await openRow(E);
  await app.click("#inspector .row-item", "GET /carts/{id}");
  await sleep(300);
  const line = await app.eval(`const v = ${VIEW}; return v.state.doc.lineAt(v.state.selection.main.head).text`);
  eq(line, "## GET /carts/{id}", "outline click jumps to heading");
  await openRow("acme-shop/cart-service/README.md");
  await app.until(() => document.querySelector("#staleness"), "staleness badge");
  eq(await app.eval(() => [document.querySelector("#staleness").textContent, document.querySelector("#staleness").classList.contains("stale")]), ["verified 100 days ago", true], "stale badge");
  await openRow("acme-shop/orders-service/README.md");
  await app.until(() => document.querySelector("#staleness")?.textContent.includes("3 days"), "fresh badge");
  ok(!(await app.eval(() => document.querySelector("#staleness").classList.contains("stale"))), "not highlighted");
  await app.click("#copy-ingest");
  await app.until(() => [...document.querySelectorAll(".toast")].some((x) => x.textContent.includes("ingest")), "copied toast");
  await app.click("#copy-refresh");
  await app.until(() => [...document.querySelectorAll(".toast")].some((x) => x.textContent.includes("refresh")), "copied refresh toast");
});

await test("rename heading rewrites links to it", async () => {
  await openRow("acme-shop/cart-service/endpoints.md");
  await app.rightClick("#inspector .row-item", "POST /carts");
  await app.click(".ctx-item", "Rename heading");
  await fillModal("POST /baskets");
  await sleep(1000);
  ok(disk("acme-shop/cart-service/endpoints.md").includes("## POST /baskets"), "heading renamed");
  ok(disk("acme-shop/cart-service/bugs.md").includes("endpoints#POST /baskets"), "link rewritten: " + disk("acme-shop/cart-service/bugs.md"));
});

await test("task tick moves the item to the archive; Ctrl+Z restores it", async () => {
  await openRow("acme-shop/cart-service/bugs.md");
  await app.until(() => document.querySelector(".cm-task"), "checkbox widget");
  const before = disk("acme-shop/cart-service/bugs.md");
  await app.click(".cm-task");
  await sleep(1200);
  const bugs = disk("acme-shop/cart-service/bugs.md");
  ok(!bugs.includes("Total ignores discounts") && bugs.includes("Second bug"), "removed from bugs.md: " + bugs);
  const arch = disk("acme-shop/archive/fixed-bugs.md");
  ok(/### Total ignores discounts/.test(arch) && /closed: \d{4}-\d\d-\d\d/.test(arch) && /source: \[\[acme-shop\/cart-service\/endpoints#POST \/baskets\]\]/.test(arch), "archive entry: " + arch);
  await shot("08-tick");
  await app.eval(`${VIEW}.focus()`);
  await app.press("Control", "z");
  await sleep(1200);
  eq(disk("acme-shop/cart-service/bugs.md"), before, "bugs.md restored");
  ok(!disk("acme-shop/archive/fixed-bugs.md").includes("Total ignores"), "archive entry removed");
});

await test("rename and move a Note rewrite links; undo restores", async () => {
  const rootBefore = disk("README.md");
  await app.rightClick(".row-item[title='acme-shop/README.md']");
  await app.click(".ctx-item", "Rename / move");
  await fillModal("acme-shop/ABOUT.md");
  await sleep(1200);
  ok(fs.existsSync(path.join(vault, "acme-shop/ABOUT.md")) && !fs.existsSync(path.join(vault, "acme-shop/README.md")), "file renamed");
  ok(disk("README.md").includes("[[acme-shop/ABOUT]]"), "link rewritten: " + disk("README.md"));
  await app.click("#undo");
  await sleep(1200);
  eq(disk("README.md"), rootBefore, "link restored");
  ok(fs.existsSync(path.join(vault, "acme-shop/README.md")), "file back");
  // move to another folder
  await app.rightClick(".row-item[title='acme-shop/overview.md']");
  await app.click(".ctx-item", "Rename / move");
  await fillModal("clients/overview.md");
  await sleep(1200);
  ok(fs.existsSync(path.join(vault, "clients/overview.md")), "moved");
  await app.click("#undo");
  await sleep(1200);
  ok(fs.existsSync(path.join(vault, "acme-shop/overview.md")), "move undone");
});

await test("new note: button, folder menu, Ctrl+N, existing path error, undo", async () => {
  const modalValue = () => app.eval(() => document.querySelector(".modal input").value);
  const exists = (f) => fs.existsSync(path.join(vault, f));
  await openRow("acme-shop/overview.md");
  await app.click("#new-note");
  await app.until(() => document.querySelector(".modal input"), "dialog");
  eq(await modalValue(), "acme-shop/", "pre-filled with the active Note's folder");
  await app.press("Escape");
  await sleep(300);
  ok(!(await app.eval(() => !!document.querySelector(".modal"))), "Escape closed the prompt");
  ok(await app.eval(() => !!document.querySelector(".side > #new-note")), "New note button is at the top of the sidebar");
  await app.click("#new-note");
  await fillModal("acme-shop/fresh/idea");
  await app.until(() => document.querySelector(".tab.active")?.title === "acme-shop/fresh/idea.md", "new note is the active tab");
  ok(await app.eval(() => !!document.activeElement?.closest(".cm-editor")), "cursor is in the editor");
  eq(disk("acme-shop/fresh/idea.md"), "", "empty file on disk");
  await app.until(() => document.querySelector(".row-item[title='acme-shop/fresh/idea.md']"), "shown in the tree");
  await app.press("Control", "z");
  await sleep(1200);
  ok(!exists("acme-shop/fresh"), "Ctrl+Z removed the new Note and the folder it made");
  ok(exists("acme-shop"), "existing folder stays");
  await app.rightClick(".row-item[title='clients']");
  await app.click(".ctx-item", "New note here");
  await app.until(() => document.querySelector(".modal input"), "dialog");
  eq(await modalValue(), "clients/", "pre-filled with the right-clicked folder");
  await app.press("Escape");
  await sleep(300);
  await app.rightClick(".row-item[title='templates']");
  ok(!(await app.eval(() => [...document.querySelectorAll(".ctx-item")].some((e) => e.textContent.includes("New note")))), "no New note here on an app-only folder");
  await app.press("Escape");
  await app.press("Control", "n");
  await app.until(() => document.querySelector(".modal input"), "Ctrl+N prompt");
  await app.eval(() => { document.querySelector(".modal input").value = "acme-shop/overview.md"; });
  await app.press("Enter");
  await app.until(() => document.querySelector(".toast.bad"), "error toast for an existing path");
  ok(disk("acme-shop/overview.md").length > 0, "existing Note unchanged");
});

await test("help: button and F1 open the cheat sheet; search does not find it", async () => {
  const CS = ".constellation/cheat-sheet.md";
  await app.click("#open-help");
  await app.until(() => document.querySelector(".tab.active")?.title === ".constellation/cheat-sheet.md", "cheat sheet is the active tab");
  ok(disk(CS).includes("Ctrl+G"), "cheat sheet on disk names Ctrl+G");
  ok((await app.eval(() => document.querySelector(".cm-content").innerText)).includes("Ctrl+G"), "tab shows Ctrl+G");
  await app.click(".tab.active .x");
  await app.press("F1");
  await app.until(() => document.querySelector(".tab.active")?.title === ".constellation/cheat-sheet.md", "F1 opens it again");
  await search("overwritten");
  eq((await resultsText()).trim(), "No results", "a phrase only in the cheat sheet finds nothing");
  await app.eval(`${VIEW}.dispatch({ changes: { from: 0, to: ${VIEW}.state.doc.length, insert: "stale" } })`);
  await app.click("#open-help");
  await app.until(() => document.querySelector(".cm-content").innerText.includes("Ctrl+G"), "Help again shows the fresh text");
  ok(!(await app.eval(() => document.querySelector(".cm-content").innerText)).includes("stale"), "stale buffer replaced");
  await search("");
});

await test("settings: staleness days and theme persist", async () => {
  await openRow("acme-shop/cart-service/README.md");
  await app.click("#open-settings");
  await app.until(() => document.querySelector("#set-days"), "settings dialog");
  await app.eval(() => { document.querySelector("#set-days").value = "200"; });
  await app.click("#set-save");
  await app.until(() => document.querySelector("#staleness") && !document.querySelector("#staleness").classList.contains("stale"), "badge no longer stale at 200 days", 4000);
  ok(JSON.parse(disk(".constellation/settings.json")).stalenessDays === 200, "settings.json written");
  const PAL = { Light: "#FFFFFF", Dark: "#1E1E1E", Dracula: "#282A36", "One Dark": "#282C34" };
  // System: the page palette follows the OS appearance (dark here if the desktop prefers dark).
  await app.click("#open-settings");
  await app.until(() => document.querySelector("#set-theme"), "settings");
  await app.eval(() => { document.querySelector("#set-theme").value = "System"; });
  await app.click("#set-save");
  await sleep(300);
  const sys = await app.eval(() => [matchMedia("(prefers-color-scheme: dark)").matches, getComputedStyle(document.documentElement).getPropertyValue("--background").trim().toUpperCase()]);
  eq(sys[1], sys[0] ? PAL.Dark : PAL.Light, "System theme follows the OS (dark: " + sys[0] + ")");
  for (const [name, bg] of Object.entries(PAL)) {
    await app.click("#open-settings");
    await app.until(() => document.querySelector("#set-theme"), "settings");
    await app.eval((n) => { const s = document.querySelector("#set-theme"); s.value = n; }, name);
    await app.click("#set-save");
    await sleep(300);
    const got = await app.eval(() => getComputedStyle(document.documentElement).getPropertyValue("--background").trim().toUpperCase());
    eq(got, bg, "theme " + name);
    const editorBg = await app.eval(() => getComputedStyle(document.querySelector(".cm-editor")).backgroundColor);
    const [r, g, b] = bg.slice(1).match(/../g).map((x) => parseInt(x, 16));
    eq(editorBg, `rgb(${r}, ${g}, ${b})`, "editor colour for " + name);
    await shot("theme-" + name.replace(" ", ""));
    // Window chrome: on Linux the GTK dark preference follows the theme, and the page sees it as prefers-color-scheme.
    eq(await app.eval(() => matchMedia("(prefers-color-scheme: dark)").matches), name !== "Light", "window appearance for " + name);
  }
});


const setDoc = (text) => app.eval(`const v = ${VIEW}; v.focus(); v.dispatch({ changes: { from: 0, to: v.state.doc.length, insert: A[0] }, selection: { anchor: 0 } });`, text);
await test("every toolbar format wraps the selection", async () => {
  write("acme-shop/fmt.md", "x\n");
  await openRow("acme-shop/fmt.md");
  const want = { bold: "**word**", italic: "*word*", underline: "<u>word</u>", strikethrough: "~~word~~", inlineCode: "`word`", codeBlock: "```", heading1: "# word", heading2: "## word", heading3: "### word", bulletList: "- word", numberedList: "1. word", taskList: "- [ ] word", quote: "> word", link: "[[word]]" };
  for (const [action, expected] of Object.entries(want)) {
    await setDoc("word\n");
    await selectText("word");
    await app.click(".fmt-" + action);
    ok((await doc()).includes(expected), `${action}: ${JSON.stringify(await doc())}`);
    await app.click(".fmt-" + action).catch(() => {});
  }
  await setDoc("word\n");
  await app.click(".fmt-table");
  ok((await doc()).includes("|"), "table skeleton: " + JSON.stringify(await doc()));
});

await test("live preview widgets: table, code block, quote, image, tag, checkbox", async () => {
  await setDoc("# Widgets\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```\nlet x = 1;\n```\n\n> quoted text\n\n![alt text](missing.png)\n\n#payments and **bold** and `code`\n\n- [ ] open task\n- [x] done task\n\nend\n");
  await caret("end");
  await app.until(() => !!document.querySelector(".cm-table") && !!document.querySelector(".cm-image-missing"), "table and missing-image widgets");
  for (const sel of [".cm-codeblock", ".cm-quote", ".cm-image-missing", ".cm-tag", ".cm-task", ".cm-bold", ".cm-code"]) ok(await app.has(sel), "has " + sel);
  ok((await doc()).includes("![alt text](missing.png)"), "a broken image must not rewrite the text: " + JSON.stringify((await doc()).slice(0, 80)));
  eq(await app.eval(() => [...document.querySelectorAll(".cm-task")].map((c) => c.checked)), [false, true], "checkbox states");
  const text = await app.eval(() => document.querySelector(".cm-content").innerText);
  ok(!text.includes("**bold**") && !text.includes("```") && !text.includes("![alt"), "markers hidden: " + text);
  eq(await app.eval(() => document.querySelectorAll(".cm-fence-collapsed").length), 2, "both fence lines collapsed");
  await shot("12-widgets");
});

await test("inline image from the vault loads", async () => {
  const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");
  fs.writeFileSync(path.join(vault, "acme-shop/pic.png"), png);
  await setDoc("![pic](pic.png)\n\nend\n");
  await caret("end");
  await app.until(() => document.querySelector("img.cm-image")?.naturalWidth > 0, "image loaded", 5000);
  ok((await doc()).startsWith("![pic](pic.png)"), "text unchanged");
});

await test("link to a heading jumps to it", async () => {
  write("acme-shop/headlink.md", "[[acme-shop/cart-service/endpoints#GET /carts/{id}]]\n\nsecond\n");
  await openRow("acme-shop/headlink.md");
  await waitDoc("second");
  await caret("second");
  await app.click(".cm-link");
  await app.until(() => document.querySelector(".tab.active")?.title === "acme-shop/cart-service/endpoints.md", "endpoints opened");
  await sleep(300);
  eq(await app.eval(`const v = ${VIEW}; return v.state.doc.lineAt(v.state.selection.main.head).text`), "## GET /carts/{id}", "caret on the heading");
});

await test("Ctrl-click on a #tag opens the Tags tab filtered", async () => {
  await openRow("acme-shop/orders-service/README.md");
  await waitDoc("#payments");
  await caret("# Orders");
  await sleep(200);
  await app.ctrlClick(".cm-tag");
  await app.until(() => document.querySelector("#tab-tags").classList.contains("on") && document.querySelector(".side .list .match"), "tag hits list");
  ok((await resultsText()).includes("#payments"), "filtered to #payments");
  await side("files");
});

await test("backlink click opens the linking note", async () => {
  await openRow("acme-shop/orders-service/endpoints.md");
  await app.until(() => [...document.querySelectorAll("#inspector .row-item")].some((r) => r.title.includes("cart-service")), "backlinks");
  await app.click("#inspector .row-item[title*='cart-service/endpoints.md']");
  await app.until(() => document.querySelector(".tab.active")?.title === "acme-shop/cart-service/endpoints.md", "backlink target open");
});

// ---------- graph window ----------
let main;
const graph = async () => { await app.focusWindow("view=graph"); };
const gstate = () => app.eval(() => document.querySelector("#graph-canvas").e2e());
const settle = async () => { // layout finished (and the view fitted) and nothing moving
  let last = "", same = 0;
  for (let i = 0; i < 60 && same < 3; i++) {
    const st = await gstate();
    const now = JSON.stringify([st.heat, st.view, st.nodes.map((n) => [Math.round(n.x), Math.round(n.y)])]);
    same = st.heat === 0 && now === last ? same + 1 : 0;
    last = now;
    await sleep(250);
  }
};
const nodeOf = async (id) => (await gstate()).nodes.find((n) => n.id === id);
const canvasPointer = async (steps, opts) => {
  const r = await app.eval(() => { const c = document.querySelector("#graph-canvas").getBoundingClientRect(); return [c.width, c.height]; });
  return app.pointer("#graph-canvas", steps.map(([k, a, b]) => (k === "move" ? [k, a - r[0] / 2, b - r[1] / 2] : [k, a, b])), opts);
};

await test("graph: window opens (Ctrl+G), renders nodes and edges", async () => {
  write("acme-shop/ghosts.md", "# Ghosts\n\n[[phantom-note]] and [[acme-shop/orders-service/README]] #alpha\n");
  await app.focusWindow(null);
  await app.eval(`${VIEW}.focus()`);
  await app.press("Control", "g");
  await graph();
  await app.until(() => document.querySelector("#graph-canvas"), "graph canvas");
  await app.until(() => document.querySelector("#graph-canvas").e2e().nodes.length > 5, "nodes", 8000);
  await settle();
  const s = await gstate();
  ok(s.edges > 3, "edges " + s.edges);
  ok(s.nodes.some((n) => n.kind === "folder") && s.nodes.some((n) => n.kind === "note"), "folder and note nodes");
  ok(s.nodes.some((n) => n.kind === "ghost" && n.name.includes("phantom")), "ghost node for the broken link: " + JSON.stringify(s.nodes.map((n) => n.id)));
  const labels = s.nodes.map((n) => n.label);
  ok(labels.includes("cart-service/endpoints") && labels.includes("orders-service/endpoints") && !labels.some((l) => l.endsWith(".md")), "disambiguated labels: " + JSON.stringify(labels));
  await shot("09-graph");
});

await test("idle app does not refresh itself (reads must not look like changes)", async () => {
  await app.focusWindow(null);
  await app.eval(() => { window.__n = 0; window.__TAURI_INTERNALS__.invoke("plugin:event|listen", { event: "vault-changed", target: { kind: "Any" }, handler: window.__TAURI_INTERNALS__.transformCallback(() => window.__n++) }); });
  await sleep(3500);
  const n = await app.eval(() => window.__n);
  ok(n <= 1, `${n} vault-changed events in 3.5 s of idling with the graph window open`);
});

await test("graph: hover highlights, click opens the note in the main window", async () => {
  await graph();
  const n = await nodeOf("acme-shop/orders-service/README.md");
  ok(n && Number.isFinite(n.x), "node present");
  await canvasPointer([["move", n.x, n.y]]);
  await app.until(() => document.querySelector("#graph-canvas").e2e().hover === "acme-shop/orders-service/README.md", "hover", 3000);
  await shot("10-graph-hover");
  await canvasPointer([["move", n.x, n.y], ["down", 0], ["up", 0]]);
  await app.focusWindow(null);
  await app.until(() => document.querySelector(".tab.active")?.title === "acme-shop/orders-service/README.md", "note opened in main", 5000);
});

await test("graph: drag a node, pan, zoom", async () => {
  await graph();
  await settle();
  const n = await nodeOf("acme-shop/orders-service/README.md");
  await canvasPointer([["move", n.x, n.y]]);
  await app.until(() => document.querySelector("#graph-canvas").e2e().hover === "acme-shop/orders-service/README.md", "pointer over the node", 3000);
  await canvasPointer([["move", n.x, n.y], ["down", 0], ["move", n.x + 60, n.y + 40], ["move", n.x + 80, n.y + 50], ["up", 0]]);
  await sleep(500);
  const moved = await nodeOf("acme-shop/orders-service/README.md");
  ok(Math.hypot(moved.x - n.x, moved.y - n.y) > 30, `node moved (${n.x},${n.y}) -> (${moved.x},${moved.y})`);
  const v0 = (await gstate()).view;
  await canvasPointer([["move", 40, 40], ["down", 0], ["move", 90, 70], ["move", 140, 100], ["up", 0]]);
  await sleep(300);
  const v1 = (await gstate()).view;
  ok(Math.abs(v1.x - v0.x) > 40, `pan changed view (${v0.x} -> ${v1.x})`);
  const id = await app.el("#graph-canvas");
  await app.req("POST", "/actions", { actions: [{ type: "wheel", id: "w", actions: [{ type: "scroll", x: 0, y: 0, deltaX: 0, deltaY: -300, origin: { "element-6066-11e4-a52e-4f735466cecf": id } }] }] });
  await sleep(300);
  const v2 = (await gstate()).view;
  ok(v2.k > v1.k, `zoom in (${v1.k} -> ${v2.k})`);
});

await test("graph: clicking a ghost node creates the Note", async () => {
  await graph();
  const g = (await gstate()).nodes.find((n) => n.kind === "ghost");
  ok(g, "ghost node present");
  await canvasPointer([["move", g.x, g.y], ["down", 0], ["up", 0]]);
  await sleep(1000);
  ok(fs.readdirSync(vault, { recursive: true }).some((f) => f.endsWith("phantom-note.md")), "phantom-note.md created");
  await app.focusWindow(null);
  await app.until(() => document.querySelector(".tab.active")?.title.includes("phantom-note"), "opened in main");
});

await test("graph: filters (edge kind, archive, tag, local depth)", async () => {
  await graph();
  await sleep(1500); // the panel is rebuilt after the previous test's file changes
  const select = (id, v) => app.eval((id, v) => { const s = document.querySelector(id); s.value = v; s.dispatchEvent(new Event("change")); }, id, v);
  /** Waits for the graph to reload into a state satisfying `pred`. */
  const reloaded = async (what, pred, ms = 6000) => {
    for (let i = 0; i < ms / 300; i++) { await sleep(300); const s = await gstate(); if (pred(s)) return s; }
    throw new Error("graph never reached: " + what + " " + JSON.stringify(await gstate().then((s) => [s.nodes.length, s.edges])) + " boxes " + JSON.stringify(await app.eval(() => [...document.querySelectorAll(".chk input")].map((c) => c.checked ? 1 : 0).join(""))));
  };
  /** Clicks, and clicks once more if the graph did not react (WebKit now and then drops a click right after a reload). */
  let retries = 0;
  const toggle = async (css, text, what, pred) => {
    for (let i = 0; ; i++) {
      await sleep(700); // a second click within the double-click time on the same spot is not a plain click
      await app.click(css, text);
      try { return await reloaded(what, pred, 2500); } catch (e) { if (i >= 2) throw e; retries++; }
    }
  };
  await settle();
  const { nodes: { length: n0 }, edges: e0 } = await gstate();
  await toggle(".chk", "containment", "fewer edges without containment", (s) => s.edges < e0);
  await toggle(".chk", "containment", "edges back", (s) => s.edges === e0);
  await toggle("#g-archive", undefined, "archive adds nodes", (s) => s.nodes.length > n0);
  await toggle("#g-archive", undefined, "archive hidden again", (s) => s.nodes.length === n0);
  await select("#g-tag", "alpha");
  const n3 = (await reloaded("tag filter narrows", (s) => s.nodes.length < n0)).nodes.length;
  ok(n3 >= 2, "tag filter keeps the tagged notes and neighbours: " + n3);
  await select("#g-tag", "");
  await reloaded("tag filter off", (s) => s.nodes.length === n0);
  const l1 = (await toggle("#g-local", undefined, "local graph smaller", (s) => s.nodes.length < n0)).nodes.length;
  await select("#g-depth", "3");
  const l3 = (await reloaded("depth 3 not smaller", (s) => s.nodes.length >= l1)).nodes.length;
  ok(l3 >= l1, "depth");
  await toggle("#g-local", undefined, "local off", (s) => s.nodes.length === n0);
  if (retries) console.log(`      (${retries} click(s) needed a retry)`);
  await shot("11-graph-filters");
});

await test("unsaved edits are flushed when the window closes", async () => {
  xwin("close", "Constellation graph");
  await sleep(500);
  await app.focusWindow(null);
  xwin("focus", "Constellation");
  await openRow(SYNC);
  await waitDoc("Theirs");
  await caret(await app.eval(`return ${VIEW}.state.doc.length`));
  await app.type(" flushed");
  ok((await doc()).includes("flushed"), "typed into the editor: " + JSON.stringify((await doc()).slice(-40)) + JSON.stringify(await app.windows()));
  // What the window manager's close button does (WM_DELETE_WINDOW); WebDriver's own "close window" skips the close request.
  ok(xwin("close", "Constellation"), "sent the close request");
  await sleep(500); // well under the 1 s autosave delay
  ok(disk(SYNC).includes("flushed"), "written on close");
});
await app.close();

app = await launch({ config: cfg });
await test("relaunch: last vault, theme and staleness days persist", async () => {
  await app.until(() => document.querySelector(".cm-content"), "editor on relaunch");
  eq(await app.eval(() => getComputedStyle(document.documentElement).getPropertyValue("--background").trim().toUpperCase()), "#282C34", "One Dark kept");
  await openRow("acme-shop/cart-service/README.md");
  await app.until(() => document.querySelector("#staleness"), "badge");
  ok(!(await app.eval(() => document.querySelector("#staleness").classList.contains("stale"))), "200-day threshold kept");
});

console.log("\nmain window batch done");
await app.close();
const failed = results.filter((r) => !r[1]);
console.log(`\n${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
