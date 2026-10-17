import XCTest
@testable import ConstellationCore

final class MarkdownWidgetsTests: XCTestCase {
    private func r(_ l: Int, _ n: Int) -> NSRange { NSRange(location: l, length: n) }

    func testImageIsAWidgetRangeHiddenOffCursorLine() {
        let text = "a\n![cat](pics/cat.png)\nb"
        let out = MarkdownStyler.style(text)
        XCTAssertEqual(out.styled, [StyledRange(range: r(2, 20), role: .image(path: "pics/cat.png", alt: "cat"))])
        XCTAssertEqual(out.hidden, [r(2, 20)])
    }

    func testImageOnCursorLineShowsRawMarkdown() {
        let text = "![cat](c.png)"
        let out = MarkdownStyler.style(text, cursorLine: r(0, 13))
        XCTAssertEqual(out.styled, [])
        XCTAssertEqual(out.hidden, [])
    }

    func testTableAlignsColumnsAndHidesRawBlock() {
        let text = "| a | bb |\n|---|:--:|\n| ccc | d |\nafter"
        let out = MarkdownStyler.style(text)
        let rendered = "| a   | bb |\n| --- | -- |\n| ccc | d  |"
        XCTAssertEqual(out.styled, [StyledRange(range: r(0, 33), role: .table(rendered: rendered))])
        XCTAssertEqual(out.hidden, [r(0, 33)])
    }

    func testCursorAnywhereInTableShowsRaw() {
        let text = "| a | b |\n|---|---|\n| 1 | 2 |\n"
        let out = MarkdownStyler.style(text, cursorLine: MarkdownStyler.lineRange(containing: 15, in: text))
        XCTAssertEqual(out.styled, [])
        XCTAssertEqual(out.hidden, [])
    }

    func testPipesWithoutDelimiterRowAreNotATable() {
        XCTAssertEqual(MarkdownStyler.style("| a | b |\n| c | d |").styled, [])
    }

    func testFencesStayCodeBlocks() {
        let text = "```mermaid\n| a | b |\n|---|---|\n![x](y.png)\n```"
        let roles = MarkdownStyler.style(text).styled.map(\.role)
        XCTAssertEqual(roles, [.codeBlock, .codeBlock, .codeBlock])
    }

    func testImageResolution() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("img-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        _ = fm.createFile(atPath: root.appendingPathComponent("notes/near.png").path, contents: Data())
        _ = fm.createFile(atPath: root.appendingPathComponent("assets/far.png").path, contents: Data())
        addTeardownBlock { try? fm.removeItem(at: root) }
        XCTAssertEqual(ImagePaths.resolve("near.png", note: "notes/a.md", root: root)?.lastPathComponent, "near.png")
        XCTAssertEqual(ImagePaths.resolve("assets/far.png", note: "notes/a.md", root: root)?.lastPathComponent, "far.png")
        XCTAssertEqual(ImagePaths.resolve("/assets/far.png", note: "notes/a.md", root: root)?.lastPathComponent, "far.png")
        XCTAssertNil(ImagePaths.resolve("gone.png", note: "notes/a.md", root: root))
        XCTAssertNil(ImagePaths.resolve("../../etc/passwd", note: "notes/a.md", root: root))
    }
}
