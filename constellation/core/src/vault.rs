//! The Vault seam: a folder of markdown Notes on disk. Paths are Vault-relative and `/`-separated.

use crate::text::{ci_cmp, is_md};
use crate::{agent_files, Error, Result};
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};

/// A folder or markdown Note inside a Vault. `relative_path` is from the Vault root; the root's is "".
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultNode {
    pub name: String,
    pub relative_path: String,
    pub is_folder: bool,
    pub children: Vec<VaultNode>,
    /// App-only files show in the tree but are excluded from search and the graph.
    pub app_only: bool,
}

const APP_ONLY_TOP: [&str; 5] = ["AGENTS.md", "repos.txt", "tags.md", "templates", ".constellation"];

/// True for the app's own files (top level only) and anything inside its folders.
pub fn is_app_only(relative_path: &str) -> bool {
    APP_ONLY_TOP.contains(&relative_path.split('/').find(|s| !s.is_empty()).unwrap_or(""))
}

/// Archive Notes live in `<project>/archive/` (ADR 0002); hidden in the graph by default, marked in search.
pub fn is_archive(relative_path: &str) -> bool {
    let mut c = relative_path.split('/').filter(|s| !s.is_empty());
    c.nth(1) == Some("archive")
}

fn join(prefix: &str, name: &str) -> String {
    if prefix.is_empty() {
        name.to_string()
    } else {
        format!("{prefix}/{name}")
    }
}

fn node(name: &str, path: &str, is_folder: bool, children: Vec<VaultNode>) -> VaultNode {
    VaultNode { name: name.into(), relative_path: path.into(), is_folder, children, app_only: is_app_only(path) }
}

fn sort(nodes: &mut [VaultNode]) {
    nodes.sort_by(|a, b| b.is_folder.cmp(&a.is_folder).then_with(|| ci_cmp(&a.name, &b.name)));
}

/// Returns the root folder node. Lists folders and `.md` files; hidden entries are skipped.
/// Folders come first, then Notes, each sorted by name.
pub fn load(root: &Path) -> Result<VaultNode> {
    load_folder(root, "")
}

fn name_of(dir: &Path) -> String {
    dir.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
}

fn load_folder(dir: &Path, path: &str) -> Result<VaultNode> {
    let mut kids = vec![];
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') && !(path.is_empty() && name == ".constellation") {
            continue;
        }
        let rel = join(path, &name);
        if entry.path().is_dir() {
            kids.push(load_folder(&entry.path(), &rel)?);
        } else if is_md(&name) || is_app_only(&rel) {
            kids.push(node(&name, &rel, false, vec![]));
        }
    }
    sort(&mut kids);
    Ok(node(&name_of(dir), path, true, kids))
}

impl VaultNode {
    /// All searchable Note paths (app-only files excluded), sorted.
    pub fn note_paths(&self) -> Vec<String> {
        fn walk(n: &VaultNode, out: &mut Vec<String>) {
            for c in &n.children {
                if c.is_folder {
                    walk(c, out);
                } else if !c.app_only && is_md(&c.relative_path) {
                    out.push(c.relative_path.clone());
                }
            }
        }
        let mut out = vec![];
        walk(self, &mut out);
        out.sort();
        out
    }

    /// Folder paths below this node that search should know (app-only folders excluded).
    pub fn folder_paths(&self) -> Vec<String> {
        let mut out = vec![];
        for c in self.children.iter().filter(|c| c.is_folder && !c.app_only) {
            out.push(c.relative_path.clone());
            out.extend(c.folder_paths());
        }
        out
    }

    /// Applies external file-system changes (create, modify, delete, move all arrive as touched paths) by re-reading
    /// each touched path's parent folder from disk. Vanished folders are dropped.
    // ponytail: re-lists whole parent folders, fine for notes-sized Vaults; switch to per-entry patches if one gets huge.
    pub fn refresh(&mut self, paths: &[String], root: &Path) -> Result<()> {
        for path in paths {
            let parts: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
            if let Some((_, parents)) = parts.split_last() {
                self.refresh_folder(parents, root)?;
            }
        }
        Ok(())
    }

    fn refresh_folder(&mut self, parts: &[&str], dir: &Path) -> Result<()> {
        let Some((name, rest)) = parts.split_first() else {
            self.children = load_folder(dir, &self.relative_path)?.children;
            return Ok(());
        };
        let (path, sub) = (join(&self.relative_path, name), dir.join(name));
        if !sub.is_dir() {
            self.children.retain(|c| c.relative_path != path);
        } else if let Some(c) = self.children.iter_mut().find(|c| c.is_folder && c.relative_path == path) {
            c.refresh_folder(rest, &sub)?;
        } else if !name.starts_with('.') || (self.relative_path.is_empty() && *name == ".constellation") {
            self.children.push(load_folder(&sub, &path)?);
            sort(&mut self.children);
        }
        Ok(())
    }
}

/// Writes the starter files into an empty (or missing) folder. Fails rather than touch existing files.
pub fn create(root: &Path) -> Result<()> {
    if fs::read_dir(root).is_ok_and(|mut d| d.next().is_some()) {
        return Err(Error(
            "That folder is not empty. Pick an empty folder for a new vault (the folder dialog can create one), or use Open vault.".into(),
        ));
    }
    for d in ["templates", "external", "clients", ".constellation"] {
        fs::create_dir_all(root.join(d))?;
    }
    for (name, text) in agent_files::TEMPLATES {
        fs::write(root.join(format!("templates/{name}.md")), text)?;
    }
    fs::write(root.join("README.md"), "# Vault\n\nWhat this vault covers.\n")?;
    fs::write(root.join("AGENTS.md"), agent_files::AGENTS_MD)?;
    fs::write(root.join("repos.txt"), "# One repository name per line.\n")?;
    fs::write(root.join("tags.md"), "# Tags\n\n- #example: what this tag means\n")?;
    Ok(())
}

/// The remembered Vault folder, or None if none was saved or it no longer exists (show the first-launch choice).
pub fn reopenable(saved_path: Option<&str>) -> Option<PathBuf> {
    saved_path.map(PathBuf::from).filter(|p| p.is_dir())
}

pub fn read_note(root: &Path, relative_path: &str) -> Result<String> {
    Ok(fs::read_to_string(root.join(relative_path))?)
}

/// Writes `text` to `path`, atomically (temp file in the same folder, then rename), so a crash never leaves half a file.
pub fn write_atomic(path: &Path, text: &str) -> Result<()> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    let tmp = path.with_file_name(format!(".{}.tmp", name_of(path)));
    fs::write(&tmp, text)?;
    fs::rename(&tmp, path).inspect_err(|_| drop(fs::remove_file(&tmp)))?;
    Ok(())
}

/// Overwrites a Note's file.
pub fn write_note(root: &Path, relative_path: &str, text: &str) -> Result<()> {
    write_atomic(&root.join(relative_path), text)
}

/// Resolves an image path from a Note: Note-relative first, then Vault-relative (a leading `/` means Vault-relative only).
/// None (show a placeholder) if missing or outside the Vault, symlinks included.
pub fn resolve_image(path: &str, note: &str, root: &Path) -> Option<PathBuf> {
    let root = root.canonicalize().ok()?;
    let note_dir = note.rsplit_once('/').map_or("", |(d, _)| d);
    let candidates = match path.strip_prefix('/') {
        Some(p) => vec![p.to_string()],
        None => vec![join(note_dir, path), path.to_string()],
    };
    candidates.iter().find_map(|c| root.join(c).canonicalize().ok().filter(|p| p.starts_with(&root) && p.is_file()))
}
