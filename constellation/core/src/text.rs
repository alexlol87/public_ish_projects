//! UTF-16 helpers. Rust strings are UTF-8; the frontend counts UTF-16 code units, so every public offset goes through here.

use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use unicode_normalization::{char::is_combining_mark, UnicodeNormalization};

/// A range in UTF-16 code units (like `NSRange`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Range16 {
    pub location: usize,
    pub length: usize,
}

impl Range16 {
    pub fn new(location: usize, length: usize) -> Self {
        Self { location, length }
    }

    pub fn end(&self) -> usize {
        self.location + self.length
    }

    pub fn contains(&self, offset: usize) -> bool {
        (self.location..self.end()).contains(&offset)
    }
}

pub fn len16(s: &str) -> usize {
    s.chars().map(char::len_utf16).sum()
}

/// Byte index of UTF-16 offset `off`, or None if it is past the end or inside a surrogate pair.
pub fn byte_at(s: &str, off: usize) -> Option<usize> {
    let mut n = 0;
    for (i, c) in s.char_indices() {
        if n >= off {
            return (n == off).then_some(i);
        }
        n += c.len_utf16();
    }
    (n == off).then_some(s.len())
}

/// Byte index of each UTF-16 offset in `offs` (ascending), in one pass.
pub fn bytes_at(s: &str, offs: &[usize]) -> Option<Vec<usize>> {
    let mut out = Vec::with_capacity(offs.len());
    let mut it = offs.iter().peekable();
    let mut n = 0;
    for (i, c) in s.char_indices() {
        while let Some(&&o) = it.peek() {
            if o < n {
                return None; // inside a surrogate pair, or out of order
            }
            if o > n {
                break;
            }
            out.push(i);
            it.next();
        }
        n += c.len_utf16();
    }
    for &o in it {
        if o != n {
            return None;
        }
        out.push(s.len());
    }
    Some(out)
}

pub fn slice16(s: &str, r: Range16) -> Option<&str> {
    s.get(byte_at(s, r.location)?..byte_at(s, r.end())?)
}

pub fn replace16(s: &str, r: Range16, with: &str) -> Option<String> {
    let (a, b) = (byte_at(s, r.location)?, byte_at(s, r.end())?);
    Some([&s[..a], with, &s[b..]].concat())
}

/// Applies replacements (non-overlapping) to `text`, in one pass.
pub fn replace_all16(text: &str, reps: &[(Range16, String)]) -> String {
    let mut sorted: Vec<_> = reps.iter().collect();
    sorted.sort_by_key(|(r, _)| r.location);
    let offs: Vec<usize> = sorted.iter().flat_map(|(r, _)| [r.location, r.end()]).collect();
    let Some(b) = bytes_at(text, &offs) else { return text.to_string() };
    let (mut out, mut from) = (String::with_capacity(text.len()), 0);
    for (k, (_, s)) in sorted.into_iter().enumerate() {
        out.push_str(&text[from..b[2 * k]]);
        out.push_str(s);
        from = b[2 * k + 1];
    }
    out + &text[from..]
}

/// One line of a text without its terminator (`\n` or `\r\n`); `start` is its UTF-16 offset.
#[derive(Debug, Clone, Copy)]
pub struct Line<'a> {
    pub start: usize,
    pub text: &'a str,
}

pub fn lines(text: &str) -> Vec<Line<'_>> {
    let mut start = 0;
    text.split_inclusive('\n')
        .map(|raw| {
            let line = Line { start, text: raw.trim_end_matches(['\n', '\r']) };
            start += len16(raw);
            line
        })
        .collect()
}

/// Case- and diacritic-insensitive form: "Café" -> "cafe", "ß" -> "ss".
pub fn fold(s: &str) -> String {
    if s.is_ascii() {
        return s.to_ascii_lowercase();
    }
    s.chars().flat_map(fold_char).collect()
}

/// Folds one char; combining marks vanish (empty).
pub fn fold_char(c: char) -> Vec<char> {
    if c.is_ascii() {
        return vec![c.to_ascii_lowercase()];
    }
    if c == 'ß' {
        return vec!['s', 's'];
    }
    c.to_string().nfd().filter(|m| !is_combining_mark(*m)).flat_map(char::to_lowercase).collect()
}

/// Order for names in the UI: folded first, then as written.
pub fn ci_cmp(a: &str, b: &str) -> Ordering {
    fold(a).cmp(&fold(b)).then_with(|| a.cmp(b))
}

pub fn strip_md(s: &str) -> &str {
    match s.len().checked_sub(3).and_then(|i| s.get(i..)) {
        Some(ext) if ext.eq_ignore_ascii_case(".md") => &s[..s.len() - 3],
        _ => s,
    }
}

pub fn is_md(s: &str) -> bool {
    strip_md(s).len() != s.len()
}
