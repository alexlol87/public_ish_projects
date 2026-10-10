import AppKit
import BorderCore
import Combine
import QuartzCore

/// Turns tracker events into borders: one `BorderWindow` per tracked window, shown when the window is visible,
/// positioned around it, colored by `ColorService`, and kept directly above it in the window stack.
///
/// Everything is event driven. A frame update touches only that window's overlay, and `BorderWindow.apply` skips
/// unchanged state, so refreshing all overlays after a settings or focus change stays cheap even with 50+ windows.
@MainActor
final class BorderOverlayController: WindowTrackerDelegate {
    private let tracker: WindowTracker
    private let settings: SettingsStore
    private let colors: ColorService

    private var overlays: [CGWindowID: BorderWindow] = [:]
    /// Windows whose overlay is ordered in right now.
    private var shownIDs: Set<CGWindowID> = []
    /// Last report per window; the tracker has already dropped a window by the time it reports its removal, and the
    /// color memory still wants its final title.
    private var lastKnown: [CGWindowID: TrackedWindow] = [:]

    private var isRunning = false
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var settingsRefreshPending = false
    private var occlusionUpdatePending = false
    /// Whether any border currently carries an occlusion mask (so switching back to attached clears them once).
    private var hasOcclusionMasks = false
    private var dragFollower: DragFollower?
    private let missionControl: MissionControlObserver
    private var missionControlBorders: MissionControlBorders?
    private var spaceObserver: NSObjectProtocol?
    /// Windows on the active Space while Mission Control is open. Asked from the apps when Mission Control opens,
    /// again after a Space switch (Spaces can be switched inside Mission Control) or a new window, and otherwise at
    /// most every couple of seconds as a safety net: each ask is one Accessibility call per app on the main thread.
    private var missionControlSpaceWindows: (ids: Set<CGWindowID>, at: CFTimeInterval)?
    private static let spaceWindowsMaxAge: CFTimeInterval = 2
    /// After a click in Mission Control the thumbnail borders stay cleared this long unless it closes first.
    private static let drawingSuspensionAfterExitHint: TimeInterval = 0.5
    /// Normal borders are re-stacked after Mission Control closes: once after its exit animation (ordering against
    /// windows still being animated misbehaved), and once more in case the animation ran long.
    private static let reorderDelaysAfterExit: [TimeInterval] = [0.5, 1.2]

    /// Cached screen geometry (AppKit coordinates), refreshed on screen-parameter changes; read on every frame
    /// update, so it is not re-queried from NSScreen each time.
    private var primaryScreenHeight: CGFloat = 0
    private var screenFrames: [CGRect] = []
    private var screenScales: [CGFloat] = []
    private let osMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    init(tracker: WindowTracker, settings: SettingsStore) {
        self.tracker = tracker
        self.settings = settings
        colors = ColorService(settings: settings)
        missionControl = MissionControlObserver()
        tracker.delegate = self
    }

    // MARK: - Public API

