import AppKit
import BorderCore
import Combine

/// The menu bar icon and its menu. The menu is rebuilt each time it opens (`menuNeedsUpdate`), so it always shows
/// the current focused window and settings without observing anything. Opening a status item menu does not change
/// the frontmost app, so "focused window" still means the user's window, not ours.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    /// Set by the app delegate: open the settings window / the Accessibility onboarding.
    var onOpenSettings: (() -> Void)?
    var onOpenOnboarding: (() -> Void)?
    /// Called right before the menu is built, e.g. to notice an Accessibility grant made while onboarding was closed.
    var onMenuWillOpen: (() -> Void)?

    private let settings: SettingsStore
    private let overlayController: BorderOverlayController
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private var enabledObservation: AnyCancellable?

    /// What a "Pin" item pins, captured when the menu was built.
    private struct PinTarget {
        let bundleID: String
        let color: RGBAColor
    }

    init(settings: SettingsStore, overlayController: BorderOverlayController) {
        self.settings = settings
        self.overlayController = overlayController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        super.init()

        // Items are enabled/disabled explicitly below; auto-enabling would re-enable the informational ones.
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "square.dashed", accessibilityDescription: "Window Borders")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Window Borders"
        }
        // Dim the icon while borders are off, so the state is visible without opening the menu.
        enabledObservation = settings.$isEnabled.sink { [weak self] isEnabled in
            self?.statusItem.button?.appearsDisabled = !isEnabled
        }
    }

    // `nonisolated` + assumeIsolated works whether or not the SDK marks NSMenuDelegate @MainActor; AppKit always
    // calls it on the main thread.
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            onMenuWillOpen?()
            rebuildMenu()
        }
    }

    // MARK: - Building

    private func rebuildMenu() {
        menu.removeAllItems()

        let enabledItem = actionItem("Borders Enabled", #selector(toggleEnabled))
        enabledItem.state = settings.isEnabled ? .on : .off
        menu.addItem(enabledItem)
        menu.addItem(.separator())

        if Permissions.isAccessibilityTrusted {
            addFocusedWindowItems()
        } else {
            menu.addItem(infoItem("Accessibility access is off, so no borders are drawn"))
            menu.addItem(actionItem("Grant Accessibility Access…", #selector(grantAccessibility)))
        }
        menu.addItem(.separator())

        menu.addItem(actionItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(launchAtLoginItem())
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Window Borders", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func addFocusedWindowItems() {
        guard let summary = overlayController.focusedWindowSummary else {
            menu.addItem(infoItem("No focused window"))
            return
        }

        let header = infoItem(Self.describe(summary))
        header.image = Self.swatchImage(for: summary.color)
        menu.addItem(header)

        let pinnedColor = summary.bundleID.flatMap { settings.appColorOverrides[$0] }

        let recolor = actionItem("Recolor Focused Window", #selector(recolorFocusedWindow))
        if settings.hotKeyEnabled {
            // Informational: the real shortcut is the global hot key (HotKeyManager); this only shows it.
            recolor.keyEquivalent = "b"
            recolor.keyEquivalentModifierMask = [.control, .option, .command]
        }
        menu.addItem(recolor)

        let colorMenu = NSMenu()
        colorMenu.autoenablesItems = false
        for color in settings.palette {
            let item = actionItem(Palette.name(for: color), #selector(setFocusedWindowColor(_:)))
            item.image = Self.swatchImage(for: color)
            item.representedObject = color
            item.state = color == summary.color ? .on : .off
            colorMenu.addItem(item)
        }
        let colorItem = NSMenuItem(title: "Set Focused Window Color", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        guard let bundleID = summary.bundleID else { return }
        if let pinnedColor {
            let title = "Unpin \(summary.appName) (\(Palette.name(for: pinnedColor)))"
            let unpin = actionItem(title, #selector(unpinApp(_:)))
            unpin.representedObject = bundleID
            menu.addItem(unpin)
        } else {
            let pin = actionItem("Pin \(summary.appName) to This Color", #selector(pinApp(_:)))
            pin.image = Self.swatchImage(for: summary.color)
            pin.representedObject = PinTarget(bundleID: bundleID, color: summary.color)
            pin.toolTip = "Every window of \(summary.appName) gets this color"
            menu.addItem(pin)
        }
    }

    private func launchAtLoginItem() -> NSMenuItem {
        if LoginItem.requiresApproval {
            let item = actionItem("Launch at Login (Approve in System Settings)…", #selector(toggleLaunchAtLogin))
            item.state = .mixed
            return item
        }
        let item = actionItem("Launch at Login", #selector(toggleLaunchAtLogin))
        item.state = LoginItem.isEnabled ? .on : .off
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// "Safari — Apple", with long titles shortened so the menu stays a sensible width.
    private static func describe(_ summary: FocusedWindowSummary) -> String {
        let title = summary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return summary.appName }
        let limit = 50
        let shortTitle = title.count > limit ? String(title.prefix(limit - 1)) + "…" : title
        return "\(summary.appName) — \(shortTitle)"
    }

    /// A small rounded color chip, drawn with Core Graphics at 2x so it is sharp on Retina displays.
    private static func swatchImage(for color: RGBAColor) -> NSImage {
        let points: CGFloat = 12
        let scale: CGFloat = 2
        let pixels = Int(points * scale)
        let size = NSSize(width: points, height: points)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return NSImage(size: size) }

        let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels).insetBy(dx: scale / 2, dy: scale / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: 3 * scale, cornerHeight: 3 * scale, transform: nil)
        context.addPath(path)
        context.setFillColor(CGColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green),
                                     blue: CGFloat(color.blue), alpha: CGFloat(color.alpha)))
        context.fillPath()
        // A faint outline keeps light colors (yellow, white) visible on a light menu.
        context.addPath(path)
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.25))
        context.setLineWidth(scale)
        context.strokePath()

        guard let cgImage = context.makeImage() else { return NSImage(size: size) }
        return NSImage(cgImage: cgImage, size: size)
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
    }

    @objc private func grantAccessibility() {
        onOpenOnboarding?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func recolorFocusedWindow() {
        overlayController.cycleColorOfFocusedWindow()
    }

    @objc private func setFocusedWindowColor(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? RGBAColor else { return }
        overlayController.setColorOfFocusedWindow(color)
    }

    @objc private func pinApp(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? PinTarget else { return }
        settings.appColorOverrides[target.bundleID] = target.color
    }

    @objc private func unpinApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        settings.appColorOverrides[bundleID] = nil
    }

    @objc private func toggleLaunchAtLogin() {
        if LoginItem.requiresApproval {
            LoginItem.openSystemSettings()
            return
        }
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nLaunch at login works when Window Borders "
                + "runs from its app bundle, ideally in the Applications folder."
            NSApp.activate()
            _ = alert.runModal()
        }
    }
}
