import XCTest
@testable import ConstellationCore

final class FormatActionTests: XCTestCase {
    private func r(_ loc: Int, _ len: Int) -> NSRange { NSRange(location: loc, length: len) }
    private func apply(_ a: FormatAction, _ t: String, _ s: NSRange) -> (String, NSRange) {
        let e = MarkdownStyler.apply(a, to: t, selection: s)
        return (e.text, e.selection)
    }

    // Inline: (action, open, close)
    private let inline: [(FormatAction, String, String)] = [
        (.bold, "**", "**"), (.italic, "*", "*"), (.underline, "<u>", "</u>"), (.strikethrough, "~~", "~~"),
        (.inlineCode, "`", "`"), (.link, "[[", "]]"),
    ]

    func testInlineWrapInsertEmptyAndToggleOff() {
        for (a, o, c) in inline {
            var (t, s) = apply(a, "a word b", r(2, 4))
            XCTAssertEqual(t, "a \(o)word\(c) b", "\(a) wrap")
            XCTAssertEqual(s, r(2 + o.utf16.count, 4), "\(a) wrap selection")
            (t, s) = apply(a, t, s)  // inner selected: surrounding markers removed
            XCTAssertEqual(t, "a word b", "\(a) toggle off")
            XCTAssertEqual(s, r(2, 4))

            (t, s) = apply(a, "ab", r(1, 0))
            XCTAssertEqual(t, "a\(o)\(c)b", "\(a) empty")
            XCTAssertEqual(s, r(1 + o.utf16.count, 0))
            (t, s) = apply(a, t, s)  // cursor inside empty pair: removed
            XCTAssertEqual(t, "ab", "\(a) empty toggle off")
            XCTAssertEqual(s, r(1, 0))

            (t, s) = apply(a, "\(o)x\(c)", r(0, o.utf16.count + 1 + c.utf16.count))  // markers inside selection
            XCTAssertEqual(t, "x", "\(a) toggle off, markers selected")
            XCTAssertEqual(s, r(0, 1))
        }
    }

    func testItalicIsNotToggledOffByBoldMarkers() {
        XCTAssertEqual(apply(.italic, "**x**", r(2, 1)).0, "***x***")
    }

    func testCodeBlockWrapEmptyAndToggle() {
        var (t, s) = apply(.codeBlock, "let x", r(0, 5))
        XCTAssertEqual(t, "```\nlet x\n```")
        XCTAssertEqual(s, r(4, 5))
        (t, s) = apply(.codeBlock, t, s)
        XCTAssertEqual(t, "let x")
        (t, s) = apply(.codeBlock, "", r(0, 0))
        XCTAssertEqual(t, "```\n\n```")
        XCTAssertEqual(s, r(4, 0))
    }

    func testLineFormatsMultiLineToggleAndCursor() {
        let lines: [(FormatAction, [String])] = [
            (.heading1, ["# ", "# "]), (.heading2, ["## ", "## "]), (.heading3, ["### ", "### "]),
            (.bulletList, ["- ", "- "]), (.numberedList, ["1. ", "2. "]), (.taskList, ["- [ ] ", "- [ ] "]),
            (.quote, ["> ", "> "]),
        ]
        for (a, p) in lines {
            var (t, s) = apply(a, "one\ntwo\nthree", r(1, 5))  // touches lines 1 and 2 only
            XCTAssertEqual(t, "\(p[0])one\n\(p[1])two\nthree", "\(a)")
            XCTAssertEqual(s, r(0, t.utf16.count - "\nthree".utf16.count), "\(a) selection covers lines")
            (t, s) = apply(a, t, s)
            XCTAssertEqual(t, "one\ntwo\nthree", "\(a) toggle off")

            (t, s) = apply(a, "one", r(3, 0))
            XCTAssertEqual(t, "\(p[0])one")
            XCTAssertEqual(s, r(3 + p[0].utf16.count, 0), "\(a) cursor shifts")
        }
    }

    func testLineFormatSwitchesWithinFamily() {
        XCTAssertEqual(apply(.heading2, "# Title", r(0, 0)).0, "## Title")
        XCTAssertEqual(apply(.numberedList, "- a\n- b", r(0, 7)).0, "1. a\n2. b")
        XCTAssertEqual(apply(.quote, "- a", r(0, 0)).0, "> - a")  // quote nests; not same family
    }

    func testSelectionEndingAtLineStartExcludesThatLine() {
        XCTAssertEqual(apply(.bulletList, "a\nb", r(0, 2)).0, "- a\nb")
    }

    func testTableInsertsSkeletonAndSelectsFirstHeader() {
        let (t, s) = apply(.table, "ab", r(1, 0))
        XCTAssertEqual(t, "a| Column | Column |\n| --- | --- |\n|  |  |\nb")
        XCTAssertEqual(s, r(3, 6))
    }

    func testEmojiUsesUTF16() {
        let (t, s) = apply(.bold, "😀 hi", r(3, 2))
        XCTAssertEqual(t, "😀 **hi**")
        XCTAssertEqual(s, r(5, 2))
    }
}