    func start() {
        guard !isRunning else { return }
        isRunning = true
        updateScreenGeometry()

        settings.changes
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.scheduleSettingsRefresh()
                }
            }
            .store(in: &cancellables)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.screenParametersDidChange()
            }
        }

        dragFollower = DragFollower(
            windowToFollow: { [weak self] in self?.tracker.focusedWindowID },
            onBoundsChange: { [weak self] id, bounds in self?.followDrag(of: id, to: bounds) }
        )
        updateDragFollower()

        missionControlBorders = MissionControlBorders(
            targets: { [weak self] in self?.missionControlTargets() ?? [] },
            style: { [weak self] in
                self?.missionControlStyle() ?? MissionControlBorders.Style(lineWidth: 4, windowCornerRadius: 10)
            }
        )
        // Windows zooming back to full size are the earliest sign of the exit; the observer confirms it with the Dock.
        missionControlBorders?.onThumbnailsVanished = { [weak self] in
            guard let self else { return }
            self.missionControl.suspectExit(.noThumbnails)
        }
        missionControlBorders?.prepareCanvases()
        missionControl.onChange = { [weak self] mode in
            self?.missionControlDidChange(mode)
        }
        // A click in Mission Control usually picks a window: clear the thumbnail borders at once, since borders
        // sampled at the thumbnail positions would trail the zooming window; they come back if it stays open.
        missionControl.onExitSuspected = { [weak self] hint in
            guard let self, hint != .noThumbnails else { return }
            self.missionControlBorders?.suspendDrawing(for: Self.drawingSuspensionAfterExitHint)
        }
        missionControl.start()
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.missionControlSpaceWindows = nil
            }
        }
        missionControlLog.notice("Tracking started; watching for Mission Control")

        refreshAll(reorder: false)
    }

    func stop() {
        isRunning = false
        cancellables.removeAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        spaceObserver = nil
        dragFollower?.stop()
        dragFollower = nil
        missionControl.stop()
        missionControl.onChange = nil
        missionControl.onExitSuspected = nil
        missionControlBorders?.tearDown()
        missionControlBorders = nil
        for overlay in overlays.values {
            overlay.orderOut(nil)
            overlay.close()
        }
        overlays.removeAll()
        shownIDs.removeAll()
        colors.persistNow()
    }

    /// For a pinned app the border shows the pin, so recoloring moves the pin to the next palette color (otherwise
    /// the menu item and the hot key would seem to do nothing). The settings change redraws every window of the app.
    func cycleColorOfFocusedWindow() {
        guard let window = focusedWindow() else { return }
        if let bundleID = window.bundleID, let pinned = settings.appColorOverrides[bundleID] {
            settings.appColorOverrides[bundleID] = BorderCore.ColorPicker.next(after: pinned, in: settings.palette)
            return
        }
        colors.cycleColor(of: window)
        refresh(window)
    }

    /// Same rule as `cycleColorOfFocusedWindow`: a pinned app's pin changes instead of the window's own color.
    func setColorOfFocusedWindow(_ color: RGBAColor) {
        guard let window = focusedWindow() else { return }
        if let bundleID = window.bundleID, settings.appColorOverrides[bundleID] != nil {
            settings.appColorOverrides[bundleID] = color
            return
        }
        colors.setColor(color, of: window)
        refresh(window)
    }

    /// The focused window as the menu shows it; `color` is the effective color (an app pin wins).
    var focusedWindowSummary: FocusedWindowSummary? {
        guard let window = focusedWindow(), let color = colors.effectiveColor(for: window) else { return nil }
        return FocusedWindowSummary(
            windowID: window.id, appName: window.appName, bundleID: window.bundleID, title: window.title, color: color
        )
    }

    func persistColorMemory() {
        colors.persistNow()
    }

    // MARK: - WindowTrackerDelegate

    func tracker(_ tracker: WindowTracker, didAdd window: TrackedWindow) {
        lastKnown[window.id] = window
        guard isRunning else { return }
        if missionControl.mode != nil {
            missionControlSpaceWindows = nil
        }
        ensureColor(for: window)
        refresh(window)
    }

    func tracker(_ tracker: WindowTracker, didUpdate window: TrackedWindow, changes: WindowChange) {
        lastKnown[window.id] = window
        guard isRunning else { return }
        // While a drag is followed, the display link already moved this border to the window server's live bounds;
        // an AX frame read a moment earlier would only make it jitter back.
        if changes == .frame, let followed = dragFollower?.followedWindowID, followed == window.id {
            return
        }
        ensureColor(for: window)
        if changes.contains(.title) {
            colors.titleDidChange(window, liveWindows: Array(tracker.windows.values))
        }
        refresh(window)
    }

    func tracker(_ tracker: WindowTracker, didRemove windowID: CGWindowID) {
        colors.remove(windowID, lastKnown: lastKnown.removeValue(forKey: windowID))
        hideOverlay(windowID)
        overlays.removeValue(forKey: windowID)?.close()
        scheduleOcclusionUpdate()
    }

    /// The newly frontmost app's windows were raised above every overlay, including their own borders: put those
    /// borders back on top of their windows, back to front. With emphasis on, every border's width/opacity may
    /// have changed too (the tracker does not report `isFocused` flips separately).
    func tracker(_ tracker: WindowTracker, didChangeFocusTo windowID: CGWindowID?, frontmostPID: pid_t?) {
        guard isRunning else { return }
        if settings.emphasizeActiveWindow {
            for id in shownIDs {
                if let window = tracker.windows[id] {
                    refresh(window)
                }
            }
        }
        guard let frontmostPID else { return }
        for id in tracker.windowIDs(ofApp: frontmostPID).reversed() where shownIDs.contains(id) {
            if let overlay = overlays[id] {
                order(overlay, above: id)
            }
        }
        scheduleOcclusionUpdate()
    }

    // MARK: - Rendering

    /// Shows, updates or hides one window's border.
    /// - Parameter axFrame: live bounds from the drag follower; nil uses the tracker's frame.
    private func refresh(_ window: TrackedWindow, axFrame: CGRect? = nil) {
        guard isRunning, isVisible(window), let color = colors.effectiveColor(for: window) else {
            hideOverlay(window.id)
            return
        }
        let emphasized = settings.emphasizeActiveWindow && window.isFocused
        let opacity = settings.emphasizeActiveWindow && !window.isFocused ? settings.inactiveOpacity : 1
        let overlay = overlay(for: window.id)
        overlay.apply(
            layout: layout(for: window, axFrame: axFrame ?? liveFrame(of: window), emphasized: emphasized),
            color: color,
            opacity: opacity
        )
        // Frame and color are in place before the overlay is ordered in, so it never flashes at a stale position.
        if shownIDs.insert(window.id).inserted {
            order(overlay, above: window.id)
        }
        scheduleOcclusionUpdate()
    }

    /// While a drag is followed, the window server's live bounds; the AX frame may be from before the drag (a title
    /// or focus refresh mid-drag would otherwise snap the border back).
    private func liveFrame(of window: TrackedWindow) -> CGRect {
        if let follower = dragFollower, follower.followedWindowID == window.id, let bounds = follower.followedBounds {
            return bounds
        }
        return window.frame
    }

    /// Contract visibility rule. Covered windows stay "visible": z-ordering hides their borders behind whatever
    /// covers them.
    private func isVisible(_ window: TrackedWindow) -> Bool {
        settings.isEnabled
            && settings.appFilter.allows(bundleID: window.bundleID)
            && !window.isMinimized
            && !window.isAppHidden
            && window.isOnScreen
            && (!window.isFullscreen || settings.showInFullscreen)
    }

    private func layout(for window: TrackedWindow, axFrame: CGRect, emphasized: Bool) -> BorderLayout {
        let windowFrame = CoordinateConverter.appKitRect(fromAX: axFrame, primaryScreenHeight: primaryScreenHeight)
        var lineWidth = CGFloat(settings.borderWidth)
        if emphasized {
            lineWidth += CGFloat(settings.activeWidthBoost)
        }
        // Whole device pixels keep both edges of the stroke crisp on the display the window is (mostly) on.
        lineWidth = BorderGeometry.pixelAligned(lineWidth, scale: backingScale(for: windowFrame))
        // Fullscreen windows fill the screen with square corners, and there is no room outside the screen edge.
        if window.isFullscreen {
            return BorderGeometry.layout(
                windowFrame: windowFrame, lineWidth: lineWidth, windowCornerRadius: 0, placement: .inside
            )
        }
        return BorderGeometry.layout(
            windowFrame: windowFrame, lineWidth: lineWidth, windowCornerRadius: windowCornerRadius, placement: .outside
        )
    }

    /// Apps cannot query a window's real corner radius, so "auto" uses the radius of standard titled windows for
    /// the running macOS version; windows with other styles may need the custom value.
    private var windowCornerRadius: CGFloat {
        switch settings.cornerRadiusMode {
        case .auto:
            return BorderGeometry.defaultWindowCornerRadius(osMajorVersion: osMajorVersion)
        case .custom:
            return CGFloat(settings.customCornerRadius)
        }
    }

    private func backingScale(for appKitFrame: CGRect) -> CGFloat {
        if let index = BorderGeometry.indexOfBestScreen(for: appKitFrame, screenFrames: screenFrames) {
            return screenScales[index]
        }
        return screenScales.first ?? 2
    }

    // MARK: - Overlay lifecycle and z-order

    private func overlay(for id: CGWindowID) -> BorderWindow {
        if let existing = overlays[id] {
            return existing
        }
        let overlay = BorderWindow(level: overlayLevel)
        overlays[id] = overlay
        return overlay
    }

    private func hideOverlay(_ id: CGWindowID) {
        guard shownIDs.remove(id) != nil else { return }
        overlays[id]?.orderOut(nil)
        scheduleOcclusionUpdate()
    }

    private var overlayLevel: NSWindow.Level {
        switch settings.borderLayering {
        case .attached:
            return .normal
        case .floating:
            return .floating
        }
    }

    /// Attached: directly above the decorated window, so windows in front of it also cover its border. Floating
    /// (fallback for apps where attached ordering misbehaves): above all normal windows; bringing it to the front of
    /// its level keeps the focused app's borders above other borders.
    private func order(_ overlay: BorderWindow, above windowID: CGWindowID) {
        switch settings.borderLayering {
        case .attached:
            overlay.order(.above, relativeTo: Int(windowID))
        case .floating:
            overlay.orderFront(nil)
        }
    }

    /// Re-stacks every shown border back to front (after a layering change).
    private func reorderAll() {
        var ordered = Set<CGWindowID>()
        for id in WindowServer.frontToBackOrder().reversed() where shownIDs.contains(id) {
            if let overlay = overlays[id] {
                order(overlay, above: id)
                ordered.insert(id)
            }
        }
        for id in shownIDs where !ordered.contains(id) {
            if let overlay = overlays[id] {
                order(overlay, above: id)
            }
        }
    }

    // MARK: - Floating layering: cut out covered parts

    /// Coalesced: many borders change at once after a focus or settings change, and during a drag every frame moves
    /// one; one window-list query per run loop pass covers them all.
    private func scheduleOcclusionUpdate() {
        guard isRunning, !occlusionUpdatePending else { return }
        occlusionUpdatePending = true
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.occlusionUpdatePending = false
                self.updateOcclusion()
            }
        }
    }

    /// In floating layering every border sits above every normal window, so a covered window's border would draw
    /// over the windows in front of it. Each border is masked by the windows in front of its own (window server
    /// order, front to back), which makes floating borders look attached without relying on per-window ordering.
    /// Attached borders need no mask: the window stack already hides them.
    private func updateOcclusion() {
        guard isRunning else { return }
        guard settings.borderLayering == .floating else {
            if hasOcclusionMasks {
                hasOcclusionMasks = false
                for overlay in overlays.values {
                    overlay.setCoveredRects([])
                }
            }
            return
        }
        hasOcclusionMasks = true
        var inFront: [CGRect] = []
        var masked = Set<CGWindowID>()
        for info in WindowServer.onScreenWindows() {
            if shownIDs.contains(info.id), let overlay = overlays[info.id] {
                let origin = overlay.frame.origin
                overlay.setCoveredRects(inFront.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) })
                masked.insert(info.id)
            }
            inFront.append(
                CoordinateConverter.appKitRect(fromAX: info.bounds, primaryScreenHeight: primaryScreenHeight)
            )
        }
        for (id, overlay) in overlays where !masked.contains(id) {
            overlay.setCoveredRects([])
        }
    }

    // MARK: - Mission Control

    private func missionControlDidChange(_ mode: MissionControlObserver.Mode?) {
        guard isRunning else { return }
        let modeName = String(describing: mode)
        let enabled = settings.isEnabled && settings.showInMissionControl
        missionControlLog.notice(
            "Mission Control mode \(modeName, privacy: .public), borders: \(enabled, privacy: .public)"
        )
        // The window server reports thumbnail bounds while Mission Control is open; following a click on a
        // thumbnail would leave the border on the thumbnail's rect.
        dragFollower?.isSuspended = mode != nil
        switch mode {
        case .allWindows?, .appWindows?:
            missionControlSpaceWindows = nil
            updateMissionControlBorders()
        case .desktop?:
            missionControlBorders?.hide()
        case nil:
            missionControlBorders?.hide()
            missionControlSpaceWindows = nil
            // Back to the real frames (from AX, which Mission Control never changes). Mission Control shows the
            // normal borders again by itself; the stack is re-asserted once its exit animation is over, since
            // ordering against windows it is still animating can leave borders above windows that cover them.
            refreshAll(reorder: false)
            for delay in Self.reorderDelaysAfterExit {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.isRunning, self.missionControl.mode == nil else { return }
                        self.reorderAll()
                        self.scheduleOcclusionUpdate()
                    }
                }
            }
        }
    }

    /// Shows or hides the thumbnail borders for the current settings (Mission Control is open).
    private func updateMissionControlBorders() {
        guard let borders = missionControlBorders else { return }
        if settings.isEnabled && settings.showInMissionControl {
            if !borders.isShowing {
                borders.show()
            }
        } else {
            borders.hide()
        }
    }

    /// Every window on the active Space that would have a border, at its real (AX) frame; MissionControlBorders
    /// finds the thumbnails. Space membership comes from the apps themselves: during Mission Control the window
    /// server reports thumbnail bounds for windows of every Space, full-screen ones included, which Mission Control
    /// does not show on this Space. The set is cached (see `missionControlSpaceWindows`), not re-asked per sample.
    private func missionControlTargets() -> [MissionControlBorders.Target] {
        let now = CACurrentMediaTime()
        let onActiveSpace: Set<CGWindowID>
        if let cached = missionControlSpaceWindows, now - cached.at < Self.spaceWindowsMaxAge {
            onActiveSpace = cached.ids
        } else {
            onActiveSpace = tracker.windowIDsOnActiveSpace()
            missionControlSpaceWindows = (onActiveSpace, now)
        }
        return tracker.windows.values.sorted { $0.id < $1.id }.compactMap { window in
            var candidate = window
            candidate.isOnScreen = onActiveSpace.contains(window.id)
            guard isVisible(candidate), let color = colors.effectiveColor(for: window) else { return nil }
            return MissionControlBorders.Target(
                windowID: window.id, axFrame: window.frame, color: color
            )
        }
    }

    private func missionControlStyle() -> MissionControlBorders.Style {
        MissionControlBorders.Style(lineWidth: CGFloat(settings.borderWidth), windowCornerRadius: windowCornerRadius)
    }

    // MARK: - Colors

    /// Colors are picked when a border is about to appear, not when the tracker first sees the window: windows that
    /// aren't visible yet (borders off, filtered app, a burst of new windows not yet on screen) would otherwise all
    /// be counted against an empty `inUse` and get the same color. By then the title is usually final too, which
    /// helps the remembered-color lookup.
    private func ensureColor(for window: TrackedWindow) {
        guard isVisible(window), colors.assignedColor(for: window.id) == nil else { return }
        let inUse = shownIDs.compactMap { (id: CGWindowID) -> RGBAColor? in
            guard id != window.id, let shown = tracker.windows[id] else { return nil }
            return colors.effectiveColor(for: shown)
        }
        colors.assign(window, inUse: inUse, liveWindows: Array(tracker.windows.values))
    }

    private func focusedWindow() -> TrackedWindow? {
        guard let id = tracker.focusedWindowID else { return nil }
        return tracker.windows[id]
    }

    // MARK: - Settings, screens, dragging

    /// `resetToDefaults()` changes many settings at once and each fires `changes`; one refresh covers them all.
    private func scheduleSettingsRefresh() {
        guard !settingsRefreshPending else { return }
        settingsRefreshPending = true
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.settingsRefreshPending = false
                self.settingsDidChange()
            }
        }
    }

    private func settingsDidChange() {
        guard isRunning else { return }
        colors.paletteDidChange()
        let level = overlayLevel
        var layeringChanged = false
        for overlay in overlays.values where overlay.level != level {
            overlay.level = level
            layeringChanged = true
        }
        updateDragFollower()
        refreshAll(reorder: layeringChanged)
        scheduleOcclusionUpdate()
        if missionControl.mode == .allWindows || missionControl.mode == .appWindows {
            updateMissionControlBorders()
        }
    }

    private func screenParametersDidChange() {
        guard isRunning else { return }
        updateScreenGeometry()
        missionControlBorders?.prepareCanvases()
        refreshAll(reorder: false)
    }

    private func updateScreenGeometry() {
        let screens = NSScreen.screens
        primaryScreenHeight = screens.first?.frame.height ?? 0
        screenFrames = screens.map { $0.frame }
        screenScales = screens.map { $0.backingScaleFactor }
    }

    /// Re-evaluates visibility, layout and color of every border (settings, screens, start).
    private func refreshAll(reorder: Bool) {
        for id in shownIDs where tracker.windows[id] == nil {
            hideOverlay(id)
        }
        // Stable order so least-used assignment of windows that have no color yet is deterministic.
        for window in tracker.windows.values.sorted(by: { $0.id < $1.id }) {
            lastKnown[window.id] = window
            ensureColor(for: window)
            refresh(window)
        }
        if reorder {
            reorderAll()
        }
    }

    /// Following is only needed while borders are drawn; when disabled, not even the mouse monitor stays installed.
    private func updateDragFollower() {
        if settings.isEnabled {
            dragFollower?.start()
        } else {
            dragFollower?.stop()
        }
    }

    private func followDrag(of id: CGWindowID, to bounds: CGRect) {
        guard shownIDs.contains(id), let window = tracker.windows[id] else { return }
        refresh(window, axFrame: bounds)
    }
}
