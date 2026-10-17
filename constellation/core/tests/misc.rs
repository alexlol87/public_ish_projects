mod common;
use chrono::NaiveDate;
use common::*;
use constellation_core::edit::apply;
use constellation_core::graph::NodeKind;
use constellation_core::{agent_files, parser::parse, vault, GraphFilter, Staleness, VaultIndex};
use std::collections::BTreeMap;

fn date(s: &str) -> NaiveDate {
    NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap()
}

// --- agent files ---

#[test]
fn agents_md_covers_workflows_and_hard_rules() {
    for s in ["## Ingest", "## Refresh", "## Answer", "repos.txt", "Archive", "Client", "unknown", "tags.md", "sibling"] {
        assert!(agent_files::AGENTS_MD.contains(s), "{s}");
    }
    assert!(agent_files::AGENTS_MD.starts_with("# Agent rules\n"));
    assert!(agent_files::AGENTS_MD.ends_with("`[[<project>/<repo>/README]]`."));
}

fn template(name: &str) -> &'static str {
    agent_files::TEMPLATES.iter().find(|t| t.0 == name).unwrap().1
}

#[test]
fn templates_give_the_right_note_types() {
    let expected = [
        ("project", "project"),
        ("repo", "repo"),
        ("endpoints", "endpoint"),
        ("architecture", "architecture"),
        ("adr", "adr"),
        ("requirements", "requirements"),
        ("future", "future"),
        ("bugs", "bugs"),
        ("todo", "todo"),
        ("external-api", "external-api"),
        ("client", "client"),
        ("archive", "archive"),
    ];
    for (name, ty) in expected {
        assert_eq!(parse(template(name)).note_type, ty, "{name}");
    }
    let repo = parse(template("repo"));
    for k in ["repo_url", "verified_commit", "verified_on"] {
        assert_eq!(repo.frontmatter[k], "unknown", "{k}");
    }
    assert!(template("repo").ends_with('\n'));
}

#[test]
fn endpoints_template_has_calls_and_status() {
    let p = parse(template("endpoints"));
    assert_eq!(p.calls.len(), 1);
    assert_eq!(p.calls[0].links.len(), 1);
    assert_eq!(p.calls[0].links[0].heading.as_deref(), Some("GET /path"));
    assert_eq!(p.status[0].values.keys().map(String::as_str).collect::<Vec<_>>(), ["implemented", "last_changed", "missing"]);
}

#[test]
fn client_and_external_templates() {
    let c = parse(template("client"));
    assert_eq!(c.uses.len(), 1);
    assert_eq!(c.uses[0].links.len(), 1);
    assert!(parse(template("external-api")).endpoints().next().is_some());
}

#[test]
fn templates_are_ignored_by_the_vault_indexes() {
    let v = make_vault(&[]);
    vault::create(v.path()).unwrap();
    assert!(vault::is_app_only("templates/endpoints.md"));
    let ix = VaultIndex::open(v.path()).unwrap();
    assert!(!ix.graph(&GraphFilter::default(), None).nodes.iter().any(|n| n.kind == NodeKind::Ghost));
}

#[test]
fn copy_prompts() {
    let i = agent_files::ingest_prompt("orders");
    assert!(i.contains("orders") && i.contains("AGENTS.md") && i.contains("Ingest"));
    let r = agent_files::refresh_prompt("orders");
    assert!(r.contains("orders") && r.contains("AGENTS.md") && r.contains("Refresh"));
    assert_eq!(i, "Follow AGENTS.md in this Vault and run the Ingest workflow for the repository \"orders\".");
}

#[test]
fn repo_folder_detection() {
    assert!(agent_files::is_repo_folder("shop/orders"));
    for p in ["shop", "shop/orders/sub", "shop/archive", "external/x", "clients/x", "templates/x", ".constellation/x", ""] {
        assert!(!agent_files::is_repo_folder(p), "{p}");
    }
}

// --- staleness ---

#[test]
fn fresh_stale_never_malformed() {
    let now = date("2026-06-30");
    assert_eq!(Staleness::of(Some("2026-06-20"), now), Staleness::Verified { days: 10 });
    assert_eq!(Staleness::of(Some("2026-05-01"), now), Staleness::Verified { days: 60 });
    assert_eq!(Staleness::of(None, now), Staleness::Never);
    assert_eq!(Staleness::of(Some("  "), now), Staleness::Never);
    assert_eq!(Staleness::of(Some("last tuesday"), now), Staleness::Malformed);
    assert_eq!(Staleness::of(Some("2026-13-45"), now), Staleness::Malformed);
    assert_eq!(Staleness::of(Some("2026-6-5"), now), Staleness::Malformed);
}

#[test]
fn highlight_and_label() {
    assert!(!Staleness::Verified { days: 30 }.is_stale(30));
    assert!(Staleness::Verified { days: 31 }.is_stale(30));
    assert!(Staleness::Never.is_stale(30));
    assert!(Staleness::Malformed.is_stale(30));
    assert_eq!(Staleness::Verified { days: 10 }.label(), "verified 10 days ago");
    assert_eq!(Staleness::Verified { days: 1 }.label(), "verified 1 day ago");
    assert_eq!(Staleness::Verified { days: 0 }.label(), "verified today");
    assert_eq!(Staleness::Never.label(), "never verified");
    assert_eq!(Staleness::Malformed.label(), "verified date unreadable");
    assert_eq!(Staleness::Verified { days: -3 }.label(), "verified today"); // future date: clamp
    assert_eq!(serde_json::to_value(Staleness::Verified { days: 5 }).unwrap(), serde_json::json!({"kind": "verified", "days": 5}));
}

