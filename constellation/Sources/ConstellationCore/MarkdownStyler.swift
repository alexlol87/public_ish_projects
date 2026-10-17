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
        while loc < ns.length {
            let full = ns.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(full)
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
            } else {
                styleInline(content, offset: line.location, into: &out, hidden: &hidden)
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
        var taken: [NSRange] = []  // spans already claimed (code wins over everything)
        func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }

        if let m = matches("^(#{1,6}) +(?=\\S)").first, ns.length > m.range.length {
            let title = NSRange(location: m.range.length, length: ns.length - m.range.length)
            out.styled.append(StyledRange(range: shift(title), role: .heading(level: m.range(at: 1).length)))
            hidden.append(shift(NSRange(location: 0, length: m.range.length)))
        }
        // Delimited spans: pattern group 1 is the content; the rest of the match is markers.
        let spans: [(String, StyleRole)] = [
            ("`([^`]+)`", .inlineCode),
            ("\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*", .bold),
            ("(?<![*\\w])\\*(?=[^\\s*])([^*]+?)(?<=\\S)\\*(?![*\\w])", .italic),
            ("(?<![\\w])_(?=[^\\s_])([^_]+?)(?<=\\S)_(?![\\w])", .italic),
            ("\\[([^\\]]+)\\]\\([^)\\s]+\\)", .link),
        ]
        for (pattern, role) in spans {
            for m in matches(pattern) where free(m.range) {
                taken.append(m.range)
                let c = m.range(at: 1)
                out.styled.append(StyledRange(range: shift(c), role: role))
                hidden.append(shift(NSRange(location: m.range.location, length: c.location - m.range.location)))
                hidden.append(shift(NSRange(location: NSMaxRange(c), length: NSMaxRange(m.range) - NSMaxRange(c))))
            }
        }
    }
}

private extension unichar {
    var asScalar: Character { Character(UnicodeScalar(self) ?? " ") }
}
