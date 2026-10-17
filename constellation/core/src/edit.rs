//! `FileEdit`: one change to one file. Commands (archiver, renames, link creation) return edits instead of writing, so the
//! app applies them as one undoable step and tests can inspect them.

use crate::text::{len16, replace16, slice16, Range16};
use crate::vault::write_atomic;
use crate::{Error, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

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
}

impl FileEdit {
    pub fn replace(path: &str, range: Range16, text: &str) -> Self {
        Self { path: path.into(), range, text: text.into(), creates_file: false, removes_file: false }
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
    let mut inverse = vec![];
    for e in edits {
        let file = root.join(&e.path);
        if e.removes_file {
            let old = fs::read_to_string(&file)?;
            fs::remove_file(&file)?;
            inverse.push(FileEdit::create(&e.path, &old));
            continue;
        }
        let old = if e.creates_file { String::new() } else { fs::read_to_string(&file)? };
        let replaced = slice16(&old, e.range).ok_or_else(|| Error(format!("Edit range is outside {}", e.path)))?.to_string();
        let new = replace16(&old, e.range, &e.text).ok_or_else(|| Error(format!("Edit range is outside {}", e.path)))?;
        write_atomic(&file, &new)?;
        inverse.push(if e.creates_file {
            FileEdit::remove(&e.path)
        } else {
            FileEdit::replace(&e.path, Range16::new(e.range.location, len16(&e.text)), &replaced)
        });
    }
    inverse.reverse();
    Ok(inverse)
}
