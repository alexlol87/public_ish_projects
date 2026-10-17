import Foundation
import XCTest
@testable import ConstellationCore

final class TagTests: XCTestCase {
    private func names(_ text: String) -> [String] { Vault.parse(text).tags.map(\.name) }

    func testValidAndInvalidForms() {
        XCTAssertEqual(names("Ship it #release and #team/payments now"), ["release", "team/payments"])
        XCTAssertEqual(names("#first at line start"), ["first"])
        XCTAssertEqual(names("# Heading\n## Another\n#123 #fff #FF00aa #1st"), [])
        XCTAssertEqual(names("See https://example.com/page#section and a#b and `#code`"), [])
        XCTAssertEqual(names("[jump](#intro) and [[Note#Head]]"), [])
        XCTAssertEqual(names("```\n#fenced\n```\n#real"), ["real"])
    }

    func testRangeCoversHashAndName() {
        let t = Vault.parse("ab #team/x!").tags[0]
        XCTAssertEqual(t.range, NSRange(location: 3, length: 7))
    }

    func testFrontmatterTags() {
        XCTAssertEqual(names("---\ntitle: x\ntags: [alpha, \"beta\", #gamma]\n---\nbody #delta"), ["alpha", "beta", "gamma", "delta"])
        XCTAssertEqual(names("---\ntags:\n  - one\n  - two/sub\nother: y\n  - notatag\n---\n"), ["one", "two/sub"])
        XCTAssertEqual(names("---\ntags: a, b\n---"), ["a", "b"])
        XCTAssertEqual(names("text\n---\ntags: [nope]\n---"), [])
    }

    func testStylerGivesTagsTheirOwnRole() {
        let r = MarkdownStyler.style("go #team/x now `#no` # H")
        XCTAssertEqual(r.styled.filter { $0.role == .tag }.map(\.range), [NSRange(location: 3, length: 7)])
    }

    private func makeIndex(_ files: [String: String]) throws -> VaultIndex {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tags-\(UUID().uuidString)")
        for (p, t) in files {
            let u = root.appendingPathComponent(p)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try t.write(to: u, atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try VaultIndex(root: root)
    }

    func testCountsFoldCaseAndRollUpToParents() throws {
        let idx = try makeIndex([
            "a.md": "#Team/Payments and #team/payments again, #team/infra",
            "sub/b.md": "---\ntags: [TEAM]\n---\nx",
            "c.md": "#other",
            "tags.md": "#ignored",
        ])
        let tree = idx.tagTree(sortedBy: .name)
        XCTAssertEqual(tree.map(\.tag), ["other", "team"])
        let team = tree[1]
        XCTAssertEqual(team.count, 2)  // a.md and b.md, each once
        XCTAssertEqual(team.children.map(\.tag), ["team/infra", "team/payments"])
        XCTAssertEqual(team.children.map(\.count), [1, 1])
        XCTAssertEqual(idx.tagTree(sortedBy: .count).map(\.tag), ["team", "other"])
    }

    func testNotesForTagIncludeChildrenAndTheLine() throws {
        let idx = try makeIndex(["a.md": "intro\nfix the bug #team/payments today\n", "b.md": "#team"])
        let hits = idx.tagHits(for: "TEAM")
        XCTAssertEqual(hits.map(\.path), ["a.md", "b.md"])
        XCTAssertEqual(hits[0].line, "fix the bug #team/payments today")
        XCTAssertEqual(idx.tagHits(for: "team/payments").map(\.path), ["a.md"])
    }

    /// A fully typed Tag must not be offered back: accepting it re-inserts the text, which re-opens completion forever.
    func testCompletionsNeverOfferExactlyWhatIsTyped() throws {
        let idx = try makeIndex(["a.md": "#acme #team/payments"])
        XCTAssertEqual(idx.tagCompletions(for: "acme"), [])
        XCTAssertEqual(idx.tagCompletions(for: "ACME"), [])
        XCTAssertEqual(idx.tagCompletions(for: "team"), ["team/payments"])
    }

    func testCompletionsAndUpdate() throws {
        let idx = try makeIndex(["a.md": "#team/payments #tax"])
        XCTAssertEqual(idx.tagCompletions(for: "ta"), ["tax"])
        XCTAssertEqual(idx.tagCompletions(for: "TEAM"), ["team/payments"])
        try "#taxes".write(to: idx.root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try idx.ingest(paths: ["a.md"])
        XCTAssertEqual(idx.tagCompletions(for: "ta"), ["taxes"])
        XCTAssertEqual(Vault.typedTagPrefix(inLineBeforeCursor: "see #te"), "te")
        XCTAssertNil(Vault.typedTagPrefix(inLineBeforeCursor: "# te"))
        XCTAssertNil(Vault.typedTagPrefix(inLineBeforeCursor: "a#te"))
    }

    func testSearchTagTermFiltersAndCombinesWithText() throws {
        let idx = try makeIndex(["z.md": "nothing"])
        let root = idx.root
        try "Refund policy #payments".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "Refund for travel".write(to: root.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try "Invoices #Payments/eu".write(to: root.appendingPathComponent("c.md"), atomically: true, encoding: .utf8)
        let s = try VaultIndex(root: root)
        let r = s.search("#payments refund")
        XCTAssertEqual(r.notes, [])
        XCTAssertEqual(r.matches.map(\.path), ["a.md"])
        XCTAssertEqual(s.search("#PAYMENTS").notes, ["a.md", "c.md"])
        XCTAssertEqual(s.search("refund").matches.count, 2)
    }
}