#[test]
fn repo_staleness_from_vault() {
    let v = make_vault(&[
        ("p/fresh/README.md", "---\ntype: repo\nverified_on: 2026-06-25\n---\n# x"),
        ("p/old/README.md", "---\ntype: repo\nverified_on: 2025-01-01\n---\n"),
        ("p/none/README.md", "---\ntype: repo\n---\n"),
        ("p/bad/README.md", "---\ntype: repo\nverified_on: soon\n---\n"),
        ("p/plain/README.md", "---\ntype: project\n---\n"),
        ("p/note.md", "hi"),
    ]);
    let r = VaultIndex::open(v.path()).unwrap().repo_staleness(date("2026-06-30"));
    let want: BTreeMap<String, Staleness> = [
        ("p/fresh", Staleness::Verified { days: 5 }),
        ("p/old", Staleness::Verified { days: 545 }),
        ("p/none", Staleness::Never),
        ("p/bad", Staleness::Malformed),
    ]
    .into_iter()
    .map(|(k, v)| (k.to_string(), v))
    .collect();
    assert_eq!(r, want);
}

// --- index ---

#[test]
fn ingest_refreshes_tree_search_tags_graph_and_backlinks_from_touched_paths_only() {
    let v = make_vault(&[("a.md", "plain"), ("b.md", "[[a]] #old")]);
    let root = v.path();
    let mut ix = VaultIndex::open(root).unwrap();
    let back = |ix: &VaultIndex| ix.backlinks("a.md").into_iter().map(|b| b.path).collect::<Vec<_>>();
    assert_eq!(back(&ix), ["b.md"]);

    // Touched and ingested: everything follows.
    write(root, "c.md", "[[a]] #fresh and [[nowhere]]");
    ix.ingest(&["c.md".into()]).unwrap();
    assert_eq!(ix.tree().children.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(), ["a.md", "b.md", "c.md"]);
    assert_eq!(back(&ix), ["b.md", "c.md"]);
    assert_eq!(ix.tag_tree(constellation_core::tags::Sort::Name).iter().map(|t| t.tag.as_str()).collect::<Vec<_>>(), ["fresh", "old"]);
    assert_eq!(ix.search("fresh").matches[0].path, "c.md");
    let g = ix.graph(&GraphFilter::default(), None);
    assert!(g.edges.iter().any(|e| e.from == "c.md" && e.to == "a.md"));
    assert!(g.nodes.iter().any(|n| n.kind == NodeKind::Ghost && n.name == "nowhere"));

    // Changed on disk but not reported: the index must not have re-read it.
    write(root, "b.md", "no links now");
    assert_eq!(back(&ix), ["b.md", "c.md"]);
    ix.ingest(&["b.md".into()]).unwrap();
    assert_eq!(back(&ix), ["c.md"]);

    std::fs::remove_file(root.join("c.md")).unwrap();
    ix.ingest(&["c.md".into()]).unwrap();
    assert!(back(&ix).is_empty());
    assert!(!ix.graph(&GraphFilter::default(), None).nodes.iter().any(|n| n.id == "c.md"));
}

#[test]
fn ingest_picks_up_a_moved_in_folder_and_drops_a_moved_out_one() {
    let v = make_vault(&[("a.md", "x"), ("old/n.md", "needle #t")]);
    let root = v.path();
    let mut ix = VaultIndex::open(root).unwrap();
    std::fs::rename(root.join("old"), root.join("new")).unwrap();
    ix.ingest(&["old".into(), "new".into()]).unwrap();
    assert_eq!(ix.note_paths(), ["a.md", "new/n.md"]);
    assert_eq!(ix.search("needle").matches[0].path, "new/n.md");
    assert_eq!(ix.tag_hits("t")[0].path, "new/n.md");
}

#[test]
fn repo_staleness_follows_ingest() {
    let v = make_vault(&[("shop/orders/README.md", "---\ntype: repo\nverified_on: 2026-10-01\n---\n"), ("shop/README.md", "plain")]);
    let mut ix = VaultIndex::open(v.path()).unwrap();
    let now = date("2026-10-11");
    assert_eq!(ix.repo_staleness(now)["shop/orders"], Staleness::Verified { days: 10 });
    assert_eq!(ix.repo_staleness(now).len(), 1);
    write(v.path(), "shop/orders/README.md", "---\ntype: repo\n---\n");
    ix.ingest(&["shop/orders/README.md".into()]).unwrap();
    assert_eq!(ix.repo_staleness(now)["shop/orders"], Staleness::Never);
}

#[test]
fn create_note_edits_apply_and_resolve() {
    let v = make_vault(&[("a.md", "x")]);
    let ix = VaultIndex::open(v.path()).unwrap();
    apply(&ix.create_note_edits("ideas/new"), v.path()).unwrap();
    assert_eq!(read(v.path(), "ideas/new.md"), "");
}
