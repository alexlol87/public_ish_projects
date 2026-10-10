import AppKit
import Combine

/// Thin NSApplicationDelegate: builds the coordinator once AppKit has finished launching and forwards lifecycle
/// events to it. Kept free of stored state with non-trivial initializers so NSObject's inherited `init()` is enough.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// NSApplication.delegate is weak; main.swift stores the delegate here so it lives as long as the app.
    static var shared: AppDelegate?

    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.launch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }

    /// Opening the app again (Finder, Spotlight) while it runs shows the settings: there is no Dock icon to click.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.showSettings()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// An accessory app never shows its menu bar, but key equivalents still go through the main menu. Without these
    /// items the settings and onboarding windows would have no copy/paste in text fields and no ⌘W.
    private static func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Window Borders", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let mainMenu = NSMenu()
        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }
}

/// Composition root: owns every long-lived object and wires them together.
@MainActor
final class AppCoordinator {
    private let settings: SettingsStore
    private let tracker: WindowTracker
    private let overlayController: BorderOverlayController
    private let menuBar: MenuBarController
    private let settingsWindow: SettingsWindowController
    private let onboarding: OnboardingWindowController
    private let hotKeys: HotKeyManager

    /// Polls Accessibility trust once a second, only while the onboarding window is open: there is no notification
    /// for the grant, and polling forever would waste wakeups.
    private var trustTimer: Timer?
    private var isTracking = false
    private var hotKeyObservation: AnyCancellable?

    init() {
        settings = SettingsStore()
        tracker = WindowTracker()
        overlayController = BorderOverlayController(tracker: tracker, settings: settings)
        menuBar = MenuBarController(settings: settings, overlayController: overlayController)
        settingsWindow = SettingsWindowController(settings: settings)
        onboarding = OnboardingWindowController()
        hotKeys = HotKeyManager()
    }

    func launch() {
        menuBar.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        menuBar.onOpenOnboarding = { [weak self] in
            self?.showOnboarding()
        }
        menuBar.onMenuWillOpen = { [weak self] in
            self?.startTrackingIfNewlyTrusted()
        }
        onboarding.onClose = { [weak self] in
            self?.stopWaitingForTrust()
        }
        hotKeys.onPress = { [weak self] in
            self?.overlayController.cycleColorOfFocusedWindow()
        }
        // Emits the current value right away, so this also does the initial registration.
        hotKeyObservation = settings.$hotKeyEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self else { return }
                if isEnabled {
                    self.hotKeys.register()
                } else {
                    self.hotKeys.unregister()
                }
            }

        if Permissions.isAccessibilityTrusted {
            startTracking()
        } else {
            showOnboarding()
        }
    }

    func shutdown() {
        overlayController.persistColorMemory()
        hotKeys.unregister()
    }

    func showSettings() {
        settingsWindow.show()
    }

    private func showOnboarding() {
        onboarding.show()
        startWaitingForTrust()
    }

    /// Access granted while the onboarding window was closed (so nobody was polling): start now.
    private func startTrackingIfNewlyTrusted() {
        guard !isTracking, Permissions.isAccessibilityTrusted else { return }
        stopWaitingForTrust()
        onboarding.close()
        startTracking()
    }

    private func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        tracker.start()
        overlayController.start()
    }

    // MARK: - Waiting for Accessibility trust

    private func startWaitingForTrust() {
        guard trustTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.checkTrust()
            }
        }
        timer.tolerance = 0.25
        trustTimer = timer
    }

    private func stopWaitingForTrust() {
        trustTimer?.invalidate()
        trustTimer = nil
    }

    private func checkTrust() {
        guard Permissions.isAccessibilityTrusted else { return }
        stopWaitingForTrust()
        onboarding.showGranted()
        startTracking()
    }
}
