//! `FileEdit`: one change to one file. Commands (archiver, renames, link creation) return edits instead of writing, so the
//! app applies them as one undoable step and tests can inspect them.

use crate::text::{bytes_at, len16, Range16};
use crate::vault::write_atomic_as;
use crate::{Error, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::os::unix::fs::{symlink, PermissionsExt};
use std::path::Path;

/// The permission bits and symlink target of `old`, for the creation that moves it to `new` (a relative link keeps pointing
/// at the same file from the new folder).
pub fn mode_and_link(root: &Path, old: &str, new: &str) -> (Option<u32>, Option<String>) {
    let Ok(m) = fs::symlink_metadata(root.join(old)) else { return (None, None) };
    if !m.is_symlink() {
        return (Some(m.permissions().mode()), None);
    }
    let dir = |p: &str| p.rsplit_once('/').map_or("", |d| d.0).to_string();
    let to = fs::read_link(root.join(old)).ok();
    let link = to.map(|t| if t.is_relative() && dir(old) != dir(new) { root.join(dir(old)).join(t) } else { t });
    (None, link.map(|t| t.to_string_lossy().into_owned()))
}

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
    /// On a creation: the permission bits to give the new file (a move keeps them).
    #[serde(default)]
    pub mode: Option<u32>,
    /// On a creation: make the file a symlink to this target instead (a moved symlinked Note stays a link).
    #[serde(default)]
    pub link: Option<String>,
}

impl FileEdit {
    pub fn replace(path: &str, range: Range16, text: &str) -> Self {
        Self { path: path.into(), range, text: text.into(), creates_file: false, removes_file: false, made_dirs: vec![], only_if: None, expect: None, mode: None, link: None }
    }

    pub fn create(path: &str, text: &str) -> Self {
        Self { creates_file: true, ..Self::replace(path, Range16::default(), text) }
    }

    pub fn remove(path: &str) -> Self {
        Self { removes_file: true, ..Self::replace(path, Range16::default(), "") }
    }
}

/// Applies edits as one all-or-nothing batch and returns the inverse edits; applying those restores every file exactly.
/// The app calls this once per user action and keeps the inverse for undo. Everything is checked and computed in memory
/// first (consecutive edits to one file, back to front or front to back, cost one pass over the file); if a write still
/// fails, the files already written are put back and the error is returned.
pub fn apply(edits: &[FileEdit], root: &Path) -> Result<Vec<FileEdit>> {
    let Plan { mut inverse, files } = plan(edits, root)?;
    for (k, f) in files.iter().enumerate() {
        let done = match &f.new {
            Some(t) => create_or_write(root, f, t),
            None => fs::remove_file(root.join(&f.path)).map_err(Error::from).map(|_| {
                for d in &f.made_dirs {
                    let _ = fs::remove_dir(root.join(d)); // not empty any more: leave it
                }
            }),
        };
        if let Err(err) = done {
            for f in &files[..k] {
                match &f.old {
                    Some(t) => drop(write_atomic_as(&root.join(&f.path), t, &f.path)),
                    None => drop(fs::remove_file(root.join(&f.path))),
                }
            }
            for f in &files[..=k] {
                if f.old.is_none() {
                    for d in &f.made_dirs {
                        let _ = fs::remove_dir(root.join(d)); // a failed create leaves no folders behind
                    }
                }
            }
            return Err(err);
        }
    }
    inverse.reverse();
    Ok(inverse)
}

fn create_or_write(root: &Path, f: &File, text: &str) -> Result<()> {
    let path = root.join(&f.path);
    if f.old.is_none() {
        if let Some(to) = &f.link {
            fs::create_dir_all(path.parent().unwrap_or(root))?;
            symlink(to, &path)?;
        }
    }
    write_atomic_as(&path, text, &f.path)?;
    if let (None, Some(m)) = (&f.link, f.mode) {
        if f.old.is_none() {
            fs::set_permissions(&path, fs::Permissions::from_mode(m))?;
        }
    }
    Ok(())
}

/// Refuses the whole batch, before anything is written, if a path leaves the Vault, a target (or, for a create, its folder) is
/// read-only, a create would overwrite a file, a guarded removal would lose text changed since, or a replace's `expect`ed text
/// is no longer in its range (e.g. undoing after the Note was edited).
pub fn check(edits: &[FileEdit], root: &Path) -> Result<()> {
    plan(edits, root).map(drop)
}

struct File {
    path: String,
    old: Option<String>,
    new: Option<String>,
    made_dirs: Vec<String>,
    mode: Option<u32>,
    link: Option<String>,
}

struct Plan {
    inverse: Vec<FileEdit>,
    /// Files whose text changes, in order of first touch.
    files: Vec<File>,
}

/// The file's text, or None if it does not exist. Any other read error (e.g. not UTF-8) fails the action: that file must not be overwritten.
fn read_existing(root: &Path, path: &str) -> Result<Option<String>> {
    match fs::read_to_string(root.join(path)) {
        Ok(t) => Ok(Some(t)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) if e.kind() == std::io::ErrorKind::InvalidData => Err(Error(format!("{path} exists but is not UTF-8 text; nothing was changed"))),
        Err(e) => Err(Error(format!("{path} can't be read ({e}); nothing was changed"))),
    }
}

