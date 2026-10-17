import XCTest
@testable import ConstellationCore

final class ForceLayoutTests: XCTestCase {
    func testConnectedNodesEndCloserThanUnconnected() {
        var l = ForceLayout(ids: ["a", "b", "c"], edges: [("a", "b")])
        for _ in 0..<300 { l.step() }
        func d(_ x: String, _ y: String) -> Double {
            let p = l.positions[x]!, q = l.positions[y]!
            return ((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)).squareRoot()
        }
        XCTAssertLessThan(d("a", "b"), d("a", "c"))
        XCTAssertTrue(l.positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    func testKeepsExistingPositionsWhenIdsChange() {
        var l = ForceLayout(ids: ["a", "b"], edges: [])
        for _ in 0..<20 { l.step() }
        let a = l.positions["a"]!
        l.update(ids: ["a", "b", "c"], edges: [])
        XCTAssertEqual(l.positions["a"]!.x, a.x)
        XCTAssertNotNil(l.positions["c"])
        l.update(ids: ["a"], edges: [])
        XCTAssertNil(l.positions["b"])
    }
}
