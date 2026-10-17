import Foundation
import XCTest
@testable import ConstellationCore

final class LinksTests: XCTestCase {
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

    private lazy var files = [
        "README.md": "Home",
        "acme-shop/overview.md": "# Overview\n\n## Goals\nText",
        "acme-shop/cart-service/api.md": "API",
        "acme-shop/notes.md": "a",
        "clients/notes.md": "b",
        "templates/daily.md": "app only",
    ]

    func testResolvesByVaultPathWithOrWithoutExtension() throws {
        let root = try makeVault(files)
        XCTAssertEqual(try Vault.resolve("acme-shop/cart-service/api", in: root), .note("acme-shop/cart-service/api.md"))
        XCTAssertEqual(try Vault.resolve("acme-shop/overview.md", in: root), .note("acme-shop/overview.md"))
    }

    func testResolvesByUniqueNameCaseInsensitive() throws {
        let root = try makeVault(files)
        XCTAssertEqual(try Vault.resolve("API", in: root), .note("acme-shop/cart-service/api.md"))
    }

    func testAmbiguousNameIsBroken() throws {
        let root = try makeVault(files)
        XCTAssertEqual(try Vault.resolve("notes", in: root), .broken(createPath: "notes.md"))
        XCTAssertEqual(try Vault.resolve("acme-shop/notes", in: root), .note("acme-shop/notes.md"))
    }

    func testMissingTargetIsBrokenWithCreatePath() throws {
        let root = try makeVault(files)
        XCTAssertEqual(try Vault.resolve("ideas/new", in: root), .broken(createPath: "ideas/new.md"))
    }

    func testAppOnlyFilesAreNotLinkTargets() throws {
        let root = try makeVault(files)
        XCTAssertEqual(try Vault.resolve("daily", in: root), .broken(createPath: "daily.md"))
    }

    func testCreateNoteMakesFileAndResolves() throws {
        let root = try makeVault(files)
        let path = try Vault.createNote(forLink: "ideas/new", in: root)
        XCTAssertEqual(path, "ideas/new.md")
        XCTAssertEqual(try Vault.resolve("ideas/new", in: root), .note("ideas/new.md"))
    }

    func testParserFindsLinksWithHeadingAndAlias() {
        let text = "See [[api]], [[overview#Goals]] and [[notes|the notes]] or [[a/b#H|x]]."
        let links = NoteParser.parse(text).links
        XCTAssertEqual(links.map(\.target), ["api", "overview", "notes", "a/b"])
        XCTAssertEqual(links.map(\.heading), [nil, "Goals", nil, "H"])
        XCTAssertEqual(links.map(\.alias), [nil, nil, "the notes", "x"])
        XCTAssertEqual((text as NSString).substring(with: links[0].range), "[[api]]")
    }

    func testLinksInCodeAreIgnored() {
        let text = "`[[inline]]`\n```\n[[fenced]]\n```\n[[real]]"
        XCTAssertEqual(NoteParser.parse(text).links.map(\.target), ["real"])
    }

    func testParserFindsHeadingsOutsideCode() {
        let text = "# One\n```\n# not\n```\n## Two\n"
        let hs = NoteParser.parse(text).headings
        XCTAssertEqual(hs.map(\.title), ["One", "Two"])
        XCTAssertEqual(hs.map(\.level), [1, 2])
        XCTAssertEqual((text as NSString).substring(with: hs[1].range), "## Two")
    }

    func testBacklinksListSourcesIncludingByNameAndExcludingSelfAndCode() throws {
        let root = try makeVault(files.merging([
            "a.md": "Go to [[acme-shop/overview#Goals]] and [[overview|ov]]",
            "b.md": "`[[overview]]` [[nothing]]",
            "acme-shop/overview.md": "# Overview\n[[overview]] self",
        ]) { $1 })
        let back = try Vault.backlinks(to: "acme-shop/overview.md", in: root)
        XCTAssertEqual(back.map(\.path), ["a.md", "a.md"])
        XCTAssertEqual(back.map(\.link.heading), ["Goals", nil])
    }

    func testCompletionsForNotesAndHeadings() throws {
        let root = try makeVault(files)
        XCTAssertEqual(try Vault.completions(for: "ov", in: root), ["overview"])
        XCTAssertEqual(try Vault.completions(for: "overview#", in: root), ["overview#Overview", "overview#Goals"])
    }
}