fn plan(edits: &[FileEdit], root: &Path) -> Result<Plan> {
    use std::collections::HashMap;
    let mut cur: HashMap<&str, usize> = HashMap::new(); // path -> index in files
    let mut files: Vec<File> = vec![];
    let mut inverse = vec![];
    let plain = |e: &FileEdit| !e.creates_file && !e.removes_file;
    let mut i = 0;
    while i < edits.len() {
        let e = &edits[i];
        crate::vault::safe_path(root, &e.path)?;
        let at = match cur.get(e.path.as_str()) {
            Some(&at) => at,
            None => {
                let old = read_existing(root, &e.path)?;
                files.push(File { path: e.path.clone(), new: old.clone(), old, made_dirs: vec![], mode: None, link: None });
                cur.insert(&e.path, files.len() - 1);
                files.len() - 1
            }
        };
        let now = files[at].new.clone();
        let mut next = i + 1;
        if e.removes_file {
            if e.only_if.is_some() && now != e.only_if {
                return Err(Error(format!("{} was {} after that action", e.path, if now.is_none() { "deleted" } else { "edited" })));
            }
            let Some(old) = now else { return Err(Error(format!("{} does not exist", e.path))) };
            writable(root, &e.path, false)?;
            files[at].made_dirs = e.made_dirs.clone();
            files[at].new = None;
            let (mode, link) = mode_and_link(root, &e.path, &e.path);
            inverse.push(FileEdit { mode, link, ..FileEdit::create(&e.path, &old) });
        } else if e.creates_file {
            if now.is_some() {
                return Err(Error(format!("{} already exists", e.path)));
            }
            writable(root, &e.path, false)?;
            let made_dirs = missing_dirs(root, &e.path);
            files[at].made_dirs = made_dirs.clone();
            files[at].new = Some(e.text.clone());
            (files[at].mode, files[at].link) = (e.mode, e.link.clone());
            inverse.push(FileEdit { made_dirs, only_if: Some(e.text.clone()), ..FileEdit::remove(&e.path) });
        } else {
            let Some(old) = now else { return Err(Error(format!("{} was deleted after that action", e.path))) };
            writable(root, &e.path, true)?;
            // The run of consecutive edits to this file that do not overlap and go back to front (or front to back).
            let mut dir = 0; // 1 back to front, 2 front to back
            while next < edits.len() && plain(&edits[next]) && edits[next].path == e.path {
                let (a, b) = (&edits[next - 1], &edits[next]);
                let back = b.range.end() <= a.range.location;
                let fwd = b.range.location >= a.range.location + len16(&a.text);
                match dir {
                    0 if back => dir = 1,
                    0 if fwd => dir = 2,
                    1 if back => {}
                    2 if fwd => {}
                    _ => break,
                }
                next += 1;
            }
            let run = &edits[i..next];
            // Each edit's range in the text before the run, ascending.
            let mut shift = 0isize;
            let mut items: Vec<(usize, Range16)> = run
                .iter()
                .enumerate()
                .map(|(n, r)| {
                    let orig = Range16::new((r.range.location as isize - if dir == 2 { shift } else { 0 }) as usize, r.range.length);
                    shift += len16(&r.text) as isize - r.range.length as isize;
                    (n, orig)
                })
                .collect();
            if dir == 1 {
                items.reverse();
            }
            let offs: Vec<usize> = items.iter().flat_map(|(_, r)| [r.location, r.end()]).collect();
            let bytes = bytes_at(&old, &offs).ok_or_else(|| Error(format!("Edit range is outside {}", e.path)))?;
            let mut new = String::with_capacity(old.len());
            let mut from = 0;
            let mut inv: Vec<Option<FileEdit>> = vec![None; run.len()];
            for (k, &(n, _)) in items.iter().enumerate() {
                let r = &run[n];
                let (a, b) = (bytes[2 * k], bytes[2 * k + 1]);
                let replaced = &old[a..b];
                if r.expect.as_deref().is_some_and(|want| want != replaced) {
                    return Err(Error(format!("{} was edited after that action", e.path)));
                }
                new.push_str(&old[from..a]);
                new.push_str(&r.text);
                from = b;
                inv[n] = Some(FileEdit { expect: Some(r.text.clone()), ..FileEdit::replace(&e.path, Range16::new(r.range.location, len16(&r.text)), replaced) });
            }
            new.push_str(&old[from..]);
            files[at].new = Some(new);
            // Inverses in the order of the edits.
            inverse.extend(inv.into_iter().flatten());
        }
        i = next;
    }
    files.retain(|f| f.old != f.new);
    Ok(Plan { inverse, files })
}

/// Refuses early what a write would fail on: a read-only file (when it exists) or a read-only folder holding it.
fn writable(root: &Path, path: &str, exists: bool) -> Result<()> {
    let file = root.join(path);
    if exists && fs::metadata(&file).is_ok_and(|m| m.permissions().readonly()) {
        return Err(Error(format!("{path} is read-only; nothing was changed")));
    }
    if let Some(dir) = file.ancestors().skip(1).find(|d| d.exists()) {
        if fs::metadata(dir).is_ok_and(|m| m.permissions().readonly()) {
            return Err(Error(format!("{}: folder is read-only; nothing was changed", dir.strip_prefix(root).unwrap_or(dir).display())));
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
