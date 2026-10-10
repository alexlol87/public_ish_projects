import AppKit
import ApplicationServices
import QuartzCore

/// Tells when Mission Control, App Exposé or Show Desktop opens and closes.
///
/// There is no public API for this, so three sources are combined, each checked against the Dock's Accessibility
/// tree (`MissionControlTree`: the Dock publishes an "mc" group only while Mission Control is open):
/// - the Dock's private AX notifications (the approach yabai uses), which register fine but never arrive on some Macs;
/// - a transient sentinel window (`MissionControlSentinel`) that Mission Control hides and shows again, so its
///   occlusion flips mark the start and the end without polling;
/// - a once-a-second look at the Dock's tree as the safety net.
///
/// While Mission Control is open the tree is re-checked 2.5 times a second. A click (the user picking a window),
/// the sentinel reappearing or the thumbnails vanishing are exit hints: they switch to 10 checks a second for a
/// moment and lower the number of misses needed, so the mode ends a fraction of a second after the exit instead of
/// more than a second later.
///
/// The Dock can be restarted (`killall Dock`, crashes), which kills the AX observer, so the Dock's launch and
/// termination are watched too and the registration is redone for the new process.
@MainActor
final class MissionControlObserver {
    enum Mode: Equatable {
        /// Mission Control (three-finger swipe up): every window of the Space as a thumbnail.
        case allWindows
        /// App Exposé (swipe down): the front app's windows as thumbnails, the others left in place.
        case appWindows
        /// Show Desktop: every window pushed off screen at full size.
        case desktop
    }

    /// Evidence that Mission Control is closing, before the Dock's tree confirms it.
    enum ExitHint: String {
        /// A mouse button went down while Mission Control was open: the user is picking a window or clicking away.
        case mouseDown
        /// The sentinel window is on screen again, which Mission Control only allows once it closes.
        case sentinelVisible
        /// The window server stopped reporting scaled-down bounds: the windows are zooming back to full size.
        case noThumbnails
    }

    static let dockBundleID = "com.apple.dock"

    /// The Dock's private notification names; nil marks the end of any mode.
    private static let notifications: [(name: String, mode: Mode?)] = [
        ("AXExposeShowAllWindows", .allWindows),
        ("AXExposeShowFrontWindows", .appWindows),
        ("AXExposeShowDesktop", .desktop),
        ("AXExposeExit", nil),
    ]

    /// A freshly launched Dock answers AX only after a moment; registration is retried after each of these delays.
    private static let retryDelays: [TimeInterval] = [0.5, 1, 2, 4]
    private static let pollInterval: TimeInterval = 1
    /// After an exit the Dock did not confirm (its tree may linger through the exit animation), the tree must not
    /// re-open the mode for this long.
    private static let quietPeriodAfterUnconfirmedExit: CFTimeInterval = 1.5
    /// The Dock builds its tree a moment after Mission Control starts, so after the sentinel is hidden the tree is
    /// looked for again after each of these delays (0.1, 0.25, 0.5, 0.8 and 1.2 s in all).
    private static let confirmDelays: [TimeInterval] = [0.1, 0.15, 0.25, 0.3, 0.4]
    /// Checks of the Dock's tree while Mission Control is open: the settled rate, and the rate after an exit hint.
    private static let exitCheckInterval: TimeInterval = 0.4
    private static let fastExitCheckInterval: TimeInterval = 0.1
    private static let fastExitCheckDuration: CFTimeInterval = 1.5
    /// A mode started by a notification may run ahead of the Dock's tree; a missing tree this soon means "not yet".
    private static let treeGracePeriod: CFTimeInterval = 1.0
    /// Checks in a row without the tree before Mission Control counts as closed. The tree was once seen missing for a
    /// single check while Mission Control stayed open, so one miss is trusted only with another sign of the exit.
    private static let missingChecksWhenSettled = 3
    private static let missingChecksWhenFast = 2
    private static let corroborationWindow: CFTimeInterval = 1.5

