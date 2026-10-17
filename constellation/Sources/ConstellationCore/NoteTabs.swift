import Foundation

extension Vault {
    /// Overwrites a Note's file (atomic, so a crash never leaves half a file).
    public static func writeNote(_ note: VaultNode, in root: URL, text: String) throws {
        try text.write(to: root.appendingPathComponent(note.relativePath), atomically: true, encoding: .utf8)
    }
}

/// Open Notes (tabs), their text and unsaved edits. Pure state; the app owns the timer and calls `saveDue`.
public struct NoteTabs {
    public static let autosaveDelay: TimeInterval = 1
    public let root: URL
    public private(set) var paths: [String] = []
    public private(set) var active: String?
    private var texts: [String: String] = [:]
    private var lastEdit: [String: Date] = [:]  // present = unsaved

    public init(root: URL) { self.root = root }

    public func text(_ path: String) -> String? { texts[path] }
    public var hasPendingEdits: Bool { !lastEdit.isEmpty }

    /// Opens (reads) a Note, or just focuses it if it is already open.
    public mutating func open(_ path: String) throws {
        if texts[path] == nil {
            texts[path] = try Vault.readNote(Self.node(path), in: root)
            paths.append(path)
        }
        active = path
    }

    public mutating func edit(_ path: String, text: String, at now: Date = Date()) {
        guard texts[path] != nil, texts[path] != text else { return }
        texts[path] = text
        lastEdit[path] = now
    }

    /// Saves Notes whose last keystroke was at least `autosaveDelay` ago.
    public mutating func saveDue(at now: Date = Date()) throws {
        for (p, t) in lastEdit where now.timeIntervalSince(t) >= Self.autosaveDelay { try save(p) }
    }

    /// Saves every unsaved Note (quit, window close).
    public mutating func saveAll() throws { for p in Array(lastEdit.keys) { try save(p) } }

    public mutating func close(_ path: String) throws {
        guard let i = paths.firstIndex(of: path) else { return }
        try save(path)
        paths.remove(at: i)
        texts[path] = nil
        if active == path { active = paths.isEmpty ? nil : paths[min(i, paths.count - 1)] }
    }

    private mutating func save(_ path: String) throws {
        guard lastEdit[path] != nil, let text = texts[path] else { return }
        try Vault.writeNote(Self.node(path), in: root, text: text)
        lastEdit[path] = nil
    }

    private static func node(_ path: String) -> VaultNode {
        VaultNode(name: String(path.split(separator: "/").last ?? ""), relativePath: path, isFolder: false, children: [])
    }
}
