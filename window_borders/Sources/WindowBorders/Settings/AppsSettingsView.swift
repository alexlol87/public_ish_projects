import AppKit
import BorderCore
import SwiftUI

/// Which apps get borders, and apps pinned to one color.
@MainActor
struct AppsSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Draw borders for", selection: $settings.appFilter.mode) {
                    Text("All apps").tag(AppFilterMode.all)
                    Text("Only selected apps").tag(AppFilterMode.allowlist)
                    Text("All apps except selected").tag(AppFilterMode.blocklist)
                }
                Text(modeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Selected apps") {
                if settings.appFilter.bundleIDs.isEmpty {
                    Text("No apps selected.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.appFilter.bundleIDs, id: \.self) { bundleID in
                    HStack {
                        AppRowLabel(bundleID: bundleID)
                        Spacer()
                        Button {
                            settings.appFilter.bundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from the list")
                    }
                }
                Menu("Add Running App") {
                    let candidates = AppCatalog.runningApps()
                        .filter { !settings.appFilter.bundleIDs.contains($0.bundleID) }
                    if candidates.isEmpty {
                        Text("Every running app is already listed")
                    }
                    ForEach(candidates, id: \.bundleID) { app in
                        Button(app.name) {
                            settings.appFilter.bundleIDs.append(app.bundleID)
                        }
                    }
                }
                .fixedSize()
            }

            Section {
                if settings.appColorOverrides.isEmpty {
                    Text("No pinned apps. Every window gets its own color.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.appColorOverrides.keys.sorted(), id: \.self) { bundleID in
                    HStack {
                        AppRowLabel(bundleID: bundleID)
                        Spacer()
                        if let color = settings.appColorOverrides[bundleID] {
                            ColorSwatch(color: color)
                        }
                        Picker("Color", selection: overrideBinding(for: bundleID)) {
                            ForEach(colorChoices(for: bundleID), id: \.self) { color in
                                Text(Palette.name(for: color)).tag(color)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        Button {
                            settings.appColorOverrides[bundleID] = nil
                        } label: {
                            Image(systemName: "pin.slash")
                        }
                        .buttonStyle(.borderless)
                        .help("Unpin: windows of this app get their own colors again")
                    }
                }
                Menu("Pin a Running App") {
                    let candidates = AppCatalog.runningApps()
                        .filter { settings.appColorOverrides[$0.bundleID] == nil }
                    if candidates.isEmpty {
                        Text("Every running app is already pinned")
                    }
                    ForEach(candidates, id: \.bundleID) { app in
                        Button(app.name) {
                            pin(app.bundleID)
                        }
                    }
                }
                .fixedSize()
            } header: {
                Text("Pinned colors")
            } footer: {
                Text("Every window of a pinned app uses that color. You can also pin the focused window's app from "
                     + "the menu bar icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var modeExplanation: String {
        switch settings.appFilter.mode {
        case .all:
            return "Every app's windows get a border. The list below is kept but not used."
        case .allowlist:
            return "Only windows of the apps listed below get a border."
        case .blocklist:
            return "Every app's windows get a border, except the apps listed below."
        }
    }

    /// Pins to the palette color fewest other apps are pinned to, so pins stay distinguishable.
    private func pin(_ bundleID: String) {
        settings.appColorOverrides[bundleID] = BorderCore.ColorPicker.leastUsed(
            palette: settings.palette, inUse: Array(settings.appColorOverrides.values))
    }

    /// The palette, plus the pinned color itself if it is no longer in the palette (otherwise the picker would have
    /// no matching entry to show).
    private func colorChoices(for bundleID: String) -> [RGBAColor] {
        var choices = settings.palette
        var seen = Set<RGBAColor>()
        choices = choices.filter { seen.insert($0).inserted }
        if let current = settings.appColorOverrides[bundleID], !seen.contains(current) {
            choices.append(current)
        }
        return choices
    }

    private func overrideBinding(for bundleID: String) -> Binding<RGBAColor> {
        Binding(
            get: { settings.appColorOverrides[bundleID] ?? settings.palette[0] },
            set: { settings.appColorOverrides[bundleID] = $0 }
        )
    }
}
