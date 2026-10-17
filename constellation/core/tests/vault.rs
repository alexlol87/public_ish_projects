mod common;
use common::*;
use constellation_core::agent_files;
use constellation_core::edit::apply;
use constellation_core::vault::{self, is_app_only, is_archive};
use constellation_core::{FileEdit, Range16, VaultIndex};
use std::fs;

fn names(n: &constellation_core::VaultNode) -> Vec<&str> {
    n.children.iter().map(|c| c.name.as_str()).collect()
}

#[test]
fn load_reports_folders_and_markdown_notes_only() {
    let v = make_vault(&[
        ("README.md", "# Welcome"),
        ("acme-shop/overview.md", "Shop"),
        ("acme-shop/cart-service/api.md", "Cart API"),
        ("acme-shop/logo.png", "x"),
        (".hidden.md", "secret"),
    ]);
    fs::create_dir(v.path().join("external")).unwrap();
    let tree = vault::load(v.path()).unwrap();
    assert_eq!(names(&tree), ["acme-shop", "external", "README.md"]);
    let shop = &tree.children[0];
    assert!(shop.is_folder);
    assert_eq!(names(shop), ["cart-service", "overview.md"]);
    assert_eq!(shop.children[0].children[0].relative_path, "acme-shop/cart-service/api.md");
    assert!(tree.children[1].children.is_empty());
}

#[test]
fn read_note_returns_raw_text() {
    let v = make_vault(&[("acme-shop/overview.md", "# Shop\n\nRaw *text*")]);
    assert_eq!(vault::read_note(v.path(), "acme-shop/overview.md").unwrap(), "# Shop\n\nRaw *text*");
}

#[test]
fn load_missing_folder_fails() {
    assert!(vault::load("/nonexistent-vault-dir".as_ref()).is_err());
}

#[test]
fn write_note_replaces_file_contents() {
    let v = make_vault(&[("a.md", "old")]);
    vault::write_note(v.path(), "a.md", "new **text**").unwrap();
    assert_eq!(read(v.path(), "a.md"), "new **text**");
    assert_eq!(fs::read_dir(v.path()).unwrap().count(), 1, "no temp file left behind");
}

#[test]
fn create_writes_exactly_the_starter_set() {
    let v = make_vault(&[]);
    vault::create(v.path()).unwrap();
    let mut found: Vec<_> = fs::read_dir(v.path()).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
    found.sort();
    assert_eq!(found, [".constellation", "AGENTS.md", "README.md", "clients", "external", "repos.txt", "tags.md", "templates"]);
    for d in [".constellation", "clients", "external", "templates"] {
        assert!(v.path().join(d).is_dir(), "{d}");
    }
}

#[test]
fn scaffold_writes_agents_and_every_template() {
    let v = make_vault(&[]);
    vault::create(v.path()).unwrap();
    assert_eq!(read(v.path(), "AGENTS.md"), agent_files::AGENTS_MD);
    let mut keys: Vec<_> = agent_files::TEMPLATES.iter().map(|t| t.0).collect();
    keys.sort();
    let mut want = [
        "project",
        "repo",
        "endpoints",
        "architecture",
        "adr",
        "requirements",
        "future",
        "bugs",
        "todo",
        "external-api",
        "client",
        "archive",
    ];
    want.sort();
    assert_eq!(keys, want);
    for (name, text) in agent_files::TEMPLATES {
        assert_eq!(read(v.path(), &format!("templates/{name}.md")), text);
    }
}

#[test]
fn create_refuses_non_empty_folder_and_keeps_files() {
    let v = make_vault(&[("README.md", "mine")]);
    assert!(vault::create(v.path()).is_err());
    assert_eq!(read(v.path(), "README.md"), "mine");
    assert_eq!(fs::read_dir(v.path()).unwrap().count(), 1);
}

#[test]
fn create_makes_missing_folder() {
    let v = make_vault(&[]);
    let root = v.path().join("new-vault");
    vault::create(&root).unwrap();
    assert!(root.join("README.md").exists());
}

