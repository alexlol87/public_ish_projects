import Foundation
import XCTest
@testable import ConstellationCore

final class AgentFilesTests: XCTestCase {
    private func created() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agentfiles-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try Vault.create(at: root)
        return root
    }
    private func read(_ root: URL, _ p: String) throws -> String { try String(contentsOf: root.appendingPathComponent(p), encoding: .utf8) }

    func testScaffoldWritesAgentsAndEveryTemplate() throws {
        let root = try created()
        XCTAssertEqual(try read(root, "AGENTS.md"), AgentFiles.agentsMD)
        XCTAssertEqual(Set(AgentFiles.templates.keys), [
            "project", "repo", "endpoints", "architecture", "adr", "requirements", "future", "bugs", "todo",
            "external-api", "client", "archive",
        ])
        for (name, text) in AgentFiles.templates { XCTAssertEqual(try read(root, "templates/\(name).md"), text) }
    }

    func testAgentsMDCoversWorkflowsAndHardRules() {
        let t = AgentFiles.agentsMD
        for s in ["## Ingest", "## Refresh", "## Answer", "repos.txt", "Archive", "Client", "unknown", "tags.md", "sibling"] {
            XCTAssertTrue(t.contains(s), s)
        }
    }

    func testTemplatesGiveTheRightNoteTypes() {
        let expected = ["project": "project", "repo": "repo", "endpoints": "endpoint", "architecture": "architecture", "adr": "adr",
                        "requirements": "requirements", "future": "future", "bugs": "bugs", "todo": "todo",
                        "external-api": "external-api", "client": "client", "archive": "archive"]
        for (name, type) in expected { XCTAssertEqual(NoteParser.parse(AgentFiles.templates[name]!).type, type, name) }
        let repo = NoteParser.parse(AgentFiles.templates["repo"]!)
        for k in ["repo_url", "verified_commit", "verified_on"] { XCTAssertNotNil(repo.frontmatter[k], k) }
    }

    func testEndpointsTemplateHasCallsAndStatus() {
        let p = NoteParser.parse(AgentFiles.templates["endpoints"]!)
        XCTAssertEqual(p.calls.count, 1)
        XCTAssertEqual(p.calls[0].links.count, 1)
        XCTAssertEqual(p.calls[0].links[0].heading, "GET /path")
        XCTAssertEqual(Set(p.status[0].values.keys), ["implemented", "last_changed", "missing"])
    }

    func testClientAndExternalTemplates() {
        let c = NoteParser.parse(AgentFiles.templates["client"]!)
        XCTAssertEqual(c.uses.count, 1)
        XCTAssertEqual(c.uses[0].links.count, 1)
        XCTAssertFalse(NoteParser.parse(AgentFiles.templates["external-api"]!).headings.filter { NoteParser.isEndpoint($0.title) }.isEmpty)
    }

    func testTemplatesAreIgnoredByTheVaultIndexes() throws {
        let root = try created()
        XCTAssertTrue(Vault.isAppOnly("templates/endpoints.md"))
        let g = try Vault.graph(in: root)
        XCTAssertFalse(g.nodes.contains { $0.kind == .ghost })
    }

    func testArchiveFormatInAgentsMDRoundTripsThroughTheArchiver() throws {
        // The example entry in AGENTS.md must be byte-identical to what the app writes.
        let root = try created()
        let bugs = root.appendingPathComponent("shop/orders/bugs.md")
        try FileManager.default.createDirectory(at: bugs.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Bugs\n- [ ] Total ignores discounts → [[endpoints#POST /orders]]\n  Discounts are applied after tax.\n".write(to: bugs, atomically: true, encoding: .utf8)
        try "## POST /orders\n".write(to: bugs.deletingLastPathComponent().appendingPathComponent("endpoints.md"), atomically: true, encoding: .utf8)
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!
        let text = try String(contentsOf: bugs, encoding: .utf8)
        try FileEdit.apply(try Vault.tick(taskAt: 10, in: text, path: "shop/orders/bugs.md", root: root, on: day), root: root)
        let archived = try read(root, "shop/archive/fixed-bugs.md")
        let entry = "### " + archived.components(separatedBy: "\n### ")[1]
        let example = AgentFiles.agentsMD.components(separatedBy: "```markdown\n").first { $0.hasPrefix("### Total") }!
            .components(separatedBy: "```")[0]
        func norm(_ t: String) -> [String] {
            t.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("- fix:") }
                .map { $0.hasPrefix("- closed:") ? "- closed: DATE" : $0 }
        }
        XCTAssertEqual(norm(example), norm(entry))
        XCTAssertTrue(example.contains("- fix: "))
    }

    func testCopyPrompts() {
        let i = AgentFiles.ingestPrompt(repo: "orders")
        XCTAssertTrue(i.contains("orders") && i.contains("AGENTS.md") && i.contains("Ingest"))
        let r = AgentFiles.refreshPrompt(repo: "orders")
        XCTAssertTrue(r.contains("orders") && r.contains("AGENTS.md") && r.contains("Refresh"))
    }

    func testRepoFolderDetection() {
        XCTAssertTrue(AgentFiles.isRepoFolder("shop/orders"))
        for p in ["shop", "shop/orders/sub", "shop/archive", "external/x", "clients/x", "templates/x", ".constellation/x", ""] {
            XCTAssertFalse(AgentFiles.isRepoFolder(p), p)
        }
    }
}
