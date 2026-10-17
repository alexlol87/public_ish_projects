#![allow(dead_code)]
use std::fs;
use std::path::Path;
use tempfile::TempDir;

/// A temp Vault holding `files` (paths are Vault-relative).
pub fn make_vault(files: &[(&str, &str)]) -> TempDir {
    let dir = tempfile::tempdir().unwrap();
    for (p, t) in files {
        write(dir.path(), p, t);
    }
    dir
}

pub fn write(root: &Path, path: &str, text: &str) {
    let file = root.join(path);
    fs::create_dir_all(file.parent().unwrap()).unwrap();
    fs::write(file, text).unwrap();
}

pub fn read(root: &Path, path: &str) -> String {
    fs::read_to_string(root.join(path)).unwrap()
}

pub fn try_read(root: &Path, path: &str) -> Option<String> {
    fs::read_to_string(root.join(path)).ok()
}

pub fn exists(root: &Path, path: &str) -> bool {
    root.join(path).exists()
}

/// UTF-16 offset of the first `needle` in `text`.
pub fn at16(text: &str, needle: &str) -> usize {
    constellation_core::text::len16(&text[..text.find(needle).unwrap()])
}
