import AppKit
import ApplicationServices
import BorderCore

/// Discovers standard windows of regular apps and keeps `windows` current, reporting every change to the delegate.
///
/// Notifications do the work: AXObserver per app (created, moved, resized, destroyed, minimized, title, focus,
/// hidden) plus NSWorkspace (launch, terminate, activate, hide, Space change). CGWindowList supplies window IDs,
/// stacking order and on-screen state. A 2 s reconcile pass catches what notifications miss; it only compares one
/// CGWindowList snapshot with the previous one and touches AX for the windows that actually differ, so idle cost is
/// one window server call every couple of seconds.
@MainActor
final class WindowTracker {
    weak var delegate: WindowTrackerDelegate?
    private(set) var windows: [CGWindowID: TrackedWindow] = [:]
    private(set) var focusedWindowID: CGWindowID?

    /// Delays between AXObserver setup attempts for an app that does not answer AX yet (freshly launched).
    private static let observerRetryDelays: [TimeInterval] = [0.25, 0.5, 1, 2, 4]
    private static let reconcileInterval: TimeInterval = 2
    /// Every Nth reconcile tick also checks that off-screen windows still exist, even if nothing on screen changed.
    private static let existenceCheckEvery = 5
    /// How long a window that was just created, shown or deminimized may take to appear in the on-screen list.
    private static let onScreenSettleDelay: TimeInterval = 0.3
    /// Rescan requests within this window are merged into one pass.
    private static let rescanCoalesceDelay: TimeInterval = 0.1
    /// A launched app's first windows can appear before its observer was registered (no kAXWindowCreated for them).
    private static let postLaunchRescanDelay: TimeInterval = 1

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var isRunning = false
    /// Bumped by start()/stop() so delayed work scheduled by an earlier run is dropped.
    private var generation = 0
    private var apps: [pid_t: TrackedApp] = [:]
    private var elements: [CGWindowID: AXUIElement] = [:]
    private var notificationTokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var reconcileTimer: Timer?
    private var reconcileTick = 0
    /// On-screen layer-0 window bounds seen by the last reconcile pass.
    private var lastOnScreenBounds: [CGWindowID: CGRect] = [:]
    private var pendingRescanPIDs = Set<pid_t>()
    private var pendingRescanAll = false
    private var rescanScheduled = false
    private var focusUpdateScheduled = false
    private var focusUpdateForced = false
    private var onScreenCheckScheduled = false
    private var onScreenCheckRequestedAgain = false

    init() {}

    // MARK: - Public API

    /// Requires Accessibility trust (caller checks). Reports existing windows through didAdd, then the focus.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        generation &+= 1
        // Applies to every AX call this process makes, so a hung app cannot stall the main thread for long.
        AXAccess.setMessagingTimeout(AXUIElementCreateSystemWide())
        observeNotifications()

        let context = ScanContext()
        for running in NSWorkspace.shared.runningApplications where isTrackable(running) {
            setUpApp(running, context: context)
        }
        updateFocus(force: true)

