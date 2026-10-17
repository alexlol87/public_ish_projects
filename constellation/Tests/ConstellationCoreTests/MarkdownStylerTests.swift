import XCTest
@testable import ConstellationCore

final class MarkdownStylerTests: XCTestCase {
    private func r(_ loc: Int, _ len: Int) -> NSRange { NSRange(location: loc, length: len) }

    // Cursor far away (nil) means every line is "off the cursor line".
    func testHeadingOffCursorStylesTitleAndHidesMarker() {
        let out = MarkdownStyler.style("## Hello")
        XCTAssertEqual(out.styled, [StyledRange(range: r(3, 5), role: .heading(level: 2))])
        XCTAssertEqual(out.hidden, [r(0, 3)])
    }

    func testHeadingOnCursorLineKeepsMarker() {
        let out = MarkdownStyler.style("## Hello", cursorLine: r(0, 8))
        XCTAssertEqual(out.styled, [StyledRange(range: r(3, 5), role: .heading(level: 2))])
        XCTAssertEqual(out.hidden, [])
    }

    private func roles(_ o: StyleResult) -> [StyleRole] { o.styled.map(\.role) }

    func testBold() {
        let out = MarkdownStyler.style("a **b** c")
        XCTAssertEqual(out.styled, [StyledRange(range: r(4, 1), role: .bold)])
        XCTAssertEqual(out.hidden, [r(2, 2), r(5, 2)])
    }

    func testItalicStarAndUnderscore() {
        let out = MarkdownStyler.style("*a* and _b_")
        XCTAssertEqual(out.styled.map(\.range), [r(1, 1), r(9, 1)])
        XCTAssertEqual(roles(out), [.italic, .italic])
        XCTAssertEqual(out.hidden, [r(0, 1), r(2, 1), r(8, 1), r(10, 1)])
    }

    func testInlineCodeContentsAreNotStyled() {
        let out = MarkdownStyler.style("`**x** [a](b)`")
        XCTAssertEqual(out.styled, [StyledRange(range: r(1, 12), role: .inlineCode)])
        XCTAssertEqual(out.hidden, [r(0, 1), r(13, 1)])
    }

    func testLink() {
        let out = MarkdownStyler.style("see [docs](a/b.md)")
        XCTAssertEqual(out.styled, [StyledRange(range: r(5, 4), role: .link)])
        XCTAssertEqual(out.hidden, [r(4, 1), r(9, 9)])
    }

    func testFencedCodeIsNotStyledInside() {
        let text = "```swift\n**not bold**\n```\nafter"
        let out = MarkdownStyler.style(text)
        XCTAssertEqual(out.styled, [StyledRange(range: r(9, 12), role: .codeBlock)])
        XCTAssertEqual(out.hidden, [r(0, 8), r(22, 3)])
    }

    func testCursorLineKeepsItsMarkersOnly() {
        let text = "**a**\n**b**"
        let cursor = MarkdownStyler.lineRange(containing: 8, in: text)
        let out = MarkdownStyler.style(text, cursorLine: cursor)
        XCTAssertEqual(out.hidden, [r(0, 2), r(3, 2)])
        XCTAssertEqual(out.styled.count, 2)
    }

    func testCursorAtEndOfTextOnTrailingNewlineLine() {
        let out = MarkdownStyler.style("**a**\n", cursorLine: MarkdownStyler.lineRange(containing: 3, in: "**a**\n"))
        XCTAssertEqual(out.hidden, [])
    }

    func testSelectionSpanningLinesKeepsMarkersOnEveryTouchedLine() {
        let text = "**a**\n**b**\n**c**"
        let sel = MarkdownStyler.lineRange(covering: r(3, 5), in: text)  // from line 1 into line 2
        XCTAssertEqual(sel, r(0, 12))
        XCTAssertEqual(MarkdownStyler.style(text, cursorLine: sel).hidden, [r(12, 2), r(15, 2)])
    }

    func testSelectionEndingAtLineStartDoesNotTouchNextLine() {
        let text = "**a**\n**b**"
        XCTAssertEqual(MarkdownStyler.lineRange(covering: r(0, 6), in: text), r(0, 6))
    }
}
