//! In-memory search over a Vault's folder names, Note names and Note text. Case- and diacritic-insensitive substring match.
//! Owned by `VaultIndex`, which feeds it the Notes (app-only files are never given to it).

use crate::parser::{is_tag_name, TagRef};
use crate::text::{fold, fold_char};
use crate::vault::is_archive;
use serde::Serialize;
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TextMatch {
    pub path: String,
    pub sentence: String,
    /// Range of the hit inside `sentence` (UTF-16), for highlighting.
    pub hit: crate::Range16,
    /// UTF-16 offset of the hit in the whole Note, for scrolling the editor.
    pub offset: usize,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Results {
    /// Relative paths.
    pub folders: Vec<String>,
    /// Relative paths.
    pub notes: Vec<String>,
    pub matches: Vec<TextMatch>,
    /// The paths among `notes` and `matches` that sit in a Project's archive; the UI marks these "archived".
    pub archived: Vec<String>,
}

impl Results {
    pub fn is_archived(&self, path: &str) -> bool {
        is_archive(path)
    }
}

/// `start[i]..end[i]` are the original UTF-16 units folded unit `i` came from (folding changes lengths:
/// "ß" -> "ss", "e" + combining accent -> "e"). Absent for ASCII text, where folding keeps every offset.
struct Origin {
    start: Vec<usize>,
    end: Vec<usize>,
}

struct Entry {
    folded: Vec<u16>,
    text: Vec<u16>,
    folded_name: String,
    /// Lowercase Tags and their parents.
    tags: HashSet<String>,
    origin: Option<Origin>,
}

const MAX_MATCHES: usize = 200;

#[derive(Default)]
pub struct SearchIndex {
    folders: Vec<String>,
    notes: HashMap<String, Entry>,
}

fn fold_with_origin(text: &str) -> (Vec<u16>, Origin) {
    let (mut folded, mut o, mut pos) = (vec![], Origin { start: vec![], end: vec![] }, 0);
    let mut prev_units = 0..0;
    for c in text.chars() {
        let end = pos + c.len_utf16();
        let units: Vec<u16> = fold_char(c).iter().collect::<String>().encode_utf16().collect();
        if units.is_empty() {
            // A combining mark belongs to the character before it.
            o.end[prev_units.clone()].fill(end);
        } else {
            prev_units = folded.len()..folded.len() + units.len();
            o.start.extend(units.iter().map(|_| pos));
            o.end.extend(units.iter().map(|_| end));
            folded.extend(units);
        }
        pos = end;
    }
    (folded, o)
}

fn find(needle: &[u16], hay: &[u16], from: usize) -> Option<usize> {
    let (first, last) = (*needle.first()?, hay.len().checked_sub(needle.len())?);
    let mut at = from;
    while at <= last {
        at += hay[at..=last].iter().position(|&u| u == first)?;
        if hay[at..].starts_with(needle) {
            return Some(at);
        }
        at += 1;
    }
    None
}

fn is_space(c: u16) -> bool {
    matches!(c, 32 | 9 | 10 | 13)
}

/// True when a sentence ends just before index `i` (after . ! ? followed by space/end, or at a line break).
fn is_break(u: &[u16], i: usize) -> bool {
    if i == 0 || i >= u.len() {
        return true;
    }
    let p = u[i - 1];
    matches!(u[i], 10 | 13) || matches!(p, 10 | 13) || (matches!(p, 46 | 33 | 63) && is_space(u[i]))
}

impl SearchIndex {
    pub fn set_folders(&mut self, folders: Vec<String>) {
        self.folders = folders;
    }

    pub fn set(&mut self, path: &str, text: &str, tags: &[TagRef]) {
        let name = crate::text::strip_md(path.rsplit('/').next().unwrap_or(""));
        let (folded, origin) = if text.is_ascii() {
            (fold(text).encode_utf16().collect(), None)
        } else {
            let (f, o) = fold_with_origin(text);
            (f, Some(o))
        };
        let tags = tags
            .iter()
            .flat_map(|t| {
                let lower = fold(&t.name);
                lower.match_indices('/').map(|(i, _)| lower[..i].to_string()).chain([lower.clone()]).collect::<Vec<_>>()
            })
            .collect();
        self.notes.insert(path.to_string(), Entry { folded, text: text.encode_utf16().collect(), folded_name: fold(name), tags, origin });
    }

    pub fn retain(&mut self, keep: impl Fn(&str) -> bool) {
        self.notes.retain(|p, _| keep(p));
    }

    pub fn search(&self, query: &str) -> Results {
        // `#tag` terms filter Notes (a parent Tag matches its children); the rest is the text query.
        let (tag_words, words): (Vec<&str>, Vec<&str>) =
            query.split_whitespace().partition(|w| w.strip_prefix('#').is_some_and(is_tag_name));
        let wanted: Vec<String> = tag_words.iter().map(|w| fold(&w[1..])).collect();
        let q = fold(&words.join(" "));
        let mut r = Results::default();
        let notes: Vec<(&String, &Entry)> = self.notes.iter().filter(|(_, e)| wanted.iter().all(|t| e.tags.contains(t))).collect();
        if q.is_empty() {
            if !wanted.is_empty() {
                r.notes = sorted(notes.iter().map(|(p, _)| *p));
                r.archived = r.notes.iter().filter(|p| is_archive(p)).cloned().collect();
            }
            return r;
        }
        let needle: Vec<u16> = q.encode_utf16().collect();
        if wanted.is_empty() {
            let last = |f: &&String| fold(f.rsplit('/').next().unwrap_or("")).contains(&q);
            r.folders = sorted(self.folders.iter().filter(last));
        }
        r.notes = sorted(notes.iter().filter(|(_, e)| e.folded_name.contains(&q)).map(|(p, _)| *p));
        // Sort only the Notes that contain the query; sorting all of them dominates the cost at 5,000 Notes.
        let hits = sorted(notes.iter().filter(|(_, e)| find(&needle, &e.folded, 0).is_some()).map(|(p, _)| *p));
        'notes: for path in hits {
            let e = &self.notes[&path];
            let mut from = 0;
            // One match per sentence. `at` is in folded text; hit_start/hit_end are the same hit in the original text.
            while let Some(at) = find(&needle, &e.folded, from) {
                if r.matches.len() >= MAX_MATCHES {
                    break 'notes;
                }
                let (hit_start, hit_end) =
                    e.origin.as_ref().map_or((at, at + needle.len()), |o| (o.start[at], o.end[at + needle.len() - 1]));
                let (mut s, mut t) = (hit_start, hit_end);
                while s > 0 && !is_break(&e.text, s) {
                    s -= 1;
                }
                while t < e.text.len() && !is_break(&e.text, t) {
                    t += 1;
                }
                while s < hit_start && is_space(e.text[s]) {
                    s += 1;
                }
                r.matches.push(TextMatch {
                    path: path.clone(),
                    sentence: String::from_utf16_lossy(&e.text[s..t]),
                    hit: crate::Range16::new(hit_start - s, hit_end - hit_start),
                    offset: hit_start,
                });
                from = e.origin.as_ref().map_or(t, |o| o.start.partition_point(|&x| x < t));
            }
        }
        r.archived = sorted(r.notes.iter().chain(r.matches.iter().map(|m| &m.path)).filter(|p| is_archive(p)));
        r.archived.dedup();
        r
    }
}

fn sorted<'a>(items: impl Iterator<Item = &'a String>) -> Vec<String> {
    let mut v: Vec<String> = items.cloned().collect();
    // Same order as `ci_cmp`, folding each path once instead of on every comparison.
    v.sort_by_cached_key(|p| (fold(p), p.clone()));
    v
}
