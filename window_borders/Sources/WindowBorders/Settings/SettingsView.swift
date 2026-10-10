import AppKit
import BorderCore
import SwiftUI

// Note: BorderCore has its own `ColorPicker` enum, so SwiftUI's view is always written `SwiftUI.ColorPicker` here.

/// Root of the settings window: General / Palette / Apps tabs.
@MainActor
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            PaletteEditorView(settings: settings)
                .tabItem { Label("Palette", systemImage: "paintpalette") }
            AppsSettingsView(settings: settings)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
        }
        // A fixed size keeps the window from jumping when switching between tabs of different heights; the grouped
        // forms scroll if they need more room.
        .frame(width: 540, height: 600)
    }
}

/// Border look, behavior and startup options.
@MainActor
struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    /// SMAppService state is not observable, so it is mirrored here and refreshed on appear and after each change.
    @State private var launchAtLogin = false
    @State private var loginItemNeedsApproval = false
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Show window borders", isOn: $settings.isEnabled)
            }

            Section("Border") {
                LabeledContent("Width") {
                    HStack {
                        Slider(value: $settings.borderWidth, in: SettingsStore.borderWidthRange, step: 1)
                        Text("\(Int(settings.borderWidth)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Picker("Corners", selection: $settings.cornerRadiusMode) {
                    Text("Match windows").tag(CornerRadiusMode.auto)
                    Text("Custom").tag(CornerRadiusMode.custom)
                }
                .pickerStyle(.segmented)
                if settings.cornerRadiusMode == .custom {
                    LabeledContent("Corner radius") {
                        HStack {
                            Slider(value: $settings.customCornerRadius, in: SettingsStore.customCornerRadiusRange,
                                   step: 1)
                            Text("\(Int(settings.customCornerRadius)) pt")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }

            Section("Active window") {
                Toggle("Emphasize the active window", isOn: $settings.emphasizeActiveWindow)
                if settings.emphasizeActiveWindow {
                    LabeledContent("Other windows' opacity") {
                        HStack {
                            Slider(value: $settings.inactiveOpacity, in: SettingsStore.inactiveOpacityRange,
                                   step: 0.05)
                            Text("\(Int((settings.inactiveOpacity * 100).rounded())) %")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    LabeledContent("Extra width") {
                        HStack {
                            Slider(value: $settings.activeWidthBoost, in: SettingsStore.activeWidthBoostRange,
                                   step: 1)
                            Text("+\(Int(settings.activeWidthBoost)) pt")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }

            Section("Behavior") {
                Toggle("Show borders on full-screen windows", isOn: $settings.showInFullscreen)
                Toggle("Show borders in Mission Control and App Exposé", isOn: $settings.showInMissionControl)
                Toggle("Remember window colors across restarts", isOn: $settings.rememberColors)
                Toggle("⌃⌥⌘B recolors the focused window", isOn: $settings.hotKeyEnabled)
                Picker("Layering", selection: $settings.borderLayering) {
                    Text("Attached to each window").tag(BorderLayering.attached)
                    Text("Above all windows").tag(BorderLayering.floating)
                }
                Text("“Above all windows” is a fallback for when borders end up behind their window. The parts "
                     + "of a border under windows in front of it are cut out, so it never draws over them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if loginItemNeedsApproval {
                    HStack {
                        Text("Allow Window Borders in System Settings to finish turning this on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { LoginItem.openSystemSettings() }
                    }
                }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Restore All Defaults") { settings.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshLoginItem() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't change this: \(error.localizedDescription) It works when Window Borders runs "
                + "from its app bundle, ideally in /Applications."
        }
        refreshLoginItem()
    }

    private func refreshLoginItem() {
        // "Needs approval" counts as on: the app is registered and switching the toggle off must unregister it.
        launchAtLogin = LoginItem.isEnabled || LoginItem.requiresApproval
        loginItemNeedsApproval = LoginItem.requiresApproval
    }
}

// MARK: - Shared helpers for the settings tabs

extension RGBAColor {
    /// SwiftUI color for swatches and `SwiftUI.ColorPicker` bindings.
    var settingsSwatchColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Reads a color picked in SwiftUI back as sRGB components (the color panel may hand out other color spaces).
    static func fromSettingsColor(_ color: Color) -> RGBAColor? {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return RGBAColor(red: Double(srgb.redComponent), green: Double(srgb.greenComponent),
                         blue: Double(srgb.blueComponent), alpha: Double(srgb.alphaComponent))
    }
}

/// A rounded color chip.
struct ColorSwatch: View {
    let color: RGBAColor
    var size: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: size / 4)
            .fill(color.settingsSwatchColor)
            .overlay {
                RoundedRectangle(cornerRadius: size / 4)
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            }
            .frame(width: size, height: size)
    }
}

/// Names and icons for bundle IDs, from running apps first (cheap, and works for apps not in /Applications), then
/// Launch Services.
@MainActor
enum AppCatalog {
    struct Entry {
        let bundleID: String
        let name: String
        let icon: NSImage?
    }

    static func entry(for bundleID: String) -> Entry {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName {
            return Entry(bundleID: bundleID, name: name, icon: running.icon)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let path = url.path(percentEncoded: false)
            var name = FileManager.default.displayName(atPath: path)
            if name.hasSuffix(".app") {
                name = String(name.dropLast(4))
            }
            return Entry(bundleID: bundleID, name: name, icon: NSWorkspace.shared.icon(forFile: path))
        }
        return Entry(bundleID: bundleID, name: bundleID, icon: nil)
    }

    /// Regular (Dock) apps that are running now, by name, without Window Borders itself.
    static func runningApps() -> [Entry] {
        var seen = Set<String>()
        var entries: [Entry] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier,
                  seen.insert(bundleID).inserted
            else { continue }
            entries.append(Entry(bundleID: bundleID, name: app.localizedName ?? bundleID, icon: app.icon))
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// App icon + name + bundle ID, for list rows.
@MainActor
struct AppRowLabel: View {
    let bundleID: String

    var body: some View {
        let entry = AppCatalog.entry(for: bundleID)
        HStack(spacing: 8) {
            if let icon = entry.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app")
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
