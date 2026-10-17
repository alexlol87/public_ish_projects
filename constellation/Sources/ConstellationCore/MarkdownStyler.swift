import Foundation

/// What a styled run of text means. Views map roles to fonts/colours; later tickets add cases
/// (e.g. toolbar actions, widgets) without changing the existing ones.
public enum StyleRole: Equatable {
    case heading(level: Int)
    case bold
    case italic
    case inlineCode
    case codeBlock
    case link
    /// `#tag` including the `#`; never hidden.
    case tag
    /// Whole `![alt](path)` range; the editor draws the image (or a placeholder) instead of the raw text.
    case image(path: String, alt: String)
    /// Whole table block; `rendered` is the column-aligned monospace text to draw instead of the raw rows.
    case table(rendered: String)
}

public struct StyledRange: Equatable {
    public let range: NSRange  // UTF-16 offsets, as NSTextView/TextKit use
    public let role: StyleRole
    public init(range: NSRange, role: StyleRole) { self.range = range; self.role = role }
}

public struct StyleResult: Equatable {
    /// Ranges to style. Markers are never inside these; code content is never styled as anything but code.
    public var styled: [StyledRange] = []
    /// Marker ranges to hide. Empty for the cursor line.
    public var hidden: [NSRange] = []
}

/// Pure markdown-to-ranges mapper (the "MarkdownStyler" seam). Line based; no state.
public enum MarkdownStyler {
    /// - Parameter cursorLine: range of the line holding the cursor (see `lineRange(containing:in:)`);
    ///   markers on that line are not hidden. nil means no line is active.
    public static func style(_ text: String, cursorLine: NSRange? = nil) -> StyleResult {
        let ns = text as NSString
        var out = StyleResult()
        var inFence = false
        var loc = 0
        var lineIndex = 0
        var lines: [String]?  // lazily split, only when a table could start
        while loc < ns.length {
            let full = ns.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(full)
            defer { lineIndex += 1 }
            var line = full  // without the trailing newline
            while line.length > 0, "\n\r".contains(ns.character(at: NSMaxRange(line) - 1).asScalar) {
                line.length -= 1
            }
            let active = cursorLine.map { NSIntersectionRange($0, full).length > 0 || $0.location == full.location } ?? false
            var hidden: [NSRange] = []
            let content = ns.substring(with: line)

            if content.hasPrefix("```") {
                inFence.toggle()
                if line.length > 0 { hidden.append(line) }
            } else if inFence {
                if line.length > 0 { out.styled.append(StyledRange(range: line, role: .codeBlock)) }

            } else if content.trimmingCharacters(in: .whitespaces).hasPrefix("|"),
                      let t = table(in: lines ?? { let l = text.components(separatedBy: "\n"); lines = l; return l }(), at: lineIndex) {
                // Block range spans t.count lines (without the last newline); active if the cursor line touches it.
                var end = full.location
                for _ in 0..<t.count { end = NSMaxRange(ns.lineRange(for: NSRange(location: end, length: 0))) }
                var block = NSRange(location: full.location, length: end - full.location)
                while block.length > 0, "\n\r".contains(ns.character(at: NSMaxRange(block) - 1).asScalar) { block.length -= 1 }
                let on = cursorLine.map { NSIntersectionRange($0, NSRange(location: block.location, length: end - block.location)).length > 0 || $0.location == block.location } ?? false
                if !on {
                    out.styled.append(StyledRange(range: block, role: .table(rendered: t.rendered)))
                    out.hidden.append(block)
                }
                loc = end
                lineIndex += t.count - 1  // the defer adds the last one
                continue
            } else {
                let before = out.styled.count
                styleInline(content, offset: line.location, into: &out, hidden: &hidden)
                // Raw markdown comes back on the cursor line: no image widget there.
                if active {
                    let mine = out.styled[before...].filter { if case .image = $0.role { return false }; return true }
                    out.styled.replaceSubrange(before..., with: mine)
                }
            }
            if !active { out.hidden += hidden }
        }
        return out
    }

