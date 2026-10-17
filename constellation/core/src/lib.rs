//! Constellation core: parses a Vault of markdown Notes and answers search, Tag, link and graph questions.
//! Every text offset and range in the public API is in UTF-16 code units, as in JavaScript.

pub mod agent_files;
pub mod archiver;
pub mod edit;
pub mod graph;
pub mod index;
pub mod links;
pub mod parser;
pub mod renames;
pub mod search;
pub mod staleness;
pub mod tags;
pub mod text;
pub mod vault;

pub use edit::FileEdit;
pub use graph::{EndpointRef, EndpointRelations, GraphEdge, GraphFilter, GraphNode, VaultGraph};
pub use index::VaultIndex;
pub use links::{Backlink, LinkResolution};
pub use parser::{ParsedNote, WikiLink};
pub use staleness::Staleness;
pub use text::Range16;
pub use vault::VaultNode;

/// The error type of every fallible call: a message fit to show the user.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error(pub String);

pub type Result<T> = std::result::Result<T, Error>;

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Error {}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error(e.to_string())
    }
}

impl serde::Serialize for Error {
    fn serialize<S: serde::Serializer>(&self, s: S) -> std::result::Result<S::Ok, S::Error> {
        s.serialize_str(&self.0)
    }
}
