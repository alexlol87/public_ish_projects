mod common;
use common::*;
use constellation_core::graph::{EdgeKind, EndpointPair, NodeKind};
use constellation_core::{EndpointRef, GraphFilter, VaultGraph, VaultIndex};
use std::collections::BTreeSet;
use std::time::Instant;

fn graph_of(files: &[(&str, &str)]) -> VaultGraph {
    let v = make_vault(files);
    VaultIndex::open(v.path()).unwrap().graph(&GraphFilter::default(), None)
}

fn strs(items: impl IntoIterator<Item = impl AsRef<str>>) -> BTreeSet<String> {
    items.into_iter().map(|s| s.as_ref().to_string()).collect()
}

fn pair(from: &str, to: &str) -> EndpointPair {
    EndpointPair { from: from.into(), to: to.into() }
}

fn plain_graph() -> VaultGraph {
    graph_of(&[
        ("README.md", "Home [[overview]]"),
        ("acme/README.md", "Acme"),
        ("acme/overview.md", "See [[api]] and [[Missing One]] and [[missing one]]"),
        ("acme/cart/api.md", "back to [[overview]]; `[[code]]`"),
        ("empty/x.md", "x"),
        ("AGENTS.md", "[[overview]]"),
        ("templates/daily.md", "[[overview]]"),
    ])
}

fn ids_of(g: &VaultGraph, kind: NodeKind) -> BTreeSet<String> {
    strs(g.nodes.iter().filter(|n| n.kind == kind).map(|n| n.id.as_str()))
}

fn edges_of(g: &VaultGraph, kind: EdgeKind) -> BTreeSet<String> {
    strs(g.edges.iter().filter(|e| e.kind == kind).map(|e| format!("{}>{}", e.from, e.to)))
}

#[test]
fn nodes_for_notes_and_folders() {
    let g = plain_graph();
    assert_eq!(ids_of(&g, NodeKind::Folder), strs(["", "acme", "acme/cart", "empty"]));
    assert_eq!(ids_of(&g, NodeKind::Note), strs(["README.md", "acme/README.md", "acme/overview.md", "acme/cart/api.md", "empty/x.md"]));
}

#[test]
fn containment_edges() {
    assert_eq!(
        edges_of(&plain_graph(), EdgeKind::Containment),
        strs([
            ">README.md",
            ">acme",
            ">empty",
            "acme>acme/README.md",
            "acme>acme/overview.md",
            "acme>acme/cart",
            "acme/cart>acme/cart/api.md",
            "empty>empty/x.md"
        ])
    );
}

#[test]
fn link_edges_and_ghost_nodes() {
    let g = plain_graph();
    assert_eq!(
        edges_of(&g, EdgeKind::Link),
        strs([
            "README.md>acme/overview.md",
            "acme/overview.md>acme/cart/api.md",
            "acme/cart/api.md>acme/overview.md",
            "acme/overview.md>ghost:missing one.md"
        ])
    );
    let ghosts: Vec<_> = g.nodes.iter().filter(|n| n.kind == NodeKind::Ghost).map(|n| n.id.as_str()).collect();
    assert_eq!(ghosts, ["ghost:missing one.md"]);
}

#[test]
fn folder_opens_readme() {
    let g = plain_graph();
    assert_eq!(g.open_path("acme").as_deref(), Some("acme/README.md"));
    assert_eq!(g.open_path("empty"), None);
    assert_eq!(g.open_path("acme/overview.md").as_deref(), Some("acme/overview.md"));
    assert_eq!(g.open_path("").as_deref(), Some("README.md"));
    assert_eq!(g.open_path("ghost:missing one.md"), None);
}

#[test]
fn neighbours() {
    assert_eq!(plain_graph().neighbours("acme/overview.md"), ["README.md", "acme", "acme/cart/api.md", "ghost:missing one.md"]);
}

