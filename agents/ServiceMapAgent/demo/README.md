# Service map demo

A made-up shop (gateway, orders, billing, inventory, notification worker, Terraform) written by hand in the format the
Service Mapper agent produces, built as an MkDocs Material site. It doubles as the starting point of a real docs repo:
copy this folder, delete the shop pages and data, and let the agent fill them.

```bash
python3 -m pip install -r requirements.txt
mkdocs serve          # http://127.0.0.1:8000, reloads when a page changes
mkdocs build          # static site in site/
```

| Path | What it is |
|------|------------|
| `mkdocs.yml` | Site settings, navigation, Mermaid, the graph page's scripts. |
| `docs/` | The pages: start here, system graph, journeys, all endpoints, calls and events, data, infrastructure and CI/CD, one folder per service, glossary, progress. |
| `data/<repo>.yaml` | One file per mapped repository: services, endpoints with "use it when", calls, events, tables, deployment. |
| `hooks/graph.py` | Merges `data/*.yaml` into `graph.json` at build time for the System graph page. |
| `docs/javascripts/graph.js` | The interactive graph (Cytoscape.js): click a service for its endpoints, calls and callers; filter by layer. |

Mermaid and Cytoscape load from CDNs, so the diagrams need internet; for an offline site, download both files into
`docs/javascripts/` and point `extra_javascript` at them.

`requirements.txt` pins MkDocs below 2.0: the Material theme's team warns that MkDocs 2.0 drops plugins and themes,
and points to its successor, [Zensical](https://zensical.org/), which reads the same `mkdocs.yml`.
