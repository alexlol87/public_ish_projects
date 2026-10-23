// System graph page: draws graph.json (built from data/*.yaml by hooks/graph.py) with Cytoscape.
(function () {
  const box = document.getElementById("service-graph");
  if (!box) return;
  const panel = document.getElementById("graph-panel");
  const css = getComputedStyle(document.body);
  const fg = css.getPropertyValue("--md-default-fg-color").trim() || "#333";
  const layerColor = { Edge: "#7b61ff", Domain: "#1a7fd4", Integration: "#e8590c", Workers: "#2f9e44" };
  // graph.json and page links are relative to the site root, one level above this script
  const root = new URL("../", document.querySelector('script[src*="javascripts/graph.js"]').src);
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

  fetch(new URL("graph.json", root)).then(r => r.json()).then(services => {
    const byId = Object.fromEntries(services.map(s => [s.id, s]));
    const nodes = {}, edges = {};
    const node = (id, kind, layer) => nodes[id] = nodes[id] || { data: { id, label: id, kind, layer } };
    const edge = (source, target, kind) => {
      const id = `${source}>${target}>${kind}`;
      edges[id] = edges[id] || { data: { id, source, target, kind, count: 0 } };
      edges[id].data.count++;
    };
    for (const s of services) {
      node(s.id, "service", s.layer);
      for (const c of s.calls || []) { node(c.to, byId[c.to] ? "service" : "external", byId[c.to]?.layer); edge(s.id, c.to, c.kind); }
      for (const t of s.produces || []) { node(t, "topic"); edge(s.id, t, "event"); }
      for (const t of s.consumes || []) { node(t, "topic"); edge(t, s.id, "event"); }
      if (s.database) { node(s.database, "db"); edge(s.id, s.database, "data"); }
    }

    const cy = cytoscape({
      container: box,
      elements: [...Object.values(nodes), ...Object.values(edges)],
      style: [
        { selector: "node", style: { label: "data(label)", color: fg, "font-size": 11, "text-valign": "bottom", "text-margin-y": 4, width: 34, height: 34 } },
        ...Object.entries(layerColor).map(([l, c]) => ({ selector: `node[layer = "${l}"]`, style: { "background-color": c } })),
        { selector: 'node[kind = "topic"]', style: { shape: "round-rectangle", "background-color": "#f59f00", width: 46, height: 20 } },
        { selector: 'node[kind = "db"]', style: { shape: "barrel", "background-color": "#868e96" } },
        { selector: 'node[kind = "external"]', style: { shape: "hexagon", "background-color": "#c92a2a" } },
        { selector: "edge", style: { width: 2, "curve-style": "bezier", "target-arrow-shape": "triangle", "line-color": "#adb5bd", "target-arrow-color": "#adb5bd", label: "data(count)", "font-size": 9, color: fg } },
        { selector: 'edge[kind = "event"]', style: { "line-style": "dashed", label: "" } },
        { selector: 'edge[kind = "data"]', style: { "line-style": "dotted", "target-arrow-shape": "none", label: "" } },
        { selector: ".faded", style: { opacity: 0.12 } },
        { selector: "node:selected", style: { "border-width": 3, "border-color": fg } },
      ],
      layout: { name: "breadthfirst", directed: true, spacingFactor: 1.2, roots: services.filter(s => s.layer === "Edge").map(s => s.id) },
      wheelSensitivity: 0.2,
    });

    const show = id => {
      const s = byId[id];
      cy.elements().addClass("faded");
      cy.getElementById(id).closedNeighborhood().removeClass("faded");
      if (!s) { panel.innerHTML = `<h3>${esc(id)}</h3><p>${esc(cy.getElementById(id).data("kind"))}</p>`; return; }
      const callers = services.flatMap(o => (o.calls || []).filter(c => c.to === id).map(c => `<li><b>${esc(o.id)}</b> ${esc(c.from)} → ${esc(c.endpoint)}</li>`));
      panel.innerHTML = `<h3><a href="${new URL(s.page, root)}">${esc(s.id)}</a></h3>
        <p>${esc(s.purpose)}<br><small>${esc(s.layer)} · repo ${esc(s.repo)}@${esc(s.commit)} · ${esc(s.deployed?.runtime || "")}</small></p>
        <h4>Endpoints</h4><ul>${(s.endpoints || []).map(e => `<li><code>${esc(e.method)} ${esc(e.path)}</code>${e.page ? ` <a href="${new URL(e.page, root)}">flow</a>` : ""}<br><small>${esc(e.use_when || "")}</small></li>`).join("") || "<li>none</li>"}</ul>
        <h4>Calls</h4><ul>${(s.calls || []).map(c => `<li>${esc(c.from)} → <b>${esc(c.to)}</b> ${esc(c.endpoint)}</li>`).join("") || "<li>none</li>"}</ul>
        <h4>Called by</h4><ul>${callers.join("") || "<li>none</li>"}</ul>`;
    };
    cy.on("tap", "node", e => show(e.target.id()));
    cy.on("tap", e => { if (e.target === cy) { cy.elements().removeClass("faded"); panel.innerHTML = "<p>Click a service.</p>"; } });

    document.querySelectorAll("#graph-layers input").forEach(input => input.addEventListener("change", () => {
      const off = [...document.querySelectorAll("#graph-layers input:not(:checked)")].map(i => i.value);
      cy.nodes('[kind = "service"]').forEach(n => n.style("display", off.includes(n.data("layer")) ? "none" : "element"));
    }));
  });
})();
