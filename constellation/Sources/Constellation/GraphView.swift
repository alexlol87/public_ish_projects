#if canImport(AppKit)
import ConstellationCore
import SwiftUI

/// Shared between the main window (sets `index`, `repos`, `onOpen`, calls `reload`) and the graph window. Uncompiled on Linux.
final class GraphModel: ObservableObject {
    static let shared = GraphModel()
    var index: VaultIndex? { didSet { filter = index.map { GraphFilter.load(from: $0.root) } ?? GraphFilter() } }  // filter's didSet reloads
    var onOpen: (String) -> Void = { _ in }
    var currentNote: String?  // set by the main window; the Local toggle centres on it
    @Published var graph = VaultGraph(nodes: [], edges: [])
    @Published var tick = 0
    /// Repo folder paths with their staleness (README `verified_on`); the main window computes it once per change.
    var repos: [String: Staleness] = [:]
    var layout = ForceLayout(ids: [], edges: [])
    /// Persisted per Vault (`.constellation/graph.json`); `localAround` = current Note when the local graph is on.
    @Published var filter = GraphFilter() { didSet { if let index { try? filter.save(to: index.root) }; reload() } }
    @Published var localAround: String? { didSet { reload() } }

    /// Rebuilds from the index's parsed Notes in memory; nothing is read from disk.
    func reload() {
        guard let index else { return }
        graph = index.graph(filter: filter, around: localAround)
        layout.update(ids: graph.nodes.map(\.id), edges: graph.edges.map { ($0.from, $0.to) })
    }
    func step() { layout.step(); tick &+= 1 }
}

