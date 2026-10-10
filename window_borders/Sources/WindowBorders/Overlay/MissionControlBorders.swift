import AppKit
import BorderCore
import os
import QuartzCore

/// Diagnostics for the Mission Control path, which can only be checked on a real Mac. Read them with
/// `log stream --level info --predicate 'subsystem == "com.codefactory.WindowBorders"'`.
let missionControlLog = Logger(subsystem: "com.codefactory.WindowBorders", category: "MissionControl")

/// Draws each window's border around its thumbnail while Mission Control or App Exposé is open.
///
/// The normal borders are transient windows, which Mission Control hides. These borders are drawn instead on one
/// transparent, click-through canvas window per display: stationary (not swept into Mission Control's layout) and at
/// the assistive-technology level (above Mission Control, like accessibility cursors). The canvases are ordered in at
/// startup and parked at 1×1 pt; Mission Control only resizes them, so it never has to show a window that was ordered
/// in after it opened.
///
/// While Mission Control is open the window server reports each window's thumbnail bounds while AX keeps the real
/// frame, so bounds uniformly scaled down from the real frame are a thumbnail (confirmed on a real Mac). Windows left
/// at full size (other apps in App Exposé, Show Desktop) get none.
///
/// Sampling: 10 times a second while the enter animation runs, then 2.5 times a second for as long as Mission Control
/// stays open (windows can be dragged between Spaces, thumbnails grow on hover). After a click in Mission Control the
/// canvases are cleared and sampling runs fast again for a moment: the picked window zooms back to full size, and a
/// border trailing it at 2.5 Hz was what made leaving Mission Control feel slow. Nothing runs outside Mission Control.
/// Whether Mission Control is open is `MissionControlObserver`'s business; this only reports vanished thumbnails.
@MainActor
final class MissionControlBorders: NSObject {
    struct Target: Equatable {
        let windowID: CGWindowID
        /// Global AX coordinates (top-left origin): the real frame, unaffected by Mission Control.
        let axFrame: CGRect
        let color: RGBAColor
    }

    struct Style: Equatable {
        let lineWidth: CGFloat
        /// The full-size window's corner radius; scaled down with the thumbnail.
        let windowCornerRadius: CGFloat
    }

    /// Sampling interval while Mission Control's enter animation runs (and while drawing is suspended), then after.
    private static let animatingInterval: TimeInterval = 0.1
    private static let settledInterval: TimeInterval = 0.4
    private static let enterAnimationDuration: CFTimeInterval = 1.5
    /// Narrower window-server bounds are not a usable thumbnail (or not a real window).
    private static let minimumThumbnailWidth: CGFloat = 20
    /// Window-server size below this fraction of the AX size means "shown scaled down".
    private static let thumbnailScaleThreshold: CGFloat = 0.97
    /// A thumbnail is scaled uniformly; scales further apart than this are a stale frame.
    private static let maximumScaleMismatch: CGFloat = 0.03
    /// Thumbnails are small; a thinner line would be hard to see.
    private static let minimumLineWidth: CGFloat = 2

    private let targets: @MainActor () -> [Target]
    private let style: @MainActor () -> Style
    /// Called once when the thumbnails disappear while there are windows to draw: they are zooming back to full
    /// size, so Mission Control is most likely closing (`MissionControlObserver` confirms it with the Dock).
    var onThumbnailsVanished: (() -> Void)?

    private var canvases: [MissionControlCanvas] = []
    private var timer: Timer?
    private var shownAt: CFTimeInterval = 0
    /// Until when nothing is drawn (after a click in Mission Control); sampling goes on at the fast rate meanwhile.
    private var drawingSuspendedUntil: CFTimeInterval = 0
    private var hadThumbnails = false
    /// What the canvases show, so a settled sample that found nothing new touches no layer.
    private var lastDrawn: (placed: [Placed], style: Style)?
    /// Last logged sample summary, so the log shows changes rather than every sample.
    private var lastLoggedSummary: String?

    private(set) var isShowing = false

    /// `targets` is asked on every sample (the controller returns visible windows with their effective colors);
    /// `style` too (current settings).
    init(targets: @escaping @MainActor () -> [Target], style: @escaping @MainActor () -> Style) {
        self.targets = targets
        self.style = style
        super.init()
    }