#[test]
fn archive_notes_are_hidden_by_default() {
    let v = make_vault(&[("shop/README.md", "# Shop [[fixed-bugs]]"), ("shop/archive/fixed-bugs.md", "### Cache bug\n")]);
    let ix = VaultIndex::open(v.path()).unwrap();
    let g = ix.graph(&GraphFilter::default(), None);
    assert!(!g.nodes.iter().any(|n| n.id.contains("archive")));
    assert!(!g.edges.iter().any(|e| e.to.contains("archive")));
    // The Link to a hidden archive Note is neither an edge nor a ghost.
    assert!(g.nodes.iter().all(|n| n.kind != NodeKind::Ghost));
    let all = ix.graph(&GraphFilter { include_archive: true, ..Default::default() }, None);
    assert!(all.nodes.iter().any(|n| n.id == "shop/archive/fixed-bugs.md"));
    assert!(all.edges.iter().any(|e| e.kind == EdgeKind::Link && e.to == "shop/archive/fixed-bugs.md"));
}

// --- endpoints ---

const CART: &str = "---\ntype: endpoint\nowner: team-a\n---\n# Cart endpoints\n\n## GET /cart\nCalls:\n- [[shop-orders/endpoints#POST /orders]]\n- [[shop-orders/endpoints#GET /stock]]\n\nStatus:\n- implemented: true\n- last_changed: 2026-01-02\n\n## DELETE /cart\nCalls:\n- [[shop-orders/endpoints#POST /orders]]";
const ORDERS: &str = "---\ntype: endpoint\n---\n## POST /orders\n## GET /stock\nCalls:\n- [[shop-cart/endpoints#GET /cart]]\n";
const WEB: &str = "---\ntype: client\n---\n# Web\nUses:\n- [[shop-cart/endpoints#GET /cart]]\n";

fn endpoint_files() -> Vec<(&'static str, &'static str)> {
    vec![
        ("shop-cart/endpoints.md", CART),
        ("shop-orders/endpoints.md", ORDERS),
        ("web.md", WEB),
        ("plain.md", "no frontmatter"),
        ("odd.md", "---\ntype: gizmo\nx: 1\n---\nbody"),
    ]
}

#[test]
fn node_types_and_folded_edges() {
    let g = graph_of(&endpoint_files());
    let ty = |id: &str| g.nodes.iter().find(|n| n.id == id).unwrap().note_type.clone();
    assert_eq!(ty("shop-cart/endpoints.md").as_deref(), Some("endpoint"));
    assert_eq!(ty("plain.md").as_deref(), Some("note"));
    assert_eq!(ty("odd.md").as_deref(), Some("gizmo"));
    let calls: Vec<_> = g.edges.iter().filter(|e| e.kind == EdgeKind::Call).collect();
    assert_eq!(calls.len(), 2);
    let out = calls.iter().find(|e| e.from == "shop-cart/endpoints.md").unwrap();
    assert_eq!(out.to, "shop-orders/endpoints.md");
    assert_eq!(out.pairs, [pair("GET /cart", "POST /orders"), pair("GET /cart", "GET /stock"), pair("DELETE /cart", "POST /orders")]);
    let uses: Vec<_> = g.edges.iter().filter(|e| e.kind == EdgeKind::Uses).collect();
    assert_eq!(uses.iter().map(|e| format!("{}>{}", e.from, e.to)).collect::<Vec<_>>(), ["web.md>shop-cart/endpoints.md"]);
    assert_eq!(uses[0].pairs, [pair("", "GET /cart")]);
}

#[test]
fn inspector_relations() {
    let v = make_vault(&endpoint_files());
    let ix = VaultIndex::open(v.path()).unwrap();
    let r = ix.endpoint_relations("shop-cart/endpoints.md", "GET /cart");
    let er = |p: &str, h: Option<&str>| EndpointRef { path: p.into(), heading: h.map(String::from) };
    assert_eq!(r.calls_out, [er("shop-orders/endpoints.md", Some("POST /orders")), er("shop-orders/endpoints.md", Some("GET /stock"))]);
    assert_eq!(r.calls_in, [er("shop-orders/endpoints.md", Some("GET /stock"))]);
    assert_eq!(r.uses_in, [er("web.md", None)]);
    let o = ix.endpoint_relations("shop-orders/endpoints.md", "POST /orders");
    assert_eq!(o.calls_in.iter().map(|e| e.heading.as_deref().unwrap()).collect::<Vec<_>>(), ["GET /cart", "DELETE /cart"]);
}

