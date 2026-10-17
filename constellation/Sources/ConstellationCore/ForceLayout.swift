import Foundation

/// Pure force-directed layout (repulsion, springs, centring). Step it from a timer; positions are not persisted.
/// shortcut: O(n^2) repulsion, fine to a few hundred Nodes; ticket 12 swaps in a grid/Barnes-Hut approximation for 5,000.
public struct ForceLayout {
    public struct Point: Equatable { public var x: Double; public var y: Double }
    public private(set) var positions: [String: Point] = [:]
    private var velocities: [String: Point] = [:]
    private var edges: [(String, String)]
    public var spring = 60.0, repulsion = 2000.0, damping = 0.85

    public init(ids: [String], edges: [(String, String)]) {
        self.edges = edges
        update(ids: ids, edges: edges)
    }

    /// Keeps positions of surviving ids; new ids start on a deterministic spiral.
    public mutating func update(ids: [String], edges: [(String, String)]) {
        self.edges = edges
        let set = Set(ids)
        positions = positions.filter { set.contains($0.key) }
        velocities = velocities.filter { set.contains($0.key) }
        for (i, id) in ids.enumerated() where positions[id] == nil {
            let a = Double(i) * 2.4, r = 20 * Double(i + 1).squareRoot()
            positions[id] = Point(x: r * cos(a), y: r * sin(a))
            velocities[id] = Point(x: 0, y: 0)
        }
    }

    /// Pins a Node while the user drags it.
    public mutating func move(_ id: String, to p: Point) {
        guard positions[id] != nil else { return }
        positions[id] = p; velocities[id] = Point(x: 0, y: 0)
    }

    public mutating func step() {
        let ids = Array(positions.keys)
        var f = Dictionary(uniqueKeysWithValues: ids.map { ($0, Point(x: 0, y: 0)) })
        for i in 0..<ids.count {
            let p = positions[ids[i]]!
            f[ids[i]]!.x -= p.x * 0.01; f[ids[i]]!.y -= p.y * 0.01
            for j in (i + 1)..<max(ids.count, i + 1) {
                let q = positions[ids[j]]!
                var dx = p.x - q.x, dy = p.y - q.y
                if dx == 0 && dy == 0 { dx = 0.1 }
                let d2 = max(dx * dx + dy * dy, 1), d = d2.squareRoot(), k = repulsion / d2
                f[ids[i]]!.x += k * dx / d; f[ids[i]]!.y += k * dy / d
                f[ids[j]]!.x -= k * dx / d; f[ids[j]]!.y -= k * dy / d
            }
        }
        for (a, b) in edges {
            guard let p = positions[a], let q = positions[b] else { continue }
            let dx = q.x - p.x, dy = q.y - p.y, d = max((dx * dx + dy * dy).squareRoot(), 0.01)
            let k = 0.05 * (d - spring) / d
            f[a]!.x += k * dx; f[a]!.y += k * dy
            f[b]!.x -= k * dx; f[b]!.y -= k * dy
        }
        for id in ids {
            var v = velocities[id]!
            v.x = (v.x + f[id]!.x) * damping; v.y = (v.y + f[id]!.y) * damping
            let m = (v.x * v.x + v.y * v.y).squareRoot()
            if m > 30 { v.x *= 30 / m; v.y *= 30 / m }
            velocities[id] = v
            positions[id]!.x += v.x; positions[id]!.y += v.y
        }
    }
}
