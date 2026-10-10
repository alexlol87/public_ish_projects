import Foundation

public enum AppFilterMode: String, Codable, CaseIterable, Sendable {
    case all, allowlist, blocklist
}

/// Which apps get borders: every app, only listed ones, or every app except listed ones.
public struct AppFilter: Codable, Equatable, Sendable {
    public var mode: AppFilterMode
    /// Ordered, unique (the initializer drops duplicates, keeping the first occurrence).
    public var bundleIDs: [String]

    public init(mode: AppFilterMode = .all, bundleIDs: [String] = []) {
        self.mode = mode
        var seen = Set<String>()
        self.bundleIDs = bundleIDs.filter { seen.insert($0).inserted }
    }

    /// .all -> true; .allowlist -> bundleID in list (nil -> false); .blocklist -> not in list (nil -> true).
    /// Apps without a bundle ID cannot be listed, so they follow the mode's default.
    public func allows(bundleID: String?) -> Bool {
        switch mode {
        case .all:
            return true
        case .allowlist:
            guard let bundleID else { return false }
            return bundleIDs.contains(bundleID)
        case .blocklist:
            guard let bundleID else { return true }
            return !bundleIDs.contains(bundleID)
        }
    }
}
