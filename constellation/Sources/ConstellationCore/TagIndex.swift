import Foundation

/// In-memory Tag index over a Vault. Tags are case-folded (lowercase); `a/b` rolls up into `a`.
/// App-only files are skipped. Build with `init(root:)`, feed touched paths to `update(paths:)` like `SearchIndex`.
public struct TagIndex {
    public struct Hit: Equatable, Sendable {
        public let path: String
        public let line: String   // the line containing the Tag
        public let offset: Int    // UTF-16 offset of the Tag in the Note
    }
    public struct Node: Equatable, Sendable {
        public let tag: String    // full lowercase path, e.g. "team/payments"
        public let count: Int     // Notes holding this Tag or any child
        public let children: [Node]
        public var name: String { String(tag.split(separator: "/").last ?? "") }
    }
    public enum Sort { case name, count }

    private struct Occ { let tag: String; let line: String; let offset: Int }
    public let root: URL
    private var notes: [String: [Occ]] = [:]

    public init(root: URL) throws {
        self.root = root
        try add(folder: try Vault.load(root: root))
    }

    private mutating func add(folder: VaultNode) throws {
        for n in folder.children where !n.isAppOnly {
            if n.isFolder { try add(folder: n) } else { try addNote(n.relativePath) }
        }
    }

    private mutating func addNote(_ path: String) throws {
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        let ns = text as NSString
        notes[path] = NoteParser.parse(text).tags.map { t in
            let line = ns.substring(with: ns.lineRange(for: t.range)).trimmingCharacters(in: .whitespacesAndNewlines)
            return Occ(tag: t.name.lowercased(), line: line, offset: t.range.location)
        }
    }

    public mutating func update(paths: [String]) throws {
        for path in paths {
            let parts = path.split(separator: "/")
            if parts.isEmpty || parts.contains(where: { $0.hasPrefix(".") }) || Vault.isAppOnly(path) { continue }
            notes = notes.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path, isDirectory: &isDir) else { continue }
            if isDir.boolValue { try add(folder: try Vault.load(folderAt: root.appendingPathComponent(path), relativePath: path)) }
            else if path.lowercased().hasSuffix(".md") { try addNote(path) }
        }
    }

    private static func matches(_ tag: String, _ query: String) -> Bool { tag == query || tag.hasPrefix(query + "/") }

    /// Foldable tree of every Tag with its Note count, parents rolled up.
    public func tree(sortedBy sort: Sort) -> [Node] {
        var paths: [String: Set<String>] = [:]  // tag (and each ancestor) -> Notes
        for (path, occs) in notes {
            for o in occs {
                var comps: [Substring] = []
                for c in o.tag.split(separator: "/") { comps.append(c); paths[comps.joined(separator: "/"), default: []].insert(path) }
            }
        }
        func build(_ parent: String?) -> [Node] {
            let kids = paths.keys.filter { k in
                guard let parent else { return !k.contains("/") }
                return k.hasPrefix(parent + "/") && !k.dropFirst(parent.count + 1).contains("/")
            }
            return kids.map { Node(tag: $0, count: paths[$0]!.count, children: build($0)) }.sorted {
                if sort == .count, $0.count != $1.count { return $0.count > $1.count }
                return $0.tag < $1.tag
            }
        }
        return build(nil)
    }

    /// Notes holding the Tag (or a child Tag), one hit per line, ordered by path then position.
    public func notes(for tag: String) -> [Hit] {
        let q = tag.lowercased()
        var out: [Hit] = []
        for path in notes.keys.sorted() {
            var seen = Set<String>()
            for o in notes[path]! where Self.matches(o.tag, q) && seen.insert(o.line).inserted {
                out.append(Hit(path: path, line: o.line, offset: o.offset))
            }
        }
        return out
    }

    /// Existing Tags (and their parents) starting with `prefix`, for `#` autocomplete.
    public func completions(for prefix: String) -> [String] {
        let q = prefix.lowercased()
        var all = Set<String>()
        for occs in notes.values { for o in occs {
            var comps: [Substring] = []
            for c in o.tag.split(separator: "/") { comps.append(c); all.insert(comps.joined(separator: "/")) }
        } }
        return all.filter { $0.hasPrefix(q) }.sorted()
    }

    /// The Tag text typed after a `#` at the end of `line` (a `#` that would start a Tag), else nil.
    public static func typedPrefix(inLineBeforeCursor line: String) -> String? {
        let ns = line as NSString
        guard let m = NoteParser.typedTagRe.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
