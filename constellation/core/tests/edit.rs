mod common;
use common::*;
use constellation_core::edit::{apply, check};
use constellation_core::text::Range16;
use constellation_core::FileEdit;
use std::fs;
use std::os::unix::fs::PermissionsExt;

fn read_only(path: std::path::PathBuf) {
    fs::set_permissions(path, fs::Permissions::from_mode(0o444)).unwrap();
}

#[test]
fn a_read_only_target_refuses_the_whole_batch() {
    let v = make_vault(&[("a.md", "aaa"), ("b.md", "bbb")]);
    read_only(v.path().join("b.md"));
    let edits = [FileEdit::replace("a.md", Range16::new(0, 1), "X"), FileEdit::replace("b.md", Range16::new(0, 1), "Y")];
    assert!(check(&edits, v.path()).is_err());
    assert!(apply(&edits, v.path()).is_err());
    assert_eq!(fs::read_to_string(v.path().join("a.md")).unwrap(), "aaa");
}

#[test]
fn a_create_in_a_read_only_folder_is_refused_up_front() {
    let v = make_vault(&[("d/a.md", "aaa"), ("b.md", "bbb")]);
    fs::set_permissions(v.path().join("d"), fs::Permissions::from_mode(0o555)).unwrap();
    let edits = [FileEdit::replace("b.md", Range16::new(0, 1), "Y"), FileEdit::create("d/n.md", "")];
    let r = apply(&edits, v.path());
    fs::set_permissions(v.path().join("d"), fs::Permissions::from_mode(0o755)).unwrap();
    assert!(r.is_err());
    assert_eq!(fs::read_to_string(v.path().join("b.md")).unwrap(), "bbb");
}

#[test]
fn a_failing_write_rolls_back_the_files_already_written() {
    // Planning cannot see this failure: the temp name is taken by a folder.
    let v = make_vault(&[("a.md", "aaa"), ("b.md", "bbb")]);
    fs::create_dir(v.path().join(".b.md.tmp")).unwrap();
    let edits = [FileEdit::replace("a.md", Range16::new(0, 1), "X"), FileEdit::replace("b.md", Range16::new(0, 1), "Y")];
    assert!(apply(&edits, v.path()).is_err());
    assert_eq!(fs::read_to_string(v.path().join("a.md")).unwrap(), "aaa");
    assert_eq!(fs::read_to_string(v.path().join("b.md")).unwrap(), "bbb");
}

#[test]
fn many_edits_to_one_file_apply_and_undo_fast() {
    let n = 10_000;
    let text: String = (0..n).map(|i| format!("é[[old]] line {i}\n")).collect();
    let v = make_vault(&[("big.md", &text)]);
    let edits: Vec<_> = (0..n)
        .rev()
        .map(|i| {
            let at = text.lines().take(i).map(|l| l.chars().map(char::len_utf16).sum::<usize>() + 1).sum::<usize>() + 1;
            FileEdit::replace("big.md", Range16::new(at, 7), "[[new-name]]")
        })
        .collect();
    let t = std::time::Instant::now();
    let inverse = apply(&edits, v.path()).unwrap();
    assert!(fs::read_to_string(v.path().join("big.md")).unwrap().starts_with("é[[new-name]] line 0\n"));
    apply(&inverse, v.path()).unwrap();
    assert_eq!(fs::read_to_string(v.path().join("big.md")).unwrap(), text);
    assert!(t.elapsed().as_secs() < 5, "{:?}", t.elapsed());
}
