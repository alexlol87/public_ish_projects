import BorderCore
import Foundation
import XCTest

final class ColorMemoryTests: XCTestCase {
    private let vsCode = "com.microsoft.VSCode"
    private let terminal = "com.apple.Terminal"
    private let palette = Palette.defaultColors

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    // MARK: normalizedTitle

    func testVSCodeKeepsOnlyTheWorkspaceName() {
        func normalized(_ title: String, _ bundleID: String = "com.microsoft.VSCode") -> String? {
            ColorMemory.normalizedTitle(title, bundleID: bundleID)
        }
        XCTAssertEqual(normalized("● main.swift — myproj"), "myproj")
        XCTAssertEqual(normalized("README.md — myproj"), "myproj")
        XCTAssertEqual(normalized("main.swift — myproj — Visual Studio Code"), "myproj")
        let insiders = "com.microsoft.VSCodeInsiders"
        XCTAssertEqual(normalized("a.swift — proj — Visual Studio Code - Insiders", insiders), "proj")
        XCTAssertEqual(normalized("app.ts - web - Cursor", "com.todesktop.230313mzl4w4u92"), "web")
        XCTAssertNil(normalized("Visual Studio Code"))
    }

    func testTerminalDropsWindowSize() {
        XCTAssertEqual(ColorMemory.normalizedTitle("alex — -zsh — 80×24", bundleID: terminal), "alex — -zsh")
        XCTAssertEqual(ColorMemory.normalizedTitle("alex — -zsh — 120×40", bundleID: terminal), "alex — -zsh")
        XCTAssertEqual(ColorMemory.normalizedTitle("alex — -zsh — 120x40", bundleID: terminal), "alex — -zsh")
        XCTAssertEqual(ColorMemory.normalizedTitle("alex — -zsh — 120 × 40", bundleID: terminal), "alex — -zsh")
        XCTAssertNil(ColorMemory.normalizedTitle("80×24", bundleID: terminal))
        XCTAssertNil(ColorMemory.normalizedTitle("Terminal", bundleID: terminal))
    }

    func testOtherAppsKeepAllSegmentsWithCasePreserved() {
        let app = "com.example.Editor"
        XCTAssertEqual(ColorMemory.normalizedTitle("Report - Draft", bundleID: app), "Report — Draft")
        XCTAssertEqual(ColorMemory.normalizedTitle("  MyNotes  ", bundleID: app), "MyNotes")
        XCTAssertEqual(ColorMemory.normalizedTitle("* notes.txt", bundleID: app), "notes.txt")
        XCTAssertEqual(ColorMemory.normalizedTitle("•Inbox", bundleID: app), "Inbox")
        // App names are only dropped for the app they belong to; "box" is not a window size.
        XCTAssertEqual(ColorMemory.normalizedTitle("Terminal - box", bundleID: app), "Terminal — box")
    }

    func testEmptyOrWhitespaceTitlesHaveNoKey() {
        for title in ["", "   ", "\n\t", "●", "● ", " - "] {
            XCTAssertNil(ColorMemory.normalizedTitle(title, bundleID: "com.example.Editor"), "\"\(title)\"")
            XCTAssertNil(ColorMemory.normalizedTitle(title, bundleID: vsCode), "\"\(title)\"")
        }
    }

    // MARK: record / lookup

    func testVSCodeWindowMatchesAcrossActiveFiles() {
        var memory = ColorMemory()
        memory.record(bundleID: vsCode, title: "● main.swift — myproj", color: palette[3], now: date(1))
        XCTAssertEqual(memory.lookup(bundleID: vsCode, title: "README.md — myproj", excluding: []), palette[3])
        XCTAssertNil(memory.lookup(bundleID: vsCode, title: "README.md — otherproj", excluding: []))
    }

    func testTerminalWindowMatchesAcrossSizes() {
        var memory = ColorMemory()
        memory.record(bundleID: terminal, title: "alex — -zsh — 80×24", color: palette[4], now: date(1))
        XCTAssertEqual(memory.lookup(bundleID: terminal, title: "alex — -zsh — 120×40", excluding: []), palette[4])
    }

    func testWindowsSharingAKeyGetDistinctColors() {
        var memory = ColorMemory()
        memory.record(bundleID: terminal, title: "alex — -zsh — 80×24", color: palette[1], now: date(1))
        memory.record(bundleID: terminal, title: "alex — -zsh — 120×40", color: palette[2], now: date(2))

        let title = "alex — -zsh — 80×24"
        let first = memory.lookup(bundleID: terminal, title: title, excluding: [])
        XCTAssertEqual(first, palette[2])
        let second = memory.lookup(bundleID: terminal, title: title, excluding: [palette[2]])
        XCTAssertEqual(second, palette[1])
        XCTAssertNil(memory.lookup(bundleID: terminal, title: title, excluding: [palette[2], palette[1]]))
    }

