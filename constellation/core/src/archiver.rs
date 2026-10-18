//! Task checkboxes and the Archive (ADR 0002): ticking a bug or todo moves it to the Project's archive Note.

use crate::links::LinkResolution;
use crate::text::{len16, strip_md, Range16};
use crate::{parser, Error, FileEdit, Result, VaultIndex};
use chrono::NaiveDate;
use regex::Regex;
use std::fs;
use std::sync::LazyLock;

// groups: 1 indent, 2 box char, 3 rest of the line
static TASK: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^([ \t]*)[-*+] \[([ xX])\] ?(.*?)\n?$").unwrap());

fn indent(s: &str) -> usize {
    s.chars().take_while(|c| *c == ' ' || *c == '\t').count()
}

/// `tick` on the Note as saved on disk. `editor_text` is the open buffer (CRLF read as LF) and must equal the disk text,
/// else the click is refused: a stale buffer (second click before the reload, unsaved or conflicting text) must not
/// pick offsets in the wrong text. Offsets are mapped onto CRLF files.
pub fn tick_saved(index: &VaultIndex, offset: usize, editor_text: &str, path: &str, on: NaiveDate) -> Result<Vec<FileEdit>> {
    let disk = fs::read_to_string(index.root().join(path))?;
    let lf = disk.replace("\r\n", "\n");
    if lf != editor_text.replace("\r\n", "\n") {
        return Err(Error(format!("{path} has changes that are not saved yet; try again in a moment")));
    }
    let Some(at) = crate::text::byte_at(&lf, offset) else { return Ok(vec![]) };
    // ponytail: assumes uniform line endings; a mixed file maps offsets a little off
    let crs = if lf.len() == disk.len() { 0 } else { lf[..at].matches('\n').count() };
    tick(index, offset + crs, &disk, path, on)
}

/// A click on a task checkbox. `offset` is any UTF-16 offset on the task's line in `text` (the open buffer of `path`).
/// Unticked item in a Repo's bugs.md / todo.md (`project/repo/bugs.md`): moves it to the Project's archive Note.
/// Any other task: toggles the box. Not a task line: no edits.
pub fn tick(index: &VaultIndex, offset: usize, text: &str, path: &str, on: NaiveDate) -> Result<Vec<FileEdit>> {
    let Some(at) = crate::text::byte_at(text, offset) else { return Ok(vec![]) };
    let first = text[..at].rfind('\n').map_or(0, |i| i + 1)..text[at..].find('\n').map_or(text.len(), |i| at + i + 1);
    let line = &text[first.clone()];
    let Some(m) = TASK.captures(line) else { return Ok(vec![]) };
    let at16 = |byte: usize| len16(&text[..byte]);
    let box_at = first.start + m.get(2).unwrap().start();
    let box_range = Range16::new(at16(box_at), 1);
    let checked = &m[2] != " ";
    let parts: Vec<&str> = path.split('/').collect();
    let file = parts.last().copied().unwrap_or("");
    if checked || parts.len() < 3 || !matches!(file, "bugs.md" | "todo.md") {
        return Ok(vec![FileEdit::replace(path, box_range, if checked { " " } else { "x" })]);
    }

    // The item: its line plus the more-indented lines after it.
    let item_indent = m[1].chars().count();
    let mut item_end = first.end;
    while let Some(next) = text[item_end..].split_inclusive('\n').next() {
        if next.trim().is_empty() || indent(next) <= item_indent {
            break;
        }
        item_end += next.len();
    }
    let item = first.start..item_end;
    let body = m[3].trim();
    let title = body.split(" → ").next().unwrap_or(body).trim();
    let rest = text[first.end..item_end].split('\n').map(str::trim).filter(|s| !s.is_empty()).collect::<Vec<_>>().join(" ");

    let repo = parts[..parts.len() - 1].join("/");
    let mut source = format!("[[{repo}/README]]");
    if let Some(l) = parser::parse(&text[item.clone()]).links.first() {
        // Resolve inside the Repo first: "endpoints" means this Repo's endpoints Note, not another Repo's.
        let local = format!("{repo}/{}.md", l.target);
        let target = match index.resolve(&l.target) {
            _ if index.parsed().contains_key(&local) => strip_md(&local).to_string(),
            LinkResolution::Note { path } => strip_md(&path).to_string(),
            LinkResolution::Broken { .. } => l.target.clone(),
        };
        source = format!("[[{target}{}]]", l.heading.as_ref().map(|h| format!("#{h}")).unwrap_or_default());
    }

    let entry = format!(
        "### {title}\n- closed: {}\n- source: {source}\n- what: {}\n- fix: unknown\n",
        on.format("%Y-%m-%d"),
        if rest.is_empty() { title } else { &rest }
    );
    let bug = file == "bugs.md";
    let archive = format!("{}/archive/{}", parts[0], if bug { "fixed-bugs.md" } else { "done-todos.md" });
    let mut edits = vec![FileEdit::replace(path, Range16::new(at16(item.start), at16(item.end) - at16(item.start)), "")];
    if let Ok(old) = fs::read_to_string(index.root().join(&archive)) {
        let sep = if old.is_empty() {
            ""
        } else if old.ends_with('\n') {
            "\n"
        } else {
            "\n\n"
        };
        edits.push(FileEdit::replace(&archive, Range16::new(len16(&old), 0), &format!("{sep}{entry}")));
    } else {
        let head = format!("---\ntype: archive\n---\n# {}\n\n", if bug { "Fixed bugs" } else { "Done todos" });
        edits.push(FileEdit::create(&archive, &format!("{head}{entry}")));
    }
    Ok(edits)
}
