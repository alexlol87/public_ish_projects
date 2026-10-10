import CoreGraphics
import Foundation

/// Thin CGWindowList helpers. The window server is the source of truth for window IDs, stacking order and whether a
/// window is on an active Space; AX knows roles and titles but not those. None of this needs Screen Recording access:
/// IDs, owner PIDs, bounds and layers are always readable, only names are withheld.
enum WindowServer {
    /// One window server entry, reduced to what the tracker needs.
    struct WindowInfo: Equatable {
        let id: CGWindowID
        let pid: pid_t
        /// Global top-left coordinates (same space as AX), points.
        let bounds: CGRect
        let layer: Int

        init?(_ entry: [String: Any]) {
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let owner = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  let boundsEntry = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsEntry as CFDictionary)
            else { return nil }
            id = number.uint32Value
            pid = owner.int32Value
            self.bounds = bounds
            layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        }
    }

    /// IDs of layer-0 windows currently on screen (active Spaces), via .optionOnScreenOnly + .excludeDesktopElements.
    static func onScreenWindowIDs() -> Set<CGWindowID> {
        Set(frontToBackOrder())
    }

    /// Current bounds (global top-left coords, points) of one window, nil if gone. Cheap: uses
    /// CGWindowListCreateDescriptionFromArray for that single ID (called every frame while dragging).
    static func bounds(of id: CGWindowID) -> CGRect? {
        guard let entries = describe([id]) else { return nil }
        return entries.compactMap(WindowInfo.init).first(where: { $0.id == id })?.bounds
    }

    /// Current bounds of several windows in one window server round trip (Mission Control samples every window
    /// each frame). Windows that are gone are missing from the result.
    static func bounds(of ids: [CGWindowID]) -> [CGWindowID: CGRect] {
        guard let entries = describe(ids) else { return [:] }
        var result: [CGWindowID: CGRect] = [:]
        for info in entries.compactMap(WindowInfo.init) {
            result[info.id] = info.bounds
        }
        return result
    }

    /// All on-screen layer-0 window IDs front-to-back.
    static func frontToBackOrder() -> [CGWindowID] {
        onScreenWindows().map(\.id)
    }

    /// On-screen layer-0 windows front-to-back, with owner and bounds (one window server round trip).
    static func onScreenWindows() -> [WindowInfo] {
        parse(CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID))
            .filter { $0.layer == 0 }
    }

    /// Every window the server knows (all Spaces, minimized and hidden ones too, any layer), keyed by ID.
    static func allWindowsByID() -> [CGWindowID: WindowInfo] {
        let windows = parse(CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID))
        return Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Which of `ids` still exist anywhere (any Space, minimized, hidden). nil when the query itself failed, so callers
    /// never mistake a failed call for "every window is gone".
    static func existingWindowIDs(among ids: [CGWindowID]) -> Set<CGWindowID>? {
        guard let entries = describe(ids) else { return nil }
        var alive = Set<CGWindowID>()
        for entry in entries {
            if let number = entry[kCGWindowNumber as String] as? NSNumber {
                alive.insert(number.uint32Value)
            }
        }
        return alive
    }

    private static func parse(_ list: CFArray?) -> [WindowInfo] {
        guard let entries = list as? [[String: Any]] else { return [] }
        return entries.compactMap(WindowInfo.init)
    }

    /// CGWindowListCreateDescriptionFromArray wants a CFArray whose values are the raw CGWindowIDs (not CFNumbers),
    /// created without retain/release callbacks.
    private static func describe(_ ids: [CGWindowID]) -> [[String: Any]]? {
        var values: [UnsafeRawPointer?] = ids.filter { $0 != 0 }.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard !values.isEmpty else { return [] }
        let array: CFArray? = values.withUnsafeMutableBufferPointer { buffer in
            CFArrayCreate(kCFAllocatorDefault, buffer.baseAddress, buffer.count, nil)
        }
        guard let array else { return nil }
        return CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]]
    }
}
