import Foundation
import XCTest
@testable import ConstellationCore

final class VaultIndexTests: XCTestCase {
    private func makeVault(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vindex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, text) in files { try write(root, path, text) }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func write(_ root: URL, _ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testIngestRefreshesTreeSearchTagsGraphAndBacklinksFromTouchedPathsOnly() throws {
        let root = try makeVault(["a.md": "plain", "b.md": "[[a]] #old"])
        let index = try VaultIndex(root: root)
        XCTAssertEqual(index.backlinks(to: "a.md").map(\.path), ["b.md"])

        // Touched and ingested: everything follows.
        try write(root, "c.md", "[[a]] #fresh and [[nowhere]]")
        try index.ingest(paths: ["c.md"])
        XCTAssertEqual(index.tree.children.map(\.name), ["a.md", "b.md", "c.md"])
        XCTAssertEqual(index.backlinks(to: "a.md").map(\.path), ["b.md", "c.md"])
        XCTAssertEqual(index.tagTree(sortedBy: .name).map(\.tag), ["fresh", "old"])
        XCTAssertEqual(index.search("fresh").matches.map(\.path), ["c.md"])
        let g = index.graph(filter: GraphFilter())
        XCTAssertTrue(g.edges.contains { $0.from == "c.md" && $0.to == "a.md" && $0.kind == .link })
        XCTAssertTrue(g.nodes.contains { $0.kind == .ghost && $0.name == "nowhere" })

        // Changed on disk but not reported: the graph must not have re-read it.
        try write(root, "b.md", "no links now")
        XCTAssertEqual(index.backlinks(to: "a.md").map(\.path), ["b.md", "c.md"])
        try index.ingest(paths: ["b.md"])
        XCTAssertEqual(index.backlinks(to: "a.md").map(\.path), ["c.md"])

        try FileManager.default.removeItem(at: root.appendingPathComponent("c.md"))
        try index.ingest(paths: ["c.md"])
        XCTAssertTrue(index.backlinks(to: "a.md").isEmpty)
        XCTAssertFalse(index.graph(filter: GraphFilter()).nodes.contains { $0.id == "c.md" })
    }

    func testIndexGraphMatchesTheStaticGraph() throws {
        let root = try makeVault(["README.md": "[[x/y]]", "x/y.md": "---\ntype: endpoint\n---\n## GET /a\nCalls:\n- [[README#H]]", "templates/t.md": "[[y]]"])
        let index = try VaultIndex(root: root)
        XCTAssertEqual(index.graph(filter: GraphFilter()), try Vault.graph(in: root))
    }

    func testBrokenLinksInUnsavedText() throws {
        let index = try VaultIndex(root: try makeVault(["a.md": "x", "docs/b.md": "y"]))
        let broken = index.brokenLinks(in: "[[a]] [[b]] [[nope]] `[[code]]`")
        XCTAssertEqual(broken.map(\.target), ["nope"])
    }

    func testRepoStalenessComesFromTheIndexedReadmes() throws {
        let root = try makeVault(["shop/orders/README.md": "---\ntype: repo\nverified_on: 2026-10-01\n---\n", "shop/README.md": "plain"])
        let index = try VaultIndex(root: root)
        let now = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 10, day: 11, hour: 12))!
        XCTAssertEqual(index.repoStaleness(now: now), ["shop/orders": .verified(days: 10)])
        XCTAssertEqual(index.repoStaleness(now: now), try Vault.repoStaleness(in: root, now: now))
        try write(root, "shop/orders/README.md", "---\ntype: repo\n---\n")
        try index.ingest(paths: ["shop/orders/README.md"])
        XCTAssertEqual(index.repoStaleness(now: now), ["shop/orders": .never])
    }
}
