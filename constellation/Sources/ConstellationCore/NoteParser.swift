import Foundation

public struct WikiLink: Equatable {
    public let range: NSRange  // whole `[[...]]`, UTF-16
    public let target: String  // Vault path or Note name, as written
    public let heading: String?
    public let alias: String?
}

public struct NoteHeading: Equatable {
    public let level: Int
    public let title: String
    public let range: NSRange  // whole heading line without newline
}

public struct ParsedNote: Equatable {
    public var links: [WikiLink] = []
    public var headings: [NoteHeading] = []
}

/// Pure Note parser. Skips fenced and inline code. Later tickets (Tags, Calls, tasks) add fields to `ParsedNote`
/// and a pattern in `parseLine`.
public enum NoteParser {
    public static func parse(_ text: String) -> ParsedNote {
        let ns = text as NSString
        var out = ParsedNote()
        var inFence = false
        var loc = 0
        while loc < ns.length {
            let full = ns.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(full)
            var line = full
            while line.length > 0, ns.character(at: NSMaxRange(line) - 1) == 10 || ns.character(at: NSMaxRange(line) - 1) == 13 { line.length -= 1 }
            let content = ns.substring(with: line)
            if content.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }
            parseLine(content, offset: line.location, into: &out)
        }
        return out
    }

    private static func regex(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    private static let headingRe = regex("^(#{1,6}) +(\\S.*?) *$")
    private static let codeRe = regex("`[^`]+`")
    private static let linkRe = regex("\\[\\[([^\\[\\]|#]+)(?:#([^\\[\\]|]*))?(?:\\|([^\\[\\]]*))?\\]\\]")

    private static func parseLine(_ s: String, offset: Int, into out: inout ParsedNote) {
        let ns = s as NSString
        let all = NSRange(location: 0, length: ns.length)
        func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location + offset, length: r.length) }
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
        }
        if let m = headingRe.firstMatch(in: s, range: all) {
            out.headings.append(NoteHeading(level: m.range(at: 1).length, title: group(m, 2)!, range: shift(all)))
        }
        let code = codeRe.matches(in: s, range: all).map(\.range)
        for m in linkRe.matches(in: s, range: all) where !code.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
            out.links.append(WikiLink(range: shift(m.range), target: group(m, 1)!.trimmingCharacters(in: .whitespaces),
                                      heading: group(m, 2).flatMap { $0.isEmpty ? nil : $0 }, alias: group(m, 3)))
        }
    }
}
