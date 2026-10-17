import Foundation
import XCTest
@testable import ConstellationCore

final class GraphFilterTests: XCTestCase {
    private func makeVault(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func vault() throws -> URL {
        try makeVault([
            "shop/a.md": "#pay [[b]]", "shop/b.md": "[[c]]", "shop/c.md": "[[d]]", "shop/d.md": "end",
            "shop/archive/old.md": "[[a]]",
            "shop/ep.md": "---\ntype: endpoint\n---\n## GET /x\nCalls:\n- [[blog/y#GET /y]]\n",
            "blog/x.md": "---\ntags: [pay/refund]\n---\nx", "blog/y.md": "---\ntype: endpoint\n---\n## GET /y\n",
            "blog/z.md": "no tags",
        ])
    }

    private func ids(_ f: GraphFilter = GraphFilter(), around: String? = nil) throws -> Set<String> {
        Set(try Vault.graph(in: vault(), filter: f, around: around).nodes.map(\.id))
    }

    func testLocalGraphDepthOneToThree() throws {
        var f = GraphFilter(); f.edgeKinds = [.link]
        f.localDepth = 1; XCTAssertEqual(try ids(f, around: "shop/a.md"), ["shop/a.md", "shop/b.md"])
        f.localDepth = 2; XCTAssertEqual(try ids(f, around: "shop/a.md"), ["shop/a.md", "shop/b.md", "shop/c.md"])
        f.localDepth = 3; XCTAssertEqual(try ids(f, around: "shop/b.md"), ["shop/a.md", "shop/b.md", "shop/c.md", "shop/d.md"])
    }

    func testArchiveToggle() throws {
        XCTAssertFalse(try ids().contains("shop/archive/old.md"))
        var f = GraphFilter(); f.includeArchive = true
        XCTAssertTrue(try ids(f).contains("shop/archive/old.md"))
    }

    func testTagFilterKeepsTaggedNotesAndNeighbours() throws {
        var f = GraphFilter(); f.tag = "PAY"; f.edgeKinds = [.link]
        // shop/a (#pay) and blog/x (child tag pay/refund) match; b is a neighbour of a.
        XCTAssertEqual(try ids(f), ["shop/a.md", "shop/b.md", "blog/x.md"])
    }

    func testProjectTypeAndEdgeKindFilters() throws {
        var f = GraphFilter(); f.projects = ["blog"]
        XCTAssertTrue(try ids(f).isSubset(of: ["", "blog", "blog/x.md", "blog/y.md", "blog/z.md"]))
        f = GraphFilter(); f.types = ["endpoint"]
        XCTAssertEqual(try ids(f).filter { $0.hasSuffix(".md") }, Set(["shop/ep.md", "blog/y.md"]))
        f = GraphFilter(); f.edgeKinds = [.call]
        let g = try Vault.graph(in: vault(), filter: f)
        XCTAssertEqual(g.edges.map(\.kind), [.call])
    }

    func testFiltersPersistInVaultSettings() throws {
        let root = try vault()
        XCTAssertEqual(GraphFilter.load(from: root), GraphFilter())
        var f = GraphFilter(); f.tag = "pay"; f.projects = ["shop"]; f.edgeKinds = [.link, .call]; f.localDepth = 3
        try f.save(to: root)
        XCTAssertEqual(GraphFilter.load(from: root), f)
        // The settings file is app-only, so it never shows up as a Node.
        XCTAssertFalse(try Vault.graph(in: root).nodes.contains { $0.id.contains(".constellation") })
    }

    func testCallAndUsesLinksProduceOnlyTheirOwnEdge() throws {
        let g = try Vault.graph(in: makeVault([
            "ep.md": "---\ntype: endpoint\n---\n## GET /a\nCalls:\n- [[other#GET /b]]\n",
            "other.md": "---\ntype: endpoint\n---\n## GET /b\n",
            "web.md": "---\ntype: client\n---\nUses:\n- [[ep#GET /a]]\nAlso see [[other]]\n",
        ]))
        let pairs = g.edges.filter { $0.kind != .containment }.map { "\($0.kind) \($0.from)>\($0.to)" }
        XCTAssertEqual(Set(pairs), ["call ep.md>other.md", "uses web.md>ep.md", "link web.md>other.md"])
        XCTAssertEqual(pairs.count, 3)
    }

    func testFiveThousandNoteVaultStaysUsable() throws {
        var files: [String: String] = [:]
        for i in 0..<5000 { files["p\(i % 20)/n\(i).md"] = "[[n\((i * 7 + 1) % 5000)]] [[n\((i + 1) % 5000)]]" }
        let root = try makeVault(files)
        let g = try Vault.graph(in: root)
        XCTAssertGreaterThan(g.nodes.count, 5000)
        var l = ForceLayout(ids: g.nodes.map(\.id), edges: g.edges.map { ($0.from, $0.to) })
        let start = Date()
        for _ in 0..<10 { l.step() }
        let perStep = Date().timeIntervalSince(start) / 10
        XCTAssertLessThan(perStep, 0.5, "debug build; release is far faster")
        for _ in 0..<40 { l.step() }
        XCTAssertTrue(l.positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1e5 && abs($0.y) < 1e5 })
    }
}