    /// Creates and orders in one parked canvas per display (call at start and when displays change).
    func prepareCanvases() {
        for canvas in canvases {
            canvas.orderOut(nil)
            canvas.close()
        }
        canvases = NSScreen.screens.map { MissionControlCanvas(screenFrame: $0.frame) }
        lastDrawn = nil
        for canvas in canvases {
            canvas.park()
            canvas.orderFrontRegardless()
        }
        missionControlLog.info("Prepared \(self.canvases.count, privacy: .public) Mission Control canvases")
        if isShowing {
            for canvas in canvases {
                canvas.expand()
            }
            sample()
        }
    }

    /// Removes the canvases (the app stops drawing borders).
    func tearDown() {
        hide()
        for canvas in canvases {
            canvas.orderOut(nil)
            canvas.close()
        }
        canvases.removeAll()
    }

    /// Mission Control started: samples now, then 10 times a second through the enter animation, then 2.5 times a
    /// second while it stays open.
    func show() {
        missionControlLog.notice("Showing thumbnail borders on \(self.canvases.count, privacy: .public) canvases")
        if !isShowing {
            shownAt = CACurrentMediaTime()
            drawingSuspendedUntil = 0
            hadThumbnails = false
            lastLoggedSummary = nil
        }
        isShowing = true
        for canvas in canvases {
            canvas.expand()
            // Re-assert the stacking in case something was ordered above the canvas since startup.
            canvas.orderFrontRegardless()
        }
        sample()
        scheduleNextSample()
    }

    /// Mission Control ended: clears and parks the canvases and stops all sampling. Idempotent.
    func hide() {
        guard isShowing else { return }
        missionControlLog.notice("Hiding thumbnail borders")
        isShowing = false
        timer?.invalidate()
        timer = nil
        lastDrawn = nil
        for canvas in canvases {
            canvas.park()
        }
    }

    /// Mission Control is probably closing (the user clicked): clears the canvases at once, since borders sampled at
    /// the thumbnail positions would trail the windows zooming back, and samples fast for `duration`. If Mission
    /// Control is still open by then (a click on the Spaces bar, a thumbnail drag), the borders are drawn again.
    func suspendDrawing(for duration: TimeInterval) {
        guard isShowing else { return }
        drawingSuspendedUntil = CACurrentMediaTime() + duration
        draw([])
        scheduleNextSample()
    }

    // MARK: - Sampling

    private func scheduleNextSample() {
        timer?.invalidate()
        guard isShowing else { return }
        let now = CACurrentMediaTime()
        let fast = now - shownAt < Self.enterAnimationDuration || now < drawingSuspendedUntil
        let interval = fast ? Self.animatingInterval : Self.settledInterval
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.timer = nil
                self.sample()
                self.scheduleNextSample()
            }
        }
        next.tolerance = interval / 4
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    /// Draws a border around every target shown as a thumbnail (nothing while drawing is suspended; the thumbnails
    /// are still looked for, so their vanishing is reported either way).
    private func sample() {
        guard isShowing else { return }
        let currentTargets = targets()
        let placed = Self.thumbnails(of: currentTargets)
        draw(CACurrentMediaTime() < drawingSuspendedUntil ? [] : placed)
        if placed.isEmpty {
            if hadThumbnails, !currentTargets.isEmpty {
                hadThumbnails = false
                onThumbnailsVanished?()
            }
        } else {
            hadThumbnails = true
        }
        logIfChanged("\(currentTargets.count) windows, \(placed.count) thumbnails")
    }

    /// Mission Control draws each window as a thumbnail, and the window server reports the thumbnail's bounds while
    /// AX keeps the real frame: bounds uniformly scaled down from the real frame are a thumbnail.
    private static func thumbnails(of targets: [Target]) -> [Placed] {
        let allBounds = WindowServer.bounds(of: targets.map(\.windowID))
        return targets.compactMap { target in
            guard let bounds = allBounds[target.windowID],
                  bounds.width >= minimumThumbnailWidth,
                  target.axFrame.width > 0, target.axFrame.height > 0,
                  bounds.width < target.axFrame.width * thumbnailScaleThreshold,
                  abs(bounds.height / target.axFrame.height - bounds.width / target.axFrame.width)
                    <= maximumScaleMismatch
            else { return nil }
            return Placed(target: target, thumbnailFrame: bounds)
        }
    }

    /// A target and the frame of its thumbnail (global AX coordinates).
    private struct Placed: Equatable {
        let target: Target
        let thumbnailFrame: CGRect
    }

    private func draw(_ placed: [Placed]) {
        let currentStyle = style()
        if let lastDrawn, lastDrawn.placed == placed, lastDrawn.style == currentStyle {
            return
        }
        lastDrawn = (placed, currentStyle)
        let screens = NSScreen.screens
        let primaryScreenHeight = screens.first?.frame.height ?? 0
        let screenFrames = screens.map { $0.frame }
        var borders: [[MissionControlCanvas.Border]] = Array(repeating: [], count: canvases.count)
        for item in placed {
            let appKitFrame = CoordinateConverter.appKitRect(
                fromAX: item.thumbnailFrame, primaryScreenHeight: primaryScreenHeight
            )
            guard let screenIndex = BorderGeometry.indexOfBestScreen(for: appKitFrame, screenFrames: screenFrames),
                  screenIndex < canvases.count
            else { continue }
            let thumbnailScale = item.target.axFrame.width > 0
                ? min(1, item.thumbnailFrame.width / item.target.axFrame.width)
                : 1
            let lineWidth = max(
                Self.minimumLineWidth,
                BorderGeometry.pixelAligned(currentStyle.lineWidth, scale: screens[screenIndex].backingScaleFactor)
            )
            let layout = BorderGeometry.layout(
                windowFrame: appKitFrame,
                lineWidth: lineWidth,
                windowCornerRadius: currentStyle.windowCornerRadius * thumbnailScale,
                placement: .outside
            )
            // From overlay-local to canvas-local (the canvas covers its whole screen).
            let origin = screenFrames[screenIndex].origin
            let rect = layout.strokeRect.offsetBy(
                dx: layout.overlayFrame.minX - origin.x,
                dy: layout.overlayFrame.minY - origin.y
            )
            borders[screenIndex].append(MissionControlCanvas.Border(
                rect: rect, cornerRadius: layout.cornerRadius, lineWidth: lineWidth, color: item.target.color
            ))
        }
        for (canvas, canvasBorders) in zip(canvases, borders) {
            canvas.draw(canvasBorders)
        }
    }

    private func logIfChanged(_ summary: String) {
        guard summary != lastLoggedSummary else { return }
        lastLoggedSummary = summary
        missionControlLog.notice("Sample: \(summary, privacy: .public)")
    }
}