    func testDifferentBundleIDsDoNotMatch() {
        var memory = ColorMemory()
        memory.record(bundleID: terminal, title: "alex — -zsh", color: palette[0], now: date(1))
        XCTAssertNil(memory.lookup(bundleID: "com.googlecode.iterm2", title: "alex — -zsh", excluding: []))
    }

    func testUnusableTitlesAndBundleIDsAreNotRecorded() {
        var memory = ColorMemory()
        memory.record(bundleID: terminal, title: "   ", color: palette[0], now: date(1))
        memory.record(bundleID: "", title: "Report", color: palette[0], now: date(1))
        XCTAssertTrue(memory.isEmpty)
        XCTAssertNil(memory.lookup(bundleID: terminal, title: "   ", excluding: []))

        memory.record(bundleID: terminal, title: "alex — -zsh", color: palette[0], now: date(1))
        XCTAssertFalse(memory.isEmpty)
    }

    func testColorsAreMostRecentFirstAndDeduplicated() {
        var memory = ColorMemory()
        let title = "Report"
        let app = "com.example.Editor"
        memory.record(bundleID: app, title: title, color: palette[0], now: date(1))
        memory.record(bundleID: app, title: title, color: palette[1], now: date(2))
        memory.record(bundleID: app, title: title, color: palette[0], now: date(3))

        XCTAssertEqual(memory.lookup(bundleID: app, title: title, excluding: []), palette[0])
        XCTAssertEqual(memory.lookup(bundleID: app, title: title, excluding: [palette[0]]), palette[1])
        XCTAssertNil(memory.lookup(bundleID: app, title: title, excluding: [palette[0], palette[1]]))
    }

    func testKeepsAtMostTenColorsPerKey() {
        var memory = ColorMemory()
        let app = "com.example.Editor"
        let extra = RGBAColor(red: 0.5, green: 0.5, blue: 0.5)
        for (offset, color) in (palette + [extra]).enumerated() {
            memory.record(bundleID: app, title: "Doc", color: color, now: date(TimeInterval(offset)))
        }
        // Remembered now: extra, palette[9] ... palette[1]; palette[0] was the oldest and fell off.
        XCTAssertEqual(memory.lookup(bundleID: app, title: "Doc", excluding: [extra]), palette[9])
        let claimed = [extra] + Array(palette[1...])
        XCTAssertNil(memory.lookup(bundleID: app, title: "Doc", excluding: claimed))
    }

    // MARK: prune

    func testPruneKeepsMostRecentlySeenKeys() {
        var memory = ColorMemory()
        let app = "com.example.Editor"
        memory.record(bundleID: app, title: "A", color: palette[0], now: date(10))
        memory.record(bundleID: app, title: "B", color: palette[1], now: date(20))
        memory.record(bundleID: app, title: "C", color: palette[2], now: date(30))
        memory.record(bundleID: app, title: "A", color: palette[0], now: date(40)) // A seen again: now the newest

        memory.prune(maxKeys: 2)
        XCTAssertEqual(memory.lookup(bundleID: app, title: "A", excluding: []), palette[0])
        XCTAssertNil(memory.lookup(bundleID: app, title: "B", excluding: []))
        XCTAssertEqual(memory.lookup(bundleID: app, title: "C", excluding: []), palette[2])

        let beforeNoOp = memory
        memory.prune(maxKeys: 5)
        XCTAssertEqual(memory, beforeNoOp)

        memory.prune(maxKeys: 0)
        XCTAssertTrue(memory.isEmpty)
    }

    // MARK: Codable

    func testCodableRoundTrip() throws {
        var memory = ColorMemory()
        memory.record(bundleID: vsCode, title: "● main.swift — myproj", color: palette[3], now: date(100))
        memory.record(bundleID: terminal, title: "alex — -zsh — 80×24", color: palette[1], now: date(200))
        memory.record(bundleID: terminal, title: "alex — -zsh — 80×24", color: palette[2], now: date(300))

        let data = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(ColorMemory.self, from: data)
        XCTAssertEqual(decoded, memory)
        XCTAssertEqual(decoded.lookup(bundleID: vsCode, title: "x.swift — myproj", excluding: []), palette[3])
        XCTAssertEqual(decoded.lookup(bundleID: terminal, title: "alex — -zsh", excluding: [palette[2]]), palette[1])

        let empty = try JSONDecoder().decode(ColorMemory.self, from: JSONEncoder().encode(ColorMemory()))
        XCTAssertTrue(empty.isEmpty)
    }
}
