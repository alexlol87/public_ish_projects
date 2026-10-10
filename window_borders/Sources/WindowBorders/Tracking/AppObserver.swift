import ApplicationServices
import CoreGraphics

@MainActor
protocol AppObserverDelegate: AnyObject {
    /// `windowID` is set for per-window registrations (moved, resized, destroyed, ...) and nil for app-level ones,
    /// where `element` is the window the notification is about (created, focused) or the app itself.
    func appObserver(_ observer: AppObserver, didReceive notification: String, element: AXUIElement,
                     windowID: CGWindowID?)
}

/// One AXObserver per tracked app. App-level notifications are registered once in `start()`; per-window ones with
/// `watch(_:id:)` for each tracked window, carrying the window ID packed into the refcon so the callback knows which
/// window moved without another AX round trip (a destroyed element can no longer be asked for its ID).
@MainActor
final class AppObserver {
    static let appNotifications: [String] = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
        kAXApplicationActivatedNotification,
    ]
    static let windowNotifications: [String] = [
        kAXUIElementDestroyedNotification,
        kAXMovedNotification,
        kAXResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXTitleChangedNotification,
    ]

    /// Started observers by AXObserver identity. The C callback cannot capture context, and the app-level refcon is
    /// nil, so the callback finds its owner here. Entries are removed in `stop()` together with the run loop source,
    /// after which no further callbacks can arrive.
    private static var started: [ObjectIdentifier: WeakAppObserver] = [:]

    let pid: pid_t
    let appElement: AXUIElement
    weak var delegate: AppObserverDelegate?
    private let observer: AXObserver
    private var isStarted = false
    private var watchedWindows: [CGWindowID: AXUIElement] = [:]

    init?(pid: pid_t, appElement: AXUIElement, delegate: AppObserverDelegate) {
        var created: AXObserver?
        guard AXObserverCreate(pid, appObserverCallback, &created) == .success, let created else { return nil }
        self.pid = pid
        self.appElement = appElement
        self.observer = created
        self.delegate = delegate
    }

    /// Attaches to the main run loop and registers the app-level notifications. Returns false when the app did not
    /// accept them (typically still launching), so the caller can retry with a fresh observer later.
    func start() -> Bool {
        guard !isStarted else { return true }
        isStarted = true
        Self.started[ObjectIdentifier(observer)] = WeakAppObserver(self)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        var registeredAny = false
        for name in Self.appNotifications {
            switch AXObserverAddNotification(observer, appElement, name as CFString, nil) {
            case .success, .notificationAlreadyRegistered:
                registeredAny = true
            case .cannotComplete:
                // Not answering: each further call would wait for the full messaging timeout.
                return false
            default:
                continue
            }
        }
        return registeredAny
    }

    /// Detaches from the run loop. Registrations are not removed one by one (that is an IPC round trip each, and the
    /// app may be gone); they die with the AXObserver, and without the run loop source nothing is delivered anyway.
    func stop() {
        guard isStarted else { return }
        isStarted = false
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        Self.started[ObjectIdentifier(observer)] = nil
        watchedWindows.removeAll()
    }

    func watch(_ window: AXUIElement, id: CGWindowID) {
        // bitPattern 0 would be nil, but 0 is never a valid window ID.
        guard isStarted, watchedWindows[id] == nil, let refcon = UnsafeMutableRawPointer(bitPattern: UInt(id)) else {
            return
        }
        watchedWindows[id] = window
        for name in Self.windowNotifications {
            if AXObserverAddNotification(observer, window, name as CFString, refcon) == .cannotComplete {
                // The app was busy (common right after launch). Forget the window so the next rescan, which calls
                // watch again for known windows, retries instead of leaving it without notifications for good.
                watchedWindows[id] = nil
                break
            }
        }
    }

    func unwatch(_ id: CGWindowID) {
        guard let window = watchedWindows.removeValue(forKey: id) else { return }
        for name in Self.windowNotifications {
            _ = AXObserverRemoveNotification(observer, window, name as CFString)
        }
    }

    fileprivate static func route(_ observer: AXObserver, element: AXUIElement, notification: String,
                                  refcon: UnsafeMutableRawPointer?) {
        guard let target = started[ObjectIdentifier(observer)]?.object else { return }
        let windowID = refcon.map { CGWindowID(truncatingIfNeeded: UInt(bitPattern: $0)) }
        target.delegate?.appObserver(target, didReceive: notification, element: element, windowID: windowID)
    }
}

private final class WeakAppObserver {
    weak var object: AppObserver?

    init(_ object: AppObserver) {
        self.object = object
    }
}

/// AXObserver callback. Runs on the main thread because the observer's source is on the main run loop.
private func appObserverCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                                 _ refcon: UnsafeMutableRawPointer?) {
    MainActor.assumeIsolated {
        AppObserver.route(observer, element: element, notification: notification as String, refcon: refcon)
    }
}
