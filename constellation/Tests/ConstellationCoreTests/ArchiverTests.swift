import Foundation
import XCTest
@testable import ConstellationCore

final class ArchiverTests: XCTestCase {
    private func makeVault(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("archiver-\(UUID().uuidString)")
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func read(_ root: URL, _ p: String) -> String? { try? String(contentsOf: root.appendingPathComponent(p), encoding: .utf8) }
    private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!
    private let bugs = "# Bugs\n- [ ] Order total ignores discounts → [[endpoints#POST /orders]]\n  Discounts are applied after tax.\n- [ ] Other\n"
    private let orders = "shop/orders-service/endpoints.md"

    private func tick(_ root: URL, _ path: String, offset: Int = 10) throws -> [FileEdit] {
        let text = read(root, path)!
        return try Vault.tick(taskAt: offset, in: text, path: path, root: root, on: day)
    }

    func testTickingABugMovesItToANewArchiveNote() throws {
        let root = try makeVault(["shop/orders-service/bugs.md": bugs, orders: "# POST /orders"])
        let edits = try tick(root, "shop/orders-service/bugs.md")
        try FileEdit.apply(edits, root: root)

        XCTAssertEqual(read(root, "shop/orders-service/bugs.md"), "# Bugs\n- [ ] Other\n")
        XCTAssertEqual(read(root, "shop/archive/fixed-bugs.md"), """
            ---
            type: archive
            ---
            # Fixed bugs

            ### Order total ignores discounts
            - closed: 2026-10-17
            - source: [[shop/orders-service/endpoints#POST /orders]]
            - what: Discounts are applied after tax.
            - fix: unknown

            """)
    }

    func testItemWithoutLinkUsesTheRepoReadmeAndTodosGoToDoneTodos() throws {
        let root = try makeVault([
            "shop/orders-service/todo.md": "- [ ] Split the handler\n",
            "shop/archive/done-todos.md": "# Done todos\n",
        ])
        try FileEdit.apply(try tick(root, "shop/orders-service/todo.md", offset: 3), root: root)

        XCTAssertEqual(read(root, "shop/orders-service/todo.md"), "")
        XCTAssertEqual(read(root, "shop/archive/done-todos.md"), """
            # Done todos

            ### Split the handler
            - closed: 2026-10-17
            - source: [[shop/orders-service/README]]
            - what: Split the handler
            - fix: unknown

            """)
    }

    func testInverseEditsRestoreEverythingExactly() throws {
        let root = try makeVault(["shop/orders-service/bugs.md": bugs, orders: "x"])
        let inverse = try FileEdit.apply(try tick(root, "shop/orders-service/bugs.md"), root: root)
        try FileEdit.apply(inverse, root: root)
        XCTAssertEqual(read(root, "shop/orders-service/bugs.md"), bugs)
        XCTAssertNil(read(root, "shop/archive/fixed-bugs.md"))
    }

    func testOtherNotesAndCheckedItemsJustToggle() throws {
        let root = try makeVault(["notes.md": "- [ ] a\n- [x] b\n", "shop/orders-service/bugs.md": "- [x] old\n"])
        try FileEdit.apply(try tick(root, "notes.md", offset: 2), root: root)
        XCTAssertEqual(read(root, "notes.md"), "- [x] a\n- [x] b\n")
        try FileEdit.apply(try tick(root, "notes.md", offset: 10), root: root)
        XCTAssertEqual(read(root, "notes.md"), "- [x] a\n- [ ] b\n")
        try FileEdit.apply(try tick(root, "shop/orders-service/bugs.md", offset: 2), root: root)
        XCTAssertEqual(read(root, "shop/orders-service/bugs.md"), "- [ ] old\n")
        XCTAssertNil(read(root, "shop/archive/fixed-bugs.md"))
    }

    func testOffsetOffATaskLineGivesNoEdits() throws {
        let root = try makeVault(["notes.md": "plain\n- [ ] a\n"])
        XCTAssertEqual(try tick(root, "notes.md", offset: 2), [])
    }

    func testArchiveNotesAreHiddenInTheGraphByDefaultAndMarkedInSearch() throws {
        let root = try makeVault([
            "shop/README.md": "# Shop",
            "shop/archive/fixed-bugs.md": "### Cache bug\n- what: stale cache\n",
        ])
        XCTAssertTrue(Vault.isArchive("shop/archive/fixed-bugs.md"))
        XCTAssertFalse(Vault.isArchive("shop/orders-service/archive.md"))

        let g = try Vault.graph(in: root)
        XCTAssertFalse(g.nodes.contains { $0.id.contains("archive") })
        XCTAssertFalse(g.edges.contains { $0.to.contains("archive") })
        let all = try Vault.graph(in: root, includeArchive: true)
        XCTAssertTrue(all.nodes.contains { $0.id == "shop/archive/fixed-bugs.md" })

        let r = try VaultIndex(root: root).search("stale")
        XCTAssertEqual(r.notes, [])
        XCTAssertEqual(r.matches.map(\.path), ["shop/archive/fixed-bugs.md"])
        XCTAssertTrue(r.isArchived("shop/archive/fixed-bugs.md"))
        XCTAssertFalse(r.isArchived("shop/README.md"))
    }

    func testTaskBoxIsStyledAndHiddenOffTheCursorLine() {
        let r = MarkdownStyler.style("- [ ] a\n- [x] b\n", cursorLine: NSRange(location: 8, length: 8))
        XCTAssertEqual(r.styled.filter { $0.role == .taskBox(checked: false) }.map(\.range), [NSRange(location: 2, length: 3)])
        XCTAssertTrue(r.styled.filter { $0.role == .taskBox(checked: true) }.isEmpty)
        XCTAssertEqual(r.hidden, [NSRange(location: 2, length: 3)])
    }
}
