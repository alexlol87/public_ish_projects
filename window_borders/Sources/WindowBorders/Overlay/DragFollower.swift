import AppKit
import QuartzCore

/// Keeps the focused window's border glued to it while the user drags or resizes.
///
/// Many apps post the AX moved/resized notifications only when a drag ends (and the window server moves title-bar
/// drags itself), so following AX alone makes the border jump at the end. While the left mouse button is down, a
/// display link samples the window's live bounds from the window server once per frame and reports changes. Nothing
/// runs while the button is up, so idle cost is zero.
@MainActor
final class DragFollower: NSObject {
    /// The window to follow, asked every frame: a click on a background window focuses it slightly after mouse-down.
    private let windowToFollow: @MainActor () -> CGWindowID?
    /// Called with the window's new bounds (global top-left coordinates, like AX) whenever they changed.
    private let onBoundsChange: @MainActor (CGWindowID, CGRect) -> Void

    private var mouseMonitor: Any?
    private var displayLink: CADisplayLink?
    private var lastSample: (id: CGWindowID, bounds: CGRect)?
    /// Bumped by every new drag and by `stop()`, so a settle re-sample scheduled for an earlier drag is dropped.
    private var generation = 0

    /// After the button goes up, the window may still be settling (snapping to a tiling position, a Mission Control
    /// exit animation): sample again once it has, so the border never stays where an animation frame left it.
    private static let settleDelays: [TimeInterval] = [0.4, 1.2]

    /// Set while Mission Control (or App Exposé) is open. The window server then reports the windows' thumbnail
    /// bounds, so a click on a thumbnail must not be followed: the border would be left on the thumbnail's rect.
    var isSuspended = false {
        didSet {
            guard isSuspended, !oldValue else { return }
            generation += 1
            stopDisplayLink()
            lastSample = nil
        }
    }

    init(windowToFollow: @escaping @MainActor () -> CGWindowID?,
         onBoundsChange: @escaping @MainActor (CGWindowID, CGRect) -> Void) {
        self.windowToFollow = windowToFollow
        self.onBoundsChange = onBoundsChange
        super.init()
    }

    /// The window whose border the display link is driving right now, nil when no drag is being followed. Tracker
    /// frame updates for it are redundant (and may be a frame stale) until the mouse goes up.
    var followedWindowID: CGWindowID? {
        displayLink == nil ? nil : lastSample?.id
    }

    /// The followed window's latest live bounds (global top-left coordinates), nil when no drag is being followed.
    var followedBounds: CGRect? {
        displayLink == nil ? nil : lastSample?.bounds
    }

    /// Installs the global mouse monitor (it sees clicks in other apps; ours never need following).
    func start() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .leftMouseDown {
                    self.beginFollowing()
                } else {
                    self.endFollowing()
                }
            }
        }
    }

    func stop() {
        generation += 1
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
        stopDisplayLink()
        lastSample = nil
    }

    // MARK: - Private

    private func beginFollowing() {
        guard !isSuspended else { return }
        generation += 1
        lastSample = nil
        guard displayLink == nil else { return }
        // The display under the pointer drives the link, so sampling matches that display's refresh rate.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let link = screen?.displayLink(target: self, selector: #selector(displayLinkFired(_:))) else { return }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// One last sample so the border lands exactly where the drag ended, then back to idle.
    private func endFollowing() {
        guard displayLink != nil else { return }
        sample()
        stopDisplayLink()
        guard let id = lastSample?.id else { return }
        let scheduledGeneration = generation
        for delay in Self.settleDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == scheduledGeneration, !self.isSuspended else { return }
                    self.settleSample(id)
                }
            }
        }
    }

    /// Like `sample()` but for the window the drag was about, even if focus has moved on since.
    private func settleSample(_ id: CGWindowID) {
        guard let bounds = WindowServer.bounds(of: id) else { return }
        if let last = lastSample, last.id == id, last.bounds == bounds { return }
        lastSample = (id: id, bounds: bounds)
        onBoundsChange(id, bounds)
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        sample()
        // Window-server title-bar drags can swallow the mouse-up the global monitor would see; never keep the link
        // running once no button is held.
        if NSEvent.pressedMouseButtons & 1 == 0 {
            endFollowing()
        }
    }

    private func sample() {
        guard !isSuspended, let id = windowToFollow(), let bounds = WindowServer.bounds(of: id) else { return }
        if let last = lastSample, last.id == id, last.bounds == bounds { return }
        lastSample = (id: id, bounds: bounds)
        onBoundsChange(id, bounds)
    }

    /// The link retains its target, so it must be invalidated (not just dropped) to release us.
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
}