#[test]
fn created_vault_loads_and_marks_app_only_nodes() {
    let v = make_vault(&[]);
    vault::create(v.path()).unwrap();
    let tree = vault::load(v.path()).unwrap();
    let got: std::collections::BTreeMap<_, _> = tree.children.iter().map(|c| (c.relative_path.as_str(), c.app_only)).collect();
    let want = [
        (".constellation", true),
        ("templates", true),
        ("clients", false),
        ("external", false),
        ("AGENTS.md", true),
        ("README.md", false),
        ("repos.txt", true),
        ("tags.md", true),
    ];
    assert_eq!(got, want.into());
}

#[test]
fn app_only_covers_nested_paths() {
    assert!(is_app_only("templates/project.md"));
    assert!(is_app_only(".constellation/settings.json"));
    assert!(!is_app_only("shop/AGENTS.md"));
    assert!(!is_app_only("shop/templates-notes.md"));
}

#[test]
fn archive_detection() {
    assert!(is_archive("shop/archive/fixed-bugs.md"));
    assert!(!is_archive("shop/orders-service/archive.md"));
}

#[test]
fn reopenable_only_when_folder_still_exists() {
    let v = make_vault(&[]);
    let p = v.path().to_str().unwrap();
    assert_eq!(vault::reopenable(Some(p)).unwrap(), v.path());
    assert!(vault::reopenable(Some(v.path().join("gone").to_str().unwrap())).is_none());
    assert!(vault::reopenable(None).is_none());
}

#[test]
fn refresh_applies_external_create_delete_and_move() {
    let v = make_vault(&[("a.md", "A"), ("docs/old.md", "O"), ("gone.md", "G")]);
    let mut tree = vault::load(v.path()).unwrap();
    write(v.path(), "new.md", "N");
    fs::remove_file(v.path().join("gone.md")).unwrap();
    fs::create_dir(v.path().join("archive")).unwrap();
    fs::rename(v.path().join("docs/old.md"), v.path().join("archive/old.md")).unwrap();
    let touched = ["new.md", "gone.md", "archive", "archive/old.md", "docs/old.md"].map(String::from);
    tree.refresh(&touched, v.path()).unwrap();
    assert_eq!(tree, vault::load(v.path()).unwrap());
    assert_eq!(names(&tree), ["archive", "docs", "a.md", "new.md"]);
}

#[test]
fn refresh_creates_nested_folders_and_ignores_vanished_parents() {
    let v = make_vault(&[("a.md", "A")]);
    let mut tree = vault::load(v.path()).unwrap();
    write(v.path(), "x/y/z.md", "Z");
    tree.refresh(&["x/y/z.md".into(), "nope/missing.md".into()], v.path()).unwrap();
    assert_eq!(tree, vault::load(v.path()).unwrap());
}

#[test]
fn image_resolution() {
    let v = make_vault(&[("notes/near.png", ""), ("assets/far.png", "")]);
    let r = |p: &str| vault::resolve_image(p, "notes/a.md", v.path()).map(|f| f.file_name().unwrap().to_string_lossy().into_owned());
    assert_eq!(r("near.png").as_deref(), Some("near.png"));
    assert_eq!(r("assets/far.png").as_deref(), Some("far.png"));
    assert_eq!(r("/assets/far.png").as_deref(), Some("far.png"));
    assert_eq!(r("gone.png"), None);
    assert_eq!(r("../../etc/passwd"), None);
}

#[test]
fn file_edit_apply_uses_utf16_offsets_and_inverts() {
    let v = make_vault(&[("a.md", "é😀 tag end")]);
    // "é😀 " is 4 UTF-16 units (but 7 bytes).
    let edit = FileEdit::replace("a.md", Range16::new(4, 3), "TAG!");
    let undo = apply(&[edit], v.path()).unwrap();
    assert_eq!(read(v.path(), "a.md"), "é😀 TAG! end");
    assert_eq!(undo, [FileEdit::replace("a.md", Range16::new(4, 4), "tag")]);
    apply(&undo, v.path()).unwrap();
    assert_eq!(read(v.path(), "a.md"), "é😀 tag end");
    // A range inside a surrogate pair is rejected.
    assert!(apply(&[FileEdit::replace("a.md", Range16::new(2, 1), "")], v.path()).is_err());
}

#[test]
fn index_open_on_scaffold_ignores_app_files() {
    let v = make_vault(&[]);
    vault::create(v.path()).unwrap();
    let ix = VaultIndex::open(v.path()).unwrap();
    assert_eq!(ix.note_paths(), ["README.md"]);
}
