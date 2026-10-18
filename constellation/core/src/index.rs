//! `VaultIndex`: an open Vault with its folder tree plus search, Tag and parsed-Note indexes. Build once, then report
//! changed paths to `ingest` (create, edit, delete and move all arrive as touched Vault-relative paths); only those are
//! re-read. Everything else answers from memory. The app holds one of these.

use crate::graph::{self, EndpointRelations, GraphFilter, VaultGraph};
use crate::links::{self, Backlink, LinkResolution, PathIndex};
use crate::parser::{self, ParsedNote, WikiLink};
use crate::search::{Results, SearchIndex};
use crate::staleness::{self, Staleness};
use crate::tags::{self, TagIndex};
use crate::vault::{self, VaultNode};
use crate::{FileEdit, Result};
use chrono::NaiveDate;
use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};

pub struct VaultIndex {
    root: PathBuf,
    tree: VaultNode,
    search: SearchIndex,
    tags: TagIndex,
    parsed: BTreeMap<String, ParsedNote>,
    paths: PathIndex,
}

impl VaultIndex {
    pub fn open(root: impl Into<PathBuf>) -> Result<Self> {
        let root = root.into();
        let tree = vault::load(&root)?;
        let mut ix = Self {
            root,
            tree,
            search: SearchIndex::default(),
            tags: TagIndex::default(),
            parsed: BTreeMap::new(),
            paths: PathIndex::default(),
        };
        for p in ix.tree.note_paths() {
            ix.load_note(&p);
        }
        ix.search.set_folders(ix.tree.folder_paths());
        ix.paths = PathIndex::new(&ix.tree.note_paths());
        Ok(ix)
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn tree(&self) -> &VaultNode {
        &self.tree
    }

    /// Searchable Note paths, sorted.
    pub fn note_paths(&self) -> Vec<String> {
        self.parsed.keys().cloned().collect()
    }

    pub fn parsed(&self) -> &BTreeMap<String, ParsedNote> {
        &self.parsed
    }

    /// An unreadable (e.g. non-UTF-8) Note is left out of the content indexes, but its path still resolves (`PathIndex`).
    fn load_note(&mut self, path: &str) {
        let Ok(text) = vault::read_note(&self.root, path) else { return };
        let note = parser::parse(&text);
        self.search.set(path, &text, &note.tags);
        self.tags.set(path, &text, &note.tags);
        self.parsed.insert(path.to_string(), note);
    }

    /// Re-reads the touched paths (and Notes inside touched folders); drops what no longer exists.
    pub fn ingest(&mut self, touched: &[String]) -> Result<()> {
        self.tree.refresh(touched, &self.root)?;
        let alive = self.tree.note_paths();
        let alive_set: HashSet<&str> = alive.iter().map(String::as_str).collect();
        self.parsed.retain(|p, _| alive_set.contains(p.as_str()));
        self.search.retain(|p| alive_set.contains(p));
        self.tags.retain(|p| alive_set.contains(p));
        for t in touched {
            let t = t.trim_matches('/');
            if alive_set.contains(t) {
                self.load_note(t);
            } else if !crate::text::is_md(t) {
                // A touched folder (created or moved in) brings its Notes along.
                let prefix = format!("{t}/");
                for p in alive.iter().filter(|p| p.starts_with(&prefix)) {
                    self.load_note(p);
                }
            }
        }
        self.search.set_folders(self.tree.folder_paths());
        self.paths = PathIndex::new(&alive);
        Ok(())
    }

    pub fn search(&self, query: &str) -> Results {
        self.search.search(query)
    }

    pub fn tag_tree(&self, sort: tags::Sort) -> Vec<tags::Node> {
        self.tags.tree(sort)
    }

    pub fn tag_hits(&self, tag: &str) -> Vec<tags::Hit> {
        self.tags.notes_for(tag)
    }

    pub fn tag_completions(&self, prefix: &str) -> Vec<String> {
        let listed = vault::read_note(&self.root, "tags.md").unwrap_or_default();
        let extra: Vec<String> = parser::parse(&listed).tags.iter().map(|t| t.name.to_lowercase()).collect();
        self.tags.completions(prefix, &extra)
    }

    /// The graph for `filter`, optionally local to `around`; built from the parsed Notes in memory.
    pub fn graph(&self, filter: &GraphFilter, around: Option<&str>) -> VaultGraph {
        graph::build(&self.tree, &self.parsed, &self.paths, filter.include_archive).filtered(filter, around)
    }

    pub fn backlinks(&self, path: &str) -> Vec<Backlink> {
        links::backlinks(&self.parsed, &self.paths, path)
    }

    /// Text to offer after `[[` (Note names, or `name#Heading` once the typed text contains `#`).
    pub fn completions(&self, typed: &str) -> Vec<String> {
        links::completions(&self.parsed, &self.paths, typed)
    }

    /// Resolves by Vault path first, else by a unique Note name (case-insensitive, `.md` optional).
    pub fn resolve(&self, target: &str) -> LinkResolution {
        self.paths.resolve(target)
    }

    pub(crate) fn path_index(&self) -> &PathIndex {
        &self.paths
    }

    /// The edit that creates the missing Note for a broken Link; none if the Link resolves. Writes nothing.
    pub fn create_note_edits(&self, target: &str) -> Result<Vec<FileEdit>> {
        links::create_note_edits(&self.paths, target)
    }

    /// The edit that creates an empty Note at an exact typed path, or why it can't. Writes nothing.
    pub fn new_note_edits(&self, path: &str) -> Result<Vec<FileEdit>> {
        links::new_note_edits(&self.paths, path)
    }

    /// Links in `text` (an open Note's current, maybe unsaved text) that are missing or ambiguous.
    pub fn broken_links(&self, text: &str) -> Vec<WikiLink> {
        links::broken(&self.paths, parser::parse(text).links)
    }

    pub fn endpoint_relations(&self, path: &str, heading: &str) -> EndpointRelations {
        graph::endpoint_relations(&self.parsed, &self.paths, path, heading)
    }

    pub fn repo_staleness(&self, now: NaiveDate) -> BTreeMap<String, Staleness> {
        staleness::repo_staleness(&self.parsed, now)
    }
}