#[test]
fn backticked_method_headings_fold_into_plain_endpoint_names() {
    let v = make_vault(&[("a.md", "## `GET /a`\nCalls:\n- [[b#GET /b]]\n"), ("b.md", "## GET /b\n")]);
    let ix = VaultIndex::open(v.path()).unwrap();
    let g = ix.graph(&GraphFilter::default(), None);
    assert_eq!(g.edges.iter().find(|e| e.kind == EdgeKind::Call).unwrap().pairs, [pair("GET /a", "GET /b")]);
    assert_eq!(ix.endpoint_relations("b.md", "GET /b").calls_in, [EndpointRef { path: "a.md".into(), heading: Some("GET /a".into()) }]);
}

#[test]
fn call_and_uses_links_produce_only_their_own_edge() {
    let g = graph_of(&[
        ("ep.md", "---\ntype: endpoint\n---\n## GET /a\nCalls:\n- [[other#GET /b]]\n"),
        ("other.md", "---\ntype: endpoint\n---\n## GET /b\n"),
        ("web.md", "---\ntype: client\n---\nUses:\n- [[ep#GET /a]]\nAlso see [[other]]\n"),
    ]);
    let pairs: Vec<_> =
        g.edges.iter().filter(|e| e.kind != EdgeKind::Containment).map(|e| format!("{:?} {}>{}", e.kind, e.from, e.to)).collect();
    assert_eq!(strs(&pairs), strs(["Call ep.md>other.md", "Uses web.md>ep.md", "Link web.md>other.md"]));
    assert_eq!(pairs.len(), 3);
}

// --- filters ---

fn filter_vault() -> tempfile::TempDir {
    make_vault(&[
        ("shop/a.md", "#pay [[b]]"),
        ("shop/b.md", "[[c]]"),
        ("shop/c.md", "[[d]]"),
        ("shop/d.md", "end"),
        ("shop/archive/old.md", "[[a]]"),
        ("shop/ep.md", "---\ntype: endpoint\n---\n## GET /x\nCalls:\n- [[blog/y#GET /y]]\n"),
        ("blog/x.md", "---\ntags: [pay/refund]\n---\nx"),
        ("blog/y.md", "---\ntype: endpoint\n---\n## GET /y\n"),
        ("blog/z.md", "no tags"),
    ])
}

fn ids(ix: &VaultIndex, f: &GraphFilter, around: Option<&str>) -> BTreeSet<String> {
    strs(ix.graph(f, around).nodes.iter().map(|n| n.id.as_str()))
}

#[test]
fn local_graph_depth_one_to_three() {
    let v = filter_vault();
    let ix = VaultIndex::open(v.path()).unwrap();
    let mut f = GraphFilter { edge_kinds: [EdgeKind::Link].into(), ..Default::default() };
    f.local_depth = 1;
    assert_eq!(ids(&ix, &f, Some("shop/a.md")), strs(["shop/a.md", "shop/b.md"]));
    f.local_depth = 2;
    assert_eq!(ids(&ix, &f, Some("shop/a.md")), strs(["shop/a.md", "shop/b.md", "shop/c.md"]));
    f.local_depth = 3;
    assert_eq!(ids(&ix, &f, Some("shop/b.md")), strs(["shop/a.md", "shop/b.md", "shop/c.md", "shop/d.md"]));
    f.local_depth = 99;
    assert_eq!(ids(&ix, &f, Some("shop/a.md")), strs(["shop/a.md", "shop/b.md", "shop/c.md", "shop/d.md"]), "depth is clamped to 3");
}

#[test]
fn archive_toggle() {
    let v = filter_vault();
    let ix = VaultIndex::open(v.path()).unwrap();
    assert!(!ids(&ix, &GraphFilter::default(), None).contains("shop/archive/old.md"));
    assert!(ids(&ix, &GraphFilter { include_archive: true, ..Default::default() }, None).contains("shop/archive/old.md"));
}

