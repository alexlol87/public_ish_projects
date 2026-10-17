import Foundation

/// Pure force-directed layout (repulsion, springs, centring). Step it from a timer; positions are not persisted.
/// Repulsion uses a Barnes-Hut quadtree (O(n log n)), so 5,000 Nodes stay interactive.
public struct ForceLayout {
    public struct Point: Equatable {
        public var x: Double; public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }
    public private(set) var positions: [String: Point] = [:]
    private var velocities: [String: Point] = [:]
    private var order: [String] = []  // stable iteration order
    private var edges: [(String, String)]
    private let spring = 60.0, repulsion = 2000.0, damping = 0.85
    /// Barnes-Hut opening angle: larger is faster and rougher.
    private let theta = 0.8

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
        order = Array(positions.keys).sorted()
    }

    /// Pins a Node while the user drags it.
    public mutating func move(_ id: String, to p: Point) {
        guard positions[id] != nil else { return }
        positions[id] = p; velocities[id] = Point(x: 0, y: 0)
    }

    private struct Cell {
        var x = 0.0, y = 0.0, half = 0.0  // centre and half-width
        var mass = 0.0, sx = 0.0, sy = 0.0  // body count and coordinate sums
        var body = -1                       // >= 0: leaf holding one body
        var kids = [Int](repeating: -1, count: 4)
    }

    public mutating func step() {
        let n = order.count
        guard n > 0 else { return }
        var px = [Double](repeating: 0, count: n), py = px, vx = px, vy = px
        var index: [String: Int] = [:]
        for (i, id) in order.enumerated() {
            index[id] = i
            px[i] = positions[id]!.x; py[i] = positions[id]!.y
            vx[i] = velocities[id]!.x; vy[i] = velocities[id]!.y
        }
        // Build the quadtree.
        let side = max(1, (px.map(abs).max() ?? 1), (py.map(abs).max() ?? 1)) + 1
        var cells = [Cell(x: 0, y: 0, half: side)]
        for i in 0..<n {
            var c = 0, depth = 0
            while true {
                cells[c].mass += 1; cells[c].sx += px[i]; cells[c].sy += py[i]
                if cells[c].mass == 1 { cells[c].body = i; break }
                if cells[c].body >= 0 {
                    if depth >= 32 { break }  // coincident bodies: counted in mass, not split further
                    let b = cells[c].body
                    cells[c].body = -1
                    let q = Self.quadrant(cells[c], px[b], py[b])
                    let k = Self.child(&cells, c, q)
                    cells[k].mass = 1; cells[k].sx = px[b]; cells[k].sy = py[b]; cells[k].body = b
                }
                c = Self.child(&cells, c, Self.quadrant(cells[c], px[i], py[i])); depth += 1
            }
        }
        var fx = [Double](repeating: 0, count: n), fy = fx
        var stack: [Int] = []
        let t2 = theta * theta
        for i in 0..<n {
            fx[i] -= px[i] * 0.01; fy[i] -= py[i] * 0.01
            stack.append(0)
            while let c = stack.popLast() {
                let cell = cells[c]
                if cell.body == i { continue }
                var dx = px[i] - cell.sx / cell.mass, dy = py[i] - cell.sy / cell.mass
                if dx == 0 && dy == 0 { dx = 0.1 }
                let d2 = max(dx * dx + dy * dy, 1)
                if cell.body >= 0 || (4 * cell.half * cell.half) < t2 * d2 {
                    let d = d2.squareRoot(), k = cell.mass * repulsion / d2
                    fx[i] += k * dx / d; fy[i] += k * dy / d
                } else {
                    for k in cell.kids where k >= 0 { stack.append(k) }
                }
            }
        }
        for (a, b) in edges {
            guard let i = index[a], let j = index[b] else { continue }
            let dx = px[j] - px[i], dy = py[j] - py[i], d = max((dx * dx + dy * dy).squareRoot(), 0.01)
            let k = 0.05 * (d - spring) / d
            fx[i] += k * dx; fy[i] += k * dy
            fx[j] -= k * dx; fy[j] -= k * dy
        }
        for (i, id) in order.enumerated() {
            var x = (vx[i] + fx[i]) * damping, y = (vy[i] + fy[i]) * damping
            let m = (x * x + y * y).squareRoot()
            if m > 30 { x *= 30 / m; y *= 30 / m }
            velocities[id] = Point(x: x, y: y)
            positions[id] = Point(x: px[i] + x, y: py[i] + y)
        }
    }

    private static func quadrant(_ c: Cell, _ x: Double, _ y: Double) -> Int { (x >= c.x ? 1 : 0) + (y >= c.y ? 2 : 0) }

    private static func child(_ cells: inout [Cell], _ c: Int, _ q: Int) -> Int {
        if cells[c].kids[q] >= 0 { return cells[c].kids[q] }
        let h = cells[c].half / 2
        cells.append(Cell(x: cells[c].x + (q & 1 == 1 ? h : -h), y: cells[c].y + (q & 2 == 2 ? h : -h), half: h))
        cells[c].kids[q] = cells.count - 1
        return cells.count - 1
    }
}
