import Foundation

/// A folder or markdown Note inside a Vault. `relativePath` is from the Vault root, "/"-separated.
public struct VaultNode: Equatable, Identifiable, Sendable {
    public let name: String
    public let relativePath: String
    public let isFolder: Bool
    public let children: [VaultNode]
    public var id: String { relativePath }
}

/// The Vault seam: reads a folder of markdown Notes. Foundation only.
public enum Vault {
    /// Returns the root folder node. Lists folders and `.md` files; hidden entries are skipped.
    /// Folders come first, then Notes, each sorted by name.
    public static func load(root: URL) throws -> VaultNode {
        VaultNode(name: root.lastPathComponent, relativePath: "", isFolder: true,
                  children: try children(of: root, prefix: ""))
    }

    public static func readNote(_ note: VaultNode, in root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(note.relativePath), encoding: .utf8)
    }

    private static func children(of dir: URL, prefix: String) throws -> [VaultNode] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var folders: [VaultNode] = [], notes: [VaultNode] = []
        for url in urls {
            let name = url.lastPathComponent
            let path = prefix + name
            if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                folders.append(VaultNode(name: name, relativePath: path, isFolder: true,
                                         children: try children(of: url, prefix: path + "/")))
            } else if url.pathExtension.lowercased() == "md" {
                notes.append(VaultNode(name: name, relativePath: path, isFolder: false, children: []))
            }
        }
        let byName = { (a: VaultNode, b: VaultNode) in a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
        return folders.sorted(by: byName) + notes.sorted(by: byName)
    }
}
