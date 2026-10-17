import Foundation

/// A folder or markdown Note inside a Vault. `relativePath` is from the Vault root, "/"-separated.
public struct VaultNode: Equatable, Identifiable, Sendable {
    public let name: String
    public let relativePath: String
    public let isFolder: Bool
    public let children: [VaultNode]
    public var id: String { relativePath }
    /// App-only files show in the tree but are excluded from search and the graph.
    public var isAppOnly: Bool { Vault.isAppOnly(relativePath) }
}

/// The Vault seam: reads a folder of markdown Notes. Foundation only.
public enum Vault {
    /// Returns the root folder node. Lists folders and `.md` files; hidden entries are skipped.
    /// Folders come first, then Notes, each sorted by name.
    public static func load(root: URL) throws -> VaultNode {
        VaultNode(name: root.lastPathComponent, relativePath: "", isFolder: true,
                  children: try children(of: root, prefix: ""))
    }

    static func load(folderAt dir: URL, relativePath: String) throws -> VaultNode {
        VaultNode(name: dir.lastPathComponent, relativePath: relativePath, isFolder: true,
                  children: try children(of: dir, prefix: relativePath.isEmpty ? "" : relativePath + "/"))
    }

    static func sorted(_ nodes: [VaultNode]) -> [VaultNode] {
        let byName = { (a: VaultNode, b: VaultNode) in a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
        return nodes.filter(\.isFolder).sorted(by: byName) + nodes.filter { !$0.isFolder }.sorted(by: byName)
    }

    public struct NotEmpty: Error {}

    private static let appOnlyTop: Set<String> = ["AGENTS.md", "repos.txt", "tags.md", "templates", ".constellation"]

    /// True for the app's own files (top level only) and anything inside its folders.
    public static func isAppOnly(_ relativePath: String) -> Bool {
        appOnlyTop.contains(String(relativePath.split(separator: "/").first ?? ""))
    }

    /// Writes the starter files into an empty (or missing) folder. Throws `NotEmpty` rather than touch existing files.
    public static func create(at root: URL) throws {
        let fm = FileManager.default
        if let existing = try? fm.contentsOfDirectory(atPath: root.path), !existing.isEmpty { throw NotEmpty() }
        for d in ["templates", "external", "clients", ".constellation"] {
            try fm.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        let files = [
            "README.md": "# Vault\n\nWhat this vault covers.\n",
            "AGENTS.md": "# Agent rules\n\nPlaceholder.\n",
            "repos.txt": "# One repository name per line.\n",
            "tags.md": "# Tags\n\n- #example: what this tag means\n",
        ]
        for (name, text) in files { try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8) }
    }

    /// The remembered Vault folder, or nil if none was saved or it no longer exists (show the first-launch choice).
    public static func reopenable(_ savedPath: String?) -> URL? {
        var isDir: ObjCBool = false
        guard let savedPath, FileManager.default.fileExists(atPath: savedPath, isDirectory: &isDir), isDir.boolValue else { return nil }
        return URL(fileURLWithPath: savedPath)
    }

    public static func readNote(_ note: VaultNode, in root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(note.relativePath), encoding: .utf8)
    }

    private static func children(of dir: URL, prefix: String) throws -> [VaultNode] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        var folders: [VaultNode] = [], notes: [VaultNode] = []
        for url in urls {
            let name = url.lastPathComponent
            if name.hasPrefix(".") && !(prefix.isEmpty && name == ".constellation") { continue }
            let path = prefix + name
            if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                folders.append(VaultNode(name: name, relativePath: path, isFolder: true,
                                         children: try children(of: url, prefix: path + "/")))
            } else if url.pathExtension.lowercased() == "md" || isAppOnly(path) {
                notes.append(VaultNode(name: name, relativePath: path, isFolder: false, children: []))
            }
        }
        let byName = { (a: VaultNode, b: VaultNode) in a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
        return folders.sorted(by: byName) + notes.sorted(by: byName)
    }
}

extension VaultNode {
    /// Applies external file-system changes (create, modify, delete, move all arrive as touched paths) by re-reading
    /// each touched path's parent folder from disk. Vanished folders are dropped; unreadable ones are left as they were.
    /// shortcut: re-lists whole parent folders, fine for notes-sized Vaults; switch to per-entry patches if one gets huge.
    public func refreshed(paths: [String], root: URL) throws -> VaultNode {
        var tree = self
        for path in paths {
            let parts = path.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }
            tree = try tree.replacing(folder: Array(parts.dropLast()), at: 0, dir: root, prefix: "")
        }
        return tree
    }

    private func replacing(folder parts: [String], at i: Int, dir: URL, prefix: String) throws -> VaultNode {
        var kids = children
        if i < parts.count {
            let name = parts[i], path = prefix + name
            let sub = dir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue else {
                return VaultNode(name: self.name, relativePath: relativePath, isFolder: true, children: kids.filter { $0.relativePath != path })
            }
            if let idx = kids.firstIndex(where: { $0.relativePath == path && $0.isFolder }) {
                kids[idx] = try kids[idx].replacing(folder: parts, at: i + 1, dir: sub, prefix: path + "/")
            } else if !name.hasPrefix(".") || (prefix.isEmpty && name == ".constellation") {
                kids.append(try Vault.load(folderAt: sub, relativePath: path))
                kids = Vault.sorted(kids)
            }
            return VaultNode(name: self.name, relativePath: relativePath, isFolder: true, children: kids)
        }
        let fresh = try Vault.load(folderAt: dir, relativePath: relativePath)
        return VaultNode(name: name, relativePath: relativePath, isFolder: true, children: fresh.children)
    }
}
