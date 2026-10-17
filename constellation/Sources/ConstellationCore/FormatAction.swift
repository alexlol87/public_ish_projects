import Foundation

/// Toolbar / shortcut actions. Buttons and shortcuts both call `MarkdownStyler.apply`.
public enum FormatAction: CaseIterable {
    case bold, italic, underline, strikethrough, inlineCode, codeBlock
    case heading1, heading2, heading3, bulletList, numberedList, taskList, quote, link, table
}

public struct TextEdit: Equatable {
    public var text: String
    public var selection: NSRange  // UTF-16
}

extension MarkdownStyler {
    /// Pure (text, selection, action) -> (text, selection). Applying a format that is already present removes it.
    public static func apply(_ action: FormatAction, to text: String, selection: NSRange) -> TextEdit {
        switch action {
        case .bold: return wrap(text, selection, "**", "**")
        case .italic: return wrap(text, selection, "*", "*")
        case .underline: return wrap(text, selection, "<u>", "</u>")
        case .strikethrough: return wrap(text, selection, "~~", "~~")
        case .inlineCode: return wrap(text, selection, "`", "`")
        case .link: return wrap(text, selection, "[[", "]]")
        case .codeBlock: return wrap(text, selection, "```\n", "\n```")  // shortcut: assumes selection starts at a line start
        case .heading1: return lines(text, selection, heading: 1)
        case .heading2: return lines(text, selection, heading: 2)
        case .heading3: return lines(text, selection, heading: 3)
        case .bulletList: return lines(text, selection, list: { _ in "- " })
        case .numberedList: return lines(text, selection, list: { "\($0 + 1). " })
        case .taskList: return lines(text, selection, list: { _ in "- [ ] " })
        case .quote: return lines(text, selection, quote: true)
        case .table:
            let head = "| Column | Column |\n| --- | --- |\n|  |  |\n"
            let ns = text as NSString
            return TextEdit(text: ns.replacingCharacters(in: selection, with: head),
                            selection: NSRange(location: selection.location + 2, length: 6))
        }
    }

    private static func wrap(_ text: String, _ sel: NSRange, _ open: String, _ close: String) -> TextEdit {
        let ns = text as NSString
        let o = open.utf16.count, c = close.utf16.count
        let selText = ns.substring(with: sel)
        func unwrapped(_ loc: Int, _ inner: Int, markersAt start: Int) -> TextEdit {
            let whole = NSRange(location: start, length: inner + o + c)
            return TextEdit(text: ns.replacingCharacters(in: whole, with: ns.substring(with: NSRange(location: start + o, length: inner))),
                            selection: NSRange(location: loc, length: inner))
        }
        // Markers just outside the selection (or around the cursor in an empty pair).
        if sel.location >= o, NSMaxRange(sel) + c <= ns.length,
           ns.substring(with: NSRange(location: sel.location - o, length: o)) == open,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: c)) == close,
           // shortcut: only `*` is guarded against `**`; mixed `***x***` is treated as bold-only
           !(open == "*" && (sel.location >= 2 && ns.character(at: sel.location - 2) == 42 || NSMaxRange(sel) + 1 < ns.length && ns.character(at: NSMaxRange(sel) + 1) == 42)) {
            return unwrapped(sel.location - o, sel.length, markersAt: sel.location - o)
        }
        // Markers inside the selection.
        if sel.length >= o + c, selText.hasPrefix(open), selText.hasSuffix(close) {
            return unwrapped(sel.location, sel.length - o - c, markersAt: sel.location)
        }
        let out = ns.replacingCharacters(in: sel, with: open + selText + close)
        return TextEdit(text: out, selection: NSRange(location: sel.location + o, length: sel.length))
    }

    private static let headingRE = try! NSRegularExpression(pattern: "^#{1,6} ")
    private static let listRE = try! NSRegularExpression(pattern: "^(- \\[[ xX]\\] |- |\\d+\\. )")

    private static func lines(_ text: String, _ sel: NSRange, heading: Int? = nil, list: ((Int) -> String)? = nil, quote: Bool = false) -> TextEdit {
        let ns = text as NSString
        var end = NSMaxRange(sel)
        if sel.length > 0, end > 0, ns.character(at: end - 1) == 10 { end -= 1 }  // ending at a line start excludes that line
        let block = ns.lineRange(for: NSRange(location: sel.location, length: end - sel.location))
        var body = block
        if body.length > 0, ns.character(at: NSMaxRange(body) - 1) == 10 { body.length -= 1 }
        let old = ns.substring(with: body).components(separatedBy: "\n")
        let strip: NSRegularExpression? = heading != nil ? headingRE : list != nil ? listRE : nil
        func prefix(_ l: String) -> String {
            guard let re = strip, let m = re.firstMatch(in: l, range: NSRange(location: 0, length: (l as NSString).length)) else { return quote && l.hasPrefix("> ") ? "> " : "" }
            return (l as NSString).substring(with: m.range)
        }
        func target(_ i: Int) -> String { heading.map { String(repeating: "#", count: $0) + " " } ?? list?(i) ?? "> " }
        let removing = old.indices.allSatisfy { prefix(old[$0]) == target($0) }
        let new = old.enumerated().map { i, l in
            let p = prefix(l)
            return (removing ? "" : target(i)) + (l as NSString).substring(from: p.utf16.count)
        }.joined(separator: "\n")
        let out = ns.replacingCharacters(in: body, with: new)
        if sel.length == 0 {  // single line
            let delta = new.utf16.count - body.length
            return TextEdit(text: out, selection: NSRange(location: max(body.location, sel.location + delta), length: 0))
        }
        return TextEdit(text: out, selection: NSRange(location: body.location, length: new.utf16.count))
    }
}
