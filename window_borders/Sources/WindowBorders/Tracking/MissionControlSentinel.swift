import AppKit

/// Notices Mission Control starting and ending from the window server, without polling.
///
/// Mission Control hides every window with the `.transient` collection behavior (the normal borders among them) and
/// shows them again when it closes. This keeps one tiny transparent transient window ordered in all the time and
/// watches its occlusion state: nothing covers it (floating level, 2×2 pt under the middle of the menu bar), so a
/// flip of `NSWindow.didChangeOcclusionStateNotification` almost always means Mission Control, App Exposé or Show
/// Desktop began or ended. `MissionControlObserver` confirms every flip against the Dock's tree, so a false flip
/// (a notification banner, a floating panel) costs one Accessibility call to the Dock and nothing else.
@MainActor
final class MissionControlSentinel {
    /// Called on every flip with whether the sentinel is on screen now.
    var onVisibilityChange: ((Bool) -> Void)?
    private(set) var isVisible = true

    private var window: SentinelWindow?
    private var tokens: [NSObjectProtocol] = []
    private static let size: CGFloat = 2

    init() {}

    /// Orders the sentinel in and starts watching it. Idempotent.
    func start() {
        guard window == nil else { return }
        let window = SentinelWindow(frame: Self.frame())
        window.orderFrontRegardless()
        self.window = window
        isVisible = window.occlusionState.contains(.visible)
        let center = NotificationCenter.default
        tokens.append(center.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.occlusionDidChange()
            }
        })
        tokens.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.window?.setFrame(Self.frame(), display: false)
            }
        })
    }

    func stop() {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
        tokens.removeAll()
        window?.orderOut(nil)
        window?.close()
        window = nil
    }

    private func occlusionDidChange() {
        guard let window else { return }
        let visible = window.occlusionState.contains(.visible)
        guard visible != isVisible else { return }
        isVisible = visible
        onVisibilityChange?(visible)
    }

    /// Top center of the primary display, just under the menu bar: app windows stay below the floating level, and
    /// the corners (Picture in Picture, notification banners, the Stage Manager strip) are avoided.
    private static func frame() -> CGRect {
        let visible = NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        return CGRect(x: visible.midX.rounded(), y: visible.maxY - size, width: size, height: size)
    }
}

/// Borderless, transparent, click-through, never key: only its occlusion state matters.
@MainActor
private final class SentinelWindow: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .floating
        // Transient like the borders, so Mission Control hides it with them; on every Space so Space switches and
        // fullscreen apps do not flip it.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        tabbingMode = .disallowed
        isRestorable = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SentinelWindow is created in code only")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
