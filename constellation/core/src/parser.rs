//! Pure Note parser. Skips fenced and inline code. All ranges are UTF-16.

use crate::text::{len16, lines, Line, Range16};
use regex::Regex;
use serde::Serialize;
use std::collections::BTreeMap;
use std::ops::Range;
use std::sync::LazyLock;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WikiLink {
    /// The whole `[[...]]`.
    pub range: Range16,
    /// Vault path or Note name, as written.
    pub target: String,
    pub heading: Option<String>,
    pub alias: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteHeading {
    pub level: usize,
    pub title: String,
    /// The whole heading line without its newline.
    pub range: Range16,
}

impl NoteHeading {
    /// The title without backticks (`` `GET /a` `` -> `GET /a`), which is how Links name an Endpoint.
    pub fn plain_title(&self) -> String {
        self.title.replace('`', "")
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TagRef {
    /// `#name` inline (with the `#`), or just the name in frontmatter.
    pub range: Range16,
    /// As written, without `#`; nested like `team/payments`.
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SectionLinks {
    pub heading: NoteHeading,
    pub links: Vec<WikiLink>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EndpointStatus {
    pub heading: NoteHeading,
    /// implemented, last_changed, missing, ...
    pub values: BTreeMap<String, String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ParsedNote {
    pub tags: Vec<TagRef>,
    pub links: Vec<WikiLink>,
    pub headings: Vec<NoteHeading>,
    /// Every key kept, known or not.
    pub frontmatter: BTreeMap<String, String>,
    /// `Calls:` lists under Endpoint headings.
    pub calls: Vec<SectionLinks>,
    /// `Uses:` lists in Client Notes.
    pub uses: Vec<SectionLinks>,
    pub status: Vec<EndpointStatus>,
    /// The frontmatter `type`; a missing one is a plain `note`.
    #[serde(rename = "type")]
    pub note_type: String,
}

impl ParsedNote {
    /// Headings that name an Endpoint (`GET /path`, optionally in backticks).
    pub fn endpoints(&self) -> impl Iterator<Item = &NoteHeading> {
        self.headings.iter().filter(|h| is_endpoint(&h.title))
    }

    /// The Endpoint the offset sits in: the nearest Endpoint heading above it, unless a heading of the same or a higher
    /// level (a sibling or parent section) comes in between. Sub-headings such as `### Request` stay inside the Endpoint.
    pub fn endpoint_heading(&self, offset: usize) -> Option<&NoteHeading> {
        let mut shallowest = usize::MAX;
        for h in self.headings.iter().rev().filter(|h| h.range.location <= offset) {
            if is_endpoint(&h.title) {
                return (shallowest > h.level).then_some(h);
            }
            shallowest = shallowest.min(h.level);
        }
        None
    }
}

fn re(p: &str) -> Regex {
    Regex::new(p).unwrap()
}

pub(crate) const TAG_NAME: &str = r"\p{L}[\p{L}\p{N}_-]*(?:/\p{L}[\p{L}\p{N}_-]*)*";
static HEADING: LazyLock<Regex> = LazyLock::new(|| re(r"^(#{1,6}) +(\S.*?) *$"));
static CODE: LazyLock<Regex> = LazyLock::new(|| re(r"`[^`]+`"));
static LINK: LazyLock<Regex> = LazyLock::new(|| re(r"\[\[([^\[\]|#]+)(?:#([^\[\]|]*))?(?:\|([^\[\]]*))?\]\]"));
static TAG: LazyLock<Regex> = LazyLock::new(|| re(&format!("#({TAG_NAME})")));
static TAG_FULL: LazyLock<Regex> = LazyLock::new(|| re(&format!("^{TAG_NAME}$")));
static TYPED_TAG: LazyLock<Regex> = LazyLock::new(|| re(r"#([\p{L}\p{N}_/-]*)$"));
static LINK_URL: LazyLock<Regex> = LazyLock::new(|| re(r"\]\([^)]*\)"));
static HEX: LazyLock<Regex> = LazyLock::new(|| re(r"^(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"));
static ENDPOINT: LazyLock<Regex> = LazyLock::new(|| re(r"^`?(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) /"));

pub fn is_tag_name(s: &str) -> bool {
    TAG_FULL.is_match(s)
}

pub fn is_endpoint(title: &str) -> bool {
    ENDPOINT.is_match(title)
}

/// A `#` starts a Tag unless a letter, digit, `_`, `/`, `&` or `#` comes right before it.
fn tag_can_start_after(prev: Option<char>) -> bool {
    prev.is_none_or(|c| !(c.is_alphanumeric() || "_/&#".contains(c)))
}

/// The Tag text typed after a `#` at the end of `line` (a `#` that would start a Tag), else None.
pub fn typed_tag_prefix(line: &str) -> Option<String> {
    let m = TYPED_TAG.captures(line)?;
    tag_can_start_after(line[..m.get(0)?.start()].chars().next_back()).then(|| m[1].to_string())
}

fn overlaps(a: &Range<usize>, b: &Range<usize>) -> bool {
    a.start < b.end && b.start < a.end
}

fn byte_ranges(re: &Regex, s: &str) -> Vec<Range<usize>> {
    re.find_iter(s).map(|m| m.range()).collect()
}

/// Range of `bytes` within `s` in UTF-16, shifted by `base`.
fn range16(s: &str, bytes: Range<usize>, base: usize) -> Range16 {
    Range16::new(base + len16(&s[..bytes.start]), len16(&s[bytes]))
}

/// Inline `#tag` ranges (with the `#`) in one line, outside inline code and `](url)` parts; offsets are from the line start.
pub fn inline_tags(s: &str) -> Vec<TagRef> {
    let skip: Vec<_> = byte_ranges(&CODE, s).into_iter().chain(byte_ranges(&LINK_URL, s)).collect();
    TAG.captures_iter(s)
        .filter_map(|c| {
            let (m, name) = (c.get(0)?, c.get(1)?.as_str());
            let ok = tag_can_start_after(s[..m.start()].chars().next_back())
                && !skip.iter().any(|r| overlaps(r, &m.range()))
                && !HEX.is_match(name);
            ok.then(|| TagRef { range: range16(s, m.range(), 0), name: name.to_string() })
        })
        .collect()
}

pub fn parse(text: &str) -> ParsedNote {
    let all = lines(text);
    let close = match all.first() {
        Some(l) if l.text.trim_end() == "---" => all.iter().skip(1).position(|l| l.text.trim_end() == "---").map(|i| i + 1),
        _ => None,
    };
    let (front, body) = match close {
        Some(c) => (&all[1..c], &all[c + 1..]),
        None => (&all[..0], &all[..]),
    };
    let mut out = ParsedNote {
        tags: vec![],
        links: vec![],
        headings: vec![],
        frontmatter: BTreeMap::new(),
        calls: vec![],
        uses: vec![],
        status: vec![],
        note_type: String::new(),
    };
    let mut in_tags = false;
    for l in front {
        frontmatter_line(l, &mut in_tags, &mut out);
    }
    let mut in_fence = false;
    for l in body {
        if l.text.starts_with("```") {
            in_fence = !in_fence;
        } else if !in_fence {
            body_line(l, &mut out);
        }
    }
    parse_lists(body, &mut out);
    out.note_type = out.frontmatter.get("type").cloned().unwrap_or_else(|| "note".into());
    out
}

/// Frontmatter `key: value` pairs and `tags:` as `[a, b]`, `a, b` or a `- a` list under `tags:`.
fn frontmatter_line(l: &Line, in_tags: &mut bool, out: &mut ParsedNote) {
    let s = l.text;
    if let Some((k, v)) = s.split_once(':') {
        out.frontmatter.insert(k.trim().to_string(), v.trim().to_string());
    }
    let (items, base) = if let Some(rest) = s.strip_prefix("tags:") {
        *in_tags = true;
        (rest, 5)
    } else if *in_tags && (s.starts_with(' ') || s.starts_with('-')) && s.trim().starts_with('-') {
        let at = s.len() - s.trim_start().len() + 1;
        (&s[at..], at)
    } else {
        *in_tags = false;
        return;
    };
    let junk = [' ', '\t', '"', '\'', '#'];
    let mut pos = base;
    for seg in items.split([',', '[', ']']) {
        let item = seg.trim_matches(junk);
        if !item.is_empty() && is_tag_name(item) {
            let start = pos + seg.len() - seg.trim_start_matches(junk).len();
            out.tags.push(TagRef { range: range16(s, start..start + item.len(), l.start), name: item.to_string() });
        }
        pos += seg.len() + 1;
    }
}

fn body_line(l: &Line, out: &mut ParsedNote) {
    let s = l.text;
    if let Some(c) = HEADING.captures(s) {
        let level = c[1].len();
        out.headings.push(NoteHeading { level, title: c[2].to_string(), range: Range16::new(l.start, len16(s)) });
    }
    out.tags.extend(inline_tags(s).into_iter().map(|t| TagRef { range: Range16::new(t.range.location + l.start, t.range.length), ..t }));
    let code = byte_ranges(&CODE, s);
    for c in LINK.captures_iter(s) {
        let m = c.get(0).unwrap();
        if code.iter().any(|r| overlaps(r, &m.range())) {
            continue;
        }
        out.links.push(WikiLink {
            range: range16(s, m.range(), l.start),
            target: c[1].trim().to_string(),
            heading: c.get(2).map(|h| h.as_str().to_string()).filter(|h| !h.is_empty()),
            alias: c.get(3).map(|a| a.as_str().to_string()),
        });
    }
}

/// `Calls:` / `Uses:` / `Status:` lines followed by bullets, attached to the nearest heading above.
fn parse_lists(body: &[Line], out: &mut ParsedNote) {
    let mut in_fence = false;
    let lines: Vec<&Line> = body
        .iter()
        .filter(|l| {
            if l.text.starts_with("```") {
                in_fence = !in_fence;
                return false;
            }
            !in_fence
        })
        .collect();
    let is_client = out.frontmatter.get("type").is_some_and(|t| t == "client");
    let mut i = 0;
    while i < lines.len() {
        let (label, at) = (lines[i].text.trim(), lines[i].start);
        i += 1;
        if !matches!(label, "Calls:" | "Uses:" | "Status:") {
            continue;
        }
        let first = i;
        while i < lines.len() && (lines[i].text.trim().starts_with("- ") || lines[i].text.trim().starts_with("* ")) {
            i += 1;
        }
        let bullets = &lines[first..i];
        let links = || -> Vec<WikiLink> {
            let in_bullet = |l: &WikiLink| bullets.iter().any(|b| Range16::new(b.start, len16(b.text)).contains(l.range.location));
            out.links.iter().filter(|l| in_bullet(l)).cloned().collect()
        };
        match label {
            "Calls:" => {
                if let Some(h) = out.endpoint_heading(at).cloned() {
                    let links = links();
                    out.calls.push(SectionLinks { heading: h, links });
                }
            }
            "Uses:" if is_client => {
                let heading = out.headings.iter().rfind(|h| h.range.location <= at).cloned();
                let heading = heading.unwrap_or(NoteHeading { level: 0, title: String::new(), range: Range16::default() });
                let links = links();
                out.uses.push(SectionLinks { heading, links });
            }
            "Status:" => {
                if let Some(h) = out.endpoint_heading(at).cloned() {
                    let values = bullets
                        .iter()
                        .filter_map(|b| b.text.trim()[2..].split_once(':'))
                        .map(|(k, v)| (k.trim().to_string(), v.trim().to_string()))
                        .filter(|(k, v)| !k.is_empty() && !v.is_empty())
                        .collect();
                    out.status.push(EndpointStatus { heading: h, values });
                }
            }
            _ => {}
        }
    }
}
