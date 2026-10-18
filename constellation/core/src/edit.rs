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
    /// On the undo of a creation: folders the creation made, deepest first; removed too when empty.
    #[serde(default)]
    pub made_dirs: Vec<String>,
    /// On the undo of a creation: the text the creation wrote; the file is only removed while it still holds exactly this.
    #[serde(default)]
    pub only_if: Option<String>,
    /// On an inverse replace: the text `range` must still hold; otherwise the file changed since and the batch is refused.
    #[serde(default)]
    pub expect: Option<String>,
}

impl FileEdit {
    pub fn replace(path: &str, range: Range16, text: &str) -> Self {
        Self { path: path.into(), range, text: text.into(), creates_file: false, removes_file: false, made_dirs: vec![], only_if: None, expect: None }
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
            FileEdit { expect: Some(e.text.clone()), ..FileEdit::replace(&e.path, Range16::new(e.range.location, len16(&e.text)), &replaced) }
        });
    }
    inverse.reverse();
    Ok(inverse)
}

/// Refuses the whole batch, before anything is written, if a path leaves the Vault, a create would overwrite a file, a guarded removal would
/// lose text changed since, or a replace's `expect`ed text is no longer in its range (e.g. undoing after the Note was
/// edited). Replays the batch in memory so each edit is checked against the text the earlier ones leave.
pub fn check(edits: &[FileEdit], root: &Path) -> Result<()> {
    let mut texts: std::collections::HashMap<&str, Option<String>> = Default::default(); // None: removed in this batch
    let current = |texts: &std::collections::HashMap<&str, Option<String>>, p: &str| match texts.get(p) {
        Some(t) => t.clone(),
        None => fs::read_to_string(root.join(p)).ok(),
    };
    for e in edits {
        crate::vault::safe_path(root, &e.path)?;
        let now = current(&texts, &e.path);
        if e.removes_file {
            if e.only_if.is_some() && now != e.only_if {
                return Err(Error(format!("{} was {} after that action", e.path, if now.is_none() { "deleted" } else { "edited" })));
            }
            texts.insert(&e.path, None);
        } else if e.creates_file {
            if now.is_some() {
                return Err(Error(format!("{} already exists", e.path)));
            }
            texts.insert(&e.path, Some(e.text.clone()));
        } else if let Some(want) = &e.expect {
            let Some(old) = now else { return Err(Error(format!("{} was deleted after that action", e.path))) };
            if slice16(&old, e.range) != Some(want.as_str()) {
                return Err(Error(format!("{} was edited after that action", e.path)));
            }
            texts.insert(&e.path, replace16(&old, e.range, &e.text));
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
