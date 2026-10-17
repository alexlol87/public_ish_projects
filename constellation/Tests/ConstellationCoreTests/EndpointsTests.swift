import Foundation
import XCTest
@testable import ConstellationCore

final class EndpointsTests: XCTestCase {
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

    private let cart = """
    ---
    type: endpoint
    owner: team-a
    ---
    # Cart endpoints

    ## GET /cart
    Calls:
    - [[shop-orders/endpoints#POST /orders]]
    - [[shop-orders/endpoints#GET /stock]]

    Status:
    - implemented: true
    - last_changed: 2026-01-02

    ## DELETE /cart
    Calls:
    - [[shop-orders/endpoints#POST /orders]]
    """
    private let orders = "---\ntype: endpoint\n---\n## POST /orders\n## GET /stock\nCalls:\n- [[shop-cart/endpoints#GET /cart]]\n"
    private let web = "---\ntype: client\n---\n# Web\nUses:\n- [[shop-cart/endpoints#GET /cart]]\n"

    private func vault() throws -> URL {
        try makeVault(["shop-cart/endpoints.md": cart, "shop-orders/endpoints.md": orders, "web.md": web,
                       "plain.md": "no frontmatter", "odd.md": "---\ntype: gizmo\nx: 1\n---\nbody"])
    }

    func testNoteTypesAndUnknownKeys() {
        let p = NoteParser.parse(cart)
        XCTAssertEqual(p.type, "endpoint")
        XCTAssertEqual(p.frontmatter["owner"], "team-a")
        XCTAssertEqual(p.headings.map(\.title), ["Cart endpoints", "GET /cart", "DELETE /cart"])
        XCTAssertEqual(NoteParser.parse("plain").type, "note")
        let odd = NoteParser.parse("---\ntype: gizmo\nx: 1\n---\nbody")
        XCTAssertEqual(odd.type, "gizmo")
        XCTAssertEqual(odd.frontmatter["x"], "1")
    }

    func testCallsPerEndpointAndStatus() {
        let p = NoteParser.parse(cart)
        XCTAssertEqual(p.calls.map(\.heading.title), ["GET /cart", "DELETE /cart"])
        XCTAssertEqual(p.calls[0].links.map(\.heading), ["POST /orders", "GET /stock"])
        XCTAssertEqual(p.status.first?.values, ["implemented": "true", "last_changed": "2026-01-02"])
    }

    func testCallsOutsideEndpointHeadingIsPlainList() {
        let p = NoteParser.parse("# Misc\nCalls:\n- [[a]]\n## GET /x\nCalls:\n- [[b#GET /y]]")
        XCTAssertEqual(p.calls.map(\.heading.title), ["GET /x"])
        XCTAssertEqual(p.links.map(\.target), ["a", "b"])
    }

    func testUsesOnlyInClientNotes() {
        XCTAssertEqual(NoteParser.parse(web).uses.first?.links.first?.target, "shop-cart/endpoints")
        XCTAssertTrue(NoteParser.parse("# W\nUses:\n- [[a#GET /x]]").uses.isEmpty)
    }

    func testGraphNodeTypesAndFoldedEdges() throws {
        let g = try Vault.graph(in: vault())
        XCTAssertEqual(g.nodes.first { $0.id == "shop-cart/endpoints.md" }?.noteType, "endpoint")
        XCTAssertEqual(g.nodes.first { $0.id == "plain.md" }?.noteType, "note")
        XCTAssertEqual(g.nodes.first { $0.id == "odd.md" }?.noteType, "gizmo")
        let calls = g.edges.filter { $0.kind == .call }
        let out = try XCTUnwrap(calls.first { $0.from == "shop-cart/endpoints.md" })
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(out.to, "shop-orders/endpoints.md")
        XCTAssertEqual(out.pairs, [EndpointPair(from: "GET /cart", to: "POST /orders"),
                                   EndpointPair(from: "GET /cart", to: "GET /stock"),
                                   EndpointPair(from: "DELETE /cart", to: "POST /orders")])
        let uses = g.edges.filter { $0.kind == .uses }
        XCTAssertEqual(uses.map { "\($0.from)>\($0.to)" }, ["web.md>shop-cart/endpoints.md"])
        XCTAssertEqual(uses[0].pairs, [EndpointPair(from: "", to: "GET /cart")])
    }

    func testInspectorRelations() throws {
        let root = try vault()
        let r = try Vault.endpointRelations(path: "shop-cart/endpoints.md", heading: "GET /cart", in: root)
        XCTAssertEqual(r.callsOut, [EndpointRef(path: "shop-orders/endpoints.md", heading: "POST /orders"),
                                    EndpointRef(path: "shop-orders/endpoints.md", heading: "GET /stock")])
        XCTAssertEqual(r.callsIn, [EndpointRef(path: "shop-orders/endpoints.md", heading: "GET /stock")])
        XCTAssertEqual(r.usesIn, [EndpointRef(path: "web.md", heading: nil)])
        let o = try Vault.endpointRelations(path: "shop-orders/endpoints.md", heading: "POST /orders", in: root)
        XCTAssertEqual(o.callsIn.map(\.heading), ["GET /cart", "DELETE /cart"])
    }

    func testEndpointHeadingUnderCursor() {
        let p = NoteParser.parse(cart)
        let ns = cart as NSString
        XCTAssertEqual(p.endpointHeading(at: ns.range(of: "[[shop-orders/endpoints#GET").location)?.title, "GET /cart")
        XCTAssertNil(p.endpointHeading(at: 0))
        XCTAssertNil(p.endpointHeading(at: ns.range(of: "# Cart").location + 3))
    }
}
