mod common;
use common::*;
use constellation_core::tags::Sort;
use constellation_core::VaultIndex;

fn tag_names(n: &[constellation_core::tags::Node]) -> Vec<&str> {
    n.iter().map(|n| n.tag.as_str()).collect()
}

#[test]
fn counts_fold_case_and_roll_up_to_parents() {
    let v = make_vault(&[
        ("a.md", "#Team/Payments and #team/payments again, #team/infra"),
        ("sub/b.md", "---\ntags: [TEAM]\n---\nx"),
        ("c.md", "#other"),
        ("tags.md", "#ignored"),
    ]);
    let ix = VaultIndex::open(v.path()).unwrap();
    let tree = ix.tag_tree(Sort::Name);
    assert_eq!(tag_names(&tree), ["other", "team"]);
    let team = &tree[1];
    assert_eq!(team.count, 2); // a.md and b.md, each once
    assert_eq!(tag_names(&team.children), ["team/infra", "team/payments"]);
    assert_eq!(team.children.iter().map(|c| c.count).collect::<Vec<_>>(), [1, 1]);
    assert_eq!(team.children[0].name, "infra");
    assert_eq!(tag_names(&ix.tag_tree(Sort::Count)), ["team", "other"]);
}

#[test]
fn notes_for_tag_include_children_and_the_line() {
    let v = make_vault(&[("a.md", "intro\nfix the bug #team/payments today\n"), ("b.md", "#team")]);
    let ix = VaultIndex::open(v.path()).unwrap();
    let hits = ix.tag_hits("TEAM");
    assert_eq!(hits.iter().map(|h| h.path.as_str()).collect::<Vec<_>>(), ["a.md", "b.md"]);
    assert_eq!(hits[0].line, "fix the bug #team/payments today");
    assert_eq!(hits[0].offset, 6 + 12);
    assert_eq!(ix.tag_hits("team/payments").len(), 1);
}

/// A fully typed Tag must not be offered back: accepting it re-inserts the text, which re-opens completion forever.
#[test]
fn completions_never_offer_exactly_what_is_typed() {
    let v = make_vault(&[("a.md", "#acme #team/payments")]);
    let ix = VaultIndex::open(v.path()).unwrap();
    assert!(ix.tag_completions("acme").is_empty());
    assert!(ix.tag_completions("ACME").is_empty());
    assert_eq!(ix.tag_completions("team"), ["team/payments"]);
}

#[test]
fn completions_and_update() {
    let v = make_vault(&[("a.md", "#team/payments #tax")]);
    let mut ix = VaultIndex::open(v.path()).unwrap();
    assert_eq!(ix.tag_completions("ta"), ["tax"]);
    assert_eq!(ix.tag_completions("TEAM"), ["team/payments"]);
    write(v.path(), "a.md", "#taxes");
    ix.ingest(&["a.md".into()]).unwrap();
    assert_eq!(ix.tag_completions("ta"), ["taxes"]);
}

#[test]
fn hit_offsets_are_utf16() {
    let v = make_vault(&[("a.md", "😀é #tag")]);
    assert_eq!(VaultIndex::open(v.path()).unwrap().tag_hits("tag")[0].offset, 4);
}

#[test]
fn tag_search_folds_diacritics() {
    let v = make_vault(&[("a.md", "#tág/ünï here"), ("tags.md", "- #Only-Listed: x\n")]);
    let ix = VaultIndex::open(v.path()).unwrap();
    assert_eq!(ix.tag_hits("tag/uni").len(), 1);
    assert_eq!(ix.tag_hits("tág").len(), 1);
    assert_eq!(ix.tag_completions("only"), ["only-listed"]);
    assert_eq!(ix.tag_completions("tag"), ["tág/ünï"].map(String::from));
}
