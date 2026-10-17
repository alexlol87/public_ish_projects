import Foundation
import XCTest
@testable import ConstellationCore

final class VaultTests: XCTestCase {
    private func makeVault(_ files: [String: String], folders: [String] = []) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
        for folder in folders {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testLoadReportsFoldersAndMarkdownNotesOnly() throws {
        let root = try makeVault([
            "README.md": "# Welcome",
            "acme-shop/overview.md": "Shop",
            "acme-shop/cart-service/api.md": "Cart API",
            "acme-shop/logo.png": "x",
            ".hidden.md": "secret",
        ], folders: ["external"])

        let tree = try Vault.load(root: root)

        XCTAssertEqual(tree.children.map(\.name), ["acme-shop", "external", "README.md"])
        let shop = tree.children[0]
        XCTAssertTrue(shop.isFolder)
        XCTAssertEqual(shop.children.map(\.name), ["cart-service", "overview.md"])
        XCTAssertEqual(shop.children[0].children.map(\.relativePath), ["acme-shop/cart-service/api.md"])
        XCTAssertTrue(tree.children[1].children.isEmpty)
    }

    func testReadNoteReturnsRawText() throws {
        let root = try makeVault(["acme-shop/overview.md": "# Shop\n\nRaw *text*"])
        let tree = try Vault.load(root: root)
        let note = tree.children[0].children[0]

        XCTAssertEqual(try Vault.readNote(note, in: root), "# Shop\n\nRaw *text*")
    }

    func testLoadMissingFolderThrows() {
        XCTAssertThrowsError(try Vault.load(root: URL(fileURLWithPath: "/nonexistent-vault-dir")))
    }
}
