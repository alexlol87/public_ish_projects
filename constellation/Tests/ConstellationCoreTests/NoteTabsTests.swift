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

    private func write(_ root: URL, _ path: String, _ text: String) throws {
        try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    func testCleanNoteReloadsSilentlyOnExternalChange() throws {
        let root = try vault(["a.md": "one"])
        var tabs = NoteTabs(root: root)
        try tabs.open("a.md")
        try write(root, "a.md", "two")
        tabs.diskChanged(["a.md"])
        XCTAssertEqual(tabs.text("a.md"), "two")
        XCTAssertNil(tabs.conflict("a.md"))
        XCTAssertEqual(tabs.revision("a.md"), 1)
    }

    func testOwnSaveEchoIsNotAConflict() throws {
        let root = try vault(["a.md": "one"])
        var tabs = NoteTabs(root: root)
        try tabs.open("a.md")
        tabs.edit("a.md", text: "mine", at: t0)
        try tabs.saveDue(at: t0 + 2)
        tabs.edit("a.md", text: "mine!", at: t0 + 3)  // typed before the FSEvent for the save arrives
        tabs.diskChanged(["a.md"])
        XCTAssertNil(tabs.conflict("a.md"))
        XCTAssertEqual(tabs.text("a.md"), "mine!")
        XCTAssertEqual(tabs.revision("a.md"), 0)
    }

    func testDirtyNoteRaisesConflictAndReloadTakesDisk() throws {
        let root = try vault(["a.md": "one"])
        var tabs = NoteTabs(root: root)
        try tabs.open("a.md")
        tabs.edit("a.md", text: "mine", at: t0)
        try write(root, "a.md", "theirs")
        tabs.diskChanged(["a.md"])
        XCTAssertEqual(tabs.text("a.md"), "mine")
        XCTAssertEqual(tabs.conflict("a.md"), "theirs")
        try tabs.resolveConflict("a.md", reload: true)
        XCTAssertEqual(tabs.text("a.md"), "theirs")
        XCTAssertNil(tabs.conflict("a.md"))
        XCTAssertFalse(tabs.hasPendingEdits)
        XCTAssertEqual(tabs.revision("a.md"), 1)
    }

    func testKeepMineSavesMyTextOverDisk() throws {
        let root = try vault(["a.md": "one"])
        var tabs = NoteTabs(root: root)
        try tabs.open("a.md")
        tabs.edit("a.md", text: "mine", at: t0)
        try write(root, "a.md", "theirs")
        tabs.diskChanged(["a.md"])
        try tabs.resolveConflict("a.md", reload: false)
        XCTAssertNil(tabs.conflict("a.md"))
        XCTAssertEqual(tabs.text("a.md"), "mine")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("a.md"), encoding: .utf8), "mine")
    }

    func testDeletedFileLeavesOpenTextAlone() throws {
        let root = try vault(["a.md": "one"])
        var tabs = NoteTabs(root: root)
        try tabs.open("a.md")
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.md"))
        tabs.diskChanged(["a.md", "other.md"])
        XCTAssertEqual(tabs.text("a.md"), "one")
    }

    func testAutosaveAndSaveAllNeverWriteOverAPendingConflict() throws {
        let root = try vault(["a.md": "one"])
        var tabs = NoteTabs(root: root)
        try tabs.open("a.md")
        tabs.edit("a.md", text: "mine", at: t0)
        try write(root, "a.md", "theirs")
        tabs.diskChanged(["a.md"])
        try tabs.saveDue(at: t0 + 60)
        try tabs.saveAll()
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("a.md"), encoding: .utf8), "theirs")
        XCTAssertTrue(tabs.hasConflicts)
        try tabs.close("a.md")  // refuses rather than dropping my edits or the disk text
        XCTAssertEqual(tabs.paths, ["a.md"])
        XCTAssertEqual(tabs.text("a.md"), "mine")
    }

    func testReloadAfterEditsRemapsMovedTabsAndRebuildsFromDisk() throws {
        let root = try vault(["a.md": "A", "b.md": "B", "c.md": "C"])
        var tabs = NoteTabs(root: root)
        for p in ["a.md", "b.md", "c.md"] { try tabs.open(p) }
        try tabs.open("b.md")
        let edits = try Vault.moveNote("b.md", toFolder: "sub", in: root) + [FileEdit(path: "c.md", range: NSRange(location: 0, length: 1), text: "C2")]
        try FileEdit.apply(edits, root: root)
        tabs.reloadAfter(edits)
        XCTAssertEqual(tabs.paths, ["a.md", "sub/b.md", "c.md"])
        XCTAssertEqual(tabs.active, "sub/b.md")
        XCTAssertEqual(tabs.text("c.md"), "C2")
        XCTAssertEqual(tabs.revision("c.md"), 1)  // bumped so the editor view is rebuilt
        XCTAssertEqual(tabs.revision("sub/b.md"), 1)
    }

    func testReloadAfterEditsDropsDeletedTabs() throws {
        let root = try vault(["a.md": "A", "b.md": "B"])
        var tabs = NoteTabs(root: root)
        try tabs.open("a.md"); try tabs.open("b.md")
        let edits = [FileEdit(path: "b.md", range: NSRange(location: 0, length: 0), text: "", removesFile: true)]
        try FileEdit.apply(edits, root: root)
        tabs.reloadAfter(edits)
        XCTAssertEqual(tabs.paths, ["a.md"])
        XCTAssertEqual(tabs.active, "a.md")
    }
}
