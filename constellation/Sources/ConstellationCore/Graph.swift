import Foundation

public struct GraphNode: Equatable, Identifiable {
    public enum Kind { case note, folder, ghost }
    public let id: String  // Vault path; ghosts are "ghost:<createPath>"
    public let name: String
    public let kind: Kind
}

public struct GraphEdge: Equatable {
    /// Calls and Uses (ticket 11) add cases here.
    public enum Kind { case containment, link }
    public let from: String
    public let to: String
    public let kind: Kind
}

public struct VaultGraph: Equatable {
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]

    /// What clicking a Node opens: a Note itself, a folder's README.md; nil for ghosts and folders without one.
    public func openPath(for id: String) -> String? {
        guard let n = nodes.first(where: { $0.id == id }) else { return nil }
        switch n.kind {
        case .note: return id
        case .ghost: return nil
        case .folder:
            let readme = id.isEmpty ? "README.md" : id + "/README.md"
            return nodes.contains { $0.id == readme } ? readme : nil
        }
    }

    /// Ids joined to `id` by any edge, sorted.
    public func neighbours(of id: String) -> [String] {
        Set(edges.compactMap { $0.from == id ? $0.to : $0.to == id ? $0.from : nil }).sorted()
    }
}

extension Vault {
    /// Every Note and folder is a Node; Containment and Link edges; broken Links become ghost Nodes. App-only files are left out.
    public static func graph(in root: URL) throws -> VaultGraph {
        let tree = try load(root: root)
        let paths = try notePaths(in: root)
        var nodes: [GraphNode] = [], edges: [GraphEdge] = []
        func walk(_ n: VaultNode) {
            for c in n.children where !c.isAppOnly && (c.isFolder || c.relativePath.hasSuffix(".md")) {
                nodes.append(GraphNode(id: c.relativePath, name: c.name, kind: c.isFolder ? .folder : .note))
                edges.append(GraphEdge(from: n.relativePath, to: c.relativePath, kind: .containment))
                if c.isFolder { walk(c) }
            }
        }
        nodes.append(GraphNode(id: "", name: root.lastPathComponent, kind: .folder))
        walk(tree)
        var ghosts = Set<String>(), seen = Set<String>()
        for p in paths {
            let text = try String(contentsOf: root.appendingPathComponent(p), encoding: .utf8)
            for l in NoteParser.parse(text).links {
                var to: String
                switch resolve(l.target, among: paths) {
                case .note(let t): to = t
                case .broken(let create):
                    to = "ghost:" + create.lowercased()
                    if ghosts.insert(to).inserted {
                        nodes.append(GraphNode(id: to, name: String(create.dropLast(3)), kind: .ghost))
                    }
                }
                if to != p, seen.insert(p + "\n" + to).inserted { edges.append(GraphEdge(from: p, to: to, kind: .link)) }
            }
        }
        return VaultGraph(nodes: nodes, edges: edges)
    }
}
