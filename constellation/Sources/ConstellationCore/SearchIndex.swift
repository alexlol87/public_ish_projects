import Foundation

/// In-memory search over a Vault's folder names, Note names and Note text. Case- and diacritic-insensitive substring match.
/// App-only files are never indexed. Build once with `init(root:)`, then feed touched paths to `update(paths:)`.
public struct SearchIndex {
    public struct TextMatch: Equatable, Sendable {
        public let path: String
        public let sentence: String
        /// Range of the hit inside `sentence` (UTF-16), for highlighting.
        public let hit: NSRange
        /// UTF-16 offset of the hit in the whole Note, for scrolling the editor.
        public let offset: Int
    }
    public struct Results: Equatable, Sendable {
        public var folders: [String] = []   // relative paths
        public var notes: [String] = []     // relative paths
        public var matches: [TextMatch] = []
        /// True for Notes in a Project's archive; the UI marks these "archived".
        public func isArchived(_ path: String) -> Bool { Vault.isArchive(path) }
    }

    private struct Entry { let folded: [UInt16]; let text: [UInt16]; let aligned: Bool; let foldedName: String; let tags: Set<String> }

    public static let maxMatches = 200
    public let root: URL
    private var folders = Set<String>()
    private var notes: [String: Entry] = [:]

    public init(root: URL) throws {
        self.root = root
        try add(folder: try Vault.load(root: root))
    }

    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    private mutating func add(folder: VaultNode) throws {
        for n in folder.children where !n.isAppOnly {
            if n.isFolder { folders.insert(n.relativePath); try add(folder: n) }
            else { try addNote(n.relativePath) }
        }
    }

    private mutating func addNote(_ path: String) throws {
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        let name = String(path.split(separator: "/").last ?? "").replacingOccurrences(of: ".md", with: "")
        let f = Array(Self.fold(text).utf16), t = Array(text.utf16)
        notes[path] = Entry(folded: f, text: t, aligned: f.count == t.count, foldedName: Self.fold(name),
                           tags: Set(NoteParser.parse(text).tags.flatMap { t in
                               let c = t.name.lowercased().split(separator: "/")
                               return (1...c.count).map { c[..<$0].joined(separator: "/") }
                           }))
    }

    /// Re-reads each touched path (create, edit, delete, move all arrive as paths). No full reload.
    public mutating func update(paths: [String]) throws {
        for path in paths {
            let parts = path.split(separator: "/")
            if parts.isEmpty || parts.contains(where: { $0.hasPrefix(".") }) || Vault.isAppOnly(path) { continue }
            folders = folders.filter { $0 != path && !$0.hasPrefix(path + "/") }
            notes = notes.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path, isDirectory: &isDir) else { continue }
            for i in 1..<parts.count { folders.insert(parts[..<i].joined(separator: "/")) }
            if isDir.boolValue {
                folders.insert(path)
                try add(folder: try Vault.load(folderAt: root.appendingPathComponent(path), relativePath: path))
            } else if path.lowercased().hasSuffix(".md") { try addNote(path) }
        }
    }

    public func search(_ query: String) -> Results {
        // `#tag` terms filter Notes (a parent Tag matches its children); the rest is the text query.
        var words: [Substring] = [], wanted: [String] = []
        for w in query.split(whereSeparator: \.isWhitespace) {
            if w.hasPrefix("#"), w.dropFirst().range(of: "^" + NoteParser.tagName + "$", options: .regularExpression) != nil { wanted.append(w.dropFirst().lowercased()) }
            else { words.append(w) }
        }
        let q = Self.fold(words.joined(separator: " "))
        var r = Results()
        let notes = wanted.isEmpty ? self.notes : self.notes.filter { e in wanted.allSatisfy { e.value.tags.contains($0) } }
        if !wanted.isEmpty, q.isEmpty { r.notes = notes.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }; return r }
        guard !q.isEmpty else { return r }
        let byPath = { (a: String, b: String) in a.localizedCaseInsensitiveCompare(b) == .orderedAscending }
        let qU = Array(q.utf16)
        r.folders = !wanted.isEmpty ? [] : folders.filter { Self.fold(String($0.split(separator: "/").last ?? "")).contains(q) }.sorted(by: byPath)
        r.notes = notes.filter { $0.value.foldedName.contains(q) }.keys.sorted(by: byPath)
        // Sort only the Notes that contain the query; sorting all of them dominates the cost at 5,000 Notes.
        let hits = notes.filter { Self.find(qU, in: $0.value.folded, from: 0) != nil }.keys.sorted(by: byPath)
        for path in hits where r.matches.count < Self.maxMatches {
            let e = notes[path]!
            var from = 0
            // shortcut: one match per sentence; if folding changed the text length the offsets can't be shared, so such Notes get no text matches.
            while e.aligned, r.matches.count < Self.maxMatches, let at = Self.find(qU, in: e.folded, from: from) {
                var s = at, t = at + qU.count
                while s > 0, !Self.isBreak(e.text, before: s) { s -= 1 }
                while t < e.text.count, !Self.isBreak(e.text, before: t) { t += 1 }
                while s < at, Self.isSpace(e.text[s]) { s += 1 }
                let sentence = String(decoding: e.text[s..<t], as: UTF16.self)
                r.matches.append(TextMatch(path: path, sentence: sentence, hit: NSRange(location: at - s, length: qU.count), offset: at))
                from = t
            }
        }
        return r
    }

    private static func find(_ needle: [UInt16], in hay: [UInt16], from: Int) -> Int? {
        var start = from
        while start + needle.count <= hay.count {
            let hit: Int? = hay.withUnsafeBytes { h in needle.withUnsafeBytes { n in
                guard let hb = h.baseAddress, let nb = n.baseAddress else { return nil }
                let skip = start * 2
                guard let p = memmem(hb + skip, h.count - skip, nb, n.count) else { return nil }
                return hb.distance(to: UnsafeRawPointer(p))
            } }
            guard let byte = hit else { return nil }
            if byte % 2 == 0 { return byte / 2 }
            start = byte / 2 + 1   // odd byte offset is not a UTF-16 boundary
        }
        return nil
    }

    /// True when a sentence ends just before index `i` (after . ! ? followed by space/end, or at a line break).
    private static func isBreak(_ u: [UInt16], before i: Int) -> Bool {
        if i >= u.count { return true }
        if i <= 0 { return true }
        let p = u[i - 1]
        if u[i] == 10 || u[i] == 13 { return true }
        if p == 10 || p == 13 { return true }
        return (p == 46 || p == 33 || p == 63) && isSpace(u[i])
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
}
