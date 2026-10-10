import Foundation

/// Best-effort color persistence across app restarts, keyed by bundle ID + normalized window title.
///
/// Window IDs change every launch, so the only stable handle on "the same window" is its title. Titles carry
/// volatile parts (dirty markers, the active file, the terminal size), which `normalizedTitle` strips. Several
/// windows can share a key, so each key keeps a short most-recent-first list of colors and callers ask for the
/// first one no live window with that key has claimed yet.
public struct ColorMemory: Codable, Equatable, Sendable {
    /// Colors seen for one key, most recent first, and when the key was last recorded (for pruning).
    struct Entry: Codable, Equatable, Sendable {
        var colors: [RGBAColor]
        var lastSeen: Date
    }

    /// Colors remembered per key.
    static let maxColorsPerKey = 10

    /// Keyed by "bundleID\u{1F}normalizedTitle" (unit separator: cannot appear in either part in practice).
    private var entries: [String: Entry]

    public init() {
        entries = [:]
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// Remembers that a window with this (bundleID, title) had `color`. Per key keeps a most-recent-first,
    /// de-duplicated list of up to 10 colors (several windows can share a key, e.g. Terminal "alex — -zsh").
    /// Titles without a usable stable part, and empty bundle IDs, are ignored.
    public mutating func record(bundleID: String, title: String, color: RGBAColor, now: Date) {
        guard let key = Self.key(bundleID: bundleID, title: title) else { return }
        var entry = entries[key] ?? Entry(colors: [], lastSeen: now)
        entry.colors.removeAll { $0 == color }
        entry.colors.insert(color, at: 0)
        if entry.colors.count > Self.maxColorsPerKey {
            entry.colors.removeLast(entry.colors.count - Self.maxColorsPerKey)
        }
        entry.lastSeen = now
        entries[key] = entry
    }

    /// First remembered color for the key that is not in `claimed` (colors already used by live windows with the
    /// same key), or nil.
    public func lookup(bundleID: String, title: String, excluding claimed: [RGBAColor]) -> RGBAColor? {
        guard let key = Self.key(bundleID: bundleID, title: title), let entry = entries[key] else { return nil }
        return entry.colors.first { !claimed.contains($0) }
    }

    /// Drops least-recently-seen keys beyond `maxKeys` (ties broken by key so the result is deterministic).
    public mutating func prune(maxKeys: Int) {
        let limit = max(0, maxKeys)
        guard entries.count > limit else { return }
        let kept = entries
            .sorted { lhs, rhs in
                lhs.value.lastSeen != rhs.value.lastSeen ? lhs.value.lastSeen > rhs.value.lastSeen : lhs.key < rhs.key
            }
            .prefix(limit)
        var pruned: [String: Entry] = [:]
        for (key, entry) in kept {
            pruned[key] = entry
        }
        entries = pruned
    }

    // MARK: - Title normalization

    /// Stable part of a title, or nil when nothing usable. Rules: trim; drop leading dirty markers ("●", "•", "*");
    /// split on " — " (em dash) and " - "; drop segments that are window sizes ("80×24", "120x40"), and segments
    /// equal to the app name for known apps ("Visual Studio Code", "Code", "Terminal", ...);
    /// VS Code family (com.microsoft.VSCode, com.microsoft.VSCodeInsiders, com.vscodium, com.todesktop.230313mzl4w4u92
    /// (Cursor)): keep only the LAST remaining segment (the workspace/folder name, since the first is the active file).
    /// Everything else: the remaining segments rejoined with " — ". Case preserved.
    /// Segments made only of punctuation (a stray "-") are dropped too.
    public static func normalizedTitle(_ title: String, bundleID: String) -> String? {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, dirtyMarkers.contains(first) {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let appNames = knownAppNames[bundleID] ?? []
        let segments = text
            .replacingOccurrences(of: " - ", with: emDashSeparator)
            .components(separatedBy: emDashSeparator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { segment in
                // allSatisfy is true for "" too, so this also drops empty segments.
                let onlyPunctuation = segment.allSatisfy { $0.isPunctuation }
                return !onlyPunctuation && !isWindowSize(segment) && !appNames.contains(segment)
            }

        if vsCodeFamily.contains(bundleID) {
            return segments.last
        }
        return segments.isEmpty ? nil : segments.joined(separator: emDashSeparator)
    }

    static func key(bundleID: String, title: String) -> String? {
        let bundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundle.isEmpty, let normalized = normalizedTitle(title, bundleID: bundle) else { return nil }
        return bundle + "\u{1F}" + normalized
    }

    private static let emDashSeparator = " \u{2014} "

    /// "●" (VS Code), "•" and "*" (various editors) prefix unsaved documents.
    private static let dirtyMarkers: Set<Character> = ["\u{25CF}", "\u{2022}", "*"]

    private static let vsCodeFamily: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92", // Cursor
    ]

    /// App-name segments some apps append to window titles. "Insiders" covers "Visual Studio Code - Insiders",
    /// which the " - " split turns into two segments.
    private static let knownAppNames: [String: Set<String>] = [
        "com.microsoft.VSCode": ["Visual Studio Code", "Code"],
        "com.microsoft.VSCodeInsiders": ["Visual Studio Code", "Code", "Insiders"],
        "com.vscodium": ["VSCodium"],
        "com.todesktop.230313mzl4w4u92": ["Cursor"],
        "com.apple.Terminal": ["Terminal"],
        "com.googlecode.iterm2": ["iTerm2", "iTerm"],
        "dev.warp.Warp-Stable": ["Warp"],
        "com.google.Chrome": ["Google Chrome"],
        "org.mozilla.firefox": ["Mozilla Firefox", "Firefox"],
        "com.microsoft.edgemac": ["Microsoft Edge"],
        "com.brave.Browser": ["Brave"],
        "com.apple.Safari": ["Safari"],
        "com.apple.dt.Xcode": ["Xcode"],
        "dev.zed.Zed": ["Zed"],
        "com.sublimetext.4": ["Sublime Text"],
    ]

    /// "80×24", "120x40", "120 × 40": a terminal's columns × rows, which changes on every resize.
    private static func isWindowSize(_ segment: String) -> Bool {
        let parts = segment.split(omittingEmptySubsequences: false, whereSeparator: { character in
            character == "\u{00D7}" || character == "x" || character == "X"
        })
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { part in
            let digits = part.trimmingCharacters(in: .whitespaces)
            return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }
}
