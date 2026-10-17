import Foundation
import XCTest
@testable import ConstellationCore

final class StalenessThemeTests: XCTestCase {
    private func date(_ s: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)!
    }

    func testFreshStaleNeverMalformed() {
        let now = date("2026-06-30")
        XCTAssertEqual(Staleness.of(verifiedOn: "2026-06-20", now: now), .verified(days: 10))
        XCTAssertEqual(Staleness.of(verifiedOn: "2026-05-01", now: now), .verified(days: 60))
        XCTAssertEqual(Staleness.of(verifiedOn: nil, now: now), .never)
        XCTAssertEqual(Staleness.of(verifiedOn: "  ", now: now), .never)
        XCTAssertEqual(Staleness.of(verifiedOn: "last tuesday", now: now), .malformed)
        XCTAssertEqual(Staleness.of(verifiedOn: "2026-13-45", now: now), .malformed)
    }

    func testHighlightAndLabel() {
        XCTAssertFalse(Staleness.verified(days: 30).isStale(threshold: 30))
        XCTAssertTrue(Staleness.verified(days: 31).isStale(threshold: 30))
        XCTAssertTrue(Staleness.never.isStale(threshold: 30))
        XCTAssertTrue(Staleness.malformed.isStale(threshold: 30))
        XCTAssertEqual(Staleness.verified(days: 10).label, "verified 10 days ago")
        XCTAssertEqual(Staleness.verified(days: 1).label, "verified 1 day ago")
        XCTAssertEqual(Staleness.verified(days: 0).label, "verified today")
        XCTAssertEqual(Staleness.never.label, "never verified")
        XCTAssertEqual(Staleness.verified(days: -3).label, "verified today")  // future date: clamp
    }

    func testRepoStalenessFromVault() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let files = [
            "p/fresh/README.md": "---\ntype: repo\nverified_on: 2026-06-25\n---\n# x",
            "p/old/README.md": "---\ntype: repo\nverified_on: 2025-01-01\n---\n",
            "p/none/README.md": "---\ntype: repo\n---\n",
            "p/bad/README.md": "---\ntype: repo\nverified_on: soon\n---\n",
            "p/plain/README.md": "---\ntype: project\n---\n",
            "p/note.md": "hi",
        ]
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let r = try Vault.repoStaleness(in: root, now: date("2026-06-30"))
        XCTAssertEqual(r, ["p/fresh": .verified(days: 5), "p/old": .verified(days: 545), "p/none": .never, "p/bad": .malformed])
    }

    func testThemes() {
        XCTAssertEqual(Set(ThemeChoice.allCases.map(\.rawValue)), ["Light", "Dark", "Dracula", "One Dark", "System"])
        XCTAssertEqual(ThemeChoice.dracula.palette(systemIsDark: false).background, "#282A36")
        XCTAssertEqual(ThemeChoice.oneDark.palette(systemIsDark: false).background, "#282C34")
        XCTAssertTrue(ThemeChoice.dracula.palette(systemIsDark: false).isDark)
        XCTAssertFalse(ThemeChoice.light.palette(systemIsDark: true).isDark)
        XCTAssertEqual(ThemeChoice.system.palette(systemIsDark: true), ThemeChoice.dark.palette(systemIsDark: false))
        XCTAssertEqual(ThemeChoice.system.palette(systemIsDark: false), ThemeChoice.light.palette(systemIsDark: true))
        for t in ThemeChoice.allCases {
            let p = t.palette(systemIsDark: false)
            for h in [p.background, p.text, p.accent, p.heading, p.link, p.code, p.tag, p.folderNode, p.noteNode, p.stale] {
                XCTAssertNotNil(h.range(of: "^#[0-9A-F]{6}$", options: .regularExpression), "\(t) \(h)")
            }
        }
    }
}
