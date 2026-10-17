//! Wiki-link resolution, backlinks and `[[` completions.

use crate::edit::FileEdit;
use crate::parser::{ParsedNote, WikiLink};
use crate::text::strip_md;
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
/// Writes nothing: the caller applies the edits.
pub fn create_note_edits(paths: &PathIndex, target: &str) -> Vec<FileEdit> {
    match paths.resolve(target) {
        LinkResolution::Broken { create_path } => vec![FileEdit::create(&create_path, "")],
        LinkResolution::Note { .. } => vec![],
    }
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
    parsed
        .keys()
        .map(|p| strip_md(p.rsplit('/').next().unwrap_or("")).to_string())
        .filter(|n| n.to_lowercase().starts_with(&lower))
        .collect()
}

/// Links in `links` that are missing or ambiguous.
pub fn broken(paths: &PathIndex, links: Vec<WikiLink>) -> Vec<WikiLink> {
    links.into_iter().filter(|l| paths.resolve(&l.target).is_broken()).collect()
}
