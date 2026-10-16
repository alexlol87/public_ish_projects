import Foundation

/// Flips the `index`-th task-list marker (`- [ ]` / `- [x]`, also `*`, `+`, `1.`) in `source`.
/// Markers inside fenced code blocks are ignored. Out-of-range index returns `source` unchanged.
public func toggleTask(_ source: String, index: Int) -> String {
    let marker = try! Regex(#"^(\s*(?:[-*+]|\d+[.)])\s+\[)([ xX])(\](?:\s|$))"#)
    var lines = source.components(separatedBy: "\n")
    var fence: String?
    var n = 0
    for i in lines.indices {
        let trimmed = lines[i].drop { $0 == " " }
        if let f = fence {
            if trimmed.hasPrefix(f) { fence = nil }
            continue
        }
        if trimmed.hasPrefix("```") { fence = "```"; continue }
        if trimmed.hasPrefix("~~~") { fence = "~~~"; continue }
        guard let m = lines[i].firstMatch(of: marker) else { continue }
        if n == index {
            let box = m.output[2].substring == " " ? "x" : " "
            lines[i].replaceSubrange(m.output[2].range!, with: box)
            return lines.joined(separator: "\n")
        }
        n += 1
    }
    return source
}
