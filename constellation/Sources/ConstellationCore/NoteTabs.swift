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
    private var onDisk: [String: String] = [:]  // last text we read or wrote; tells our own save echoes from outside edits
    private var conflicts: [String: String] = [:]  // disk text waiting for the "Reload from disk / Keep mine" choice
    private var revisions: [String: Int] = [:]

    /// Disk text for a Note with unsaved edits that also changed on disk (show the banner); nil = no conflict.
    public func conflict(_ path: String) -> String? { conflicts[path] }
    /// Bumps each time the text is replaced from disk; the app uses it to rebuild the editor view.
    public func revision(_ path: String) -> Int { revisions[path, default: 0] }
    public var hasConflicts: Bool { !conflicts.isEmpty }

    /// Feed paths FSEvents reported as changed. Clean open Notes reload silently; dirty ones get a conflict.
    public mutating func diskChanged(_ changed: [String]) {
        for p in changed where texts[p] != nil {
            guard let disk = try? Vault.readNote(Self.node(p), in: root), disk != onDisk[p] else { continue }
            if lastEdit[p] == nil { adopt(p, disk) } else { conflicts[p] = disk }
        }
    }

    /// `reload`: take the disk text (mine is dropped). Otherwise keep mine and save it over the disk text now.
    public mutating func resolveConflict(_ path: String, reload: Bool) throws {
        guard let disk = conflicts[path] else { return }
        conflicts[path] = nil
        if reload { adopt(path, disk) } else { onDisk[path] = disk; try save(path) }
    }

    private mutating func adopt(_ path: String, _ disk: String) {
        texts[path] = disk; onDisk[path] = disk; lastEdit[path] = nil; conflicts[path] = nil
        revisions[path, default: 0] += 1
    }

    public init(root: URL) { self.root = root }

    public func text(_ path: String) -> String? { texts[path] }
    public var hasPendingEdits: Bool { !lastEdit.isEmpty }

    /// Opens (reads) a Note, or just focuses it if it is already open.
    public mutating func open(_ path: String) throws {
        if texts[path] == nil {
            let t = try Vault.readNote(Self.node(path), in: root)
            texts[path] = t; onDisk[path] = t
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

    /// Saves, then closes. A Note with a pending conflict stays open: closing would drop my edits or overwrite the disk text.
    public mutating func close(_ path: String) throws {
        guard let i = paths.firstIndex(of: path), conflicts[path] == nil else { return }
        try save(path)
        paths.remove(at: i)
        texts[path] = nil; onDisk[path] = nil; conflicts[path] = nil
        if active == path { active = paths.isEmpty ? nil : paths[min(i, paths.count - 1)] }
    }

    /// Rebuilds every open tab from disk after `edits` were applied (renames, moves, their undo and redo). A moved Note's
    /// tab follows it to the new path, tabs whose file is gone are dropped, and revisions are bumped so editors reload.
    public mutating func reloadAfter(_ edits: [FileEdit]) {
        let removed = edits.filter(\.removesFile).map(\.path), created = edits.filter(\.createsFile).map(\.path)
        let moved = removed.count == created.count ? Dictionary(zip(removed, created), uniquingKeysWith: { a, _ in a }) : [:]
        let (oldPaths, oldActive, oldRevisions) = (paths, active, revisions)
        self = NoteTabs(root: root)
        for p in oldPaths {
            let now = moved[p] ?? p
            guard (try? open(now)) != nil else { continue }
            revisions[now] = oldRevisions[p, default: 0] + 1
        }
        if let a = oldActive { try? open(moved[a] ?? a) }
    }

    private mutating func save(_ path: String) throws {
        guard lastEdit[path] != nil, conflicts[path] == nil, let text = texts[path] else { return }
        try Vault.writeNote(Self.node(path), in: root, text: text)
        lastEdit[path] = nil; onDisk[path] = text
    }

    private static func node(_ path: String) -> VaultNode {
        VaultNode(name: String(path.split(separator: "/").last ?? ""), relativePath: path, isFolder: false, children: [])
    }
}
