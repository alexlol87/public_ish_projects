import Foundation
import XCTest
@testable import ConstellationCore

final class NoteTabsTests: XCTestCase {
    private func vault(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tabs-\(UUID().uuidString)")
        for (p, t) in files {
            let url = root.appendingPathComponent(p)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try t.write(to: url, atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testWriteNoteReplacesFileContents() throws {
        let root = try vault(["a.md": "old"])
        let node = VaultNode(name: "a.md", relativePath: "a.md", isFolder: false, children: [])
        try Vault.writeNote(node, in: root, text: "new **text**")
        XCTAssertEqual(try Vault.readNote(node, in: root), "new **text**")
    }

    func testSeveralNotesOpenAndFocusing() throws {
        let root = try vault(["a.md": "A", "b.md": "B"])
        var tabs = NoteTabs(root: root)
        try tabs.open("a.md")
        try tabs.open("b.md")
        try tabs.open("a.md")  // already open: just focuses it
        XCTAssertEqual(tabs.paths, ["a.md", "b.md"])
        XCTAssertEqual(tabs.active, "a.md")
        XCTAssertEqual(tabs.text("b.md"), "B")
    }

    func testClosingActiveTabFocusesNeighbourAndSavesPendingEdits() throws {
        let root = try vault(["a.md": "A", "b.md": "B"])
        var tabs = NoteTabs(root: root)
        try tabs.open("a.md"); try tabs.open("b.md")
        tabs.edit("b.md", text: "B2", at: t0)
        try tabs.close("b.md")
        XCTAssertEqual(tabs.paths, ["a.md"])
        XCTAssertEqual(tabs.active, "a.md")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("b.md")), "B2")
    }

    func testAutosaveOnlyOneSecondAfterLastEdit() throws {
        let root = try vault(["a.md": "A"])
        var tabs = NoteTabs(root: root)
        try tabs.open("a.md")
        tabs.edit("a.md", text: "A1", at: t0)
        tabs.edit("a.md", text: "A12", at: t0.addingTimeInterval(0.8))
        try tabs.saveDue(at: t0.addingTimeInterval(1.5))  // 0.7 s since last keystroke
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("a.md")), "A")
        try tabs.saveDue(at: t0.addingTimeInterval(1.8))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("a.md")), "A12")
        XCTAssertFalse(tabs.hasPendingEdits)
    }

    func testSaveAllFlushesOnQuit() throws {
        let root = try vault(["a.md": "A", "b.md": "B"])
        var tabs = NoteTabs(root: root)
        try tabs.open("a.md"); try tabs.open("b.md")
        tabs.edit("a.md", text: "A!", at: t0)
        XCTAssertTrue(tabs.hasPendingEdits)
        try tabs.saveAll()
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("a.md")), "A!")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("b.md")), "B")
        XCTAssertFalse(tabs.hasPendingEdits)
    }
}