/// A transparent, click-through window covering one display, drawing thumbnail borders as shape layers.
@MainActor
private final class MissionControlCanvas: NSWindow {
    struct Border {
        let rect: CGRect
        let cornerRadius: CGFloat
        let lineWidth: CGFloat
        let color: RGBAColor
    }

    private let screenFrame: CGRect
    private var shapeLayers: [CAShapeLayer] = []

    init(screenFrame: CGRect) {
        self.screenFrame = screenFrame
        super.init(contentRect: screenFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        // Stationary: left alone by Mission Control instead of being laid out (or hidden) with the other windows.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        tabbingMode = .disallowed
        isRestorable = false
        let view = NSView(frame: CGRect(origin: .zero, size: screenFrame.size))
        view.wantsLayer = true
        contentView = view
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MissionControlCanvas is created in code only")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// 1×1 pt and empty while Mission Control is closed: ordered in, but costs next to nothing.
    func park() {
        draw([])
        setFrame(CGRect(origin: screenFrame.origin, size: CGSize(width: 1, height: 1)), display: false, animate: false)
    }

    func expand() {
        setFrame(screenFrame, display: false, animate: false)
        contentView?.frame = CGRect(origin: .zero, size: screenFrame.size)
    }

    /// Replaces the drawn borders; reuses shape layers so per-frame updates allocate nothing.
    func draw(_ borders: [Border]) {
        guard let root = contentView?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        while shapeLayers.count < borders.count {
            let layer = CAShapeLayer()
            layer.fillColor = nil
            layer.actions = ["path": NSNull(), "strokeColor": NSNull(), "lineWidth": NSNull(), "hidden": NSNull()]
            root.addSublayer(layer)
            shapeLayers.append(layer)
        }
        for (index, layer) in shapeLayers.enumerated() {
            guard index < borders.count else {
                layer.isHidden = true
                continue
            }
            let border = borders[index]
            let radius = max(0, min(border.cornerRadius, border.rect.width / 2, border.rect.height / 2))
            layer.isHidden = false
            layer.frame = root.bounds
            layer.contentsScale = backingScaleFactor
            layer.path = border.rect.width > 0 && border.rect.height > 0
                ? CGPath(roundedRect: border.rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                : nil
            layer.lineWidth = border.lineWidth
            layer.strokeColor = NSColor(
                srgbRed: CGFloat(border.color.red),
                green: CGFloat(border.color.green),
                blue: CGFloat(border.color.blue),
                alpha: CGFloat(border.color.alpha)
            ).cgColor
        }
        CATransaction.commit()
    }
}
