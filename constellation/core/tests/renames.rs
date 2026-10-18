mod common;
use common::*;
use constellation_core::edit::apply;
use constellation_core::graph::NodeKind;
use constellation_core::renames::{move_note_to_folder, rename_heading, rename_note, rename_tag};
use constellation_core::{GraphFilter, VaultIndex};

const FILES: [(&str, &str); 3] = [
    ("acme/cart.md", "# Cart\n## Totals\nBody"),
    ("acme/orders.md", "See [[cart]] and [[acme/cart#Totals|sum]] and [[acme/cart.md]]. `[[cart]]`"),
    ("other.md", "[[Cart#Totals]] [[missing]]"),
];

fn open(v: &tempfile::TempDir) -> VaultIndex {
    VaultIndex::open(v.path()).unwrap()
}

/// Names of the ghost Nodes the graph shows for broken Links.
fn ghosts(v: &tempfile::TempDir) -> Vec<String> {
    open(v).graph(&GraphFilter::default(), None).nodes.into_iter().filter(|n| n.kind == NodeKind::Ghost).map(|n| n.name).collect()
}

#[test]
fn rename_note_rewrites_links_and_undo_restores() {
    let v = make_vault(&FILES);
    let root = v.path();
    let edits = rename_note(&open(&v), "acme/cart.md", "basket").unwrap();
    assert!(edits.iter().any(|e| e.path == "acme/basket.md" && e.creates_file));
    assert!(edits.iter().any(|e| e.path == "acme/cart.md" && e.removes_file));

    let undo = apply(&edits, root).unwrap();
    assert_eq!(read(root, "acme/orders.md"), "See [[basket]] and [[acme/basket#Totals|sum]] and [[acme/basket.md]]. `[[cart]]`");
    assert_eq!(read(root, "other.md"), "[[basket#Totals]] [[missing]]");
    assert_eq!(ghosts(&v), ["missing"]);

    apply(&undo, root).unwrap();
    assert_eq!(read(root, "acme/orders.md"), FILES[1].1);
    assert_eq!(read(root, "acme/cart.md"), FILES[0].1);
    assert!(!exists(root, "acme/basket.md"));
}

#[test]
fn undo_of_rename_after_editing_the_note_is_refused_and_writes_nothing() {
    let v = make_vault(&FILES);
    let root = v.path();
    let undo = apply(&rename_note(&open(&v), "acme/cart.md", "basket").unwrap(), root).unwrap();
    std::fs::write(root.join("acme/basket.md"), "edited").unwrap();
    let orders = read(root, "acme/orders.md");

    assert!(apply(&undo, root).is_err());
    assert_eq!(read(root, "acme/basket.md"), "edited");
    assert!(!exists(root, "acme/cart.md"));
    assert_eq!(read(root, "acme/orders.md"), orders);
}

#[test]
fn move_note_keeps_name_links_and_rewrites_path_links() {
    let v = make_vault(&FILES);
    let root = v.path();
    let undo = apply(&move_note_to_folder(&open(&v), "acme/cart.md", "shop/v2").unwrap(), root).unwrap();
    let moved = "See [[cart]] and [[shop/v2/cart#Totals|sum]] and [[shop/v2/cart.md]]. `[[cart]]`";
    assert_eq!(read(root, "acme/orders.md"), moved);
    assert_eq!(read(root, "other.md"), "[[Cart#Totals]] [[missing]]");
    assert_eq!(ghosts(&v), ["missing"]);
    assert!(exists(root, "shop/v2/cart.md"));
    let redo = apply(&undo, root).unwrap();
    for (p, text) in FILES {
        assert_eq!(read(root, p), text);
    }
    assert!(!exists(root, "shop/v2/cart.md"));
    apply(&redo, root).unwrap();
    assert_eq!(read(root, "acme/orders.md"), moved);
}

#[test]
fn rename_to_name_clashing_with_another_note_falls_back_to_path() {
    let v = make_vault(&[FILES[0], FILES[1], FILES[2], ("x/basket.md", "x")]);
    apply(&rename_note(&open(&v), "acme/cart.md", "basket").unwrap(), v.path()).unwrap();
    assert_eq!(read(v.path(), "other.md"), "[[acme/basket#Totals]] [[missing]]");
}

#[test]
fn rename_onto_existing_note_fails() {
    let v = make_vault(&FILES);
    assert!(rename_note(&open(&v), "acme/cart.md", "orders").is_err());
    assert!(rename_note(&open(&v), "nope.md", "x").is_err());
    assert!(rename_note(&open(&v), "acme/cart.md", "cart").unwrap().is_empty());
}

#[test]
fn rename_heading_rewrites_heading_and_links() {
    let v = make_vault(&FILES);
    let root = v.path();
    let undo = apply(&rename_heading(&open(&v), "Totals", "Sums", "acme/cart.md").unwrap(), root).unwrap();
    assert_eq!(read(root, "acme/cart.md"), "# Cart\n## Sums\nBody");
    assert_eq!(read(root, "acme/orders.md"), "See [[cart]] and [[acme/cart#Sums|sum]] and [[acme/cart.md]]. `[[cart]]`");
    assert_eq!(read(root, "other.md"), "[[Cart#Sums]] [[missing]]");
    apply(&undo, root).unwrap();
    assert_eq!(read(root, "other.md"), FILES[2].1);
    assert_eq!(read(root, "acme/cart.md"), FILES[0].1);
    assert!(rename_heading(&open(&v), "Nope", "x", "acme/cart.md").is_err());
}

#[test]
fn rename_tag_covers_nested_and_frontmatter() {
    let v = make_vault(&[
        ("a.md", "---\ntags: [team/pay, other]\n---\nText #team/pay and #team/pay/api, not #teamwork or `#team/pay`."),
        ("b.md", "---\ntags:\n  - team\n---\n#team #Team/Pay"),
    ]);
    let root = v.path();
    let undo = apply(&rename_tag(&open(&v), "team/pay", "squad/billing").unwrap(), root).unwrap();
    assert_eq!(
        read(root, "a.md"),
        "---\ntags: [squad/billing, other]\n---\nText #squad/billing and #squad/billing/api, not #teamwork or `#team/pay`."
    );
    assert_eq!(read(root, "b.md"), "---\ntags:\n  - team\n---\n#team #squad/billing");
    assert!(open(&v).tag_hits("team/pay").is_empty());
    apply(&undo, root).unwrap();
    assert_eq!(read(root, "b.md"), "---\ntags:\n  - team\n---\n#team #Team/Pay");
}

#[test]
fn edits_after_non_ascii_text_use_utf16_ranges() {
    let v = make_vault(&[("cart.md", "# Café 😀\n## Totals\n"), ("b.md", "é😀é [[cart#Totals]] 😀 #pay/x ok")]);
    let root = v.path();
    apply(&rename_heading(&open(&v), "Totals", "Sums", "cart.md").unwrap(), root).unwrap();
    assert_eq!(read(root, "cart.md"), "# Café 😀\n## Sums\n");
    assert_eq!(read(root, "b.md"), "é😀é [[cart#Sums]] 😀 #pay/x ok");
    apply(&rename_tag(&open(&v), "pay", "fee").unwrap(), root).unwrap();
    assert_eq!(read(root, "b.md"), "é😀é [[cart#Sums]] 😀 #fee/x ok");
    apply(&rename_note(&open(&v), "cart.md", "basket").unwrap(), root).unwrap();
    assert_eq!(read(root, "b.md"), "é😀é [[basket#Sums]] 😀 #fee/x ok");
}
