import Foundation

/// Image and table widgets (ticket 16). Roles carry what the editor needs to draw; the editor never parses markdown.
extension MarkdownStyler {
    static let imagePattern = try! NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^)\\s]+)\\)")

    /// If a table starts on `lines[i]` (header row + delimiter row), returns its line count and aligned text.
    static func table(in lines: [String], at i: Int) -> (count: Int, rendered: String)? {
        func cells(_ l: String) -> [String]? {
            let t = l.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("|") else { return nil }
            var parts = t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            parts.removeFirst()
            if t.hasSuffix("|") { parts.removeLast() }
            return parts
        }
        guard i + 1 < lines.count, let head = cells(lines[i]), let delim = cells(lines[i + 1]),
              delim.count == head.count, delim.allSatisfy({ $0.range(of: "^:?-+:?$", options: .regularExpression) != nil })
        else { return nil }
        var rows = [head]
        var n = 2
        while i + n < lines.count, let c = cells(lines[i + n]) { rows.append(c); n += 1 }
        let cols = head.count
        // shortcut: widths by UTF-16 count, not display width; upgrade for CJK/emoji cells.
        let widths = (0..<cols).map { c in max(1, rows.map { $0.indices.contains(c) ? ($0[c] as NSString).length : 0 }.max() ?? 0) }
        func line(_ r: [String]) -> String {
            "| " + (0..<cols).map { c in
                let s = r.indices.contains(c) ? r[c] : ""
                return s + String(repeating: " ", count: widths[c] - (s as NSString).length)
            }.joined(separator: " | ") + " |"
        }
        let dash = (0..<cols).map { String(repeating: "-", count: widths[$0]) }
        return (n, ([line(head), line(dash)] + rows.dropFirst().map(line)).joined(separator: "\n"))
    }
}

/// Resolves an image path from a Note: Note-relative first, then Vault-relative. Never escapes the Vault.
public enum ImagePaths {
    public static func resolve(_ path: String, note: String, root: URL) -> URL? {
        let rootPath = root.standardizedFileURL.path
        let noteDir = (note as NSString).deletingLastPathComponent
        let rel = path.hasPrefix("/") ? [String(path.dropFirst())] : [(noteDir as NSString).appendingPathComponent(path), path]
        for r in rel {
            let url = root.appendingPathComponent(r).standardizedFileURL
            if url.path.hasPrefix(rootPath + "/"), FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
