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

#[test]
fn rename_and_move_refuse_paths_that_are_not_valid_notes() {
    let v = make_vault(&FILES);
    let ix = open(&v);
    for bad in ["../overview", "a/b", ".md", "", "a\\b", ".hid"] {
        assert!(rename_note(&ix, "acme/cart.md", bad).is_err(), "rename {bad:?}");
    }
    for bad in ["..", "../x", ".hid", "templates", "TEMPLATES/z", "a\\b"] {
        assert!(move_note_to_folder(&ix, "acme/cart.md", bad).is_err(), "move {bad:?}");
    }
}

#[test]
fn rename_tag_refuses_bad_names() {
    let v = make_vault(&[("a.md", "#team text")]);
    for bad in ["", "#", " ", "my tag", "x], [y", "a,b", "1", "a/", "#a b"] {
        assert!(rename_tag(&open(&v), "team", bad).is_err(), "{bad:?}");
    }
    assert!(rename_tag(&open(&v), "team", "#squad").is_ok(), "one leading # is fine");
}

#[test]
fn rename_tag_onto_an_existing_tag_merges_without_duplicates() {
    let v = make_vault(&[
        ("a.md", "---\ntags: [alpha, beta]\n---\n#alpha"),
        ("b.md", "---\ntags:\n  - alpha\n  - beta\n---\n"),
        ("c.md", "---\ntags: [beta, \"alpha\"]\n---\n"),
        ("d.md", "---\ntags: alpha, beta\n---\n"),
        ("e.md", "---\ntags: [alpha]\n---\n"),
    ]);
    let root = v.path();
    apply(&rename_tag(&open(&v), "alpha", "beta").unwrap(), root).unwrap();
    assert_eq!(read(root, "a.md"), "---\ntags: [beta]\n---\n#beta");
    assert_eq!(read(root, "b.md"), "---\ntags:\n  - beta\n---\n");
    assert_eq!(read(root, "c.md"), "---\ntags: [beta]\n---\n");
    assert_eq!(read(root, "d.md"), "---\ntags: beta\n---\n");
    assert_eq!(read(root, "e.md"), "---\ntags: [beta]\n---\n");
}

#[test]
fn rename_heading_refuses_bad_titles_and_duplicates() {
    let v = make_vault(&FILES);
    let ix = open(&v);
    for bad in ["", "  ", "a]] | x#y", "a|b", "a#b", "a[[b", "a]]"] {
        assert!(rename_heading(&ix, "Totals", bad, "acme/cart.md").is_err(), "{bad:?}");
    }
    assert!(rename_heading(&ix, "Totals", "cart", "acme/cart.md").is_err(), "title already in the Note");
    assert!(rename_heading(&ix, "Totals", "TOTALS", "acme/cart.md").is_ok(), "case change of itself is fine");
}

#[test]
fn rename_tag_follows_folded_spelling_and_updates_tags_md() {
    let v = make_vault(&[
        ("a.md", "#tag/uni and #tág/ünï/x and #straße/y"),
        ("tags.md", "# Tags\n\n- #tag/uni: unit\n- #other: o\n"),
    ]);
    let root = v.path();
    apply(&rename_tag(&open(&v), "tag/uni", "x").unwrap(), root).unwrap();
    assert_eq!(read(root, "a.md"), "#x and #x/x and #straße/y");
    assert_eq!(read(root, "tags.md"), "# Tags\n\n- #x: unit\n- #other: o\n");
    apply(&rename_tag(&open(&v), "strasse", "z").unwrap(), root).unwrap();
    assert_eq!(read(root, "a.md"), "#x and #x/x and #z/y");
}

#[test]
fn rename_heading_rewrites_same_note_anchor_links() {
    let v = make_vault(&[("t.md", "# T\n\n## Sec\n\nSee [[#Sec]] and [[#sec|al]] and [[t#Sec]].\n")]);
    let root = v.path();
    apply(&rename_heading(&open(&v), "Sec", "Section", "t.md").unwrap(), root).unwrap();
    assert_eq!(read(root, "t.md"), "# T\n\n## Section\n\nSee [[#Section]] and [[#Section|al]] and [[t#Section]].\n");
}

#[test]
fn rename_heading_skips_same_note_links_in_code() {
    let v = make_vault(&[("t.md", "# T\n\n## Sec\n\n[[#Sec]] `[[#Sec]]`\n\n```\n[[#Sec]]\n```\n")]);
    let root = v.path();
    apply(&rename_heading(&open(&v), "Sec", "Part", "t.md").unwrap(), root).unwrap();
    assert_eq!(read(root, "t.md"), "# T\n\n## Part\n\n[[#Part]] `[[#Sec]]`\n\n```\n[[#Sec]]\n```\n");
}

#[test]
fn rename_tag_merge_into_listed_tag_keeps_one_line_in_tags_md() {
    let v = make_vault(&[("a.md", "#road"), ("tags.md", "# Tags\n\n- #road: r\n- #payments: p\n")]);
    let root = v.path();
    apply(&rename_tag(&open(&v), "road", "payments").unwrap(), root).unwrap();
    assert_eq!(read(root, "tags.md"), "# Tags\n\n- #payments: p\n");
}
