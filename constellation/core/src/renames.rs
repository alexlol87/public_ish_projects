//! Renames and moves that rewrite every Link (or Tag) pointing at the old name. They return `FileEdit`s and write nothing.

use crate::links::{LinkResolution, PathIndex};
use crate::parser::{self, WikiLink};
use crate::text::{replace_all16, slice16, strip_md, Range16};
use crate::{Error, FileEdit, Result, VaultIndex};
use std::collections::BTreeMap;
use std::fs;

type Rewrites = BTreeMap<String, Vec<(Range16, String)>>;

pub fn rename_note(index: &VaultIndex, path: &str, new_name: &str) -> Result<Vec<FileEdit>> {
    let name = if new_name.ends_with(".md") { new_name.to_string() } else { format!("{new_name}.md") };
    let new = path.rsplit_once('/').map_or(name.clone(), |(dir, _)| format!("{dir}/{name}"));
    move_note(index, path, &new)
}

pub fn move_note_to_folder(index: &VaultIndex, path: &str, folder: &str) -> Result<Vec<FileEdit>> {
    let name = path.rsplit('/').next().unwrap_or(path);
    let folder = folder.trim_matches('/');
    move_note(index, path, &if folder.is_empty() { name.to_string() } else { format!("{folder}/{name}") })
}

fn move_note(index: &VaultIndex, old: &str, new: &str) -> Result<Vec<FileEdit>> {
    let before = index.note_paths();
    if !before.iter().any(|p| p == old) {
        return Err(Error(format!("No such Note: {old}")));
    }
    if old == new {
        return Ok(vec![]);
    }
    if index.root().join(new).exists() {
        return Err(Error(format!("{new} already exists")));
    }
    let after = PathIndex::new(&before.iter().map(|p| if p == old { new } else { p }).collect::<Vec<_>>());
    let new_note = LinkResolution::note(new);
    let new_name = strip_md(new.rsplit('/').next().unwrap_or(new));
    let new_target = |link: &WikiLink| {
        let had_md = link.target.to_lowercase().ends_with(".md");
        let path_style = link.target.contains('/');
        if !path_style && after.resolve(&link.target) == new_note {
            return link.target.clone(); // still resolves: leave as written
        }
        let t = if path_style || after.resolve(new_name) != new_note { strip_md(new) } else { new_name };
        if had_md {
            format!("{t}.md")
        } else {
            t.to_string()
        }
    };
    let rewrites = rewrite_links(index, old, &new_target, &|h| h.to_string(), BTreeMap::new())?;
    // A move is create-new + remove-old; the moved Note's own Link rewrites are folded into the new file's text.
    let text = fs::read_to_string(index.root().join(old))?;
    let moved = rewrites.get(old).map_or(text.clone(), |r| replace_all16(&text, r));
    let others = rewrites.into_iter().filter(|(p, _)| p != old).collect();
    let mut edits = to_edits(others);
    edits.push(FileEdit::create(new, &moved));
    edits.push(FileEdit::remove(old));
    Ok(edits)
}

/// Renames the first heading titled `old` in `note_path` and rewrites `[[note#old]]` Links (Calls and Uses included).
pub fn rename_heading(index: &VaultIndex, old: &str, new: &str, note_path: &str) -> Result<Vec<FileEdit>> {
    let text = fs::read_to_string(index.root().join(note_path))?;
    let h = parser::parse(&text).headings.into_iter().find(|h| h.title == old).ok_or_else(|| Error(format!("No heading {old}")))?;
    let line = format!("{} {new}", "#".repeat(h.level));
    let extra = BTreeMap::from([(note_path.to_string(), vec![(h.range, line)])]);
    let heading_to = |h: &str| if h.to_lowercase() == old.to_lowercase() { new.to_string() } else { h.to_string() };
    Ok(to_edits(rewrite_links(index, note_path, &|l| l.target.clone(), &heading_to, extra)?))
}

/// Renames a Tag and its children (`a/b` -> `c` also turns `a/b/x` into `c/x`) in text and frontmatter, case-insensitively.
pub fn rename_tag(index: &VaultIndex, old: &str, new: &str) -> Result<Vec<FileEdit>> {
    let o = old.to_lowercase();
    let mut rewrites = Rewrites::new();
    for p in index.note_paths() {
        let text = fs::read_to_string(index.root().join(&p))?;
        let reps: Vec<_> = parser::parse(&text)
            .tags
            .into_iter()
            .filter(|t| {
                let l = t.name.to_lowercase();
                l == o || l.strip_prefix(&o).is_some_and(|r| r.starts_with('/'))
            })
            .map(|t| {
                let hash = if slice16(&text, t.range).is_some_and(|s| s.starts_with('#')) { "#" } else { "" };
                (t.range, format!("{hash}{new}{}", t.name.chars().skip(old.chars().count()).collect::<String>()))
            })
            .collect();
        if !reps.is_empty() {
            rewrites.insert(p, reps);
        }
    }
    Ok(to_edits(rewrites))
}

/// Replacements per Note whose Links resolve to `target` (plus `extra`, e.g. a heading line).
fn rewrite_links(
    index: &VaultIndex,
    target: &str,
    new_target: &dyn Fn(&WikiLink) -> String,
    heading_to: &dyn Fn(&str) -> String,
    extra: Rewrites,
) -> Result<Rewrites> {
    let (mut out, want) = (Rewrites::new(), LinkResolution::note(target));
    for p in index.note_paths() {
        let text = fs::read_to_string(index.root().join(&p))?;
        let mut reps = extra.get(&p).cloned().unwrap_or_default();
        for l in parser::parse(&text).links.iter().filter(|l| index.path_index().resolve(&l.target) == want) {
            let heading = l.heading.as_ref().map(|h| format!("#{}", heading_to(h))).unwrap_or_default();
            let alias = l.alias.as_ref().map(|a| format!("|{a}")).unwrap_or_default();
            let s = format!("[[{}{heading}{alias}]]", new_target(l));
            if slice16(&text, l.range) != Some(s.as_str()) {
                reps.push((l.range, s));
            }
        }
        if !reps.is_empty() {
            out.insert(p, reps);
        }
    }
    Ok(out)
}

/// Replacements per file as `FileEdit`s, back to front within each file, files in path order.
fn to_edits(rewrites: Rewrites) -> Vec<FileEdit> {
    rewrites
        .into_iter()
        .flat_map(|(p, mut reps)| {
            reps.sort_by_key(|(r, _)| std::cmp::Reverse(r.location));
            reps.into_iter().map(move |(r, s)| FileEdit::replace(&p, r, &s))
        })
        .collect()
}
