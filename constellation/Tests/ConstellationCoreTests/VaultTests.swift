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

    // MARK: create / reopen / app-only

    private func emptyDir() throws -> URL { try makeVault([:], folders: ["."]) }

    func testCreateWritesExactlyTheStarterSet() throws {
        let root = try emptyDir()
        try Vault.create(at: root)

        let names = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        XCTAssertEqual(names, [".constellation", "AGENTS.md", "README.md", "clients", "external", "repos.txt", "tags.md", "templates"])
        var isDir: ObjCBool = false
        for d in [".constellation", "clients", "external", "templates"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(d).path, isDirectory: &isDir) && isDir.boolValue, d)
        }
    }

    func testCreateRefusesNonEmptyFolderAndKeepsFiles() throws {
        let root = try makeVault(["README.md": "mine"])
        XCTAssertThrowsError(try Vault.create(at: root))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8), "mine")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["README.md"])
    }

    func testCreateMakesMissingFolder() throws {
        let root = try emptyDir().appendingPathComponent("new-vault")
        try Vault.create(at: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("README.md").path))
    }

    func testCreatedVaultLoadsAndMarksAppOnlyNodes() throws {
        let root = try emptyDir()
        try Vault.create(at: root)
        let tree = try Vault.load(root: root)

        let byPath = Dictionary(uniqueKeysWithValues: tree.children.map { ($0.relativePath, $0.isAppOnly) })
        XCTAssertEqual(byPath, [
            ".constellation": true, "templates": true, "clients": false, "external": false,
            "AGENTS.md": true, "README.md": false, "repos.txt": true, "tags.md": true,
        ])
    }

    func testAppOnlyCoversNestedPaths() {
        XCTAssertTrue(Vault.isAppOnly("templates/project.md"))
        XCTAssertTrue(Vault.isAppOnly(".constellation/settings.json"))
        XCTAssertFalse(Vault.isAppOnly("shop/AGENTS.md"))
        XCTAssertFalse(Vault.isAppOnly("shop/templates-notes.md"))
    }

    func testReopenableOnlyWhenFolderStillExists() throws {
        let root = try emptyDir()
        XCTAssertEqual(Vault.reopenable(root.path)?.path, root.path)
        XCTAssertNil(Vault.reopenable(root.appendingPathComponent("gone").path))
        XCTAssertNil(Vault.reopenable(nil))
    }
}