    /// The line (including newline) containing a UTF-16 cursor offset.
    public static func lineRange(containing cursor: Int, in text: String) -> NSRange {
        let ns = text as NSString
        return ns.lineRange(for: NSRange(location: min(max(cursor, 0), ns.length), length: 0))
    }

    /// The whole lines touched by a selection, so markers stay visible across a multi-line selection.
    /// A selection ending exactly at a line start does not include that next line.
    public static func lineRange(covering sel: NSRange, in text: String) -> NSRange {
        let ns = text as NSString
        let loc = min(max(sel.location, 0), ns.length)
        let end = min(max(NSMaxRange(sel) - (sel.length > 0 ? 1 : 0), loc), ns.length)
        return NSUnionRange(ns.lineRange(for: NSRange(location: loc, length: 0)), ns.lineRange(for: NSRange(location: end, length: 0)))
    }

    private static func styleInline(_ s: String, offset: Int, into out: inout StyleResult, hidden: inout [NSRange]) {
        let ns = s as NSString
        func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location + offset, length: r.length) }
        func matches(_ pattern: String) -> [NSTextCheckingResult] {
            // shortcut: regex per line, no nesting of bold inside italic etc.; upgrade when ticket 14 needs it
            let re = try! NSRegularExpression(pattern: pattern)
            return re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        }
        let wikilink = "\\[\\[([^\\[\\]|]+)(?:\\|([^\\[\\]]*))?\\]\\]"  // group 1 target[#heading], group 2 alias
        var taken: [NSRange] = []  // spans already claimed (code wins over everything)
        func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }

        for m in imagePattern.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            taken.append(m.range)
            out.styled.append(StyledRange(range: shift(m.range), role: .image(path: ns.substring(with: m.range(at: 2)), alt: ns.substring(with: m.range(at: 1)))))
            hidden.append(shift(m.range))
        }

        if let m = matches("^(#{1,6}) +(?=\\S)").first, ns.length > m.range.length {
            let title = NSRange(location: m.range.length, length: ns.length - m.range.length)
            out.styled.append(StyledRange(range: shift(title), role: .heading(level: m.range(at: 1).length)))
            hidden.append(shift(NSRange(location: 0, length: m.range.length)))
        }
        // Delimited spans: pattern group 1 is the content; the rest of the match is markers.
        let spans: [(String, StyleRole)] = [
            ("`([^`]+)`", .inlineCode),
            (wikilink, .link),
            ("\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*", .bold),
            ("(?<![*\\w])\\*(?=[^\\s*])([^*]+?)(?<=\\S)\\*(?![*\\w])", .italic),
            ("(?<![\\w])_(?=[^\\s_])([^_]+?)(?<=\\S)_(?![\\w])", .italic),
            ("\\[([^\\]]+)\\]\\([^)\\s]+\\)", .link),
        ]
        for (pattern, role) in spans {
            for m in matches(pattern) where free(m.range) {
                taken.append(m.range)
                if pattern == wikilink {
                    // Visible part: the alias if given, else target and heading. Everything else is a marker.
                    let alias = m.range(at: 2)
                    let vis = alias.location == NSNotFound ? m.range(at: 1) : alias
                    out.styled.append(StyledRange(range: shift(vis), role: .link))
                    hidden.append(shift(NSRange(location: m.range.location, length: vis.location - m.range.location)))
                    hidden.append(shift(NSRange(location: NSMaxRange(vis), length: NSMaxRange(m.range) - NSMaxRange(vis))))
                    continue
                }
                let c = m.range(at: 1)
                out.styled.append(StyledRange(range: shift(c), role: role))
                hidden.append(shift(NSRange(location: m.range.location, length: c.location - m.range.location)))
                hidden.append(shift(NSRange(location: NSMaxRange(c), length: NSMaxRange(m.range) - NSMaxRange(c))))
            }
        }
        for t in NoteParser.inlineTags(in: s) where free(t.range) { out.styled.append(StyledRange(range: shift(t.range), role: .tag)) }
    }
}

private extension unichar {
    var asScalar: Character { Character(UnicodeScalar(self) ?? " ") }
}
