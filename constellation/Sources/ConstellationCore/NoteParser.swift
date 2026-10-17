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

public struct TagRef: Equatable {
    public let range: NSRange  // `#name` inline (with the `#`), or just the name in frontmatter; UTF-16
    public let name: String    // as written, without `#`; nested like `team/payments`
}

public struct ParsedNote: Equatable {
    public var tags: [TagRef] = []
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
        var fm: Frontmatter? = ns.hasPrefix("---\n") ? Frontmatter() : nil
        while loc < ns.length {
            let full = ns.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(full)
            var line = full
            while line.length > 0, ns.character(at: NSMaxRange(line) - 1) == 10 || ns.character(at: NSMaxRange(line) - 1) == 13 { line.length -= 1 }
            let content = ns.substring(with: line)
            if fm != nil {
                if line.location > 0 {
                    if content == "---" { fm = nil } else { fm!.line(content, offset: line.location, into: &out) }
                }
                continue
            }
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

    static let tagName = "\\p{L}[\\p{L}\\p{N}_-]*(?:/\\p{L}[\\p{L}\\p{N}_-]*)*"
    private static let tagRe = regex("(?<![\\p{L}\\p{N}_/&#])#(" + tagName + ")")
    static let typedTagRe = regex("(?<![\\p{L}\\p{N}_/&#])#([\\p{L}\\p{N}_/-]*)$")
    private static let linkUrlRe = regex("\\]\\([^)]*\\)")
    private static let hexRe = regex("^(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")

    /// Inline `#tag` ranges (with the `#`) in one line, outside inline code and `](url)` parts. Shared with the styler.
    static func inlineTags(in s: String) -> [TagRef] {
        let ns = s as NSString
        let all = NSRange(location: 0, length: ns.length)
        let skip = (codeRe.matches(in: s, range: all) + linkUrlRe.matches(in: s, range: all)).map(\.range)
        return tagRe.matches(in: s, range: all).compactMap { m in
            let name = ns.substring(with: m.range(at: 1))
            if skip.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) || hexRe.firstMatch(in: name, range: NSRange(location: 0, length: name.utf16.count)) != nil { return nil }
            return TagRef(range: m.range, name: name)
        }
    }

    /// Frontmatter `tags:` as `[a, b]`, `a, b` or a `- a` list under `tags:`.
    private struct Frontmatter {
        var inTags = false
        mutating func line(_ s: String, offset: Int, into out: inout ParsedNote) {
            let ns = s as NSString
            var items = s
            if s.hasPrefix("tags:") { inTags = true; items = String(s.dropFirst(5)) }
            else if inTags, s.hasPrefix(" ") || s.hasPrefix("-"), s.trimmingCharacters(in: .whitespaces).hasPrefix("-") {
                items = String(s.trimmingCharacters(in: .whitespaces).dropFirst())
            } else { inTags = false; return }
            for raw in items.split(whereSeparator: { ",[]".contains($0) }) {
                let item = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'#"))
                let r = ns.range(of: item)
                guard !item.isEmpty, r.location != NSNotFound,
                      item.range(of: "^" + NoteParser.tagName + "$", options: .regularExpression) != nil else { continue }
                out.tags.append(TagRef(range: NSRange(location: r.location + offset, length: r.length), name: item))
            }
        }
    }

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
        for t in inlineTags(in: s) { out.tags.append(TagRef(range: shift(t.range), name: t.name)) }
        let code = codeRe.matches(in: s, range: all).map(\.range)
        for m in linkRe.matches(in: s, range: all) where !code.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
            out.links.append(WikiLink(range: shift(m.range), target: group(m, 1)!.trimmingCharacters(in: .whitespaces),
                                      heading: group(m, 2).flatMap { $0.isEmpty ? nil : $0 }, alias: group(m, 3)))
        }
    }
}
