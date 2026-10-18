//! QA round 4, file safety: unreadable Notes, paths outside the Vault, permissions and links on moves, messages.
mod common;
use common::*;
use constellation_core::edit::apply;
use constellation_core::links::clean_note_path;
use constellation_core::renames::{move_note_to_folder, rename_note};
use constellation_core::{FileEdit, GraphFilter, LinkResolution, VaultIndex};
use std::fs;
use std::os::unix::fs::{symlink, PermissionsExt};

const LATIN1: &[u8] = b"# Caf\xe9\n\nPrecious\n";

fn with_latin1() -> tempfile::TempDir {
    let v = make_vault(&[("a.md", "# A\n\n[[latin]]\n")]);
    fs::write(v.path().join("latin.md"), LATIN1).unwrap();
    v
}

#[test]
fn a_create_over_a_non_utf8_note_fails_and_keeps_it() {
    let v = with_latin1();
    assert!(apply(&[FileEdit::create("latin.md", "")], v.path()).is_err());
    assert_eq!(fs::read(v.path().join("latin.md")).unwrap(), LATIN1);
}

#[test]
fn the_index_knows_a_non_utf8_note_exists() {
    let v = with_latin1();
    let ix = VaultIndex::open(v.path()).unwrap();
    assert_eq!(ix.resolve("latin"), LinkResolution::note("latin.md"));
    assert!(ix.new_note_edits("latin").is_err());
    assert!(ix.create_note_edits("latin").unwrap().is_empty());
}

#[test]
fn app_files_are_not_written_through_a_symlinked_dot_constellation() {
    let v = make_vault(&[("a.md", "# A\n")]);
    let out = tempfile::tempdir().unwrap();
    symlink(out.path(), v.path().join(".constellation")).unwrap();
    assert!(GraphFilter::default().save(v.path()).is_err());
    assert!(fs::read_dir(out.path()).unwrap().next().is_none());
}

#[test]
fn rename_heading_and_tick_do_not_read_outside_the_vault() {
    let out = tempfile::tempdir().unwrap();
    fs::write(out.path().join("s.md"), "# S\n\n## Top\n").unwrap();
    let v = make_vault(&[("a.md", "# A\n")]);
    symlink(out.path(), v.path().join("link")).unwrap();
    let ix = VaultIndex::open(v.path()).unwrap();
    let e = constellation_core::renames::rename_heading(&ix, "Top", "B", "link/s.md").unwrap_err();
    assert!(e.0.contains("outside"), "{e}");
}

#[test]
fn a_move_keeps_permissions_and_undo_restores_them() {
    let v = make_vault(&[("a.md", "# A\n"), ("d/x.md", "x")]);
    fs::set_permissions(v.path().join("a.md"), fs::Permissions::from_mode(0o600)).unwrap();
    let ix = VaultIndex::open(v.path()).unwrap();
    let inv = apply(&rename_note(&ix, "a.md", "b").unwrap(), v.path()).unwrap();
    let mode = |p: &str| fs::metadata(v.path().join(p)).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode("b.md"), 0o600);
    apply(&inv, v.path()).unwrap();
    assert_eq!(mode("a.md"), 0o600);
}

#[test]
fn moving_a_symlinked_note_moves_the_link() {
    let v = make_vault(&[("real/r.md", "# R\n"), ("d/x.md", "x")]);
    symlink("../real/r.md", v.path().join("d/alias.md")).unwrap();
    let ix = VaultIndex::open(v.path()).unwrap();
    let inv = apply(&move_note_to_folder(&ix, "d/alias.md", "e").unwrap(), v.path()).unwrap();
    let new = v.path().join("e/alias.md");
    assert!(fs::symlink_metadata(&new).unwrap().is_symlink());
    assert_eq!(fs::read_to_string(&new).unwrap(), "# R\n");
    assert!(!v.path().join("d/alias.md").exists());
    apply(&inv, v.path()).unwrap();
    assert!(fs::symlink_metadata(v.path().join("d/alias.md")).unwrap().is_symlink());
    assert!(!v.path().join("e/alias.md").exists());
    assert_eq!(read(v.path(), "real/r.md"), "# R\n");
}

#[test]
fn names_with_control_characters_are_refused() {
    for bad in ["a\nb", "a\tb", "a\u{7}b"] {
        assert!(clean_note_path(bad).is_err(), "{bad:?}");
    }
}

#[test]
fn a_rename_after_a_linker_vanished_names_the_missing_note() {
    let v = make_vault(&[("t.md", "# T\n"), ("l.md", "[[t]]\n")]);
    let ix = VaultIndex::open(v.path()).unwrap();
    fs::remove_file(v.path().join("l.md")).unwrap();
    let e = rename_note(&ix, "t.md", "u").unwrap_err();
    assert!(e.0.contains("l.md") && e.0.contains("nothing was changed") && !e.0.contains("os error"), "{e}");
}

#[test]
fn a_write_failing_through_a_symlink_names_the_note() {
    let v = make_vault(&[("a.md", "abc")]);
    fs::create_dir(v.path().join("lock")).unwrap();
    fs::write(v.path().join("lock/real.md"), "abc").unwrap();
    symlink("lock/real.md", v.path().join("link.md")).unwrap();
    fs::set_permissions(v.path().join("lock"), fs::Permissions::from_mode(0o555)).unwrap();
    let r = apply(&[FileEdit::replace("link.md", constellation_core::Range16::new(0, 1), "X")], v.path());
    fs::set_permissions(v.path().join("lock"), fs::Permissions::from_mode(0o755)).unwrap();
    let e = r.unwrap_err();
    assert!(e.0.contains("link.md") && !e.0.contains("real.md"), "{e}");
}