    /// Called on every change; nil = Mission Control ended.
    var onChange: ((Mode?) -> Void)?
    /// Called on every exit hint, before the Dock confirms it (the thumbnail borders clear themselves meanwhile).
    var onExitSuspected: ((ExitHint) -> Void)?
    private(set) var mode: Mode?

    private var isRunning = false
    /// Bumped by start()/stop() and on every Dock launch/exit, so retries scheduled for an earlier Dock are dropped.
    private var generation = 0
    private var observer: AXObserver?
    /// The Dock process the observer is registered with.
    private var observedDockPID: pid_t?
    private var workspaceTokens: [NSObjectProtocol] = []
    private let sentinel = MissionControlSentinel()
    /// Bumped by every sentinel flip, so a confirmation burst pending for an earlier flip is dropped.
    private var confirmBurst = 0
    private var pollTimer: Timer?
    private var lastUnconfirmedExit: CFTimeInterval = 0
    /// Exit detection while Mission Control is open.
    private var exitCheckTimer: Timer?
    private var modeStartedAt: CFTimeInterval = 0
    /// Whether the Dock's tree has been seen during this mode; until then a missing tree may just be "not built yet".
    private var treeSeen = false
    private var missingTreeChecks = 0
    private var fastChecksUntil: CFTimeInterval = 0
    private var corroboratedUntil: CFTimeInterval = 0
    /// Installed only while Mission Control is open: a click there usually ends it.
    private var mouseMonitor: Any?

    /// The running Dock's pid (the observed one when registered).
    var dockPID: pid_t? {
        if let observedDockPID {
            return observedDockPID
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: Self.dockBundleID).first?
            .processIdentifier
    }

    init() {}

