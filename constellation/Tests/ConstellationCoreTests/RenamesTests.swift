import Foundation
import XCTest
@testable import ConstellationCore

final class RenamesTests: XCTestCase {
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
    private func read(_ root: URL, _ p: String) throws -> String { try String(contentsOf: root.appendingPathComponent(p), encoding: .utf8) }
    private func brokenLinks(_ root: URL) throws -> [String] {
        let paths = try Vault.notePaths(in: root)
        return try paths.flatMap { p in
            try NoteParser.parse(read(root, p)).links.filter { l in
                if case .broken = Vault.resolve(l.target, among: paths) { return true } else { return false }
            }.map { "\(p): \($0.target)" }
        }
    }

    private let files = [
        "acme/cart.md": "# Cart\n## Totals\nBody",
        "acme/orders.md": "See [[cart]] and [[acme/cart#Totals|sum]] and [[acme/cart.md]]. `[[cart]]`",
        "other.md": "[[Cart#Totals]] [[missing]]",
    ]

    func testRenameNoteRewritesLinksAndUndoRestores() throws {
        let root = try makeVault(files)
        let edits = try Vault.renameNote("acme/cart.md", to: "basket", in: root)
        XCTAssertTrue(edits.contains(.move(from: "acme/cart.md", to: "acme/basket.md")))

        let undo = try Vault.apply(edits, in: root)
        XCTAssertEqual(try read(root, "acme/orders.md"), "See [[basket]] and [[acme/basket#Totals|sum]] and [[acme/basket.md]]. `[[cart]]`")
        XCTAssertEqual(try read(root, "other.md"), "[[basket#Totals]] [[missing]]")
        XCTAssertEqual(try brokenLinks(root), ["other.md: missing"])

        _ = try Vault.apply(undo, in: root)
        XCTAssertEqual(try read(root, "acme/orders.md"), files["acme/orders.md"])
        XCTAssertEqual(try read(root, "acme/cart.md"), files["acme/cart.md"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("acme/basket.md").path))
    }

    func testMoveNoteKeepsNameLinksAndRewritesPathLinks() throws {
        let root = try makeVault(files)
        _ = try Vault.apply(try Vault.moveNote("acme/cart.md", toFolder: "shop/v2", in: root), in: root)
        XCTAssertEqual(try read(root, "acme/orders.md"), "See [[cart]] and [[shop/v2/cart#Totals|sum]] and [[shop/v2/cart.md]]. `[[cart]]`")
        XCTAssertEqual(try read(root, "other.md"), "[[Cart#Totals]] [[missing]]")
        XCTAssertEqual(try brokenLinks(root), ["other.md: missing"])
    }

    func testRenameToNameClashingWithAnotherNoteFallsBackToPath() throws {
        let root = try makeVault(files.merging(["x/basket.md": "x"]) { a, _ in a })
        _ = try Vault.apply(try Vault.renameNote("acme/cart.md", to: "basket", in: root), in: root)
        XCTAssertEqual(try read(root, "other.md"), "[[acme/basket#Totals]] [[missing]]")
    }

    func testRenameOntoExistingNoteThrows() throws {
        let root = try makeVault(files)
        XCTAssertThrowsError(try Vault.renameNote("acme/cart.md", to: "orders", in: root))
    }

    func testRenameHeadingRewritesHeadingAndLinks() throws {
        let root = try makeVault(files)
        let edits = try Vault.renameHeading("Totals", to: "Sums", inNote: "acme/cart.md", in: root)
        let undo = try Vault.apply(edits, in: root)
        XCTAssertEqual(try read(root, "acme/cart.md"), "# Cart\n## Sums\nBody")
        XCTAssertEqual(try read(root, "acme/orders.md"), "See [[cart]] and [[acme/cart#Sums|sum]] and [[acme/cart.md]]. `[[cart]]`")
        XCTAssertEqual(try read(root, "other.md"), "[[Cart#Sums]] [[missing]]")
        _ = try Vault.apply(undo, in: root)
        XCTAssertEqual(try read(root, "other.md"), files["other.md"])
        XCTAssertEqual(try read(root, "acme/cart.md"), files["acme/cart.md"])
    }

    func testRenameTagCoversNestedAndFrontmatter() throws {
        let root = try makeVault([
            "a.md": "---\ntags: [team/pay, other]\n---\nText #team/pay and #team/pay/api, not #teamwork or `#team/pay`.",
            "b.md": "---\ntags:\n  - team\n---\n#team #Team/Pay",
        ])
        let undo = try Vault.apply(try Vault.renameTag("team/pay", to: "squad/billing", in: root), in: root)
        XCTAssertEqual(try read(root, "a.md"), "---\ntags: [squad/billing, other]\n---\nText #squad/billing and #squad/billing/api, not #teamwork or `#team/pay`.")
        XCTAssertEqual(try read(root, "b.md"), "---\ntags:\n  - team\n---\n#team #squad/billing")
        let idx = try TagIndex(root: root)
        XCTAssertNil(idx.notes(for: "team/pay").first)
        _ = try Vault.apply(undo, in: root)
        XCTAssertEqual(try read(root, "b.md"), "---\ntags:\n  - team\n---\n#team #Team/Pay")
    }
}
