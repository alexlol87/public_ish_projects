import Foundation

/// One file change. Commands return these instead of writing; the app applies them as one undoable step.
public enum FileEdit: Equatable {
    case write(path: String, text: String)   // Vault-relative; creates folders as needed
    case move(from: String, to: String)
}

extension Vault {
    public struct RenameError: Error { public let message: String }

    /// Applies edits in order and returns the edits that undo them (apply those for one ⌘Z). Writes must target existing files.
    @discardableResult
    public static func apply(_ edits: [FileEdit], in root: URL) throws -> [FileEdit] {
        var undo: [FileEdit] = []
        let fm = FileManager.default
        for e in edits {
            switch e {
            case .write(let path, let text):
                let url = root.appendingPathComponent(path)
                undo.append(.write(path: path, text: try String(contentsOf: url, encoding: .utf8)))
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            case .move(let from, let to):
                let dst = root.appendingPathComponent(to)
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: root.appendingPathComponent(from), to: dst)
                undo.append(.move(from: to, to: from))
            }
        }
        return undo.reversed()
    }

    public static func renameNote(_ path: String, to newName: String, in root: URL) throws -> [FileEdit] {
        let folder = (path as NSString).deletingLastPathComponent
        let name = newName.hasSuffix(".md") ? newName : newName + ".md"
        return try moveNote(path, to: folder.isEmpty ? name : folder + "/" + name, in: root)
    }

    public static func moveNote(_ path: String, toFolder folder: String, in root: URL) throws -> [FileEdit] {
        let name = (path as NSString).lastPathComponent
        return try moveNote(path, to: folder.isEmpty ? name : folder + "/" + name, in: root)
    }

    static func moveNote(_ old: String, to new: String, in root: URL) throws -> [FileEdit] {
        let before = try notePaths(in: root)
        guard before.contains(old) else { throw RenameError(message: "No such Note: \(old)") }
        guard old != new else { return [] }
        guard !FileManager.default.fileExists(atPath: root.appendingPathComponent(new).path) else { throw RenameError(message: "\(new) already exists") }
        let after = before.map { $0 == old ? new : $0 }
        let newName = String(((new as NSString).lastPathComponent as NSString).deletingPathExtension)
        var edits = try rewriteLinks(to: old, among: before, newTarget: { link in
            let hadMd = link.target.lowercased().hasSuffix(".md"), pathStyle = link.target.contains("/")
            if !pathStyle, resolve(link.target, among: after) == .note(new) { return link.target }  // still resolves: leave as written
            var t = pathStyle ? String(new.dropLast(3)) : newName
            if !pathStyle, resolve(t, among: after) != .note(new) { t = String(new.dropLast(3)) }  // name now ambiguous
            return hadMd ? t + ".md" : t
        }, headingTo: { $0 }, in: root)
        edits.append(.move(from: old, to: new))
        return edits
    }

    /// Renames the first heading titled `old` in `notePath` and rewrites `[[note#old]]` Links (Calls and Uses included).
    public static func renameHeading(_ old: String, to new: String, inNote notePath: String, in root: URL) throws -> [FileEdit] {
        let paths = try notePaths(in: root)
        let text = try String(contentsOf: root.appendingPathComponent(notePath), encoding: .utf8)
        guard let h = NoteParser.parse(text).headings.first(where: { $0.title == old }) else { throw RenameError(message: "No heading \(old)") }
        let hashes = String(repeating: "#", count: h.level)
        return try rewriteLinks(to: notePath, among: paths, newTarget: { $0.target }, headingTo: { $0.lowercased() == old.lowercased() ? new : $0 }, in: root,
                                     extra: [notePath: [(h.range, hashes + " " + new)]])
    }

    /// Renames a Tag and its children (`a/b` -> `c` also turns `a/b/x` into `c/x`) in text and frontmatter, case-insensitively.
    public static func renameTag(_ old: String, to new: String, in root: URL) throws -> [FileEdit] {
        let o = old.lowercased()
        var edits: [FileEdit] = []
        for p in try notePaths(in: root) {
            let text = try String(contentsOf: root.appendingPathComponent(p), encoding: .utf8)
            let ns = text as NSString
            let reps: [(NSRange, String)] = NoteParser.parse(text).tags.compactMap { t in
                let l = t.name.lowercased()
                guard l == o || l.hasPrefix(o + "/") else { return nil }
                let inline = ns.substring(with: t.range).hasPrefix("#")
                return (t.range, (inline ? "#" : "") + new + t.name.dropFirst(old.count))
            }
            if !reps.isEmpty { edits.append(.write(path: p, text: replacing(text, reps))) }
        }
        return edits
    }

    // MARK: helpers

    private static func replacing(_ text: String, _ reps: [(NSRange, String)]) -> String {
        let out = NSMutableString(string: text)
        for (r, s) in reps.sorted(by: { $0.0.location > $1.0.location }) { out.replaceCharacters(in: r, with: s) }
        return out as String
    }

    /// One `.write` per Note whose Links resolve to `target` (plus `extra` replacements, e.g. a heading line).
    private static func rewriteLinks(to target: String, among paths: [String], newTarget: (WikiLink) -> String, headingTo: (String) -> String,
                                     in root: URL, extra: [String: [(NSRange, String)]] = [:]) throws -> [FileEdit] {
        var edits: [FileEdit] = []
        for p in paths {
            let text = try String(contentsOf: root.appendingPathComponent(p), encoding: .utf8)
            var reps = extra[p] ?? []
            for l in NoteParser.parse(text).links where resolve(l.target, among: paths) == .note(target) {
                let t = newTarget(l), h = l.heading.map(headingTo)
                let s = "[[" + t + (h.map { "#" + $0 } ?? "") + (l.alias.map { "|" + $0 } ?? "") + "]]"
                if s != (text as NSString).substring(with: l.range) { reps.append((l.range, s)) }
            }
            if !reps.isEmpty { edits.append(.write(path: p, text: replacing(text, reps))) }
        }
        return edits
    }
}
