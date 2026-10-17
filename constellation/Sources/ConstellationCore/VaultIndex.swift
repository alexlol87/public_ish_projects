import Foundation

extension Vault {
    /// Parses Note text (links, headings, tags, frontmatter, Calls/Uses/Status). Pure; works on unsaved editor text too.
    public static func parse(_ text: String) -> ParsedNote { NoteParser.parse(text) }

    /// The Tag text typed after a `#` at the end of `line` (a `#` that would start a Tag), else nil.
    public static func typedTagPrefix(inLineBeforeCursor line: String) -> String? { TagIndex.typedPrefix(inLineBeforeCursor: line) }

    /// Note-relative, then Vault-relative image file; nil (show a placeholder) if missing or outside the Vault.
    public static func resolveImage(_ path: String, note: String, root: URL) -> URL? { ImagePaths.resolve(path, note: note, root: root) }
}

/// An open Vault: the folder tree plus search, Tag and parsed-Note indexes. Build once, then report changed paths to
/// `ingest(paths:)` (create, edit, delete and move all arrive as touched Vault-relative paths); only those are re-read.
/// Everything else here answers from memory. The app holds one of these and talks to the Vault only through it and `Vault`.
public final class VaultIndex {
    public let root: URL
    public private(set) var tree: VaultNode
    private var search: SearchIndex
    private var tags: TagIndex
    private var parsed: [String: ParsedNote]
    private var paths: Vault.PathIndex

    public init(root: URL) throws {
        self.root = root
        tree = try Vault.load(root: root)
        search = try SearchIndex(root: root)
        tags = try TagIndex(root: root)
        parsed = try Vault.parsedNotes(in: root)
        paths = Vault.PathIndex(parsed.keys.sorted())
    }

    public func ingest(paths touched: [String]) throws {
        tree = try tree.refreshed(paths: touched, root: root)
        try search.update(paths: touched)
        try tags.update(paths: touched)
        let alive = Vault.notePaths(in: tree)
        let aliveSet = Set(alive)
        parsed = parsed.filter { aliveSet.contains($0.key) }
        for t in touched {
            // A touched folder (created or moved in) brings its Notes along.
            for p in aliveSet.contains(t) ? [t] : t.lowercased().hasSuffix(".md") ? [] : alive.filter({ $0.hasPrefix(t + "/") }) {
                parsed[p] = (try? String(contentsOf: root.appendingPathComponent(p), encoding: .utf8)).map(Vault.parse)
            }
        }
        paths = Vault.PathIndex(alive)
    }

    public func search(_ query: String) -> SearchIndex.Results { search.search(query) }

    public func tagTree(sortedBy sort: TagIndex.Sort) -> [TagIndex.Node] { tags.tree(sortedBy: sort) }
    public func tagHits(for tag: String) -> [TagIndex.Hit] { tags.notes(for: tag) }
    public func tagCompletions(for prefix: String) -> [String] { tags.completions(for: prefix) }

    /// The graph for `filter`, optionally local to `around`; built from the parsed Notes in memory.
    public func graph(filter: GraphFilter, around: String? = nil) -> VaultGraph {
        Vault.graph(tree: tree, parsed: parsed, includeArchive: filter.includeArchive).filtered(filter, around: around)
    }

    public func backlinks(to path: String) -> [Backlink] { Vault.backlinks(to: path, parsed: parsed) }

    /// Text to offer after `[[` (see `Vault.completions`).
    public func completions(for typed: String) -> [String] { Vault.completions(for: typed, parsed: parsed) }

    /// Links in `text` (an open Note's current, maybe unsaved text) that are missing or ambiguous.
    public func brokenLinks(in text: String) -> [WikiLink] {
        Vault.parse(text).links.filter { if case .broken = paths.resolve($0.target) { true } else { false } }
    }

    public func repoStaleness(now: Date = Date()) -> [String: Staleness] { Vault.repoStaleness(parsed: parsed, now: now) }
}
