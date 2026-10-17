#if canImport(AppKit)
import ConstellationCore
import SwiftUI

/// Shared between the main window (sets `root`, `onOpen`, calls `reload`) and the graph window. Uncompiled on Linux.
final class GraphModel: ObservableObject {
    static let shared = GraphModel()
    var root: URL? { didSet { reload() } }
    var onOpen: (String) -> Void = { _ in }
    @Published var graph = VaultGraph(nodes: [], edges: [])
    @Published var tick = 0
    var layout = ForceLayout(ids: [], edges: [])

    func reload() {
        guard let root, let g = try? Vault.graph(in: root) else { return }
        graph = g
        layout.update(ids: g.nodes.map(\.id), edges: g.edges.map { ($0.from, $0.to) })
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

    var body: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width / 2 + pan.width, y: geo.size.height / 2 + pan.height)
            let to = { (p: ForceLayout.Point) in CGPoint(x: centre.x + p.x * zoom, y: centre.y + p.y * zoom) }
            Canvas { ctx, _ in
                _ = model.tick
                let near = Set(hover.map { model.graph.neighbours(of: $0) + [$0] } ?? [])
                let pos = model.layout.positions
                for e in model.graph.edges {
                    guard let a = pos[e.from], let b = pos[e.to] else { continue }
                    var path = Path(); path.move(to: to(a)); path.addLine(to: to(b))
                    let lit = hover == nil || (near.contains(e.from) && near.contains(e.to))
                    let colour: Color = e.kind == .containment ? .gray.opacity(0.35) : e.kind == .call ? .green : e.kind == .uses ? .purple : .accentColor
                    let dash: [CGFloat] = e.kind == .uses ? [4, 3] : []
                    ctx.stroke(path, with: .color(lit ? colour : colour.opacity(0.1)),
                               style: StrokeStyle(lineWidth: e.kind == .containment ? 0.5 : e.kind == .call ? 2.5 : 1.5, dash: dash))
                }
                for n in model.graph.nodes {
                    guard let p = pos[n.id] else { continue }
                    let c = to(p), r = n.kind == .folder ? 7.0 : 5.0
                    let base: Color = n.kind == .folder ? .orange : n.kind == .ghost ? .red : Self.typeColour(n.noteType)
                    let on = hover == nil || near.contains(n.id)
                    let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                    ctx.fill(dot, with: .color(on ? base.opacity(n.kind == .ghost ? 0.5 : 1) : base.opacity(0.15)))
                    if on && (zoom > 0.8 || n.id == hover) {
                        ctx.draw(Text(n.name).font(.caption2), at: CGPoint(x: c.x, y: c.y + r + 8))
                    }
                }
            }
            .onContinuousHover { phase in
                if case .active(let l) = phase { hover = hit(l, to: to); tip = hover == nil ? edgeHit(l, to: to) : "" } else { hover = nil; tip = "" }
            }
            .help(tip)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if dragging == nil && panStart == nil {
                        if let id = hit(v.startLocation, to: to) { dragging = id } else { panStart = pan }
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
        .onAppear { model.reload() }
        .onReceive(Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()) { _ in model.step() }
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
    private func edgeTip(_ e: GraphEdge) -> String {
        e.pairs.map { $0.from.isEmpty ? "uses \($0.to)" : "\($0.from) -> \($0.to)" }.joined(separator: "\n")
    }

    private func edgeHit(_ p: CGPoint, to: (ForceLayout.Point) -> CGPoint) -> String {
        for e in model.graph.edges where e.kind == .call || e.kind == .uses {
            guard let a = model.layout.positions[e.from].map(to), let b = model.layout.positions[e.to].map(to) else { continue }
            let len2 = max(1, pow(b.x - a.x, 2) + pow(b.y - a.y, 2))
            let t = min(1, max(0, ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / len2))
            if hypot(a.x + t * (b.x - a.x) - p.x, a.y + t * (b.y - a.y) - p.y) < 5 { return edgeTip(e) }
        }
        return ""
    }

    private func hit(_ p: CGPoint, to: (ForceLayout.Point) -> CGPoint) -> String? {
        model.graph.nodes.first { n in
            guard let q = model.layout.positions[n.id] else { return false }
            let c = to(q); return hypot(c.x - p.x, c.y - p.y) < 9
        }?.id
    }
}
#endif
