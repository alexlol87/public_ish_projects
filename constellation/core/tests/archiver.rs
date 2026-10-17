mod common;
use common::*;
use constellation_core::archiver::tick;
use constellation_core::edit::apply;
use constellation_core::{agent_files, FileEdit, Range16, VaultIndex};

fn day() -> chrono::NaiveDate {
    chrono::NaiveDate::from_ymd_opt(2026, 10, 17).unwrap()
}

const BUGS: &str =
    "# Bugs\n- [ ] Order total ignores discounts → [[endpoints#POST /orders]]\n  Discounts are applied after tax.\n- [ ] Other\n";
const ORDERS: &str = "shop/orders-service/endpoints.md";

fn tick_at(root: &std::path::Path, path: &str, offset: usize) -> Vec<FileEdit> {
    let text = read(root, path);
    tick(&VaultIndex::open(root).unwrap(), offset, &text, path, day()).unwrap()
}

#[test]
fn ticking_a_bug_moves_it_to_a_new_archive_note() {
    let v = make_vault(&[("shop/orders-service/bugs.md", BUGS), (ORDERS, "# POST /orders")]);
    let root = v.path();
    apply(&tick_at(root, "shop/orders-service/bugs.md", 10), root).unwrap();
    assert_eq!(read(root, "shop/orders-service/bugs.md"), "# Bugs\n- [ ] Other\n");
    assert_eq!(
        read(root, "shop/archive/fixed-bugs.md"),
        "---\ntype: archive\n---\n# Fixed bugs\n\n### Order total ignores discounts\n- closed: 2026-10-17\n- source: [[shop/orders-service/endpoints#POST /orders]]\n- what: Discounts are applied after tax.\n- fix: unknown\n"
    );
}

#[test]
fn item_without_link_uses_the_repo_readme_and_todos_go_to_done_todos() {
    let v = make_vault(&[("shop/orders-service/todo.md", "- [ ] Split the handler\n"), ("shop/archive/done-todos.md", "# Done todos\n")]);
    let root = v.path();
    apply(&tick_at(root, "shop/orders-service/todo.md", 3), root).unwrap();
    assert_eq!(read(root, "shop/orders-service/todo.md"), "");
    assert_eq!(
        read(root, "shop/archive/done-todos.md"),
        "# Done todos\n\n### Split the handler\n- closed: 2026-10-17\n- source: [[shop/orders-service/README]]\n- what: Split the handler\n- fix: unknown\n"
    );
}

#[test]
fn inverse_edits_restore_everything_exactly() {
    let v = make_vault(&[("shop/orders-service/bugs.md", BUGS), (ORDERS, "x")]);
    let root = v.path();
    let inverse = apply(&tick_at(root, "shop/orders-service/bugs.md", 10), root).unwrap();
    apply(&inverse, root).unwrap();
    assert_eq!(read(root, "shop/orders-service/bugs.md"), BUGS);
    assert!(try_read(root, "shop/archive/fixed-bugs.md").is_none());
}

#[test]
fn other_notes_and_checked_items_just_toggle() {
    let v = make_vault(&[("notes.md", "- [ ] a\n- [x] b\n"), ("shop/orders-service/bugs.md", "- [x] old\n")]);
    let root = v.path();
    apply(&tick_at(root, "notes.md", 2), root).unwrap();
    assert_eq!(read(root, "notes.md"), "- [x] a\n- [x] b\n");
    apply(&tick_at(root, "notes.md", 10), root).unwrap();
    assert_eq!(read(root, "notes.md"), "- [x] a\n- [ ] b\n");
    apply(&tick_at(root, "shop/orders-service/bugs.md", 2), root).unwrap();
    assert_eq!(read(root, "shop/orders-service/bugs.md"), "- [ ] old\n");
    assert!(try_read(root, "shop/archive/fixed-bugs.md").is_none());
}

#[test]
fn offset_off_a_task_line_gives_no_edits() {
    let v = make_vault(&[("notes.md", "plain\n- [ ] a\n")]);
    assert!(tick_at(v.path(), "notes.md", 2).is_empty());
    assert!(tick_at(v.path(), "notes.md", 999).is_empty());
}

#[test]
fn offsets_are_utf16_after_emoji_and_accents() {
    let text = "# Bugs ééé 😀\n- [ ] Crash on 😀 input → [[endpoints#POST /orders]]\n  Détail ünï.\n- [ ] Other\n";
    let v = make_vault(&[("shop/orders-service/bugs.md", text), (ORDERS, "x")]);
    let root = v.path();
    // Any offset on the task line: right after the emoji in the title.
    let offset = text.encode_utf16().position(|u| u == b'C' as u16).unwrap() + 11;
    let edits = tick_at(root, "shop/orders-service/bugs.md", offset);
    assert_eq!(edits[0].range, Range16::new(14, 67));
    let inverse = apply(&edits, root).unwrap();
    assert_eq!(read(root, "shop/orders-service/bugs.md"), "# Bugs ééé 😀\n- [ ] Other\n");
    let archived = read(root, "shop/archive/fixed-bugs.md");
    assert!(archived.contains("### Crash on 😀 input\n"));
    assert!(archived.contains("- what: Détail ünï.\n"));
    apply(&inverse, root).unwrap();
    assert_eq!(read(root, "shop/orders-service/bugs.md"), text);

    // Toggle: the box range counts the emoji as two units.
    let t = "😀 - [ ] x\n";
    let v = make_vault(&[("n.md", t)]);
    assert!(tick_at(v.path(), "n.md", 0).is_empty(), "the line does not start with a task");
    let t = "😀\n- [ ] x 😀\n- [ ] y\n";
    write(v.path(), "n.md", t);
    let e = tick_at(v.path(), "n.md", 9);
    assert_eq!(e, [FileEdit::replace("n.md", Range16::new(6, 1), "x")]);
}

#[test]
fn archive_format_in_agents_md_round_trips_through_the_archiver() {
    // The example entry in AGENTS.md must match what the app writes.
    let v = make_vault(&[
        ("shop/orders/bugs.md", "# Bugs\n- [ ] Total ignores discounts → [[endpoints#POST /orders]]\n  Discounts are applied after tax.\n"),
        ("shop/orders/endpoints.md", "## POST /orders\n"),
    ]);
    let root = v.path();
    apply(&tick_at(root, "shop/orders/bugs.md", 10), root).unwrap();
    let archived = read(root, "shop/archive/fixed-bugs.md");
    let entry = format!("### {}", archived.split("\n### ").nth(1).unwrap());
    let example = agent_files::AGENTS_MD.split("```markdown\n").find(|s| s.starts_with("### Total")).unwrap().split("```").next().unwrap();
    let norm = |t: &str| -> Vec<String> {
        t.lines()
            .filter(|l| !l.starts_with("- fix:"))
            .map(|l| if l.starts_with("- closed:") { "- closed: DATE".into() } else { l.to_string() })
            .collect()
    };
    assert_eq!(norm(example), norm(&entry));
    assert!(example.contains("- fix: "));
}
