import Foundation

public struct GraphNode: Equatable, Identifiable {
    public enum Kind { case note, folder, ghost }
    public let id: String  // Vault path; ghosts are "ghost:<createPath>"
    public let name: String
    public let kind: Kind
    public var noteType: String? = nil  // frontmatter type for notes; nil for folders and ghosts
}

/// One Endpoint-level Call (or a Client Use, where `from` is "") folded into a Note-to-Note edge.
public struct EndpointPair: Equatable {
    public let from: String
    public let to: String
}

public struct GraphEdge: Equatable {
    public enum Kind { case containment, link, call, uses }
    public let from: String
    public let to: String
    public let kind: Kind
    public var pairs: [EndpointPair] = []  // call/uses edges: what the edge folds, for hover
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
    /// Archive Notes are left out unless `includeArchive`. Every Note and folder is a Node; Containment and Link edges; broken Links become ghost Nodes. App-only files are left out.
    public static func graph(in root: URL, includeArchive: Bool = false) throws -> VaultGraph {
        let tree = try load(root: root)
        let paths = try notePaths(in: root).filter { includeArchive || !isArchive($0) }
        var nodes: [GraphNode] = [], edges: [GraphEdge] = []
        func walk(_ n: VaultNode) {
            for c in n.children where !c.isAppOnly && (includeArchive || !isArchive(c.relativePath)) && (c.isFolder || c.relativePath.hasSuffix(".md")) {
                nodes.append(GraphNode(id: c.relativePath, name: c.name, kind: c.isFolder ? .folder : .note))
                edges.append(GraphEdge(from: n.relativePath, to: c.relativePath, kind: .containment))
                if c.isFolder { walk(c) }
            }
        }
        nodes.append(GraphNode(id: "", name: root.lastPathComponent, kind: .folder))
        walk(tree)
        var ghosts = Set<String>(), seen = Set<String>()
        var folded: [String: Int] = [:]  // "kind from>to" -> index in edges
        func fold(_ kind: GraphEdge.Kind, _ from: String, _ target: String, _ pair: EndpointPair) {
            guard case .note(let to) = resolve(target, among: paths), to != from else { return }
            let key = "\(kind) \(from)>\(to)"
            if let i = folded[key] { edges[i].pairs.append(pair) } else {
                folded[key] = edges.count
                edges.append(GraphEdge(from: from, to: to, kind: kind, pairs: [pair]))
            }
        }
        for p in paths {
            let text = try String(contentsOf: root.appendingPathComponent(p), encoding: .utf8)
            let parsed = NoteParser.parse(text)
            if let i = nodes.firstIndex(where: { $0.id == p }) { nodes[i].noteType = parsed.type }
            for s in parsed.calls { for l in s.links { fold(.call, p, l.target, EndpointPair(from: s.heading.title, to: l.heading ?? "")) } }
            for s in parsed.uses { for l in s.links { fold(.uses, p, l.target, EndpointPair(from: "", to: l.heading ?? "")) } }
            for l in parsed.links {
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

public struct EndpointRef: Equatable {
    public let path: String
    public let heading: String?  // nil for a Client (Uses are per Note)
}

public struct EndpointRelations: Equatable {
    public var callsOut: [EndpointRef] = [], callsIn: [EndpointRef] = [], usesIn: [EndpointRef] = []
}

extension Vault {
    /// Inspector data for the Endpoint `heading` in Note `path`: what it calls, who calls it, which Clients use it.
    public static func endpointRelations(path: String, heading: String, in root: URL) throws -> EndpointRelations {
        let paths = try notePaths(in: root)
        var r = EndpointRelations()
        func hits(_ l: WikiLink) -> Bool {
            resolve(l.target, among: paths) == .note(path) && l.heading?.lowercased() == heading.lowercased()
        }
        for p in paths {
            let parsed = NoteParser.parse(try String(contentsOf: root.appendingPathComponent(p), encoding: .utf8))
            for s in parsed.calls {
                if p == path && s.heading.title == heading {
                    for l in s.links { if case .note(let t) = resolve(l.target, among: paths) { r.callsOut.append(EndpointRef(path: t, heading: l.heading)) } }
                }
                if s.links.contains(where: hits) { r.callsIn.append(EndpointRef(path: p, heading: s.heading.title)) }
            }
            if parsed.uses.contains(where: { $0.links.contains(where: hits) }) { r.usesIn.append(EndpointRef(path: p, heading: nil)) }
        }
        return r
    }
}
