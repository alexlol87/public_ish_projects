import Foundation
import XCTest
@testable import ConstellationCore

final class GraphTests: XCTestCase {
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

    private func graph() throws -> VaultGraph {
        try Vault.graph(in: makeVault([
            "README.md": "Home [[overview]]",
            "acme/README.md": "Acme",
            "acme/overview.md": "See [[api]] and [[Missing One]] and [[missing one]]",
            "acme/cart/api.md": "back to [[overview]]; `[[code]]`",
            "empty/x.md": "x",
            "AGENTS.md": "[[overview]]",
            "templates/daily.md": "[[overview]]",
        ]))
    }

    func testNodesForNotesAndFolders() throws {
        let g = try graph()
        XCTAssertEqual(Set(g.nodes.filter { $0.kind == .folder }.map(\.id)), ["", "acme", "acme/cart", "empty"])
        XCTAssertEqual(Set(g.nodes.filter { $0.kind == .note }.map(\.id)),
                       ["README.md", "acme/README.md", "acme/overview.md", "acme/cart/api.md", "empty/x.md"])
    }

    func testContainmentEdges() throws {
        let c = Set(try graph().edges.filter { $0.kind == .containment }.map { "\($0.from)>\($0.to)" })
        XCTAssertEqual(c, [">README.md", ">acme", ">empty", "acme>acme/README.md", "acme>acme/overview.md",
                           "acme>acme/cart", "acme/cart>acme/cart/api.md", "empty>empty/x.md"])
    }

    func testLinkEdgesAndGhostNodes() throws {
        let g = try graph()
        let links = g.edges.filter { $0.kind == .link }
        XCTAssertEqual(Set(links.map { "\($0.from)>\($0.to)" }),
                       ["README.md>acme/overview.md", "acme/overview.md>acme/cart/api.md",
                        "acme/cart/api.md>acme/overview.md", "acme/overview.md>ghost:missing one.md"])
        XCTAssertEqual(g.nodes.filter { $0.kind == .ghost }.map(\.id), ["ghost:missing one.md"])
    }

    func testFolderOpensReadme() throws {
        let g = try graph()
        XCTAssertEqual(g.openPath(for: "acme"), "acme/README.md")
        XCTAssertNil(g.openPath(for: "empty"))
        XCTAssertEqual(g.openPath(for: "acme/overview.md"), "acme/overview.md")
        XCTAssertEqual(g.openPath(for: ""), "README.md")
    }

    func testNeighbours() throws {
        XCTAssertEqual(try graph().neighbours(of: "acme/overview.md"),
                       ["README.md", "acme", "acme/cart/api.md", "ghost:missing one.md"])
    }
}
