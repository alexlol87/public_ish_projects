import Foundation

/// How long ago a Repo was verified (README frontmatter `verified_on: YYYY-MM-DD`).
public enum Staleness: Equatable {
    case verified(days: Int)
    case never
    case malformed

    public static let defaultThreshold = 30

    public static func of(verifiedOn raw: String?, now: Date) -> Staleness {
        guard let s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return .never }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s), f.string(from: d) == s else { return .malformed }  // rejects 2026-13-45 rollover
        return .verified(days: cal.dateComponents([.day], from: d, to: now).day ?? 0)
    }

    /// Past the threshold, never verified, or unreadable.
    public func isStale(threshold: Int) -> Bool {
        if case .verified(let d) = self { return d > threshold }
        return true
    }

    public var label: String {
        switch self {
        case .verified(let d) where d <= 0: "verified today"
        case .verified(let d): "verified \(d) day\(d == 1 ? "" : "s") ago"
        case .never: "never verified"
        case .malformed: "verified date unreadable"
        }
    }
}

extension Vault {
    /// Vault-relative Repo folder -> staleness, for every `<folder>/README.md` with `type: repo`. Skips app-only files.
    public static func repoStaleness(in root: URL, now: Date = Date()) throws -> [String: Staleness] {
        var out: [String: Staleness] = [:]
        func walk(_ node: VaultNode) throws {
            for c in node.children {
                if c.isFolder { try walk(c); continue }
                guard c.name.lowercased() == "readme.md" || c.name.lowercased() == "readme", !c.isAppOnly,
                      let slash = c.relativePath.lastIndex(of: "/") else { continue }
                let parsed = NoteParser.parse(try readNote(c, in: root))
                if parsed.type == "repo" {
                    out[String(c.relativePath[..<slash])] = Staleness.of(verifiedOn: parsed.frontmatter["verified_on"], now: now)
                }
            }
        }
        try walk(try load(root: root))
        return out
    }
}
