// Service Map viewer. data/repos.js calls SERVICE_MAP.system(), which loads data/<repo>.js for every repository;
// each of those calls SERVICE_MAP.repo(). Script tags, not fetch, so the page also works opened from disk.
const SERVICE_MAP = (() => {
  const state = { system: null, repos: [], journeys: [], missing: [] };
  let pending = 0;

  function system(s) {
    state.system = s;
    pending = s.repos.length;
    if (!pending) start();
    for (const name of s.repos) {
      const el = document.createElement("script");
      el.src = `data/${encodeURIComponent(name)}.js`;
      el.onload = done;
      el.onerror = () => { state.missing.push(name); done(); };
      document.body.appendChild(el);
    }
  }
  function done() { if (--pending === 0) start(); }
  const repo = r => state.repos.push(r);
  const journey = j => state.journeys.push(j);

  // ---------- index ----------
  let ix;
  function buildIndex() {
    const services = [], byId = {}, endpoints = [], calls = [], topics = {}, tables = [], glossary = [], notes = [], questions = [];
    for (const r of state.repos) {
      for (const s of r.services || []) {
        const svc = { ...s, repo: r.repo, commit: r.commit, mapped: r.mapped };
        services.push(svc); byId[svc.id] = svc;
        for (const e of s.endpoints || []) {
          endpoints.push({ ...e, svc });
          if (e.question) questions.push({ text: e.question, where: `${svc.id} ${e.method} ${e.path}`, href: epHref(svc.id, e) });
        }
        for (const c of s.calls || []) calls.push({ ...c, svc });
        for (const [list, role] of [[s.produces, "producers"], [s.consumes, "consumers"]]) {
          for (const t of list || []) {
            const topic = topics[t.topic] ||= { name: t.topic, producers: [], consumers: [], events: new Set() };
            topic[role].push(svc.id);
            (t.events || []).forEach(ev => topic.events.add(ev));
            if (t.question) questions.push({ text: t.question, where: `${svc.id} ${t.topic}`, href: `#/service/${enc(svc.id)}` });
          }
        }
        for (const t of s.tables || []) tables.push({ ...t, svc });
        for (const n of s.notes || []) notes.push({ ...n, svc });
      }
      glossary.push(...(r.glossary || []));
    }
    const layerOrder = (state.system.layers || []).map(l => l.id);
    services.sort((a, b) => layerOrder.indexOf(a.layer) - layerOrder.indexOf(b.layer) || a.id.localeCompare(b.id));
    ix = { services, byId, endpoints, calls, topics, tables, glossary, notes, questions };
  }

  // A call's target ("ANY /orders/**") matches an endpoint ("GET /orders/{id}").
  function matches(target, e) {
    const [m, p] = target.split(" ");
    const methodOk = m === "ANY" || e.method === "ANY" || m === e.method;
    const pathOk = p.endsWith("/**") ? (e.path + "/").startsWith(p.slice(0, -2)) : p === e.path;
    return methodOk && pathOk;
  }
  const callersOf = (svcId, e) => ix.calls.filter(c => c.to === svcId && matches(c.endpoint, e));
  const callersOfService = svcId => ix.calls.filter(c => c.to === svcId);

  // ---------- helpers ----------
  const esc = v => String(v ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const enc = encodeURIComponent;
  const epHref = (svcId, e) => `#/endpoint/${enc(svcId)}/${enc(e.method + " " + e.path)}`;
  const method = m => `<span class="method m-${esc(m)}">${esc(m)}</span>`;
  const layerDot = l => `<span class="dot layer-${esc(l)}"></span>`;
  const layerPill = l => `<span class="pill layer layer-${esc(l)}">${esc(l)}</span>`;
  const svcLink = id => ix.byId[id] ? `<a href="#/service/${enc(id)}">${esc(id)}</a>` : `<span>${esc(id)}</span> <span class="pill">external</span>`;
  function ref(r) {
    if (!r) return "";
    const i = r.lastIndexOf(":"), path = i > 0 ? r.slice(0, i) : r, line = i > 0 ? r.slice(i + 1) : "1";
    const label = `${path.split("/").pop()}${i > 0 ? ":" + line : ""}`;
    const tpl = state.system.codeLink;
    return tpl ? `<a class="mono ref" href="${esc(tpl.replace("{path}", path).replace("{line}", line))}" title="${esc(path)}">${esc(label)}</a>`
      : `<code class="ref" title="${esc(path)}">${esc(label)}</code>`;
  }
  const table = (head, rows) => rows.length
    ? `<div class="table-wrap"><table><thead><tr>${head.map(h => `<th>${h}</th>`).join("")}</tr></thead><tbody>${rows.map(r => `<tr>${r.map(c => `<td>${c}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`
    : `<p class="muted">None.</p>`;
  const callout = (level, text, r) => `<div class="callout ${esc(level)}"><span class="tag">${esc({ risk: "Risk", warn: "Watch", info: "Note", question: "Open" }[level] || level)}</span><p>${esc(text)} ${ref(r)}</p></div>`;
  const diagram = src => src ? `<div class="diagram"><pre class="mermaid">${esc(src)}</pre></div>` : "";
  const foot = s => `<p class="foot">Mapped from <code>${esc(s.repo)}@${esc(s.commit)}</code> on ${esc(s.mapped)}.</p>`;
  const nid = s => "n_" + String(s).replace(/[^A-Za-z0-9]/g, "_");
  const qlabel = s => `"${String(s).replace(/"/g, "'")}"`;

  // A service's neighbours as a Mermaid flowchart, drawn from the data so the agent never writes it.
  function neighbourhood(s) {
    const lines = ["flowchart LR", `  ${nid(s.id)}[${qlabel(s.id)}]`, `  style ${nid(s.id)} stroke-width:3px`];
    const group = (items, key) => items.reduce((m, c) => ((m[c[key]] ||= []).push(c), m), {});
    const inbound = {};
    for (const c of callersOfService(s.id)) (inbound[c.svc.id] ||= new Set()).add(c.endpoint);
    for (const [from, eps] of Object.entries(inbound)) lines.push(`  ${nid(from)}[${qlabel(from)}] -->|${qlabel([...eps].join(", "))}| ${nid(s.id)}`);
    for (const [to, cs] of Object.entries(group(s.calls || [], "to"))) {
      const shape = cs[0].external ? `{{${qlabel(to)}}}` : `[${qlabel(to)}]`;
      lines.push(`  ${nid(s.id)} -->|${qlabel([...new Set(cs.map(c => c.endpoint))].join(", "))}| ${nid(to)}${shape}`);
    }
    for (const t of s.produces || []) lines.push(`  ${nid(s.id)} -.->|${qlabel((t.events || []).join(", ") || "events")}| ${nid(t.topic)}[[${qlabel(t.topic)}]]`);
    for (const t of s.consumes || []) lines.push(`  ${nid(t.topic)}[[${qlabel(t.topic)}]] -.->|${qlabel((t.events || []).join(", ") || "events")}| ${nid(s.id)}`);
    if (s.database) lines.push(`  ${nid(s.id)} --- ${nid(s.database)}[(${qlabel(s.database)})]`);
    return lines.join("\n");
  }

  // ---------- views ----------
  const views = {
    home() {
      const sys = state.system;
      const layers = (sys.layers || []).map(l => {
        const list = ix.services.filter(s => s.layer === l.id);
        return list.length ? `<section class="layer-band layer-${esc(l.id)}"><h3>${esc(l.id)}</h3><p>${esc(l.about)}</p><div class="grid">${list.map(serviceCard).join("")}</div></section>` : "";
      }).join("");
      const unlayered = ix.services.filter(s => !(sys.layers || []).some(l => l.id === s.layer));
      return `
        <div class="eyebrow">${sys.demo ? `<span class="pill">Demo with made-up services</span>` : ""}<span>${ix.services.length} services · ${state.repos.length} repositories</span></div>
        <h1>${esc(sys.name)} service map</h1>
        <p class="lede">${esc(sys.summary)}</p>
        <div class="stats">
          <a class="stat" href="#/endpoints"><b>${ix.endpoints.length}</b><span>endpoints</span></a>
          <a class="stat" href="#/calls"><b>${ix.calls.length}</b><span>calls between services</span></a>
          <a class="stat" href="#/calls"><b>${Object.keys(ix.topics).length}</b><span>Kafka topics</span></a>
          <a class="stat" href="#/data"><b>${ix.tables.length}</b><span>tables</span></a>
          <a class="stat" href="#/questions"><b>${ix.questions.length}</b><span>open questions</span></a>
        </div>
        ${state.journeys.length ? `<h2>Start with a journey</h2><div class="grid">${state.journeys.map(j => `<a class="card" href="#/journey/${enc(j.id)}"><span class="title">${esc(j.title)}</span><p>${esc(j.story.split(". ")[0])}.</p></a>`).join("")}</div>` : ""}
        <h2>Things to know</h2>
        ${ix.notes.filter(n => n.level !== "info").map(n => callout(n.level, `${n.svc.id}: ${n.text}`, n.ref)).join("") || `<p class="muted">Nothing flagged.</p>`}
        <h2>Services by layer</h2>
        ${layers}${unlayered.length ? `<div class="grid">${unlayered.map(serviceCard).join("")}</div>` : ""}
        ${state.missing.length ? callout("warn", `Listed in data/repos.js but not found: ${state.missing.join(", ")}.`) : ""}`;
    },

    graph() {
      const layers = [...new Set(ix.services.map(s => s.layer))];
      setTimeout(drawGraph);
      return `
        <h1>System graph</h1>
        <p class="lede">Every service, topic and database. Click a node to see its endpoints and neighbours, double-click a service to open it. Drag to move, scroll to zoom.</p>
        <div class="toggles" id="layer-toggles">${layers.map(l => `<label><input type="checkbox" value="${esc(l)}" checked> ${layerDot(l)} ${esc(l)}</label>`).join("")}
          <label><input type="checkbox" id="show-data" checked> databases</label><label><input type="checkbox" id="show-events" checked> topics</label></div>
        <div class="graph-wrap"><div id="graph" role="img" aria-label="Graph of services and their connections"></div><div id="graph-panel"><p class="muted">Click a service.</p></div></div>
        <div class="legend"><span><i style="background:var(--domain)"></i>service (colour = layer)</span><span><i class="sq" style="background:var(--warn)"></i>topic</span>
          <span><i class="sq" style="background:var(--infra)"></i>database</span><span><i style="background:var(--risk)"></i>external system</span>
          <span>── HTTP call (number = endpoint calls)</span><span>- - - event</span></div>`;
    },

    endpoints() {
      setTimeout(() => {
        const q = document.getElementById("ep-q"), svc = document.getElementById("ep-svc"), m = document.getElementById("ep-m");
        const apply = () => document.querySelectorAll("#ep-table tbody tr").forEach(tr => {
          tr.hidden = !(tr.dataset.text.includes(q.value.toLowerCase()) && (!svc.value || tr.dataset.svc === svc.value) && (!m.value || tr.dataset.m === m.value));
        });
        [q, svc, m].forEach(el => el.addEventListener("input", apply));
        q.focus();
      });
      const rows = ix.endpoints.map(e => {
        const callers = callersOf(e.svc.id, e).map(c => c.svc.id);
        return `<tr data-svc="${esc(e.svc.id)}" data-m="${esc(e.method)}" data-text="${esc([e.svc.id, e.method, e.path, e.purpose, e.use_when, e.auth].join(" ").toLowerCase())}">
          <td>${layerDot(e.svc.layer)} ${svcLink(e.svc.id)}</td><td>${method(e.method)}</td>
          <td class="path"><a href="${epHref(e.svc.id, e)}">${esc(e.path)}</a></td>
          <td>${esc(e.use_when)}${e.dont_confuse ? `<br><small>Don't confuse with ${esc(e.dont_confuse)}</small>` : ""}</td>
          <td>${callers.length ? [...new Set(callers)].map(svcLink).join(", ") : `<small>${e.question ? "❓ none found" : "clients"}</small>`}</td>
          <td><small>${esc(e.auth)}</small></td><td>${e.flow ? `<a href="${epHref(e.svc.id, e)}">flow</a>` : ""}</td></tr>`;
      });
      return `
        <h1>All endpoints</h1>
        <p class="lede">Every endpoint of every service in one place, instead of one Swagger page per service. "Flow" opens the step-by-step view.</p>
        <div class="filters"><input id="ep-q" type="search" placeholder="Filter by path, purpose, auth…" aria-label="Filter endpoints">
          <select id="ep-svc" aria-label="Service"><option value="">All services</option>${ix.services.map(s => `<option>${esc(s.id)}</option>`).join("")}</select>
          <select id="ep-m" aria-label="Method"><option value="">All methods</option>${[...new Set(ix.endpoints.map(e => e.method))].map(m => `<option>${esc(m)}</option>`).join("")}</select></div>
        <div class="table-wrap" id="ep-table"><table><thead><tr><th>Service</th><th>Method</th><th>Path</th><th>Use it when</th><th>Called by</th><th>Auth</th><th></th></tr></thead><tbody>${rows.join("")}</tbody></table></div>`;
    },

    service(id) {
      const s = ix.byId[id];
      if (!s) return notFound(`No service ${id}.`);
      const callers = callersOfService(id);
      return `
        <div class="eyebrow">${layerPill(s.layer)}<span>repository ${esc(s.repo)}</span></div>
        <h1>${esc(s.id)}</h1>
        <p class="lede">${esc(s.purpose)}</p>
        <div class="meta">${s.tech ? `<span><b>Tech</b> ${esc(s.tech)}</span>` : ""}${s.runtime ? `<span><b>Runs on</b> ${esc(s.runtime)} ${ref(s.terraform)}</span>` : ""}
          ${s.pipeline ? `<span><b>Ships with</b> <code>${esc(s.pipeline.workflow)}</code></span>` : ""}${s.owner ? `<span><b>Owner</b> ${esc(s.owner)}</span>` : ""}</div>
        ${(s.notes || []).map(n => callout(n.level, n.text, n.ref)).join("")}
        <h2>Neighbours</h2>${diagram(neighbourhood(s))}
        <h2>Endpoints</h2>
        ${table(["Method", "Path", "Use it when", "Called by", "Auth"], (s.endpoints || []).map(e => [method(e.method), `<a class="mono" href="${epHref(s.id, e)}">${esc(e.path)}</a>${e.flow ? ` <span class="pill">flow</span>` : ""}`,
          esc(e.use_when), [...new Set(callersOf(s.id, e).map(c => c.svc.id))].map(svcLink).join(", ") || (e.question ? "❓" : `<small>clients</small>`), `<small>${esc(e.auth)}</small>`]))}
        ${s.entry_points?.length ? `<h2>Runs without a request</h2>${table(["Kind", "Name", "What it does"], s.entry_points.map(p => [`<span class="pill">${esc(p.kind)}</span>`, `<code>${esc(p.name)}</code> ${ref(p.ref)}`, esc(p.does)]))}` : ""}
        <h2>Calls out</h2>${table(["From", "To", "Endpoint", "Kind", "When it fails"], (s.calls || []).map(c => [`<code>${esc(c.from)}</code>`, svcLink(c.to), `<code>${esc(c.endpoint)}</code>`, esc(c.kind), esc(c.on_failure)]))}
        <h2>Called by</h2>${table(["Service", "From", "Endpoint"], callers.map(c => [svcLink(c.svc.id), `<code>${esc(c.from)}</code>`, `<code>${esc(c.endpoint)}</code>`]))}
        ${(s.produces?.length || s.consumes?.length) ? `<h2>Events</h2>${table(["Direction", "Topic", "Events"], [...(s.produces || []).map(t => ["sends", t]), ...(s.consumes || []).map(t => ["receives", t])].map(([d, t]) => [d, `<code>${esc(t.topic)}</code>`, esc((t.events || []).join(", ")) + (t.question ? ` <small>❓ ${esc(t.question)}</small>` : "")]))}` : ""}
        ${s.tables?.length ? `<h2>Data</h2><p class="muted">Database <code>${esc(s.database || "?")}</code></p>${table(["Table", "Written by", "Read by"], s.tables.map(t => [`<code>${esc(t.name)}</code>`, esc((t.written_by || []).join(", ")), esc((t.read_by || []).join(", "))]))}${diagram(s.er)}` : ""}
        ${s.lifecycle ? `<h2>Lifecycle</h2>${diagram(s.lifecycle)}` : ""}
        ${s.pipeline ? `<h2>How it ships</h2>${table(["Workflow", "On pull request", "On merge", "To production"], [[`<code>${esc(s.pipeline.workflow)}</code>`, esc(s.pipeline.pr), esc(s.pipeline.merge), esc(s.pipeline.prod)]])}` : ""}
        ${foot(s)}`;
    },

    endpoint(svcId, key) {
      const s = ix.byId[svcId], e = s && (s.endpoints || []).find(x => `${x.method} ${x.path}` === key);
      if (!e) return notFound(`No endpoint ${key} in ${svcId}.`);
      const callers = callersOf(svcId, e), out = (s.calls || []).filter(c => c.from === key), f = e.flow;
      return `
        <div class="eyebrow">${layerPill(s.layer)}<a href="#/service/${enc(s.id)}">${esc(s.id)}</a></div>
        <h1>${method(e.method)} <span class="mono">${esc(e.path)}</span></h1>
        <p class="lede">${esc(e.purpose)}</p>
        <div class="use"><p><b>Use it when</b> ${esc(e.use_when)}</p>${e.dont_confuse ? `<p><b>Don't confuse with</b> ${esc(e.dont_confuse)}</p>` : ""}
          <p><b>Called by</b> ${callers.length ? callers.map(c => `${svcLink(c.svc.id)} <code>${esc(c.from)}</code>`).join(", ") : "clients (no service calls it)"} · <b>Auth</b> ${esc(e.auth)} · ${ref(e.ref)}</p></div>
        ${e.question ? callout("question", e.question) : ""}
        ${f ? `<h2>What it does</h2>${diagram(f.diagram)}
          ${f.steps?.length ? `<h3>Steps</h3><ol class="steps">${f.steps.map(st => `<li>${esc(st.text)} ${ref(st.ref)}</li>`).join("")}</ol>` : ""}
          ${f.errors?.length ? `<h2>Validation and errors</h2>${table(["When", "Status", "Error"], f.errors.map(x => [esc(x.when), `<b>${esc(x.status)}</b>`, `<code>${esc(x.code)}</code>`]))}` : ""}
          ${f.changes ? `<h2>What changes</h2><p>${esc(f.changes)}</p>` : ""}`
        : `<p class="muted">A simple read or save; no step-by-step view.</p>`}
        ${out.length ? `<h2>Calls out</h2>${table(["To", "Endpoint", "When it fails"], out.map(c => [svcLink(c.to), `<code>${esc(c.endpoint)}</code>`, esc(c.on_failure)]))}` : ""}
        ${foot(s)}`;
    },

    journey(id) {
      const j = state.journeys.find(x => x.id === id);
      if (!j) return notFound(`No journey ${id}.`);
      return `
        <div class="eyebrow"><span>Journey</span></div><h1>${esc(j.title)}</h1><p class="lede">${esc(j.story)}</p>
        ${j.start ? `<p>Starts at ${svcLink(j.start.service)} <a class="mono" href="#/endpoint/${enc(j.start.service)}/${enc(j.start.endpoint)}">${esc(j.start.endpoint)}</a></p>` : ""}
        ${diagram(j.diagram)}
        ${j.failures?.length ? `<h2>When it goes wrong</h2>${j.failures.map(t => callout("warn", t)).join("")}` : ""}
        ${j.changes ? `<h2>What changes</h2><p>${esc(j.changes)}</p>` : ""}`;
    },

    calls() {
      return `
        <h1>Calls and events</h1><p class="lede">Which endpoint calls which endpoint of which service, and who sends and receives each event.</p>
        <h2>Endpoint to endpoint</h2>
        ${table(["Caller", "From", "Callee", "Endpoint", "Kind", "When it fails"], ix.calls.map(c => [svcLink(c.svc.id), `<code>${esc(c.from)}</code>`, svcLink(c.to), `<code>${esc(c.endpoint)}</code>`, esc(c.kind), esc(c.on_failure)]))}
        <h2>Events</h2>
        ${table(["Topic", "Events", "Sent by", "Received by"], Object.values(ix.topics).map(t => [`<code>${esc(t.name)}</code>`, esc([...t.events].join(", ")), t.producers.map(svcLink).join(", ") || "❓ not in the mapped repositories", t.consumers.map(svcLink).join(", ") || "❓"]))}`;
    },

    data() {
      return `
        <h1>Data</h1><p class="lede">Which service owns each table, and which endpoints and jobs read and write it.</p>
        ${table(["Table", "Database", "Owner", "Written by", "Read by"], ix.tables.map(t => [`<code>${esc(t.name)}</code>`, `<code>${esc(t.svc.database || "?")}</code>`, svcLink(t.svc.id), esc((t.written_by || []).join(", ")), esc((t.read_by || []).join(", "))]))}
        ${ix.services.filter(s => s.er).map(s => `<h2>${esc(s.database || s.id)}</h2>${diagram(s.er)}`).join("")}`;
    },

    infra() {
      const shared = state.repos.flatMap(r => r.shared || []);
      return `
        <h1>Infrastructure and CI/CD</h1><p class="lede">Where each service runs (from Terraform) and how it ships (from GitHub Actions).</p>
        <h2>Where each service runs</h2>
        ${table(["Service", "Runs on", "Database", "Topics", "Terraform"], ix.services.map(s => [svcLink(s.id), esc(s.runtime), `<code>${esc(s.database || "—")}</code>`, esc([...(s.produces || []), ...(s.consumes || [])].map(t => t.topic).join(", ")), ref(s.terraform)]))}
        <h2>How it ships</h2>
        ${table(["Service", "Workflow", "On pull request", "On merge", "To production"], ix.services.filter(s => s.pipeline).map(s => [svcLink(s.id), `<code>${esc(s.pipeline.workflow)}</code>`, esc(s.pipeline.pr), esc(s.pipeline.merge), esc(s.pipeline.prod)]))}
        <h2>Shared infrastructure</h2>
        ${table(["Name", "Kind", "Where"], shared.map(x => [`<code>${esc(x.name)}</code>`, esc(x.kind), ref(x.ref)]))}`;
    },

    glossary() {
      return `<h1>Glossary</h1>${table(["Word", "Meaning"], [...ix.glossary].sort((a, b) => a.term.localeCompare(b.term)).map(g => [`<b>${esc(g.term)}</b>`, esc(g.meaning)]))}`;
    },

    questions() {
      return `<h1>Open questions</h1><p class="lede">What the agent couldn't prove from the code. Ask the team, then tell the agent the answer.</p>
        ${ix.questions.map(q => `<div class="callout question"><span class="tag">Open</span><p>${esc(q.text)} <a href="${q.href}">${esc(q.where)}</a></p></div>`).join("") || `<p class="muted">None.</p>`}`;
    },

    progress() {
      return `<h1>Map progress</h1><p class="lede">One repository per session, in the order of <code>data/repos.js</code>. Say <code>update &lt;repo&gt;</code> to the agent to re-map the changes since the commit below.</p>
        ${table(["#", "Repository", "Services", "Mapped at", "Date"], state.system.repos.map((name, i) => {
          const r = state.repos.find(x => x.repo === name);
          return [i + 1, `<code>${esc(name)}</code>`, r ? (r.services || []).map(s => svcLink(s.id)).join(", ") || `<small>${esc(r.kind || "")}</small>` : "<small>not mapped yet</small>", r ? `<code>${esc(r.commit)}</code>` : "", r ? esc(r.mapped) : ""];
        }))}`;
    },
  };

  function serviceCard(s) {
    return `<a class="card layer-${esc(s.layer)}" href="#/service/${enc(s.id)}"><span class="title">${layerDot(s.layer)}${esc(s.id)}</span><p>${esc(s.purpose)}</p>
      <span class="meta"><span>${(s.endpoints || []).length} endpoints</span><span>${(s.calls || []).length} calls out</span>${(s.notes || []).some(n => n.level === "risk") ? `<span style="color:var(--risk)">has risks</span>` : ""}</span></a>`;
  }
  const notFound = msg => `<h1>Not found</h1><p class="lede">${esc(msg)}</p><p><a href="#/">Back to the start</a></p>`;

  // ---------- graph ----------
  function drawGraph() {
    const box = document.getElementById("graph");
    if (!box || !window.cytoscape) return;
    const css = getComputedStyle(document.documentElement), v = n => css.getPropertyValue(n).trim();
    const layerColor = { Edge: v("--edge"), Domain: v("--domain"), Integration: v("--integration"), Workers: v("--workers") };
    const nodes = {}, edges = {};
    const node = (id, kind, layer) => nodes[id] ||= { data: { id, label: id, kind, layer: layer || "" } };
    const edge = (source, target, kind) => { const id = `${source}>${target}>${kind}`; (edges[id] ||= { data: { id, source, target, kind, count: 0 } }).data.count++; };
    for (const s of ix.services) {
      node(s.id, "service", s.layer);
      for (const c of s.calls || []) { node(c.to, ix.byId[c.to] ? "service" : "external", ix.byId[c.to]?.layer); edge(s.id, c.to, "http"); }
      for (const t of s.produces || []) { node(t.topic, "topic"); edge(s.id, t.topic, "event"); }
      for (const t of s.consumes || []) { node(t.topic, "topic"); edge(t.topic, s.id, "event"); }
      if (s.database) { node(s.database, "db"); edge(s.id, s.database, "data"); }
    }
    const cy = cytoscape({
      container: box, elements: [...Object.values(nodes), ...Object.values(edges)], wheelSensitivity: 0.2,
      style: [
        { selector: "node", style: { label: "data(label)", color: v("--fg"), "font-size": 11, "font-family": v("--font"), "text-valign": "bottom", "text-margin-y": 5, width: 30, height: 30, "background-color": v("--infra") } },
        ...Object.entries(layerColor).map(([l, c]) => ({ selector: `node[layer = "${l}"]`, style: { "background-color": c } })),
        { selector: 'node[kind = "topic"]', style: { shape: "round-rectangle", "background-color": v("--warn"), width: 44, height: 18 } },
        { selector: 'node[kind = "db"]', style: { shape: "barrel", "background-color": v("--infra"), width: 24, height: 28 } },
        { selector: 'node[kind = "external"]', style: { shape: "hexagon", "background-color": v("--risk") } },
        { selector: "edge", style: { width: 1.6, "curve-style": "bezier", "target-arrow-shape": "triangle", "line-color": v("--muted"), "target-arrow-color": v("--muted"), label: "data(count)", "font-size": 9, color: v("--muted"), "text-background-color": v("--surface"), "text-background-opacity": 1 } },
        { selector: 'edge[kind = "event"]', style: { "line-style": "dashed", label: "", "line-color": v("--warn"), "target-arrow-color": v("--warn") } },
        { selector: 'edge[kind = "data"]', style: { "line-style": "dotted", "target-arrow-shape": "none", label: "" } },
        { selector: ".faded", style: { opacity: 0.12 } },
        { selector: "node:selected", style: { "border-width": 3, "border-color": v("--accent") } },
      ],
      layout: { name: "breadthfirst", directed: true, spacingFactor: 1.15, roots: ix.services.filter(s => s.layer === (state.system.layers?.[0]?.id)).map(s => s.id) },
    });
    const panel = document.getElementById("graph-panel");
    const show = id => {
      cy.elements().addClass("faded");
      cy.getElementById(id).closedNeighborhood().removeClass("faded");
      const s = ix.byId[id], t = ix.topics[id];
      if (t) { panel.innerHTML = `<h3>${esc(id)}</h3><p class="muted">Topic · ${esc([...t.events].join(", "))}</p><b>Sent by</b><ul>${t.producers.map(p => `<li>${svcLink(p)}</li>`).join("") || "<li>❓</li>"}</ul><b>Received by</b><ul>${t.consumers.map(p => `<li>${svcLink(p)}</li>`).join("")}</ul>`; return; }
      if (!s) { panel.innerHTML = `<h3>${esc(id)}</h3><p class="muted">${esc(cy.getElementById(id).data("kind") === "db" ? "Database" : "External system")}</p>`; return; }
      panel.innerHTML = `<h3><a href="#/service/${enc(s.id)}">${esc(s.id)}</a></h3>${layerPill(s.layer)}<p>${esc(s.purpose)}</p>
        <b>Endpoints</b><ul>${(s.endpoints || []).map(e => `<li>${method(e.method)} <a class="mono" href="${epHref(s.id, e)}">${esc(e.path)}</a><br><small class="muted">${esc(e.use_when)}</small></li>`).join("") || "<li class='muted'>none</li>"}</ul>
        <b>Calls</b><ul>${(s.calls || []).map(c => `<li>${svcLink(c.to)} <code>${esc(c.endpoint)}</code></li>`).join("") || "<li class='muted'>none</li>"}</ul>
        <b>Called by</b><ul>${callersOfService(s.id).map(c => `<li>${svcLink(c.svc.id)} <code>${esc(c.from)}</code></li>`).join("") || "<li class='muted'>none</li>"}</ul>`;
    };
    cy.on("tap", "node", e => show(e.target.id()));
    cy.on("dbltap", "node", e => { if (ix.byId[e.target.id()]) location.hash = `#/service/${enc(e.target.id())}`; });
    cy.on("tap", e => { if (e.target === cy) { cy.elements().removeClass("faded"); panel.innerHTML = `<p class="muted">Click a service.</p>`; } });
    const toggles = document.getElementById("layer-toggles");
    toggles.addEventListener("change", () => {
      const off = [...toggles.querySelectorAll("input[value]:not(:checked)")].map(i => i.value);
      const showData = document.getElementById("show-data").checked, showEvents = document.getElementById("show-events").checked;
      cy.nodes().forEach(n => {
        const k = n.data("kind"), hide = (k === "service" && off.includes(n.data("layer"))) || (k === "db" && !showData) || (k === "topic" && !showEvents);
        n.style("display", hide ? "none" : "element");
      });
    });
  }

  // ---------- nav, search, routing ----------
  function nav() {
    const pages = [["", "Start here"], ["graph", "System graph"], ["endpoints", "All endpoints"], ["calls", "Calls and events"], ["data", "Data"],
      ["infra", "Infrastructure and CI/CD"], ["glossary", "Glossary"], ["questions", `Open questions (${ix.questions.length})`], ["progress", "Map progress"]];
    const byLayer = {};
    ix.services.forEach(s => (byLayer[s.layer] ||= []).push(s));
    document.getElementById("nav").innerHTML =
      pages.map(([r, t]) => `<a href="#/${r}" data-route="${r}">${esc(t)}</a>`).join("") +
      (state.journeys.length ? `<h4>Journeys</h4>` + state.journeys.map(j => `<a href="#/journey/${enc(j.id)}" data-route="journey/${esc(j.id)}">${esc(j.title)}</a>`).join("") : "") +
      Object.entries(byLayer).map(([l, list]) => `<h4>${esc(l)}</h4>` + list.map(s => `<a href="#/service/${enc(s.id)}" data-route="service/${esc(s.id)}">${layerDot(l)}${esc(s.id)}</a>`).join("")).join("");
  }

  function search() {
    const input = document.getElementById("search"), box = document.getElementById("results");
    const items = [
      ...ix.services.map(s => ({ t: s.id, sub: `service · ${s.layer}`, href: `#/service/${enc(s.id)}`, k: `${s.id} ${s.purpose}` })),
      ...ix.endpoints.map(e => ({ t: `${e.method} ${e.path}`, sub: `${e.svc.id} · ${e.purpose}`, href: epHref(e.svc.id, e), k: `${e.method} ${e.path} ${e.purpose} ${e.use_when} ${e.svc.id}` })),
      ...ix.tables.map(t => ({ t: t.name, sub: `table · ${t.svc.id}`, href: "#/data", k: t.name })),
      ...Object.keys(ix.topics).map(n => ({ t: n, sub: "topic", href: "#/calls", k: `${n} ${[...ix.topics[n].events].join(" ")}` })),
      ...state.journeys.map(j => ({ t: j.title, sub: "journey", href: `#/journey/${enc(j.id)}`, k: `${j.title} ${j.story}` })),
      ...ix.glossary.map(g => ({ t: g.term, sub: "glossary", href: "#/glossary", k: `${g.term} ${g.meaning}` })),
    ];
    input.addEventListener("input", () => {
      const q = input.value.trim().toLowerCase();
      const found = q ? items.filter(i => i.k.toLowerCase().includes(q)).slice(0, 12) : [];
      box.hidden = !q;
      box.innerHTML = found.map(i => `<a href="${i.href}">${esc(i.t)}<small>${esc(i.sub)}</small></a>`).join("") || `<p class="muted" style="margin:8px 10px">Nothing found.</p>`;
    });
    input.addEventListener("keydown", e => { if (e.key === "Enter") box.querySelector("a")?.click(); if (e.key === "Escape") { input.value = ""; box.hidden = true; } });
    box.addEventListener("click", () => { input.value = ""; box.hidden = true; });
    document.addEventListener("keydown", e => { if (e.key === "/" && document.activeElement.tagName !== "INPUT") { e.preventDefault(); input.focus(); } });
  }

  function route() {
    const [name, ...args] = location.hash.replace(/^#\/?/, "").split("/").map(decodeURIComponent);
    const main = document.getElementById("main");
    main.innerHTML = (views[name || "home"] || (() => notFound(`No page ${name}.`)))(...args);
    const current = location.hash.replace(/^#\/?/, "");
    document.querySelectorAll("#nav a").forEach(a => a.classList.toggle("active", a.dataset.route === decodeURIComponent(current)));
    document.title = `${main.querySelector("h1")?.textContent || "Service Map"} · ${state.system.name} map`;
    window.scrollTo(0, 0);
    if (window.mermaid) mermaid.run({ nodes: main.querySelectorAll(".mermaid") }).catch(err => console.error(err));
  }

  function start() {
    buildIndex();
    document.getElementById("brand-name").textContent = `${state.system.name} map`;
    const dark = matchMedia("(prefers-color-scheme: dark)").matches && document.documentElement.dataset.theme !== "light" || document.documentElement.dataset.theme === "dark";
    if (window.mermaid) mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: dark ? "dark" : "neutral", fontFamily: "system-ui, sans-serif" });
    nav(); search();
    addEventListener("hashchange", route);
    route();
  }

  return { system, repo, journey };
})();
