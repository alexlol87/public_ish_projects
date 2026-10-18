//! Renames and moves that rewrite every Link (or Tag) pointing at the old name. They return `FileEdit`s and write nothing.

use crate::links::{clean_note_path, LinkResolution, PathIndex};
use crate::parser::{self, WikiLink};
use crate::text::{byte_at, fold, len16, replace_all16, slice16, strip_md, Range16};
use crate::{Error, FileEdit, Result, VaultIndex};
use std::collections::BTreeMap;
use std::fs;

static SELF_LINK: std::sync::LazyLock<regex::Regex> = std::sync::LazyLock::new(|| regex::Regex::new(r"\[\[#([^\[\]|]*)(\|[^\[\]]*)?\]\]").unwrap());

type Rewrites = BTreeMap<String, Vec<(Range16, String)>>;

pub fn rename_note(index: &VaultIndex, path: &str, new_name: &str) -> Result<Vec<FileEdit>> {
    if new_name.contains('/') {
        return Err(Error("A Note name cannot contain /".into()));
    }
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
    let new = &clean_note_path(new)?;
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
    let new = new.trim();
    if new.is_empty() || ["[[", "]]", "|", "#"].iter().any(|c| new.contains(c)) {
        return Err(Error("A heading title cannot be empty or contain [[ ]] | #".into()));
    }
    let parsed = parser::parse(&text);
    if parsed.headings.iter().any(|x| x.range != h.range && x.title.to_lowercase() == new.to_lowercase()) {
        return Err(Error(format!("This Note already has a heading \"{new}\"")));
    }
    let line = format!("{} {new}", "#".repeat(h.level));
    let mut reps = vec![(h.range, line)];
    // `[[#Heading]]` has no Note part, so the Link parser skips it; rewrite those in this Note directly.
    for c in SELF_LINK.captures_iter(&text) {
        if c[1].to_lowercase() == old.to_lowercase() {
            let m = c.get(0).unwrap();
            reps.push((Range16::new(len16(&text[..m.start()]), len16(m.as_str())), format!("[[#{new}{}]]", c.get(2).map_or("", |a| a.as_str()))));
        }
    }
    let extra = BTreeMap::from([(note_path.to_string(), reps)]);
    let heading_to = |h: &str| if h.to_lowercase() == old.to_lowercase() { new.to_string() } else { h.to_string() };
    Ok(to_edits(rewrite_links(index, note_path, &|l| l.target.clone(), &heading_to, extra)?))
}

/// Renames a Tag and its children (`a/b` -> `c` also turns `a/b/x` into `c/x`) in text and frontmatter, case-insensitively.
pub fn rename_tag(index: &VaultIndex, old: &str, new: &str) -> Result<Vec<FileEdit>> {
    let new = new.trim().strip_prefix('#').unwrap_or(new.trim());
    if !parser::is_tag_name(new) {
        return Err(Error(format!("Not a valid Tag name: \"{new}\" (letters, digits, _ - and / between parts)")));
    }
    // Matching is folded (case and diacritics), per path segment; `rest` is what follows the old name ("" or "/child...").
    let o: Vec<String> = old.split('/').map(fold).collect();
    let rest_of = |n: &str| -> Option<String> {
        let segs: Vec<&str> = n.split('/').collect();
        let k = o.len();
        (segs.len() >= k && segs[..k].iter().zip(&o).all(|(a, b)| fold(a) == *b)).then(|| segs[k..].iter().map(|s| format!("/{s}")).collect())
    };
    let mut files = index.note_paths();
    if index.root().join("tags.md").is_file() && !files.iter().any(|p| p == "tags.md") {
        files.push("tags.md".into()); // the Tag list autocomplete reads
    }
    let mut rewrites = Rewrites::new();
    for p in files {
        let text = fs::read_to_string(index.root().join(&p))?;
        let tags = parser::parse(&text).tags;
        let hit = |n: &str| rest_of(n).is_some();
        let in_text = |t: &parser::TagRef| slice16(&text, t.range).is_some_and(|s| s.starts_with('#'));
        // Frontmatter list items that would repeat a Tag already in the list are dropped, not renamed.
        let mut seen: std::collections::HashSet<_> = tags.iter().filter(|t| !in_text(t) && !hit(&t.name)).map(|t| t.name.to_lowercase()).collect();
        let reps: Vec<_> = tags
            .iter()
            .filter(|t| hit(&t.name))
            .map(|t| {
                let name = format!("{new}{}", rest_of(&t.name).unwrap_or_default());
                if in_text(t) {
                    (t.range, format!("#{name}"))
                } else if seen.insert(name.to_lowercase()) {
                    (t.range, name)
                } else {
                    (item_with_separator(&text, t.range), String::new())
                }
            })
            .collect();
        if !reps.is_empty() {
            rewrites.insert(p, reps);
        }
    }
    Ok(to_edits(rewrites))
}

/// `r` (a frontmatter Tag item) widened over its quotes and one list separator, or its whole `- item` line.
fn item_with_separator(text: &str, r: Range16) -> Range16 {
    let (mut a, mut b) = (byte_at(text, r.location).unwrap_or(0), byte_at(text, r.end()).unwrap_or(0));
    let ls = text[..a].rfind('\n').map_or(0, |i| i + 1);
    let le = text[b..].find('\n').map_or(text.len(), |i| b + i);
    if text[ls..le].trim_start().starts_with('-') {
        (a, b) = (ls, (le + 1).min(text.len()));
    } else {
        let q = |c: char| c == '"' || c == '\'';
        a -= text[ls..a].len() - text[ls..a].trim_end_matches(q).len();
        b += text[b..le].len() - text[b..le].trim_start_matches(q).len();
        let after = text[b..le].trim_start();
        if let Some(rest) = after.strip_prefix(',') {
            b = le - rest.trim_start().len();
        } else if text[ls..a].trim_end().ends_with(',') {
            a = ls + text[ls..a].trim_end().len() - 1;
        }
    }
    Range16::new(len16(&text[..a]), len16(&text[a..b]))
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
