import AppKit
import BorderCore
import QuartzCore

/// The click-through, transparent window that carries one border. One per tracked window, ordered directly above
/// the window it decorates (see `BorderOverlayController`).
@MainActor
final class BorderWindow: NSWindow {
    /// What the stroke currently shows, so a move-only update (the common case while dragging) touches nothing but
    /// the window frame.
    private struct Appearance: Equatable {
        var size: CGSize
        var strokeRect: CGRect
        var cornerRadius: CGFloat
        var lineWidth: CGFloat
        var color: RGBAColor
        var opacity: Double
        var scale: CGFloat
    }

    private var lastAppearance: Appearance?
    /// Last frame we asked for; compared instead of `frame` so window-server rounding can't defeat the skip.
    private var lastFrame: CGRect?
    private var lastCoveredRects: [CGRect] = []

    /// Follows its window to every Space (shown/hidden by the controller), may sit on a fullscreen Space, is hidden by
    /// Mission Control like other helpers, and never appears in Cmd-` cycling. Nonisolated: it is a default argument.
    nonisolated static let standardBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle,
    ]

    /// No designated initializer of our own: the subclass inherits NSWindow's, and this convenience init configures
    /// the overlay. `defer: true` postpones the window-server window until the overlay is first shown.
    convenience init(
        level: NSWindow.Level,
        collectionBehavior: NSWindow.CollectionBehavior = BorderWindow.standardBehavior
    ) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        self.collectionBehavior = collectionBehavior
        isExcludedFromWindowsMenu = true
        tabbingMode = .disallowed
        isRestorable = false
        contentView = BorderView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit would push a window that pokes past a screen edge or under the menu bar back on screen; the border
    /// must stay exactly around its window wherever that is.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Places and paints the border. Moves never animate: the frame is set without animation and the layer changes
    /// run with implicit actions disabled. Unchanged inputs return immediately, so callers may apply freely.
    /// - Parameter opacity: multiplies the color's alpha (inactive-window dimming).
    func apply(layout: BorderLayout, color: RGBAColor, opacity: Double) {
        var appearance = Appearance(
            size: layout.overlayFrame.size,
            strokeRect: layout.strokeRect,
            cornerRadius: layout.cornerRadius,
            lineWidth: layout.lineWidth,
            color: color,
            opacity: opacity,
            scale: backingScaleFactor
        )
        let frameChanged = lastFrame != layout.overlayFrame
        guard frameChanged || lastAppearance != appearance else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if frameChanged {
            setFrame(layout.overlayFrame, display: false, animate: false)
            lastFrame = layout.overlayFrame
            // The frame may have put the overlay on a display with another scale.
            appearance.scale = backingScaleFactor
        }
        if lastAppearance != appearance, let borderView = contentView as? BorderView {
            let stroke = NSColor(
                srgbRed: CGFloat(color.red),
                green: CGFloat(color.green),
                blue: CGFloat(color.blue),
                alpha: CGFloat(max(0, min(1, color.alpha * opacity)))
            )
            borderView.update(
                size: appearance.size,
                strokeRect: appearance.strokeRect,
                cornerRadius: appearance.cornerRadius,
                lineWidth: appearance.lineWidth,
                color: stroke.cgColor,
                scale: appearance.scale
            )
            lastAppearance = appearance
        }
        CATransaction.commit()
    }

    /// Hides the parts of the border under other windows. Only used in floating layering, where the overlay sits above
    /// every normal window and would otherwise draw over windows in front of its own.
    /// - Parameter coveredRects: overlay-local rects (origin bottom-left, like the view) covered by windows in front;
    ///   empty shows the whole border.
    func setCoveredRects(_ coveredRects: [CGRect]) {
        guard coveredRects != lastCoveredRects else { return }
        lastCoveredRects = coveredRects
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        (contentView as? BorderView)?.setCoveredRects(coveredRects)
        CATransaction.commit()
    }
}
