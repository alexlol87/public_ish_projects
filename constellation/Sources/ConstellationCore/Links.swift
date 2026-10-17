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
    static func notePaths(in root: URL) throws -> [String] { notePaths(in: try load(root: root)) }

    static func notePaths(in tree: VaultNode) -> [String] {
        func walk(_ n: VaultNode) -> [String] { n.isFolder ? n.children.flatMap(walk) : (n.isAppOnly || !n.relativePath.hasSuffix(".md") ? [] : [n.relativePath]) }
        return walk(tree).sorted()
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

    /// `resolve(_:among:)` with dictionary lookups, for resolving many Links against one path list (the graph).
    struct PathIndex {
        private var byPath: [String: String] = [:], byName: [String: [String]] = [:]
        init(_ paths: [String]) {
            for p in paths {
                let key = p.dropLast(3).lowercased()
                if byPath[key] == nil { byPath[key] = p }
                byName[p.split(separator: "/").last.map { $0.dropLast(3).lowercased() } ?? "", default: []].append(p)
            }
        }
        func resolve(_ target: String) -> LinkResolution {
            let t = (target.lowercased().hasSuffix(".md") ? String(target.dropLast(3)) : target).lowercased()
            if let p = byPath[t] { return .note(p) }
            if let named = byName[t], named.count == 1, !t.contains("/") { return .note(named[0]) }
            return .broken(createPath: (target.lowercased().hasSuffix(".md") ? String(target.dropLast(3)) : target) + ".md")
        }
    }

    /// The edit that creates the missing Note for a broken Link (empty file, folders as needed); none if the Link resolves.
    /// `resolve` tells where it lands. Writes nothing: the caller applies the edits.
    public static func createNote(forLink target: String, in root: URL) throws -> [FileEdit] {
        guard case .broken(let path) = try resolve(target, in: root) else { return [] }
        return [FileEdit(path: path, range: NSRange(location: 0, length: 0), text: "", createsFile: true)]
    }

    /// Links in other Notes that resolve to `path`, in path then text order.
    public static func backlinks(to path: String, in root: URL) throws -> [Backlink] {
        backlinks(to: path, parsed: try parsedNotes(in: root))
    }

    static func backlinks(to path: String, parsed: [String: ParsedNote]) -> [Backlink] {
        let paths = parsed.keys.sorted()
        var out: [Backlink] = []
        for p in paths where p != path {
            for l in parsed[p]!.links where resolve(l.target, among: paths) == .note(path) { out.append(Backlink(path: p, link: l)) }
        }
        return out
    }

    /// Text to offer after `[[`: Note names, or `name#Heading` once the typed text contains `#`.
    public static func completions(for typed: String, in root: URL) throws -> [String] {
        completions(for: typed, parsed: try parsedNotes(in: root))
    }

    static func completions(for typed: String, parsed: [String: ParsedNote]) -> [String] {
        let paths = parsed.keys.sorted()
        if let hash = typed.firstIndex(of: "#") {
            let target = String(typed[..<hash]), prefix = typed[typed.index(after: hash)...].lowercased()
            guard case .note(let p) = resolve(target, among: paths) else { return [] }
            return parsed[p]!.headings.filter { $0.title.lowercased().hasPrefix(prefix) }.map { "\(target)#\($0.title)" }
        }
        return paths.map { String($0.split(separator: "/").last!.dropLast(3)) }
            .filter { $0.lowercased().hasPrefix(typed.lowercased()) }
    }
}
