import AppKit
import SwiftUI

/// Owns the settings window. The window is created once and kept (hidden) after closing, so reopening is instant and
/// keeps the selected tab.
@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private var window: NSWindow?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // An accessory (menu bar) app is never active on its own; without activating, the window would open behind
        // the frontmost app and not take keyboard focus.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Window Borders Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        // We keep a strong reference and reuse the window; AppKit must not also release it on close.
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
