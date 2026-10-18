//! In-memory Tag index over a Vault. Tags are case-folded (lowercase); `a/b` rolls up into `a`.
//! Owned by `VaultIndex`, which feeds it the parsed Notes.

use crate::parser::TagRef;
use crate::text::{fold, lines, Line};
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet, HashMap};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Hit {
    pub path: String,
    /// The line containing the Tag.
    pub line: String,
    /// UTF-16 offset of the Tag in the Note.
    pub offset: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Node {
    /// Full lowercase path, e.g. "team/payments".
    pub tag: String,
    /// Last path component.
    pub name: String,
    /// Notes holding this Tag or any child.
    pub count: usize,
    pub children: Vec<Node>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Sort {
    Name,
    Count,
}

struct Occ {
    tag: String,
    line: String,
    offset: usize,
}

#[derive(Default)]
pub struct TagIndex {
    notes: BTreeMap<String, Vec<Occ>>,
}

/// The tag itself and its ancestors: `a/b/c` -> `a`, `a/b`, `a/b/c`.
fn with_parents(tag: &str) -> impl Iterator<Item = &str> {
    tag.match_indices('/').map(move |(i, _)| &tag[..i]).chain([tag])
}

fn matches(tag: &str, query: &str) -> bool {
    let (tag, query) = (&fold(tag), &fold(query));
    tag == query || tag.strip_prefix(query).is_some_and(|r| r.starts_with('/'))
}

impl TagIndex {
    pub fn set(&mut self, path: &str, text: &str, tags: &[TagRef]) {
        let all = lines(text);
        let line_of = |off: usize| -> &Line { &all[all.partition_point(|l| l.start <= off) - 1] };
        let occs = tags.iter().map(|t| Occ {
            tag: t.name.to_lowercase(),
            line: line_of(t.range.location).text.trim().to_string(),
            offset: t.range.location,
        });
        self.notes.insert(path.to_string(), occs.collect());
    }

    pub fn retain(&mut self, keep: impl Fn(&str) -> bool) {
        self.notes.retain(|p, _| keep(p));
    }

    /// Foldable tree of every Tag with its Note count, parents rolled up.
    pub fn tree(&self, sort: Sort) -> Vec<Node> {
        let mut notes_of: HashMap<&str, BTreeSet<&str>> = HashMap::new();
        for (path, occs) in &self.notes {
            for t in occs.iter().flat_map(|o| with_parents(&o.tag)) {
                notes_of.entry(t).or_default().insert(path);
            }
        }
        let mut kids: HashMap<&str, Vec<&str>> = HashMap::new();
        for &t in notes_of.keys() {
            kids.entry(t.rsplit_once('/').map_or("", |(p, _)| p)).or_default().push(t);
        }
        fn build(parent: &str, kids: &HashMap<&str, Vec<&str>>, counts: &HashMap<&str, BTreeSet<&str>>, sort: Sort) -> Vec<Node> {
            let mut out: Vec<Node> = kids
                .get(parent)
                .into_iter()
                .flatten()
                .map(|&t| Node {
                    tag: t.to_string(),
                    name: t.rsplit('/').next().unwrap_or(t).to_string(),
                    count: counts[t].len(),
                    children: build(t, kids, counts, sort),
                })
                .collect();
            out.sort_by(|a, b| {
                let by_count = if sort == Sort::Count { b.count.cmp(&a.count) } else { Ordering::Equal };
                by_count.then_with(|| a.tag.cmp(&b.tag))
            });
            out
        }
        build("", &kids, &notes_of, sort)
    }

    /// Notes holding the Tag (or a child Tag), one hit per line, ordered by path then position.
    pub fn notes_for(&self, tag: &str) -> Vec<Hit> {
        let q = tag.to_lowercase();
        let mut out = vec![];
        for (path, occs) in &self.notes {
            let mut seen = BTreeSet::new();
            for o in occs.iter().filter(|o| matches(&o.tag, &q)) {
                if seen.insert(&o.line) {
                    out.push(Hit { path: path.clone(), line: o.line.clone(), offset: o.offset });
                }
            }
        }
        out
    }

    /// Existing Tags (and their parents) starting with `prefix`, for `#` autocomplete.
    /// `extra` are Tags known from elsewhere (tags.md).
    pub fn completions(&self, prefix: &str, extra: &[String]) -> Vec<String> {
        let q = fold(prefix);
        let all: BTreeSet<&str> = self.notes.values().flatten().map(|o| o.tag.as_str()).chain(extra.iter().map(String::as_str)).flat_map(with_parents).collect();
        // An exact match offers nothing new and loops the popup.
        all.into_iter().filter(|t| fold(t).starts_with(&q) && fold(t) != q).map(String::from).collect()
    }
}
