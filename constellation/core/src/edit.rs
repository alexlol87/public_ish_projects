//! `FileEdit`: one change to one file. Commands (archiver, renames, link creation) return edits instead of writing, so the
//! app applies them as one undoable step and tests can inspect them.

use crate::text::{len16, replace16, slice16, Range16};
use crate::vault::write_atomic;
use crate::{Error, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Component, Path};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FileEdit {
    /// Vault-relative.
    pub path: String,
    /// UTF-16, in the file's current text.
    pub range: Range16,
    pub text: String,
    /// The file does not exist yet; applying creates it (`range` is {0,0}).
    #[serde(default)]
    pub creates_file: bool,
    /// Undo of a creation: applying deletes the file.
    #[serde(default)]
    pub removes_file: bool,
    /// On the undo of a creation: folders the creation made, deepest first; removed too when empty.
    #[serde(default)]
    pub made_dirs: Vec<String>,
    /// On the undo of a creation: the text the creation wrote; the file is only removed while it still holds exactly this.
    #[serde(default)]
    pub only_if: Option<String>,
}

impl FileEdit {
    pub fn replace(path: &str, range: Range16, text: &str) -> Self {
        Self { path: path.into(), range, text: text.into(), creates_file: false, removes_file: false, made_dirs: vec![], only_if: None }
    }

    pub fn create(path: &str, text: &str) -> Self {
        Self { creates_file: true, ..Self::replace(path, Range16::default(), text) }
    }

    pub fn remove(path: &str) -> Self {
        Self { removes_file: true, ..Self::replace(path, Range16::default(), "") }
    }
}

/// Applies edits in order (give edits to one file back to front) and returns the inverse edits; applying those
/// restores every file exactly. The app calls this once per user action and keeps the inverse for undo.
pub fn apply(edits: &[FileEdit], root: &Path) -> Result<Vec<FileEdit>> {
    check(edits, root)?;
    let mut inverse = vec![];
    for e in edits {
        let file = root.join(&e.path);
        if e.removes_file {
            let old = fs::read_to_string(&file)?;
            fs::remove_file(&file)?;
            for d in &e.made_dirs {
                let _ = fs::remove_dir(root.join(d)); // not empty any more: leave it
            }
            inverse.push(FileEdit::create(&e.path, &old));
            continue;
        }
        let made_dirs = if e.creates_file { missing_dirs(root, &e.path) } else { vec![] };
        let old = if e.creates_file { String::new() } else { fs::read_to_string(&file)? };
        let replaced = slice16(&old, e.range).ok_or_else(|| Error(format!("Edit range is outside {}", e.path)))?.to_string();
        let new = replace16(&old, e.range, &e.text).ok_or_else(|| Error(format!("Edit range is outside {}", e.path)))?;
        if let Err(err) = write_atomic(&file, &new) {
            for d in &made_dirs {
                let _ = fs::remove_dir(root.join(d)); // a failed create leaves no folders behind
            }
            return Err(err);
        }
        inverse.push(if e.creates_file {
            FileEdit { made_dirs, only_if: Some(new), ..FileEdit::remove(&e.path) }
        } else {
            FileEdit::replace(&e.path, Range16::new(e.range.location, len16(&e.text)), &replaced)
        });
    }
    inverse.reverse();
    Ok(inverse)
}

/// Refuses the whole batch, before anything is written, if a path leaves the Vault, a create would overwrite a file or a guarded removal would
/// lose text changed since (e.g. undoing a create or rename after the Note was edited).
pub fn check(edits: &[FileEdit], root: &Path) -> Result<()> {
    let mut removed = std::collections::HashSet::new();
    for e in edits {
        if Path::new(&e.path).components().any(|c| !matches!(c, Component::Normal(_))) {
            return Err(Error(format!("{} is outside the Vault", e.path)));
        }
        let file = root.join(&e.path);
        if e.removes_file {
            if let Some(t) = &e.only_if {
                if fs::read_to_string(&file).ok().as_ref() != Some(t) {
                    return Err(Error(format!("{} was edited after that action; not undoing it, so the edit is kept", e.path)));
                }
            }
            removed.insert(&e.path);
        } else if e.creates_file && file.exists() && !removed.contains(&e.path) {
            return Err(Error(format!("{} already exists", e.path)));
        }
    }
    Ok(())
}

/// Folders above `path` that do not exist yet, deepest first.
fn missing_dirs(root: &Path, path: &str) -> Vec<String> {
    let mut dirs: Vec<String> = Path::new(path).ancestors().skip(1).filter(|a| !a.as_os_str().is_empty()).map(|a| a.to_string_lossy().into_owned()).collect();
    dirs.retain(|d| !root.join(d).exists());
    dirs
}
