mod common;
use common::*;
use constellation_core::edit::apply;
use constellation_core::{FileEdit, LinkResolution, VaultIndex};

const FILES: [(&str, &str); 6] = [
    ("README.md", "Home"),
    ("acme-shop/overview.md", "# Overview\n\n## Goals\nText"),
    ("acme-shop/cart-service/api.md", "API"),
    ("acme-shop/notes.md", "a"),
    ("clients/notes.md", "b"),
    ("templates/daily.md", "app only"),
];

fn note(p: &str) -> LinkResolution {
    LinkResolution::note(p)
}

fn broken(p: &str) -> LinkResolution {
    LinkResolution::Broken { create_path: p.into() }
}

#[test]
fn resolves_by_vault_path_with_or_without_extension() {
    let v = make_vault(&FILES);
    let ix = VaultIndex::open(v.path()).unwrap();
    assert_eq!(ix.resolve("acme-shop/cart-service/api"), note("acme-shop/cart-service/api.md"));
    assert_eq!(ix.resolve("acme-shop/overview.md"), note("acme-shop/overview.md"));
}

#[test]
fn resolves_by_unique_name_case_insensitive() {
    let v = make_vault(&FILES);
    assert_eq!(VaultIndex::open(v.path()).unwrap().resolve("API"), note("acme-shop/cart-service/api.md"));
}

#[test]
fn ambiguous_name_is_broken() {
    let v = make_vault(&FILES);
    let ix = VaultIndex::open(v.path()).unwrap();
    assert_eq!(ix.resolve("notes"), broken("notes.md"));
    assert_eq!(ix.resolve("acme-shop/notes"), note("acme-shop/notes.md"));
}

#[test]
fn missing_target_is_broken_with_create_path() {
    let v = make_vault(&FILES);
    assert_eq!(VaultIndex::open(v.path()).unwrap().resolve("ideas/new"), broken("ideas/new.md"));
}

#[test]
fn app_only_files_are_not_link_targets() {
    let v = make_vault(&FILES);
    assert_eq!(VaultIndex::open(v.path()).unwrap().resolve("daily"), broken("daily.md"));
}

#[test]
fn create_note_makes_file_and_resolves() {
    let v = make_vault(&FILES);
    let ix = VaultIndex::open(v.path()).unwrap();
    let edits = ix.create_note_edits("ideas/new");
    assert_eq!(edits, [FileEdit::create("ideas/new.md", "")]);
    assert!(!exists(v.path(), "ideas/new.md"), "returns edits, writes nothing");
    apply(&edits, v.path()).unwrap();
    let mut ix = VaultIndex::open(v.path()).unwrap();
    assert_eq!(ix.resolve("ideas/new"), note("ideas/new.md"));
    ix.ingest(&["ideas/new.md".into()]).unwrap();
    assert_eq!(ix.resolve("ideas/new"), note("ideas/new.md"));
}

#[test]
fn create_note_for_a_resolved_link_is_no_edits() {
    let v = make_vault(&FILES);
    assert!(VaultIndex::open(v.path()).unwrap().create_note_edits("overview").is_empty());
}

#[test]
fn backlinks_list_sources_including_by_name_and_excluding_self_and_code() {
    let v = make_vault(&FILES);
    write(v.path(), "a.md", "Go to [[acme-shop/overview#Goals]] and [[overview|ov]]");
    write(v.path(), "b.md", "`[[overview]]` [[nothing]]");
    write(v.path(), "acme-shop/overview.md", "# Overview\n[[overview]] self");
    let back = VaultIndex::open(v.path()).unwrap().backlinks("acme-shop/overview.md");
    assert_eq!(back.iter().map(|b| b.path.as_str()).collect::<Vec<_>>(), ["a.md", "a.md"]);
    assert_eq!(back.iter().map(|b| b.link.heading.as_deref()).collect::<Vec<_>>(), [Some("Goals"), None]);
}

#[test]
fn completions_for_notes_and_headings() {
    let v = make_vault(&FILES);
    let ix = VaultIndex::open(v.path()).unwrap();
    assert_eq!(ix.completions("ov"), ["overview"]);
    // ambiguous names are offered as paths, and the typed text may match inside a path
    assert_eq!(ix.completions("note"), ["acme-shop/notes", "clients/notes"]);
    assert_eq!(ix.completions("shop/cart"), ["api"]);
    assert_eq!(ix.completions("overview#"), ["overview#Overview", "overview#Goals"]);
    assert_eq!(ix.completions("overview#go"), ["overview#Goals"]);
    assert!(ix.completions("nothing#").is_empty());
}

#[test]
fn broken_links_in_unsaved_text() {
    let v = make_vault(&[("a.md", "x"), ("docs/b.md", "y")]);
    let ix = VaultIndex::open(v.path()).unwrap();
    let broken = ix.broken_links("[[a]] [[b]] [[nope]] `[[code]]`");
    assert_eq!(broken.iter().map(|l| l.target.as_str()).collect::<Vec<_>>(), ["nope"]);
}

#[test]
fn new_note_creates_at_exact_path_and_resolves() {
    let v = make_vault(&FILES);
    let ix = VaultIndex::open(v.path()).unwrap();
    for (typed, made) in [("acme-shop/ideas", "acme-shop/ideas.md"), ("  new-project/docs/README.md ", "new-project/docs/README.md"), ("overview", "overview.md")] {
        assert_eq!(ix.new_note_edits(typed).unwrap(), [FileEdit::create(made, "")], "{typed}");
    }
    let edits = ix.new_note_edits("new-project/README").unwrap();
    assert!(!exists(v.path(), "new-project/README.md"), "writes nothing");
    apply(&edits, v.path()).unwrap();
    assert_eq!(VaultIndex::open(v.path()).unwrap().resolve("new-project/README"), note("new-project/README.md"));
}

#[test]
fn new_note_refuses_bad_paths() {
    let v = make_vault(&FILES);
    let ix = VaultIndex::open(v.path()).unwrap();
    for bad in ["acme-shop/Overview", "ACME-SHOP/overview.md", "", "  ", "acme-shop/", "/abs", "../x", "a/../x", "templates/x", ".constellation/x.md", "AGENTS.md"] {
        assert!(ix.new_note_edits(bad).is_err(), "{bad:?}");
    }
}