    /// Watches the running Dock (if any) and every later Dock launch. Idempotent.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        generation &+= 1
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applicationLaunched(note)
            }
        })
        workspaceTokens.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applicationTerminated(note)
            }
        })
        register(attempt: 0)
        sentinel.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.sentinelDidChange(visible: visible)
        }
        sentinel.start()
        startPolling()
    }

    /// Removes every observer, timer and monitor. Does not call `onChange`; `mode` is reset silently.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation &+= 1
        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceTokens {
            center.removeObserver(token)
        }
        workspaceTokens.removeAll()
        removeAXObserver()
        sentinel.onVisibilityChange = nil
        sentinel.stop()
        pollTimer?.invalidate()
        pollTimer = nil
        exitCheckTimer?.invalidate()
        exitCheckTimer = nil
        removeMouseMonitor()
        mode = nil
    }

    /// Evidence that Mission Control is closing (a click, the sentinel reappearing, no more thumbnails): the Dock's
    /// tree is checked now and then 10 times a second for a moment, needing fewer misses than at the settled rate.
    func suspectExit(_ hint: ExitHint) {
        guard isRunning, let current = mode else { return }
        missionControlLog.info("Exit hint: \(hint.rawValue, privacy: .public)")
        onExitSuspected?(hint)
        if hint == .sentinelVisible, current != .allWindows {
            // App Exposé and Show Desktop publish no tree to check against; the sentinel reappearing is the exit.
            endMode(detectedBy: "sentinel visible", treeGone: false)
            return
        }
        let now = CACurrentMediaTime()
        fastChecksUntil = now + Self.fastExitCheckDuration
        if hint != .mouseDown {
            corroboratedUntil = now + Self.corroborationWindow
        }
        checkForExit(reason: hint.rawValue)
        scheduleExitCheck()
    }

    // MARK: - Mode changes

    private func beginMode(_ newMode: Mode, detectedBy source: String, treeSeen: Bool) {
        let modeName = String(describing: newMode)
        missionControlLog.notice("Mission Control: \(modeName, privacy: .public) (\(source, privacy: .public))")
        mode = newMode
        modeStartedAt = CACurrentMediaTime()
        self.treeSeen = treeSeen
        missingTreeChecks = 0
        fastChecksUntil = 0
        corroboratedUntil = 0
        installMouseMonitor()
        scheduleExitCheck()
        onChange?(newMode)
    }

    /// - Parameter treeGone: the Dock's tree was just seen missing. Otherwise it may linger through the exit
    ///   animation, and the tree must not re-open the mode right away.
    private func endMode(detectedBy source: String, treeGone: Bool) {
        guard mode != nil else { return }
        missionControlLog.notice("Mission Control ended (\(source, privacy: .public))")
        if !treeGone {
            lastUnconfirmedExit = CACurrentMediaTime()
        }
        mode = nil
        removeMouseMonitor()
        scheduleExitCheck()
        onChange?(nil)
    }

    private var inQuietPeriod: Bool {
        CACurrentMediaTime() - lastUnconfirmedExit < Self.quietPeriodAfterUnconfirmedExit
    }

    private func treeIsPresent() -> Bool {
        guard let pid = dockPID else { return false }
        return MissionControlTree.missionControlGroup(dockPID: pid) != nil
    }

    // MARK: - Polling (fallback)

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.poll()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        guard isRunning, mode == nil, !inQuietPeriod, treeIsPresent() else { return }
        beginMode(.allWindows, detectedBy: "poll: the Dock's tree is there without a notification or a sentinel flip",
                  treeSeen: true)
    }

    // MARK: - Sentinel

    private func sentinelDidChange(visible: Bool) {
        guard isRunning else { return }
        confirmBurst &+= 1
        let state = visible ? "visible" : "hidden"
        missionControlLog.info("Sentinel \(state, privacy: .public)")
        if visible {
            if mode != nil {
                suspectExit(.sentinelVisible)
            }
        } else if mode == nil {
            confirmEntry(attempt: 0)
        }
    }

    /// The sentinel was hidden: Mission Control, if the Dock's tree agrees. The tree is built a moment after Mission
    /// Control starts, so it is looked for a few more times; right after an unconfirmed exit only once (it may linger).
    private func confirmEntry(attempt: Int) {
        guard isRunning, mode == nil else { return }
        if treeIsPresent() {
            beginMode(.allWindows, detectedBy: "sentinel hidden, the Dock's tree found at check \(attempt + 1)",
                      treeSeen: true)
            return
        }
        guard attempt < Self.confirmDelays.count, !inQuietPeriod else { return }
        let scheduledGeneration = generation
        let scheduledBurst = confirmBurst
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmDelays[attempt]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, self.generation == scheduledGeneration,
                      self.confirmBurst == scheduledBurst
                else { return }
                self.confirmEntry(attempt: attempt + 1)
            }
        }
    }

    // MARK: - Exit detection while open

    private func scheduleExitCheck() {
        exitCheckTimer?.invalidate()
        exitCheckTimer = nil
        guard isRunning, mode == .allWindows else { return }
        let interval = CACurrentMediaTime() < fastChecksUntil ? Self.fastExitCheckInterval : Self.exitCheckInterval
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.exitCheckTimer = nil
                self.checkForExit(reason: "periodic check")
                self.scheduleExitCheck()
            }
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        exitCheckTimer = timer
    }

    /// One look at the Dock's tree while Mission Control is open; enough misses in a row end the mode. Only full
    /// Mission Control is known to publish the tree; the other modes end with their notification or the sentinel.
    private func checkForExit(reason: String) {
        guard isRunning, mode == .allWindows else { return }
        if treeIsPresent() {
            treeSeen = true
            missingTreeChecks = 0
            return
        }
        let now = CACurrentMediaTime()
        guard treeSeen || now - modeStartedAt > Self.treeGracePeriod else { return }
        missingTreeChecks += 1
        let required: Int
        if now < corroboratedUntil {
            required = 1
        } else if now < fastChecksUntil {
            required = Self.missingChecksWhenFast
        } else {
            required = Self.missingChecksWhenSettled
        }
        guard missingTreeChecks >= required else { return }
        endMode(
            detectedBy: "the Dock's tree gone for \(missingTreeChecks) check(s), \(reason)", treeGone: true
        )
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.suspectExit(.mouseDown)
            }
        }
    }

    private func removeMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
    }

    // MARK: - The Dock's notifications

    /// Entry point of the C callback.
    fileprivate func handle(_ notification: String) {
        missionControlLog.notice("Dock posted \(notification, privacy: .public)")
        guard isRunning, let entry = Self.notifications.first(where: { $0.name == notification }),
              entry.mode != mode else { return }
        if let newMode = entry.mode {
            beginMode(newMode, detectedBy: "notification", treeSeen: false)
        } else {
            endMode(detectedBy: "notification", treeGone: false)
        }
    }

    /// Creates an observer for the current Dock process and registers the Exposé notifications. Without a running
    /// Dock it does nothing: the launch notification registers later.
    private func register(attempt: Int) {
        guard isRunning else { return }
        removeAXObserver()
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: Self.dockBundleID).first
        else {
            missionControlLog.error("The Dock is not running; waiting for it to launch")
            return
        }
        let pid = dock.processIdentifier
        var created: AXObserver?
        let createResult = AXObserverCreate(pid, missionControlObserverCallback, &created)
        guard createResult == .success, let created else {
            missionControlLog.error("AXObserverCreate for the Dock failed: \(createResult.rawValue, privacy: .public)")
            scheduleRetry(after: attempt)
            return
        }
        let dockElement = AXUIElementCreateApplication(pid)
        // Unretained: the controller keeps this object for the app's lifetime, and stop() removes the run loop
        // source (no more callbacks) before it could be freed.
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var registeredAny = false
        var dockBusy = false
        for entry in Self.notifications where !dockBusy {
            let result = AXObserverAddNotification(created, dockElement, entry.name as CFString, refcon)
            missionControlLog.info("Register \(entry.name, privacy: .public): \(result.rawValue, privacy: .public)")
            switch result {
            case .success, .notificationAlreadyRegistered:
                registeredAny = true
            case .cannotComplete:
                // Not answering yet: each further call would wait for the full messaging timeout.
                dockBusy = true
            default:
                continue
            }
        }
        guard registeredAny, !dockBusy else {
            missionControlLog.error("Dock notifications not registered (attempt \(attempt, privacy: .public))")
            scheduleRetry(after: attempt)
            return
        }
        missionControlLog.notice("Watching the Dock (pid \(Int(pid), privacy: .public)) for Mission Control")
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        observedDockPID = pid
    }

    private func scheduleRetry(after attempt: Int) {
        guard attempt < Self.retryDelays.count else { return }
        let scheduledGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelays[attempt]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, self.generation == scheduledGeneration else { return }
                self.register(attempt: attempt + 1)
            }
        }
    }

    /// Registrations die with the AXObserver; without the run loop source nothing is delivered in the meantime.
    private func removeAXObserver() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
        observedDockPID = nil
    }

    private func applicationLaunched(_ note: Notification) {
        guard isRunning, isDock(note) else { return }
        generation &+= 1
        register(attempt: 0)
    }

    /// A Dock that dies mid-Mission Control never posts AXExposeExit, so the mode ends here.
    private func applicationTerminated(_ note: Notification) {
        guard isRunning, isDock(note) else { return }
        generation &+= 1
        removeAXObserver()
        endMode(detectedBy: "the Dock quit", treeGone: true)
    }

    private func isDock(_ note: Notification) -> Bool {
        let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return running?.bundleIdentifier == Self.dockBundleID
    }
}

/// AXObserver callback. Runs on the main thread because the observer's source is on the main run loop; the refcon is
/// the unretained `MissionControlObserver` that registered the notification.
private func missionControlObserverCallback(_ observer: AXObserver, _ element: AXUIElement,
                                            _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    MainActor.assumeIsolated {
        let owner = Unmanaged<MissionControlObserver>.fromOpaque(refcon).takeUnretainedValue()
        owner.handle(notification as String)
    }
}
