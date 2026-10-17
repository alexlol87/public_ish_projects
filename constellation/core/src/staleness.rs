//! How long ago a Repo was verified (README frontmatter `verified_on: YYYY-MM-DD`).

use crate::parser::ParsedNote;
use chrono::NaiveDate;
use serde::Serialize;
use std::collections::BTreeMap;

pub const DEFAULT_THRESHOLD: i64 = 30;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum Staleness {
    Verified { days: i64 },
    Never,
    Malformed,
}

impl Staleness {
    /// `now` is today's date in UTC.
    pub fn of(verified_on: Option<&str>, now: NaiveDate) -> Self {
        let Some(s) = verified_on.map(str::trim).filter(|s| !s.is_empty()) else { return Self::Never };
        // The round trip rejects loose forms such as "2026-6-5".
        match NaiveDate::parse_from_str(s, "%Y-%m-%d") {
            Ok(d) if d.format("%Y-%m-%d").to_string() == s => Self::Verified { days: (now - d).num_days() },
            _ => Self::Malformed,
        }
    }

    /// Past the threshold, never verified, or unreadable.
    pub fn is_stale(&self, threshold: i64) -> bool {
        !matches!(self, Self::Verified { days } if *days <= threshold)
    }

    pub fn label(&self) -> String {
        match self {
            Self::Verified { days } if *days <= 0 => "verified today".into(),
            Self::Verified { days } => format!("verified {days} day{} ago", if *days == 1 { "" } else { "s" }),
            Self::Never => "never verified".into(),
            Self::Malformed => "verified date unreadable".into(),
        }
    }
}

pub fn today() -> NaiveDate {
    chrono::Utc::now().date_naive()
}

/// Vault-relative Repo folder -> staleness, for every `<folder>/README.md` with `type: repo`.
pub fn repo_staleness(parsed: &BTreeMap<String, ParsedNote>, now: NaiveDate) -> BTreeMap<String, Staleness> {
    parsed
        .iter()
        .filter(|(_, n)| n.note_type == "repo")
        .filter_map(|(path, n)| {
            let (dir, file) = path.rsplit_once('/')?;
            file.eq_ignore_ascii_case("readme.md")
                .then(|| (dir.to_string(), Staleness::of(n.frontmatter.get("verified_on").map(String::as_str), now)))
        })
        .collect()
}
