import Foundation

/// One change to one file. Commands (Archiver, later renames) return `[FileEdit]` instead of writing, so the app applies
/// them as one undoable step and tests can inspect them. `range` is UTF-16 in the file's current text.
public struct FileEdit: Equatable {
    public var path: String  // Vault-relative
    public var range: NSRange
    public var text: String
    /// The file does not exist yet; applying creates it (`range` is {0,0}).
    public var createsFile = false
    /// Undo of a creation: applying deletes the file.
    public var removesFile = false

    public init(path: String, range: NSRange, text: String, createsFile: Bool = false, removesFile: Bool = false) {
        self.path = path; self.range = range; self.text = text; self.createsFile = createsFile; self.removesFile = removesFile
    }

    /// Applies edits in order (give edits to one file back to front) and returns the inverse edits; applying those
    /// restores every file exactly. The app calls this once per user action and keeps the inverse for ⌘Z.
    @discardableResult
    public static func apply(_ edits: [FileEdit], root: URL) throws -> [FileEdit] {
        var inverse: [FileEdit] = []
        for e in edits {
            let url = root.appendingPathComponent(e.path)
            if e.removesFile {
                let old = try String(contentsOf: url, encoding: .utf8)
                try FileManager.default.removeItem(at: url)
                inverse.append(FileEdit(path: e.path, range: NSRange(location: 0, length: 0), text: old, createsFile: true))
                continue
            }
            let old = e.createsFile ? "" : try String(contentsOf: url, encoding: .utf8)
            let ns = old as NSString
            let replaced = ns.substring(with: e.range)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ns.replacingCharacters(in: e.range, with: e.text).write(to: url, atomically: true, encoding: .utf8)
            inverse.append(e.createsFile
                ? FileEdit(path: e.path, range: NSRange(location: 0, length: 0), text: "", removesFile: true)
                : FileEdit(path: e.path, range: NSRange(location: e.range.location, length: (e.text as NSString).length), text: replaced))
        }
        return inverse.reversed()
    }
}
