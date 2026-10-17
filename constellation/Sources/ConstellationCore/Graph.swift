import Foundation

public struct GraphNode: Equatable, Identifiable {
    public enum Kind { case note, folder, ghost }
    public let id: String  // Vault path; ghosts are "ghost:<createPath>"
    public let name: String
    public let kind: Kind
    public var noteType: String? = nil  // frontmatter type for notes; nil for folders and ghosts
    public var tags: [String] = []  // lowercased tag names of a Note
}

/// One Endpoint-level Call (or a Client Use, where `from` is "") folded into a Note-to-Note edge.
public struct EndpointPair: Equatable {
    public let from: String
    public let to: String
}

public struct GraphEdge: Equatable {
    public enum Kind: String, Codable, CaseIterable { case containment, link, call, uses }
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
        var nodeIndex: [String: Int] = [:]
        func walk(_ n: VaultNode) {
            for c in n.children where !c.isAppOnly && (includeArchive || !isArchive(c.relativePath)) && (c.isFolder || c.relativePath.hasSuffix(".md")) {
                nodeIndex[c.relativePath] = nodes.count
                nodes.append(GraphNode(id: c.relativePath, name: c.name, kind: c.isFolder ? .folder : .note))
                edges.append(GraphEdge(from: n.relativePath, to: c.relativePath, kind: .containment))
                if c.isFolder { walk(c) }
            }
        }
        nodes.append(GraphNode(id: "", name: root.lastPathComponent, kind: .folder))
        walk(tree)
        let index = PathIndex(paths)
        var ghosts = Set<String>(), seen = Set<String>()
        var folded: [String: Int] = [:]  // "kind from>to" -> index in edges
        func fold(_ kind: GraphEdge.Kind, _ from: String, _ target: String, _ pair: EndpointPair) {
            guard case .note(let to) = index.resolve(target), to != from else { return }
            let key = "\(kind) \(from)>\(to)"
            if let i = folded[key] { edges[i].pairs.append(pair) } else {
                folded[key] = edges.count
                edges.append(GraphEdge(from: from, to: to, kind: kind, pairs: [pair]))
            }
        }
        for p in paths {
            let text = try String(contentsOf: root.appendingPathComponent(p), encoding: .utf8)
            let parsed = NoteParser.parse(text)
            if let i = nodeIndex[p] { nodes[i].noteType = parsed.type; nodes[i].tags = Set(parsed.tags.map { $0.name.lowercased() }).sorted() }
            // A Call/Uses Link gets only its Call/Uses edge, not a plain Link edge too.
            let sectioned = Set((parsed.calls + parsed.uses).flatMap { $0.links.map(\.range.location) })
            for s in parsed.calls { for l in s.links { fold(.call, p, l.target, EndpointPair(from: s.heading.title, to: l.heading ?? "")) } }
            for s in parsed.uses { for l in s.links { fold(.uses, p, l.target, EndpointPair(from: "", to: l.heading ?? "")) } }
            for l in parsed.links where !sectioned.contains(l.range.location) {
                var to: String
                switch index.resolve(l.target) {
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

/// Graph window filters; empty `projects`/`types` mean "all". Persisted per Vault in `.constellation/graph.json`.
public struct GraphFilter: Codable, Equatable {
    public var projects: Set<String> = []  // top-level folder names
    public var types: Set<String> = []     // Note types
    public var edgeKinds = Set(GraphEdge.Kind.allCases)
    public var tag: String? = nil          // tagged Notes (and child tags) plus their neighbours
    public var includeArchive = false
    public var localDepth = 2              // 1...3, used when the graph is built `around:` a Note
    public init() {}

    static func file(_ root: URL) -> URL { root.appendingPathComponent(".constellation/graph.json") }
    public static func load(from root: URL) -> GraphFilter {
        (try? JSONDecoder().decode(GraphFilter.self, from: Data(contentsOf: file(root)))) ?? GraphFilter()
    }
    public func save(to root: URL) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".constellation"), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.file(root), options: .atomic)
    }
}

extension VaultGraph {
    /// Applies `f` (archive is handled when the graph is built). With `around`, keeps Nodes within `f.localDepth` (1...3) edges of it.
    public func filtered(_ f: GraphFilter, around: String? = nil) -> VaultGraph {
        var g = self
        g.nodes = nodes.filter { n in
            if n.kind == .note, !f.types.isEmpty, !f.types.contains(n.noteType ?? "note") { return false }
            guard n.kind != .ghost, !n.id.isEmpty, !f.projects.isEmpty else { return true }
            return f.projects.contains(String(n.id.split(separator: "/").first ?? ""))
        }
        func prune() {
            let keep = Set(g.nodes.map(\.id))
            g.edges = g.edges.filter { keep.contains($0.from) && keep.contains($0.to) }
        }
        g.edges = g.edges.filter { f.edgeKinds.contains($0.kind) }
        prune()
        func adjacency() -> [String: [String]] {
            var adj: [String: [String]] = [:]
            for e in g.edges { adj[e.from, default: []].append(e.to); adj[e.to, default: []].append(e.from) }
            return adj
        }
        func restrict(to keep: Set<String>) { g.nodes = g.nodes.filter { keep.contains($0.id) }; prune() }
        if let tag = f.tag?.lowercased(), !tag.isEmpty {
            let hit = Set(g.nodes.filter { $0.tags.contains { $0 == tag || $0.hasPrefix(tag + "/") } }.map(\.id))
            let adj = adjacency()
            restrict(to: hit.union(hit.flatMap { adj[$0] ?? [] }))
        }
        if let start = around {
            let adj = adjacency()
            var seen: Set<String> = [start], frontier = [start]
            for _ in 0..<min(3, max(1, f.localDepth)) {
                frontier = frontier.flatMap { adj[$0] ?? [] }.filter { seen.insert($0).inserted }
            }
            restrict(to: seen)
        }
        return g
    }
}

extension Vault {
    public static func graph(in root: URL, filter: GraphFilter, around: String? = nil) throws -> VaultGraph {
        try graph(in: root, includeArchive: filter.includeArchive).filtered(filter, around: around)
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