#[test]
fn tag_filter_keeps_tagged_notes_and_neighbours() {
    let v = filter_vault();
    let ix = VaultIndex::open(v.path()).unwrap();
    let f = GraphFilter { tag: Some("PAY".into()), edge_kinds: [EdgeKind::Link].into(), ..Default::default() };
    // shop/a (#pay) and blog/x (child tag pay/refund) match; b is a neighbour of a.
    assert_eq!(ids(&ix, &f, None), strs(["shop/a.md", "shop/b.md", "blog/x.md"]));
}

#[test]
fn project_type_and_edge_kind_filters() {
    let v = filter_vault();
    let ix = VaultIndex::open(v.path()).unwrap();
    let f = GraphFilter { projects: strs(["blog"]), ..Default::default() };
    assert!(ids(&ix, &f, None).is_subset(&strs(["", "blog", "blog/x.md", "blog/y.md", "blog/z.md"])));
    let f = GraphFilter { types: strs(["endpoint"]), ..Default::default() };
    assert_eq!(strs(ids(&ix, &f, None).iter().filter(|i| i.ends_with(".md"))), strs(["shop/ep.md", "blog/y.md"]));
    let f = GraphFilter { edge_kinds: [EdgeKind::Call].into(), ..Default::default() };
    assert!(ix.graph(&f, None).edges.iter().all(|e| e.kind == EdgeKind::Call));
    assert_eq!(ix.graph(&f, None).edges.len(), 1);
}

#[test]
fn filters_persist_in_vault_settings() {
    let v = filter_vault();
    let root = v.path();
    assert_eq!(GraphFilter::load(root), GraphFilter::default());
    let f = GraphFilter {
        tag: Some("pay".into()),
        projects: strs(["shop"]),
        edge_kinds: [EdgeKind::Link, EdgeKind::Call].into(),
        local_depth: 3,
        ..Default::default()
    };
    f.save(root).unwrap();
    assert_eq!(GraphFilter::load(root), f);
    // The settings file is app-only, so it never shows up as a Node.
    let ix = VaultIndex::open(root).unwrap();
    assert!(!ix.graph(&GraphFilter::default(), None).nodes.iter().any(|n| n.id.contains(".constellation")));
    assert!(ix.tree().children.iter().any(|c| c.relative_path == ".constellation"));
}

#[test]
fn filter_json_is_camel_case_and_tolerates_missing_fields() {
    let f: GraphFilter = serde_json::from_str(r#"{"edgeKinds":["link","uses"],"includeArchive":true}"#).unwrap();
    assert_eq!(f.edge_kinds, [EdgeKind::Link, EdgeKind::Uses].into());
    assert!(f.include_archive);
    assert_eq!(f.local_depth, 2);
    let v = serde_json::to_value(GraphFilter::default()).unwrap();
    assert_eq!(v["edgeKinds"], serde_json::json!(["containment", "link", "call", "uses"]));
    assert_eq!(v["localDepth"], 2);
    let g = serde_json::to_value(plain_graph()).unwrap();
    assert_eq!(g["nodes"][0]["kind"], "folder");
    assert!(g["nodes"].as_array().unwrap().iter().any(|n| n["kind"] == "note" && n["noteType"] == "note"));
}

#[test]
fn five_thousand_note_vault_stays_usable() {
    let owned: Vec<(String, String)> =
        (0..5000).map(|i| (format!("p{}/n{i}.md", i % 20), format!("[[n{}]] [[n{}]]", (i * 7 + 1) % 5000, (i + 1) % 5000))).collect();
    let v = make_vault(&owned.iter().map(|(p, t)| (p.as_str(), t.as_str())).collect::<Vec<_>>());
    let ix = VaultIndex::open(v.path()).unwrap();
    let start = Instant::now();
    let g = ix.graph(&GraphFilter::default(), None);
    let local = ix.graph(&GraphFilter::default(), Some("p1/n1.md"));
    assert!(g.nodes.len() > 5000);
    assert!(local.nodes.len() < g.nodes.len());
    assert!(start.elapsed().as_secs_f64() < if cfg!(debug_assertions) { 10.0 } else { 1.0 });
}
