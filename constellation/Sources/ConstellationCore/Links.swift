import Foundation

public enum LinkResolution: Equatable {
    case note(String)
    /// Missing or ambiguous; `createPath` is where clicking the Link creates the Note.
    case broken(createPath: String)
}

public struct Backlink: Equatable {
    public let path: String  // the Note containing the Link
    public let link: WikiLink
}

extension Vault {
    /// All searchable Note paths (app-only files excluded), sorted.
    static func notePaths(in root: URL) throws -> [String] {
        func walk(_ n: VaultNode) -> [String] { n.isFolder ? n.children.flatMap(walk) : (n.isAppOnly || !n.relativePath.hasSuffix(".md") ? [] : [n.relativePath]) }
        return walk(try load(root: root)).sorted()
    }

    /// Resolves by Vault path first, else by a unique Note name (case-insensitive, `.md` optional).
    public static func resolve(_ target: String, in root: URL) throws -> LinkResolution {
        resolve(target, among: try notePaths(in: root))
    }

    static func resolve(_ target: String, among paths: [String]) -> LinkResolution {
        let t = target.lowercased().hasSuffix(".md") ? String(target.dropLast(3)) : target
        if let p = paths.first(where: { $0.dropLast(3).lowercased() == t.lowercased() }) { return .note(p) }
        let named = paths.filter { $0.split(separator: "/").last.map { $0.dropLast(3).lowercased() } == t.lowercased() }
        if named.count == 1 && !t.contains("/") { return .note(named[0]) }
        return .broken(createPath: t + ".md")
    }

    /// Creates the missing Note for a broken Link (empty file; folders as needed) and returns its path.
    @discardableResult
    public static func createNote(forLink target: String, in root: URL) throws -> String {
        guard case .broken(let path) = try resolve(target, in: root) else { return try resolve(target, in: root).path }
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: url, atomically: true, encoding: .utf8)
        return path
    }

    /// Links in other Notes that resolve to `path`, in path then text order.
    public static func backlinks(to path: String, in root: URL) throws -> [Backlink] {
        let paths = try notePaths(in: root)
        var out: [Backlink] = []
        for p in paths where p != path {
            let text = try String(contentsOf: root.appendingPathComponent(p), encoding: .utf8)
            for l in NoteParser.parse(text).links where resolve(l.target, among: paths) == .note(path) {
                out.append(Backlink(path: p, link: l))
            }
        }
        return out
    }

    /// Text to offer after `[[`: Note names, or `name#Heading` once the typed text contains `#`.
    public static func completions(for typed: String, in root: URL) throws -> [String] {
        let paths = try notePaths(in: root)
        if let hash = typed.firstIndex(of: "#") {
            let target = String(typed[..<hash]), prefix = typed[typed.index(after: hash)...].lowercased()
            guard case .note(let p) = resolve(target, among: paths) else { return [] }
            let text = try String(contentsOf: root.appendingPathComponent(p), encoding: .utf8)
            return NoteParser.parse(text).headings.filter { $0.title.lowercased().hasPrefix(prefix) }.map { "\(target)#\($0.title)" }
        }
        return paths.map { String($0.split(separator: "/").last!.dropLast(3)) }
            .filter { $0.lowercased().hasPrefix(typed.lowercased()) }
    }
}

extension LinkResolution {
    var path: String { if case .note(let p) = self { return p } else { return "" } }
}
