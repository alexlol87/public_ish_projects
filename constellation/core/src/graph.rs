//! The Vault graph: Notes and folders as Nodes; Containment, Link, Call and Uses edges; broken Links as ghost Nodes.

use crate::links::{LinkResolution, PathIndex};
use crate::parser::ParsedNote;
use crate::vault::{is_archive, VaultNode};
use crate::Result;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum NodeKind {
    Note,
    Folder,
    Ghost,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphNode {
    /// Vault path; ghosts are "ghost:<createPath>".
    pub id: String,
    pub name: String,
    pub kind: NodeKind,
    /// Frontmatter type for notes; None for folders and ghosts.
    pub note_type: Option<String>,
    /// Lowercased tag names of a Note.
    pub tags: Vec<String>,
}

/// One Endpoint-level Call (or a Client Use, where `from` is "") folded into a Note-to-Note edge.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EndpointPair {
    pub from: String,
    pub to: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum EdgeKind {
    Containment,
    Link,
    Call,
    Uses,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphEdge {
    pub from: String,
    pub to: String,
    pub kind: EdgeKind,
    /// Call/uses edges: what the edge folds, for hover.
    pub pairs: Vec<EndpointPair>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultGraph {
    pub nodes: Vec<GraphNode>,
    pub edges: Vec<GraphEdge>,
}

impl VaultGraph {
    /// What clicking a Node opens: a Note itself, a folder's README.md; None for ghosts and folders without one.
    pub fn open_path(&self, id: &str) -> Option<String> {
        let n = self.nodes.iter().find(|n| n.id == id)?;
        match n.kind {
            NodeKind::Note => Some(id.to_string()),
            NodeKind::Ghost => None,
            NodeKind::Folder => {
                let readme = if id.is_empty() { "README.md".to_string() } else { format!("{id}/README.md") };
                self.nodes.iter().any(|n| n.id == readme).then_some(readme)
            }
        }
    }

    /// Ids joined to `id` by any edge, sorted.
    pub fn neighbours(&self, id: &str) -> Vec<String> {
        let set: BTreeSet<&str> = self
            .edges
            .iter()
            .filter_map(|e| {
                if e.from == id {
                    Some(&*e.to)
                } else if e.to == id {
                    Some(&*e.from)
                } else {
                    None
                }
            })
            .collect();
        set.into_iter().map(String::from).collect()
    }

    /// Applies `f` (archive is handled when the graph is built). With `around`, keeps Nodes within `f.local_depth` (1..=3) edges of it.
    pub fn filtered(&self, f: &GraphFilter, around: Option<&str>) -> VaultGraph {
        let mut g = self.clone();
        g.nodes.retain(|n| {
            if n.kind == NodeKind::Note && !f.types.is_empty() && !f.types.contains(n.note_type.as_deref().unwrap_or("note")) {
                return false;
            }
            if n.kind == NodeKind::Ghost || n.id.is_empty() || f.projects.is_empty() {
                return true;
            }
            f.projects.contains(n.id.split('/').next().unwrap_or(""))
        });
        g.edges.retain(|e| f.edge_kinds.contains(&e.kind));
        g.prune();
        if let Some(tag) = f.tag.as_deref().map(str::to_lowercase).filter(|t| !t.is_empty()) {
            let hit: HashSet<&str> = g
                .nodes
                .iter()
                .filter(|n| n.tags.iter().any(|t| *t == tag || t.strip_prefix(&tag).is_some_and(|r| r.starts_with('/'))))
                .map(|n| &*n.id)
                .collect();
            let adj = g.adjacency();
            let keep: HashSet<String> =
                hit.iter().flat_map(|id| adj.get(id).into_iter().flatten().copied().chain([*id])).map(String::from).collect();
            g.restrict(&keep);
        }
        if let Some(start) = around {
            let adj = g.adjacency();
            let mut seen: HashSet<&str> = HashSet::from([start]);
            let mut frontier = vec![start];
            for _ in 0..f.local_depth.clamp(1, 3) {
                frontier = frontier.iter().flat_map(|id| adj.get(id).into_iter().flatten().copied()).filter(|n| seen.insert(n)).collect();
            }
            let keep = seen.into_iter().map(String::from).collect();
            g.restrict(&keep);
        }
        g
    }

    fn prune(&mut self) {
        let keep: HashSet<&str> = self.nodes.iter().map(|n| &*n.id).collect();
        let edges = std::mem::take(&mut self.edges);
        self.edges = edges.into_iter().filter(|e| keep.contains(e.from.as_str()) && keep.contains(e.to.as_str())).collect();
    }

    fn restrict(&mut self, keep: &HashSet<String>) {
        self.nodes.retain(|n| keep.contains(&n.id));
        self.prune();
    }

    fn adjacency(&self) -> HashMap<&str, Vec<&str>> {
        let mut adj: HashMap<&str, Vec<&str>> = HashMap::new();
        for e in &self.edges {
            adj.entry(&e.from).or_default().push(&e.to);
            adj.entry(&e.to).or_default().push(&e.from);
        }
        adj
    }
}

/// Graph window filters; empty `projects`/`types` mean "all". Persisted per Vault in `.constellation/graph.json`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct GraphFilter {
    /// Top-level folder names.
    pub projects: BTreeSet<String>,
    /// Note types.
    pub types: BTreeSet<String>,
    pub edge_kinds: BTreeSet<EdgeKind>,
    /// Tagged Notes (and child tags) plus their neighbours.
    pub tag: Option<String>,
    pub include_archive: bool,
    /// 1..=3, used when the graph is built `around` a Note.
    pub local_depth: usize,
}

impl Default for GraphFilter {
    fn default() -> Self {
        Self {
            projects: BTreeSet::new(),
            types: BTreeSet::new(),
            edge_kinds: [EdgeKind::Containment, EdgeKind::Link, EdgeKind::Call, EdgeKind::Uses].into(),
            tag: None,
            include_archive: false,
            local_depth: 2,
        }
    }
}

impl GraphFilter {
    fn file(root: &Path) -> std::path::PathBuf {
        root.join(".constellation/graph.json")
    }

    /// The saved filter, or the default if there is none or it is unreadable.
    pub fn load(root: &Path) -> Self {
        std::fs::read(Self::file(root)).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
    }

    pub fn save(&self, root: &Path) -> Result<()> {
        let json = serde_json::to_string(self).map_err(|e| crate::Error(e.to_string()))?;
        crate::vault::write_atomic(&Self::file(root), &json)
    }
}

/// The graph from an already-loaded tree and parsed Notes (no disk reads). Archive Notes are left out unless `include_archive`.
pub fn build(tree: &VaultNode, parsed: &BTreeMap<String, ParsedNote>, paths: &PathIndex, include_archive: bool) -> VaultGraph {
    let mut nodes = vec![GraphNode { id: String::new(), name: tree.name.clone(), kind: NodeKind::Folder, note_type: None, tags: vec![] }];
    let mut edges = vec![];
    let mut node_at: HashMap<&str, usize> = HashMap::new();
    fn walk<'a>(
        n: &'a VaultNode,
        include_archive: bool,
        nodes: &mut Vec<GraphNode>,
        edges: &mut Vec<GraphEdge>,
        node_at: &mut HashMap<&'a str, usize>,
    ) {
        for c in n.children.iter().filter(|c| {
            !c.app_only && (include_archive || !is_archive(&c.relative_path)) && (c.is_folder || crate::text::is_md(&c.relative_path))
        }) {
            node_at.insert(&c.relative_path, nodes.len());
            let kind = if c.is_folder { NodeKind::Folder } else { NodeKind::Note };
            nodes.push(GraphNode { id: c.relative_path.clone(), name: c.name.clone(), kind, note_type: None, tags: vec![] });
            edges.push(GraphEdge {
                from: n.relative_path.clone(),
                to: c.relative_path.clone(),
                kind: EdgeKind::Containment,
                pairs: vec![],
            });
            if c.is_folder {
                walk(c, include_archive, nodes, edges, node_at);
            }
        }
    }
    walk(tree, include_archive, &mut nodes, &mut edges, &mut node_at);

    let mut ghosts = HashSet::new();
    let mut seen = HashSet::new();
    let mut folded: HashMap<(EdgeKind, String, String), usize> = HashMap::new();
    for (p, note) in parsed.iter().filter(|(p, _)| include_archive || !is_archive(p)) {
        if let Some(&i) = node_at.get(p.as_str()) {
            nodes[i].note_type = Some(note.note_type.clone());
            nodes[i].tags = note.tags.iter().map(|t| t.name.to_lowercase()).collect::<BTreeSet<_>>().into_iter().collect();
        }
        let mut fold = |kind: EdgeKind, target: &str, pair: EndpointPair| {
            let LinkResolution::Note { path: to } = paths.resolve(target) else { return };
            if to == *p || (!include_archive && is_archive(&to)) {
                return;
            }
            let i = *folded.entry((kind, p.clone(), to.clone())).or_insert_with(|| {
                edges.push(GraphEdge { from: p.clone(), to, kind, pairs: vec![] });
                edges.len() - 1
            });
            edges[i].pairs.push(pair);
        };
        // A Call/Uses Link gets only its Call/Uses edge, not a plain Link edge too.
        let mut sectioned = HashSet::new();
        for s in &note.calls {
            for l in &s.links {
                sectioned.insert(l.range.location);
                fold(EdgeKind::Call, &l.target, EndpointPair { from: s.heading.plain_title(), to: l.heading.clone().unwrap_or_default() });
            }
        }
        for s in &note.uses {
            for l in &s.links {
                sectioned.insert(l.range.location);
                fold(EdgeKind::Uses, &l.target, EndpointPair { from: String::new(), to: l.heading.clone().unwrap_or_default() });
            }
        }
        for l in note.links.iter().filter(|l| !sectioned.contains(&l.range.location)) {
            let to = match paths.resolve(&l.target) {
                // A Link to a hidden archive Note draws nothing: the Note exists, so it is no ghost.
                LinkResolution::Note { path } if !include_archive && is_archive(&path) => continue,
                LinkResolution::Note { path } => path,
                LinkResolution::Broken { create_path } => {
                    let id = format!("ghost:{}", create_path.to_lowercase());
                    if ghosts.insert(id.clone()) {
                        let name = crate::text::strip_md(&create_path).to_string();
                        nodes.push(GraphNode { id: id.clone(), name, kind: NodeKind::Ghost, note_type: None, tags: vec![] });
                    }
                    id
                }
            };
            if to != *p && seen.insert((p.clone(), to.clone())) {
                edges.push(GraphEdge { from: p.clone(), to, kind: EdgeKind::Link, pairs: vec![] });
            }
        }
    }
    VaultGraph { nodes, edges }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EndpointRef {
    pub path: String,
    /// None for a Client (Uses are per Note).
    pub heading: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EndpointRelations {
    pub calls_out: Vec<EndpointRef>,
    pub calls_in: Vec<EndpointRef>,
    pub uses_in: Vec<EndpointRef>,
}

/// Inspector data for the Endpoint `heading` in Note `path`: what it calls, who calls it, which Clients use it.
pub fn endpoint_relations(parsed: &BTreeMap<String, ParsedNote>, paths: &PathIndex, path: &str, heading: &str) -> EndpointRelations {
    let mut r = EndpointRelations::default();
    let plain = heading.replace('`', "").to_lowercase();
    let target = LinkResolution::note(path);
    let hits = |l: &crate::WikiLink| paths.resolve(&l.target) == target && l.heading.as_ref().is_some_and(|h| h.to_lowercase() == plain);
    for (p, note) in parsed {
        for s in &note.calls {
            if p == path && s.heading.plain_title().to_lowercase() == plain {
                for l in &s.links {
                    if let LinkResolution::Note { path } = paths.resolve(&l.target) {
                        r.calls_out.push(EndpointRef { path, heading: l.heading.clone() });
                    }
                }
            }
            if s.links.iter().any(hits) {
                r.calls_in.push(EndpointRef { path: p.clone(), heading: Some(s.heading.plain_title()) });
            }
        }
        if note.uses.iter().any(|s| s.links.iter().any(hits)) {
            r.uses_in.push(EndpointRef { path: p.clone(), heading: None });
        }
    }
    r
}