struct GraphView: View {
    @ObservedObject var model = GraphModel.shared
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @State private var hover: String?
    @State private var tip = ""
    @State private var dragging: String?
    @State private var panStart: CGSize?
    @State private var zoomStart: Double?
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) { filterBar; canvas }
    }

    /// Filters (uncompiled): Project/Type menus, Edge kinds, Tag, Archive, Local depth.
    private var filterBar: some View {
        HStack {
            Menu("Edges") {
                ForEach(GraphEdge.Kind.allCases, id: \.self) { k in
                    Toggle(k.rawValue.capitalized, isOn: Binding(
                        get: { model.filter.edgeKinds.contains(k) },
                        set: { if $0 { model.filter.edgeKinds.insert(k) } else { model.filter.edgeKinds.remove(k) } }))
                }
            }
            listField("Project", $model.filter.projects)
            listField("Type", $model.filter.types)
            TextField("Tag", text: Binding(get: { model.filter.tag ?? "" },
                set: { model.filter.tag = $0.isEmpty ? nil : $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }))
            Toggle("Archive", isOn: $model.filter.includeArchive)
            Toggle("Local", isOn: Binding(get: { model.localAround != nil }, set: { model.localAround = $0 ? model.currentNote : nil }))
            Picker("Depth", selection: $model.filter.localDepth) { ForEach(1...3, id: \.self) { Text("\($0)").tag($0) } }
                .frame(width: 90).disabled(model.localAround == nil)
        }
        .padding(6)
    }

    /// Comma-separated text field editing a set of names.
    private func listField(_ title: String, _ values: Binding<Set<String>>) -> some View {
        TextField(title, text: Binding(
            get: { values.wrappedValue.sorted().joined(separator: ",") },
            set: { values.wrappedValue = Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) }))
    }

    private var canvas: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width / 2 + pan.width, y: geo.size.height / 2 + pan.height)
            let toScreen = { (point: ForceLayout.Point) in CGPoint(x: centre.x + point.x * zoom, y: centre.y + point.y * zoom) }
            Canvas { ctx, _ in
                _ = model.tick
                let near = Set(hover.map { model.graph.neighbours(of: $0) + [$0] } ?? [])
                let positions = model.layout.positions
                let palette = settings.palette
                for edge in model.graph.edges {
                    guard let from = positions[edge.from], let to = positions[edge.to] else { continue }
                    var line = Path(); line.move(to: toScreen(from)); line.addLine(to: toScreen(to))
                    let style = Self.style(of: edge.kind)
                    let lit = hover == nil || (near.contains(edge.from) && near.contains(edge.to))
                    ctx.stroke(line, with: .color(lit ? style.colour : style.colour.opacity(0.1)),
                               style: StrokeStyle(lineWidth: style.width, dash: style.dash))
                }
                for node in model.graph.nodes {
                    guard let position = positions[node.id] else { continue }
                    let screen = toScreen(position), radius = node.kind == .folder ? 7.0 : 5.0
                    // A Repo is its folder plus its README Node.
                    let repoPath = node.kind == .folder ? node.id : node.id.hasSuffix("/README.md") ? String(node.id.dropLast(10)) : ""
                    let stale = model.repos[repoPath]?.isStale(threshold: settings.thresholdDays) == true
                    let base = Self.colour(of: node, stale: stale, palette: palette)
                    let on = hover == nil || near.contains(node.id)
                    let dot = Path(ellipseIn: CGRect(x: screen.x - radius, y: screen.y - radius, width: 2 * radius, height: 2 * radius))
                    ctx.fill(dot, with: .color(on ? base.opacity(node.kind == .ghost ? 0.5 : 1) : base.opacity(0.15)))
                    if on && (zoom > 0.8 || node.id == hover) {
                        ctx.draw(Text(node.name).font(.caption2), at: CGPoint(x: screen.x, y: screen.y + radius + 8))
                    }
                }
            }
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    hover = nodeID(at: location, toScreen: toScreen)
                    tip = hover == nil ? edgeTip(at: location, toScreen: toScreen) : ""
                } else { hover = nil; tip = "" }
            }
            .help(tip)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if dragging == nil && panStart == nil {
                        if let id = nodeID(at: v.startLocation, toScreen: toScreen) { dragging = id } else { panStart = pan }
                    }
                    if let id = dragging {
                        model.layout.move(id, to: .init(x: (v.location.x - centre.x) / zoom, y: (v.location.y - centre.y) / zoom))
                    } else if let s = panStart {
                        pan = CGSize(width: s.width + v.translation.width, height: s.height + v.translation.height)
                    }
                }
                .onEnded { v in
                    // A tap (no real movement) on a Node opens it.
                    if hypot(v.translation.width, v.translation.height) < 3, let id = dragging,
                       let path = model.graph.openPath(for: id) { model.onOpen(path) }
                    dragging = nil; panStart = nil
                })
            .gesture(MagnifyGesture()
                .onChanged { v in
                    if zoomStart == nil { zoomStart = zoom }
                    zoom = min(5, max(0.1, zoomStart! * v.magnification))
                }
                .onEnded { _ in zoomStart = nil })
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(hex: settings.palette.background))
        .onAppear { model.reload() }
        .onReceive(Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()) { _ in model.step() }
    }

    private struct EdgeStyle { let colour: Color; let width: CGFloat; let dash: [CGFloat] }

    /// How each kind of edge is drawn.
    private static func style(of kind: GraphEdge.Kind) -> EdgeStyle {
        switch kind {
        case .containment: EdgeStyle(colour: Color.gray.opacity(0.35), width: 0.5, dash: [])
        case .link: EdgeStyle(colour: Color.accentColor, width: 1.5, dash: [])
        case .call: EdgeStyle(colour: Color.green, width: 2.5, dash: [])
        case .uses: EdgeStyle(colour: Color.purple, width: 1.5, dash: [4, 3])
        }
    }

    private static func colour(of node: GraphNode, stale: Bool, palette: Palette) -> Color {
        if stale { return Color(hex: palette.stale) }
        switch node.kind {
        case .folder: return Color(hex: palette.folderNode)
        case .ghost: return .red
        case .note: return node.noteType == nil || node.noteType == "note" ? Color(hex: palette.noteNode) : typeColour(node.noteType)
        }
    }

    /// One colour per Note type; plain and unknown types stay blue.
    static func typeColour(_ type: String?) -> Color {
        switch type {
        case "endpoint": .green
        case "client": .purple
        case "repo": .teal
        case "project": .indigo
        case "bugs", "todo": .pink
        case "adr", "architecture", "requirements", "future", "external-api": .brown
        default: .blue
        }
    }

    /// Hover on a call/uses edge lists the Endpoint pairs it folds.
    private func pairsText(_ edge: GraphEdge) -> String {
        edge.pairs.map { $0.from.isEmpty ? "uses \($0.to)" : "\($0.from) -> \($0.to)" }.joined(separator: "\n")
    }

    private func edgeTip(at point: CGPoint, toScreen: (ForceLayout.Point) -> CGPoint) -> String {
        for edge in model.graph.edges where !edge.pairs.isEmpty {
            guard let a = model.layout.positions[edge.from].map(toScreen), let b = model.layout.positions[edge.to].map(toScreen) else { continue }
            let length2 = max(1, pow(b.x - a.x, 2) + pow(b.y - a.y, 2))
            let along = min(1, max(0, ((point.x - a.x) * (b.x - a.x) + (point.y - a.y) * (b.y - a.y)) / length2))
            if hypot(a.x + along * (b.x - a.x) - point.x, a.y + along * (b.y - a.y) - point.y) < 5 { return pairsText(edge) }
        }
        return ""
    }

    private func nodeID(at point: CGPoint, toScreen: (ForceLayout.Point) -> CGPoint) -> String? {
        model.graph.nodes.first { node in
            guard let position = model.layout.positions[node.id] else { return false }
            let centre = toScreen(position)
            return hypot(centre.x - point.x, centre.y - point.y) < 9
        }?.id
    }
}
#endif