        let timer = Timer.scheduledTimer(withTimeInterval: Self.reconcileInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reconcile()
            }
        }
        timer.tolerance = 1
        reconcileTimer = timer
    }

    /// Removes every observer/timer and reports nothing further (does not send didRemove).
    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation &+= 1
        reconcileTimer?.invalidate()
        reconcileTimer = nil
        for entry in notificationTokens {
            entry.center.removeObserver(entry.token)
        }
        notificationTokens.removeAll()
        for app in apps.values {
            app.observer?.stop()
        }
        apps.removeAll()
        windows.removeAll()
        elements.removeAll()
        focusedWindowID = nil
        lastOnScreenBounds.removeAll()
        reconcileTick = 0
        pendingRescanPIDs.removeAll()
        pendingRescanAll = false
        rescanScheduled = false
        focusUpdateScheduled = false
        focusUpdateForced = false
        onScreenCheckScheduled = false
        onScreenCheckRequestedAgain = false
    }

    /// Re-enumerate everything now (e.g. after a Space change); diff against `windows`, send add/update/remove.
    func rescanAll() {
        guard isRunning else { return }
        let running = NSWorkspace.shared.runningApplications
        let livePIDs = Set(running.filter { !$0.isTerminated }.map(\.processIdentifier))
        for pid in Array(apps.keys) where !livePIDs.contains(pid) {
            removeApp(pid)
        }
        let context = ScanContext()
        var justSetUp = Set<pid_t>()
        for app in running where isTrackable(app) && apps[app.processIdentifier] == nil {
            justSetUp.insert(app.processIdentifier)
            setUpApp(app, context: context)
        }
        for app in apps.values where !justSetUp.contains(app.pid) {
            app.ignoredWindowIDs.removeAll()
            setAppHidden(app.pid, hidden: app.running.isHidden)
            rescanApp(app, context: context)
        }
        syncOnScreenFlags()
    }

    /// Our windows for app `pid`, front-to-back (CGWindowList order), then tracked windows that are not on screen.
    func windowIDs(ofApp pid: pid_t) -> [CGWindowID] {
        var ordered = WindowServer.frontToBackOrder().filter { windows[$0]?.pid == pid }
        let onScreen = Set(ordered)
        ordered += windows.values.filter { $0.pid == pid && !onScreen.contains($0.id) }.map(\.id).sorted()
        return ordered
    }

    /// Tracked windows on the active Space(s), asked from each app: Accessibility only lists an app's windows on
    /// the active Space. Used while Mission Control is open, when the window server reports thumbnail bounds for
    /// windows of every Space (including full-screen ones). Every app is asked in a row on the main thread, so apps
    /// with no window on screen (hidden, minimized, on another Space: nothing of theirs is on this Space) are
    /// skipped and the rest get a short timeout; an app that does not answer in time keeps its on-screen flags.
    func windowIDsOnActiveSpace() -> Set<CGWindowID> {
        var byApp: [pid_t: [CGWindowID]] = [:]
        for window in windows.values where window.isOnScreen {
            byApp[window.pid, default: []].append(window.id)
        }
        var result = Set<CGWindowID>()
        for (pid, onScreen) in byApp {
            guard let app = apps[pid], !app.isSettingUp, let axWindows = AXAccess.windows(of: app.quickElement)
            else {
                result.formUnion(onScreen)
                continue
            }
            for element in axWindows {
                if let id = AXAccess.windowID(of: element), windows[id] != nil {
                    result.insert(id)
                }
            }
        }
        return result
    }

    // MARK: - Apps

    private func isTrackable(_ running: NSRunningApplication) -> Bool {
        running.activationPolicy == .regular
            && running.processIdentifier > 0
            && running.processIdentifier != ownPID
            && !running.isTerminated
    }

    private func setUpApp(_ running: NSRunningApplication, context: ScanContext?) {
        let pid = running.processIdentifier
        guard apps[pid] == nil else { return }
        let app = TrackedApp(running: running)
        apps[pid] = app
        attachObserver(to: app, context: context)
    }

    /// Registers the app's AXObserver, retrying with backoff while the app does not answer. After the last attempt
    /// the app is tracked anyway (with whatever registrations succeeded) so the reconcile pass can still find windows.
    private func attachObserver(to app: TrackedApp, context: ScanContext?) {
        let observer = AppObserver(pid: app.pid, appElement: app.element, delegate: self)
        let ready = observer?.start() ?? false
        if !ready, app.observerAttempts < Self.observerRetryDelays.count {
            observer?.stop()
            let delay = Self.observerRetryDelays[app.observerAttempts]
            app.observerAttempts += 1
            app.isSettingUp = true
            let pid = app.pid
            after(delay) { tracker in tracker.retryObserver(pid) }
            return
        }
        app.isSettingUp = false
        app.observer = observer
        if let observer {
            for (id, element) in elements where windows[id]?.pid == app.pid {
                observer.watch(element, id: id)
            }
        }
        rescanApp(app, context: context ?? ScanContext())
    }

    private func retryObserver(_ pid: pid_t) {
        guard let app = apps[pid], app.observer == nil, !app.running.isTerminated else { return }
        attachObserver(to: app, context: nil)
    }

    private func removeApp(_ pid: pid_t) {
        guard let app = apps.removeValue(forKey: pid) else { return }
        app.observer?.stop()
        app.observer = nil
        for id in windows.values.filter({ $0.pid == pid }).map(\.id) {
            removeWindow(id)
        }
    }

    private func setAppHidden(_ pid: pid_t, hidden: Bool) {
        guard let app = apps[pid], app.isHidden != hidden else { return }
        app.isHidden = hidden
        for window in windows.values where window.pid == pid {
            var updated = window
            updated.isAppHidden = hidden
            commit(updated, .visibility)
        }
        if !hidden {
            syncOnScreenFlags()
        }
        scheduleOnScreenCheck()
    }

    // MARK: - Scanning

    /// Enumerates the app's AX windows: adds new standard windows, refreshes known ones. Tracked windows AX does not
    /// list are kept unless the window server no longer knows them: AX only lists windows on the active Space(s), and
    /// dropping the others would lose their colors on every Space switch.
    private func rescanApp(_ app: TrackedApp, context: ScanContext) {
        guard apps[app.pid] === app, !app.isSettingUp else { return }
        guard let axWindows = AXAccess.windows(of: app.element) else {
            app.noteRescanFailure()
            return
        }
        app.noteRescanSuccess()

        var listed = Set<CGWindowID>()
        for element in axWindows {
            guard let id = resolveWindowID(of: element, app: app, context: context, claimed: listed),
                  !listed.contains(id)
            else { continue }
            listed.insert(id)
            if windows[id] != nil {
                elements[id] = element
                app.observer?.watch(element, id: id) // no-op when already watched; retries a failed registration
                refreshWindow(id, element: element, isOnScreen: context.onScreen.contains(id))
            } else if !addWindow(element, id: id, app: app, context: context) {
                app.ignoredWindowIDs.insert(id)
            }
        }

        let unlisted = windows.values.filter { $0.pid == app.pid && !listed.contains($0.id) }.map(\.id)
        if !unlisted.isEmpty, let alive = WindowServer.existingWindowIDs(among: unlisted) {
            for id in unlisted {
                if !alive.contains(id) {
                    removeWindow(id)
                } else if var window = windows[id], window.isOnScreen != context.onScreen.contains(id) {
                    window.isOnScreen.toggle()
                    commit(window, .visibility)
                }
            }
        }
        // On-screen windows of this app with no standard AX window behind them: seeing them again in the reconcile
        // pass must not trigger another AX enumeration.
        for info in context.onScreenWindows where info.pid == app.pid && windows[info.id] == nil {
            app.ignoredWindowIDs.insert(info.id)
        }
    }

    /// Window ID for an AX window element: a tracked element first (local comparison, no IPC), then the private
    /// `_AXUIElementGetWindow`, then a same-process window with the same bounds that nothing else claimed.
    private func resolveWindowID(of element: AXUIElement, app: TrackedApp, context: ScanContext,
                                 claimed: Set<CGWindowID>) -> CGWindowID? {
        if let id = trackedWindowID(of: element, pid: app.pid) { return id }
        if let id = AXAccess.windowID(of: element) { return id }
        guard let frame = AXAccess.frame(of: element) else { return nil }
        return context.allWindows.values
            .filter {
                $0.pid == app.pid && $0.layer == 0 && !claimed.contains($0.id) && windows[$0.id] == nil
                    && Self.roughlyEqual($0.bounds, frame)
            }
            .map(\.id)
            .min()
    }

    private func trackedWindowID(of element: AXUIElement, pid: pid_t) -> CGWindowID? {
        for (id, candidate) in elements where windows[id]?.pid == pid && CFEqual(candidate, element) {
            return id
        }
        return nil
    }

    /// Adds the window if it is a standard window; returns whether it is (now) tracked.
    private func addWindow(_ element: AXUIElement, id: CGWindowID, app: TrackedApp, context: ScanContext) -> Bool {
        guard windows[id] == nil else { return true }
        let role = AXAccess.string(element, kAXRoleAttribute)
        guard role == kAXWindowRole else { return false }
        let subrole = AXAccess.string(element, kAXSubroleAttribute)
        // Cheap checks first: the layer lookup below may list every window (focus on a sheet/panel lands here).
        guard subrole == kAXStandardWindowSubrole else { return false }
        guard let frame = AXAccess.frame(of: element),
              WindowEligibility.isStandardWindow(role: role, subrole: subrole, size: frame.size,
                                                 layer: context.allWindows[id]?.layer)
        else { return false }

        let window = TrackedWindow(
            id: id,
            pid: app.pid,
            bundleID: app.bundleID,
            appName: app.name,
            title: AXAccess.string(element, kAXTitleAttribute) ?? "",
            frame: frame,
            isMinimized: AXAccess.bool(element, kAXMinimizedAttribute) ?? false,
            isFullscreen: AXAccess.bool(element, AXAccess.fullScreenAttribute) ?? false,
            isAppHidden: app.isHidden,
            isOnScreen: context.onScreen.contains(id),
            isFocused: false,
            firstSeen: Date()
        )
        windows[id] = window
        elements[id] = element
        app.ignoredWindowIDs.remove(id)
        app.observer?.watch(element, id: id)
        delegate?.tracker(self, didAdd: window)
        return true
    }

    private func removeWindow(_ id: CGWindowID) {
        guard let window = windows.removeValue(forKey: id) else { return }
        elements[id] = nil
        apps[window.pid]?.observer?.unwatch(id)
        if focusedWindowID == id {
            focusedWindowID = nil
            requestFocusUpdate(force: false)
        }
        delegate?.tracker(self, didRemove: id)
    }

    /// Re-reads a tracked window's AX state and reports what changed.
    private func refreshWindow(_ id: CGWindowID, element: AXUIElement? = nil, isOnScreen: Bool? = nil) {
        guard var window = windows[id], let element = element ?? elements[id] else { return }
        var changes: WindowChange = []
        if let title = AXAccess.string(element, kAXTitleAttribute), title != window.title {
            window.title = title
            changes.insert(.title)
        }
        if let frame = AXAccess.frame(of: element), frame != window.frame {
            window.frame = frame
            changes.insert(.frame)
        }
        if let minimized = AXAccess.bool(element, kAXMinimizedAttribute), minimized != window.isMinimized {
            window.isMinimized = minimized
            changes.insert(.visibility)
        }
        if let fullscreen = AXAccess.bool(element, AXAccess.fullScreenAttribute), fullscreen != window.isFullscreen {
            window.isFullscreen = fullscreen
            changes.insert(.visibility)
        }
        if let isOnScreen, isOnScreen != window.isOnScreen {
            window.isOnScreen = isOnScreen
            changes.insert(.visibility)
        }
        commit(window, changes)
    }

    private func commit(_ window: TrackedWindow, _ changes: WindowChange) {
        guard !changes.isEmpty, windows[window.id] != nil else { return }
        windows[window.id] = window
        delegate?.tracker(self, didUpdate: window, changes: changes)
    }

    /// Recomputes `isOnScreen` for every tracked window from one CGWindowList call.
    private func syncOnScreenFlags() {
        guard !windows.isEmpty else { return }
        let onScreen = WindowServer.onScreenWindowIDs()
        for (id, window) in windows where window.isOnScreen != onScreen.contains(id) {
            var updated = window
            var changes: WindowChange = .visibility
            updated.isOnScreen.toggle()
            // Moves while on another Space or hidden may have gone unreported; take the current frame on return.
            if updated.isOnScreen, let element = elements[id], let frame = AXAccess.frame(of: element),
               frame != window.frame {
                updated.frame = frame
                changes.insert(.frame)
            }
            commit(updated, changes)
        }
    }

    // MARK: - Reconcile

    /// Low-frequency safety net. Cheap when nothing changed: one CGWindowList call and a dictionary comparison.
    private func reconcile() {
        guard isRunning else { return }
        reconcileTick &+= 1
        let checkExistence = reconcileTick % Self.existenceCheckEvery == 0
        let onScreenWindows = WindowServer.onScreenWindows()
        var bounds: [CGWindowID: CGRect] = [:]
        bounds.reserveCapacity(onScreenWindows.count)
        for info in onScreenWindows {
            bounds[info.id] = info.bounds
        }
        guard checkExistence || bounds != lastOnScreenBounds else { return }
        let previous = lastOnScreenBounds
        lastOnScreenBounds = bounds

        let now = Date()
        var appsToRescan = Set<pid_t>()
        for info in onScreenWindows {
            if let window = windows[info.id] {
                // Only windows whose server-side bounds changed since the last pass and disagree with ours are
                // re-read, so a window whose AX and CG frames never quite match is not re-read every tick.
                let movedSilently = previous[info.id] != info.bounds && !Self.roughlyEqual(info.bounds, window.frame)
                if !window.isOnScreen || movedSilently {
                    refreshWindow(info.id, isOnScreen: true)
                }
            } else if let app = apps[info.pid], app.canRescan(at: now), !app.ignoredWindowIDs.contains(info.id) {
                appsToRescan.insert(info.pid)
            }
        }

        // Tracked windows that just left the screen (or all off-screen ones, now and then): minimized, hidden and
        // other-Space windows still exist; the rest were closed without a destroyed notification reaching us.
        let offScreen = windows.values
            .filter { bounds[$0.id] == nil && (checkExistence || $0.isOnScreen) }
            .map(\.id)
        if !offScreen.isEmpty, let alive = WindowServer.existingWindowIDs(among: offScreen) {
            for id in offScreen {
                if !alive.contains(id) {
                    removeWindow(id)
                } else if var window = windows[id], window.isOnScreen {
                    window.isOnScreen = false
                    commit(window, .visibility)
                }
            }
        }

        for app in apps.values {
            app.ignoredWindowIDs.formIntersection(bounds.keys)
        }
        if !appsToRescan.isEmpty {
            let context = ScanContext(onScreenWindows: onScreenWindows)
            for pid in appsToRescan {
                if let app = apps[pid] {
                    rescanApp(app, context: context)
                }
            }
        }
    }

    // MARK: - Focus

    /// Coalesces focus updates to the next main-queue turn: activation arrives through both NSWorkspace and AX.
    private func requestFocusUpdate(force: Bool) {
        if force {
            focusUpdateForced = true
        }
        guard !focusUpdateScheduled else { return }
        focusUpdateScheduled = true
        after(0) { tracker in
            tracker.focusUpdateScheduled = false
            let forced = tracker.focusUpdateForced
            tracker.focusUpdateForced = false
            tracker.updateFocus(force: forced)
        }
    }

    /// `force`: report even if the focused window is unchanged. Activation re-raises the app's windows above our
    /// overlays, so the overlay controller must re-order them every time.
    private func updateFocus(force: Bool) {
        guard isRunning else { return }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var newID: CGWindowID?
        if let frontPID, let app = apps[frontPID], !app.isSettingUp {
            newID = focusedWindow(of: app)
        }
        let changed = newID != focusedWindowID
        if changed {
            if let oldID = focusedWindowID, var window = windows[oldID] {
                window.isFocused = false
                windows[oldID] = window
            }
            if let newID, var window = windows[newID] {
                window.isFocused = true
                windows[newID] = window
            }
            focusedWindowID = newID
        }
        // Switching native tabs focuses a window that was off screen a moment ago.
        if let newID, let window = windows[newID], !window.isOnScreen, !window.isMinimized {
            syncOnScreenFlags()
            scheduleOnScreenCheck()
        }
        if changed || force {
            delegate?.tracker(self, didChangeFocusTo: newID, frontmostPID: frontPID)
        }
    }

    /// The app's focused window, or its main window when a sheet/panel/dialog has focus.
    private func focusedWindow(of app: TrackedApp) -> CGWindowID? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            guard let element = AXAccess.element(app.element, attribute) else { continue }
            if let id = trackedWindowID(of: element, pid: app.pid) { return id }
            // Focus can be reported before the window's kAXWindowCreated reaches us.
            let context = ScanContext()
            if let id = resolveWindowID(of: element, app: app, context: context, claimed: []),
               addWindow(element, id: id, app: app, context: context) {
                return id
            }
        }
        return nil
    }

    // MARK: - Scheduling

    /// Merges rescan requests arriving in a burst into one pass. `pid` nil means every app.
    private func scheduleRescan(_ pid: pid_t?) {
        if let pid {
            pendingRescanPIDs.insert(pid)
        } else {
            pendingRescanAll = true
        }
        guard !rescanScheduled else { return }
        rescanScheduled = true
        after(Self.rescanCoalesceDelay) { tracker in tracker.flushRescans() }
    }

    private func rescanLater(_ pid: pid_t?, delay: TimeInterval) {
        after(delay) { tracker in tracker.scheduleRescan(pid) }
    }

    private func flushRescans() {
        rescanScheduled = false
        let pids = pendingRescanPIDs
        let all = pendingRescanAll
        pendingRescanPIDs.removeAll()
        pendingRescanAll = false
        if all {
            rescanAll()
            return
        }
        let context = ScanContext()
        for pid in pids {
            if let app = apps[pid] {
                rescanApp(app, context: context)
            }
        }
    }

    /// Re-checks `isOnScreen` for all windows shortly; requests while one is pending add a single follow-up check.
    private func scheduleOnScreenCheck() {
        if onScreenCheckScheduled {
            onScreenCheckRequestedAgain = true
            return
        }
        onScreenCheckScheduled = true
        after(Self.onScreenSettleDelay) { tracker in
            tracker.onScreenCheckScheduled = false
            tracker.syncOnScreenFlags()
            if tracker.onScreenCheckRequestedAgain {
                tracker.onScreenCheckRequestedAgain = false
                tracker.scheduleOnScreenCheck()
            }
        }
    }

    /// Runs `work` on the main queue after `delay`, unless the tracker was stopped (or restarted) meanwhile.
    private func after(_ delay: TimeInterval, _ work: @escaping @MainActor @Sendable (WindowTracker) -> Void) {
        let scheduledGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, self.generation == scheduledGeneration else { return }
                work(self)
            }
        }
    }

    // MARK: - Notifications

    private func observeNotifications() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { tracker, note in
            tracker.appLaunched(note)
        }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { tracker, note in
            tracker.appTerminated(note)
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { tracker, note in
            tracker.appActivated(note)
        }
        observe(workspace, NSWorkspace.didHideApplicationNotification) { tracker, note in
            tracker.appHiddenChanged(note, hidden: true)
        }
        observe(workspace, NSWorkspace.didUnhideApplicationNotification) { tracker, note in
            tracker.appHiddenChanged(note, hidden: false)
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { tracker, _ in
            tracker.activeSpaceChanged()
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { tracker, _ in
            tracker.screenParametersChanged()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor @Sendable (WindowTracker, Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                handler(self, note)
            }
        }
        notificationTokens.append((center: center, token: token))
    }

    private func runningApp(in note: Notification) -> NSRunningApplication? {
        note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    private func appLaunched(_ note: Notification) {
        guard let running = runningApp(in: note), isTrackable(running) else { return }
        setUpApp(running, context: nil)
        rescanLater(running.processIdentifier, delay: Self.postLaunchRescanDelay)
    }

    private func appTerminated(_ note: Notification) {
        guard let running = runningApp(in: note) else { return }
        removeApp(running.processIdentifier)
    }

    private func appActivated(_ note: Notification) {
        // Apps that switch to .regular after launch are only noticed once they come to the front.
        if let running = runningApp(in: note), isTrackable(running), apps[running.processIdentifier] == nil {
            setUpApp(running, context: nil)
        }
        requestFocusUpdate(force: true)
    }

    private func appHiddenChanged(_ note: Notification, hidden: Bool) {
        guard let running = runningApp(in: note) else { return }
        setAppHidden(running.processIdentifier, hidden: hidden)
    }

    /// Windows of the old Space leave the on-screen list, those of the new one join it, and AX starts listing windows
    /// it did not list before (and fullscreen state may have flipped), so re-enumerate as well.
    private func activeSpaceChanged() {
        syncOnScreenFlags()
        scheduleRescan(nil)
        scheduleOnScreenCheck()
        requestFocusUpdate(force: true)
    }

    private func screenParametersChanged() {
        scheduleRescan(nil)
        scheduleOnScreenCheck()
    }

    // MARK: - AX events

    private func windowCreated(_ element: AXUIElement, pid: pid_t) {
        guard let app = apps[pid], !app.isSettingUp else { return }
        let context = ScanContext()
        if let id = resolveWindowID(of: element, app: app, context: context, claimed: []),
           addWindow(element, id: id, app: app, context: context) {
            // A brand-new window usually reaches the on-screen list only once it has been ordered in.
            scheduleOnScreenCheck()
            return
        }
        // Role, subrole, size or the window ID are often filled in just after creation; look again shortly.
        rescanLater(pid, delay: Self.onScreenSettleDelay)
    }

    /// Frame changes are reported synchronously (no debounce): the overlay follows them live.
    private func frameChanged(_ id: CGWindowID, element: AXUIElement, resized: Bool) {
        guard var window = windows[id], let frame = AXAccess.frame(of: element) else { return }
        var changes: WindowChange = []
        if frame != window.frame {
            window.frame = frame
            changes.insert(.frame)
        }
        // Entering or leaving fullscreen arrives as a resize.
        if resized, let fullscreen = AXAccess.bool(element, AXAccess.fullScreenAttribute),
           fullscreen != window.isFullscreen {
            window.isFullscreen = fullscreen
            changes.insert(.visibility)
        }
        commit(window, changes)
    }

    private func setMinimized(_ id: CGWindowID, _ minimized: Bool) {
        guard var window = windows[id] else { return }
        var changes: WindowChange = []
        if window.isMinimized != minimized {
            window.isMinimized = minimized
            changes.insert(.visibility)
        }
        if minimized {
            if window.isOnScreen {
                window.isOnScreen = false
                changes.insert(.visibility)
            }
        } else {
            // Deminimizing brings the window back on the current Space; the check below confirms it.
            if !window.isOnScreen {
                window.isOnScreen = true
                changes.insert(.visibility)
            }
            if let element = elements[id], let frame = AXAccess.frame(of: element), frame != window.frame {
                window.frame = frame
                changes.insert(.frame)
            }
        }
        commit(window, changes)
        scheduleOnScreenCheck()
    }

    private func titleChanged(_ id: CGWindowID, element: AXUIElement) {
        guard var window = windows[id], let title = AXAccess.string(element, kAXTitleAttribute),
              title != window.title
        else { return }
        window.title = title
        commit(window, .title)
    }

    private static func roughlyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

extension WindowTracker: AppObserverDelegate {
    func appObserver(_ observer: AppObserver, didReceive notification: String, element: AXUIElement,
                     windowID: CGWindowID?) {
        guard isRunning else { return }
        let pid = observer.pid
        switch notification {
        case kAXWindowCreatedNotification:
            windowCreated(element, pid: pid)
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            requestFocusUpdate(force: false)
        case kAXApplicationActivatedNotification:
            requestFocusUpdate(force: true)
        case kAXApplicationHiddenNotification:
            setAppHidden(pid, hidden: true)
        case kAXApplicationShownNotification:
            setAppHidden(pid, hidden: false)
        default:
            guard let windowID else { return }
            switch notification {
            case kAXUIElementDestroyedNotification:
                removeWindow(windowID)
            case kAXMovedNotification:
                frameChanged(windowID, element: element, resized: false)
            case kAXResizedNotification:
                frameChanged(windowID, element: element, resized: true)
            case kAXWindowMiniaturizedNotification:
                setMinimized(windowID, true)
            case kAXWindowDeminiaturizedNotification:
                setMinimized(windowID, false)
            case kAXTitleChangedNotification:
                titleChanged(windowID, element: element)
            default:
                break
            }
        }
    }
}

/// Per-process state, kept even while the AXObserver is not ready so rescans and termination still work.
@MainActor
private final class TrackedApp {
    let running: NSRunningApplication
    let pid: pid_t
    let element: AXUIElement
    let bundleID: String?
    let name: String
    var observer: AppObserver?
    var isHidden: Bool
    /// Observer setup retries are pending: the app does not answer AX yet, so other AX calls would just time out.
    var isSettingUp = false
    var observerAttempts = 0
    /// On-screen window IDs with no standard AX window behind them; they must not trigger rescans while on screen.
    var ignoredWindowIDs = Set<CGWindowID>()
    /// The same app with a short messaging timeout, for Mission Control's per-app Space query: a slow app may cost
    /// the main thread 0.1 s there, not 0.5 s (a timeout falls back to the window's on-screen flags).
    lazy var quickElement: AXUIElement = {
        let quick = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(quick, AXAccess.quickMessagingTimeout)
        return quick
    }()
    private var rescanFailures = 0
    private var rescanBlockedUntil = Date.distantPast

    init(running: NSRunningApplication) {
        let pid = running.processIdentifier
        self.running = running
        self.pid = pid
        element = AXUIElementCreateApplication(pid)
        bundleID = running.bundleIdentifier
        name = running.localizedName ?? running.bundleIdentifier ?? "Process \(pid)"
        isHidden = running.isHidden
        AXAccess.setMessagingTimeout(element)
    }

    func canRescan(at now: Date) -> Bool {
        !isSettingUp && now >= rescanBlockedUntil
    }

    /// An app that stops answering AX is not re-enumerated on every reconcile tick (each try costs a full messaging
    /// timeout on the main thread); back off 4, 8, ... up to 60 s.
    func noteRescanFailure() {
        rescanFailures += 1
        let delay = min(60, 2 * Double(1 << min(rescanFailures, 5)))
        rescanBlockedUntil = Date().addingTimeInterval(delay)
    }

    func noteRescanSuccess() {
        rescanFailures = 0
        rescanBlockedUntil = .distantPast
    }
}

/// Window server state for one scan pass, fetched lazily and at most once per pass.
private final class ScanContext {
    lazy var onScreenWindows: [WindowServer.WindowInfo] = WindowServer.onScreenWindows()
    lazy var onScreen: Set<CGWindowID> = Set(onScreenWindows.map(\.id))
    /// Every window on every Space, for layers and the bounds-matching fallback of window ID resolution.
    lazy var allWindows: [CGWindowID: WindowServer.WindowInfo] = WindowServer.allWindowsByID()

    init() {}

    init(onScreenWindows: [WindowServer.WindowInfo]) {
        self.onScreenWindows = onScreenWindows
    }
}
