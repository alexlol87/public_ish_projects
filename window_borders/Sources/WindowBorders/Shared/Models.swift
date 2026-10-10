import AppKit
import BorderCore

/// One standard window the tracker follows. Produced by `WindowTracker`, consumed by `BorderOverlayController`.
struct TrackedWindow: Equatable {
    /// Window server ID (also the `windowNumber` to order an overlay against).
    let id: CGWindowID
    let pid: pid_t
    let bundleID: String?
    let appName: String
    var title: String
    /// Global AX / CGWindowList coordinates: origin at the top-left of the primary display, y grows downward, points.
    var frame: CGRect
    var isMinimized: Bool
    var isFullscreen: Bool
    /// The owning app is hidden (Cmd-H).
    var isAppHidden: Bool
    /// Listed by CGWindowList with `.optionOnScreenOnly`, i.e. on an active Space (covered windows still count).
    var isOnScreen: Bool
    /// The focused window of the frontmost app.
    var isFocused: Bool
    /// When the tracker first saw this window (used for the color-restore grace period).
    let firstSeen: Date
}

/// What changed in a `tracker(_:didUpdate:changes:)` call.
struct WindowChange: OptionSet {
    let rawValue: Int
    static let frame = WindowChange(rawValue: 1 << 0)
    static let title = WindowChange(rawValue: 1 << 1)
    /// isMinimized, isAppHidden, isOnScreen or isFullscreen changed.
    static let visibility = WindowChange(rawValue: 1 << 2)
    static let focus = WindowChange(rawValue: 1 << 3)
}

@MainActor
protocol WindowTrackerDelegate: AnyObject {
    func tracker(_ tracker: WindowTracker, didAdd window: TrackedWindow)
    func tracker(_ tracker: WindowTracker, didUpdate window: TrackedWindow, changes: WindowChange)
    func tracker(_ tracker: WindowTracker, didRemove windowID: CGWindowID)
    /// The frontmost app or its focused window changed (the app's windows were just raised above our overlays).
    /// Sent after the affected windows' `isFocused` flags were updated (those updates are not reported separately).
    func tracker(_ tracker: WindowTracker, didChangeFocusTo windowID: CGWindowID?, frontmostPID: pid_t?)
}

/// What the menu shows about the focused window.
struct FocusedWindowSummary: Equatable {
    let windowID: CGWindowID
    let appName: String
    let bundleID: String?
    let title: String
    let color: RGBAColor
}
