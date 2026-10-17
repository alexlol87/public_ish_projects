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
    public var frontmatter: [String: String] = [:]  // every key kept, known or not
    public var calls: [SectionLinks] = []   // `Calls:` lists under Endpoint headings
    public var uses: [SectionLinks] = []    // `Uses:` lists in Client Notes
    public var status: [EndpointStatus] = []
    /// Missing `type` is a plain Note.
    public var type: String { frontmatter["type"] ?? "note" }

    /// The Endpoint heading the offset sits under (nearest heading above it), if that heading is an Endpoint.
    public func endpointHeading(at offset: Int) -> NoteHeading? {
        headings.last { $0.range.location <= offset }.flatMap { NoteParser.isEndpoint($0.title) ? $0 : nil }
    }
}

public struct SectionLinks: Equatable {
    public let heading: NoteHeading
    public let links: [WikiLink]
}

public struct EndpointStatus: Equatable {
    public let heading: NoteHeading
    public let values: [String: String]  // implemented, last_changed, missing, ...
}

/// Pure Note parser. Skips fenced and inline code. Later tickets (Tags, Calls, tasks) add fields to `ParsedNote`
/// and a pattern in `parseLine`.
public enum NoteParser {
    public static func parse(_ text: String) -> ParsedNote {
        let ns = text as NSString
        var out = ParsedNote()
        var inFence = false
        var loc = frontmatterEnd(ns)
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
        parseFrontmatter(text, into: &out)
        parseLists(text, into: &out)
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

// Endpoints, Calls and Uses (ticket 11): separate functions to keep ticket merges small.
extension NoteParser {
    private static let endpointRe = regex("^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) /")

    static func isEndpoint(_ title: String) -> Bool {
        endpointRe.firstMatch(in: title, range: NSRange(location: 0, length: (title as NSString).length)) != nil
    }

    /// UTF-16 offset just past a leading `---` ... `---` block, or 0.
    private static func frontmatterEnd(_ ns: NSString) -> Int {
        guard ns.hasPrefix("---\n") else { return 0 }
        let close = ns.range(of: "\n---", range: NSRange(location: 3, length: ns.length - 3))
        guard close.location != NSNotFound else { return 0 }
        return min(ns.length, NSMaxRange(ns.lineRange(for: NSRange(location: close.location + 1, length: 0))))
    }

    fileprivate static func parseFrontmatter(_ text: String, into out: inout ParsedNote) {
        let ns = text as NSString
        let end = frontmatterEnd(ns)
        guard end > 0 else { return }
        for line in ns.substring(to: end).split(separator: "\n").dropFirst() {
            guard let c = line.firstIndex(of: ":") else { continue }
            out.frontmatter[line[..<c].trimmingCharacters(in: .whitespaces)] = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
    }

    /// `Calls:` / `Uses:` / `Status:` lines followed by bullets, attached to the nearest heading above.
    fileprivate static func parseLists(_ text: String, into out: inout ParsedNote) {
        let ns = text as NSString
        var lines: [(String, NSRange)] = [], inFence = false, loc = frontmatterEnd(ns)
        while loc < ns.length {
            let r = ns.lineRange(for: NSRange(location: loc, length: 0)); loc = NSMaxRange(r)
            let c = ns.substring(with: r).trimmingCharacters(in: .newlines)
            if c.hasPrefix("```") { inFence.toggle(); continue }
            if !inFence { lines.append((c, NSRange(location: r.location, length: (c as NSString).length))) }
        }
        let isClient = out.type == "client"
        var i = 0
        while i < lines.count {
            let label = lines[i].0
            i += 1
            guard label == "Calls:" || label == "Uses:" || label == "Status:" else { continue }
            var bullets: [(String, NSRange)] = []
            while i < lines.count, lines[i].0.hasPrefix("- ") || lines[i].0.hasPrefix("* ") { bullets.append(lines[i]); i += 1 }
            let at = lines[i - bullets.count - 1].1.location
            let heading = out.headings.last { $0.range.location <= at }
            switch label {
            case "Calls:":
                guard let h = heading, isEndpoint(h.title) else { continue }
                out.calls.append(SectionLinks(heading: h, links: links(in: bullets, out)))
            case "Uses:":
                guard isClient else { continue }
                let h = heading ?? NoteHeading(level: 0, title: "", range: NSRange(location: 0, length: 0))
                out.uses.append(SectionLinks(heading: h, links: links(in: bullets, out)))
            default:
                guard let h = heading, isEndpoint(h.title) else { continue }
                var v: [String: String] = [:]
                for (b, _) in bullets {
                    let kv = b.dropFirst(2).split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if kv.count == 2 { v[kv[0]] = kv[1] }
                }
                out.status.append(EndpointStatus(heading: h, values: v))
            }
        }
    }

    private static func links(in bullets: [(String, NSRange)], _ out: ParsedNote) -> [WikiLink] {
        out.links.filter { l in bullets.contains { NSLocationInRange(l.range.location, $0.1) } }
    }
}
