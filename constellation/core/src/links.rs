//! Wiki-link resolution, backlinks and `[[` completions.

use crate::edit::FileEdit;
use crate::parser::{ParsedNote, WikiLink};
use crate::text::strip_md;
use crate::vault::is_app_only;
use crate::{Error, Result};
use serde::Serialize;
use std::collections::{BTreeMap, HashMap};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum LinkResolution {
    Note {
        path: String,
    },
    /// Missing or ambiguous; `create_path` is where clicking the Link creates the Note.
    Broken {
        create_path: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Backlink {
    /// The Note containing the Link.
    pub path: String,
    pub link: WikiLink,
}

impl LinkResolution {
    pub fn note(path: &str) -> Self {
        Self::Note { path: path.into() }
    }

    pub fn is_broken(&self) -> bool {
        matches!(self, Self::Broken { .. })
    }
}

fn stem_lower(path: &str) -> String {
    strip_md(path.rsplit('/').next().unwrap_or("")).to_lowercase()
}

/// Resolves by Vault path first, else by a unique Note name (case-insensitive, `.md` optional).
#[derive(Debug, Clone, Default)]
pub struct PathIndex {
    by_path: HashMap<String, String>,
    by_name: HashMap<String, Vec<String>>,
}

impl PathIndex {
    pub fn new<S: AsRef<str>>(paths: &[S]) -> Self {
        let mut ix = Self::default();
        for p in paths.iter().map(AsRef::as_ref) {
            ix.by_path.entry(strip_md(p).to_lowercase()).or_insert_with(|| p.to_string());
            ix.by_name.entry(stem_lower(p)).or_default().push(p.to_string());
        }
        ix
    }

    pub fn resolve(&self, target: &str) -> LinkResolution {
        let t = strip_md(target);
        let key = t.to_lowercase();
        if let Some(p) = self.by_path.get(&key) {
            return LinkResolution::note(p);
        }
        match self.by_name.get(&key) {
            Some(named) if named.len() == 1 && !t.contains('/') => LinkResolution::note(&named[0]),
            _ => LinkResolution::Broken { create_path: format!("{t}.md") },
        }
    }
}

/// The edit that creates the missing Note for a broken Link (empty file, folders as needed); none if the Link resolves.
/// Refuses a target that is not a valid Vault path (see `clean_note_path`). Writes nothing: the caller applies the edits.
pub fn create_note_edits(paths: &PathIndex, target: &str) -> Result<Vec<FileEdit>> {
    match paths.resolve(target) {
        LinkResolution::Broken { create_path } => Ok(vec![FileEdit::create(&clean_note_path(&create_path)?, "")]),
        LinkResolution::Note { .. } => Ok(vec![]),
    }
}

/// A Vault-relative Note path from what a person or Link typed: trimmed, a leading `./` and doubled `/` dropped, `.md`
/// added unless it already ends in it. Refuses empty, trailing-slash, absolute, backslash, `.`, `..` and hidden segments,
/// and app-only places (checked on the final path, any case). So the result always stays inside the Vault.
pub fn clean_note_path(typed: &str) -> Result<String> {
    let t = typed.trim();
    let t = t.strip_prefix("./").unwrap_or(t);
    let bad = t.starts_with('/') || t.ends_with('/') || t.contains('\\') || t.split('/').any(|s| s == "." || s.starts_with('.'));
    let t = t.split('/').filter(|s| !s.is_empty()).collect::<Vec<_>>().join("/");
    if bad || t.is_empty() {
        return Err(Error(format!("Not a valid Note path: \"{}\"", typed.trim())));
    }
    let path = if t.to_lowercase().ends_with(".md") { t } else { format!("{t}.md") };
    if is_app_only(&path) {
        return Err(Error("That place is for the app's own files".into()));
    }
    Ok(path)
}

/// The edit that creates an empty Note at the exact Vault path a person typed (see `clean_note_path`); refuses existing Notes.
pub fn new_note_edits(paths: &PathIndex, typed: &str) -> Result<Vec<FileEdit>> {
    let path = clean_note_path(typed)?;
    if paths.by_path.contains_key(&strip_md(&path).to_lowercase()) {
        return Err(Error(format!("A Note already exists at {path}")));
    }
    Ok(vec![FileEdit::create(&path, "")])
}

/// Links in other Notes that resolve to `path`, in path then text order.
pub fn backlinks(parsed: &BTreeMap<String, ParsedNote>, paths: &PathIndex, path: &str) -> Vec<Backlink> {
    let target = LinkResolution::note(path);
    parsed
        .iter()
        .filter(|(p, _)| p.as_str() != path)
        .flat_map(|(p, n)| {
            n.links.iter().filter(|l| paths.resolve(&l.target) == target).map(|l| Backlink { path: p.clone(), link: l.clone() })
        })
        .collect()
}

/// Text to offer after `[[`: Note names, or `name#Heading` once the typed text contains `#`.
pub fn completions(parsed: &BTreeMap<String, ParsedNote>, paths: &PathIndex, typed: &str) -> Vec<String> {
    let lower = typed.to_lowercase();
    if let Some((target, prefix)) = typed.split_once('#') {
        let LinkResolution::Note { path } = paths.resolve(target) else { return vec![] };
        let prefix = prefix.to_lowercase();
        return parsed[&path]
            .headings
            .iter()
            .filter(|h| h.title.to_lowercase().starts_with(&prefix))
            .map(|h| format!("{target}#{}", h.title))
            .collect();
    }
    // A unique name is enough to link to a Note; an ambiguous name would resolve to nothing, so offer its full path.
    // Typed text matches the start of that label or anywhere in the path (`acme/cart` finds `acme-shop/cart-service/..`).
    let name = |p: &str| strip_md(p.rsplit('/').next().unwrap_or("")).to_string();
    let mut seen = std::collections::HashSet::new();
    parsed
        .keys()
        .filter_map(|p| {
            let n = name(p);
            let label = if paths.resolve(&n) == LinkResolution::note(p) { n } else { strip_md(p).to_string() };
            (label.to_lowercase().starts_with(&lower) || p.to_lowercase().contains(&lower)).then_some(label)
        })
        .filter(|l| seen.insert(l.clone()))
        .collect()
}

/// Links in `links` that are missing or ambiguous.
pub fn broken(paths: &PathIndex, links: Vec<WikiLink>) -> Vec<WikiLink> {
    links.into_iter().filter(|l| paths.resolve(&l.target).is_broken()).collect()
}
