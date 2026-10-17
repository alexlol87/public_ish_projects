import Foundation
import XCTest
@testable import ConstellationCore

final class SearchIndexTests: XCTestCase {
    private func makeVault(_ files: [String: String], folders: [String] = []) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for f in folders { try FileManager.default.createDirectory(at: root.appendingPathComponent(f), withIntermediateDirectories: true) }
        for (path, text) in files { try write(root, path, text) }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func write(_ root: URL, _ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testFoldsCaseAndDiacriticsAndGroupsResults() throws {
        let root = try makeVault([
            "Applications/overview.md": "Nothing here.",
            "cafe-notes.md": "We met at the Café on Friday. Bring the budget.",
            "Résumé.md": "Plain text.",
        ])
        let index = try SearchIndex(root: root)

        XCTAssertEqual(index.search("application").folders, ["Applications"])
        XCTAssertEqual(index.search("resume").notes, ["Résumé.md"])
        let r = index.search("CAFE")
        XCTAssertEqual(r.notes, ["cafe-notes.md"])
        XCTAssertEqual(r.matches.count, 1)
        XCTAssertEqual(r.matches[0].path, "cafe-notes.md")
        XCTAssertEqual(r.matches[0].sentence, "We met at the Café on Friday.")
        let s = r.matches[0].sentence as NSString
        XCTAssertEqual(s.substring(with: r.matches[0].hit), "Café")
    }

    func testSentenceAndOffsetPointAtTheHit() throws {
        let text = "# Title\n\nFirst sentence. The deadline moves! Last one?"
        let root = try makeVault(["a.md": text])
        let m = try SearchIndex(root: root).search("deadline").matches
        XCTAssertEqual(m.map(\.sentence), ["The deadline moves!"])
        XCTAssertEqual((text as NSString).substring(with: NSRange(location: m[0].offset, length: 8)), "deadline")
    }

    func testAppOnlyFilesAndFoldersAreExcluded() throws {
        let root = try makeVault(["AGENTS.md": "secret rule", "templates/daily.md": "secret template", "tags.md": "secret",
                                  "pub.md": "visible secret"])
        let r = try SearchIndex(root: root).search("secret")
        XCTAssertEqual(r.matches.map(\.path), ["pub.md"])
        XCTAssertTrue(try SearchIndex(root: root).search("templates").folders.isEmpty)
        XCTAssertTrue(try SearchIndex(root: root).search("agents").notes.isEmpty)
    }

    func testUpdateAppliesCreateEditDeleteAndFolderRemoval() throws {
        let root = try makeVault(["a.md": "alpha", "dir/b.md": "beta"])
        var index = try SearchIndex(root: root)
        XCTAssertEqual(index.search("beta").matches.count, 1)

        try write(root, "a.md", "gamma")
        try write(root, "new/c.md", "gamma too")
        try index.update(paths: ["a.md", "new/c.md"])
        XCTAssertTrue(index.search("alpha").matches.isEmpty)
        XCTAssertEqual(index.search("gamma").matches.map(\.path).sorted(), ["a.md", "new/c.md"])
        XCTAssertEqual(index.search("new").folders, ["new"])

        try FileManager.default.removeItem(at: root.appendingPathComponent("dir"))
        try index.update(paths: ["dir"])
        XCTAssertTrue(index.search("beta").matches.isEmpty)
        XCTAssertTrue(index.search("dir").folders.isEmpty)
        XCTAssertTrue(index.search("b.md").notes.isEmpty)
    }

    func testBenchmark5000NotesUnder50ms() throws {
        var files: [String: String] = [:]
        for i in 0..<5000 {
            files["f\(i % 50)/note-\(i).md"] = (0..<10).map { "Sentence \($0) of note \(i) talks about topic\($0 * i % 97)." }.joined(separator: " ")
        }
        let index = try SearchIndex(root: try makeVault(files))
        let start = Date()
        let r = index.search("topic42")
        let ms = Date().timeIntervalSince(start) * 1000
        XCTAssertFalse(r.matches.isEmpty)
        XCTAssertLessThan(ms, 50)
    }
}
