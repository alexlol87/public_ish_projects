#if canImport(AppKit)
import AppKit
import ConstellationCore
import SwiftUI

/// Settings (theme, staleness threshold) in UserDefaults; views observe it so changes apply without a restart. Uncompiled on Linux.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    @Published var theme: ThemeChoice { didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme"); applyAppearance() } }
    @Published var thresholdDays: Int { didSet { UserDefaults.standard.set(thresholdDays, forKey: "stalenessDays") } }

    init() {
        theme = UserDefaults.standard.string(forKey: "theme").flatMap(ThemeChoice.init(rawValue:)) ?? .system
        let d = UserDefaults.standard.integer(forKey: "stalenessDays")
        thresholdDays = d > 0 ? d : Staleness.defaultThreshold
    }

    var palette: Palette {
        theme.palette(systemIsDark: NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    /// Window chrome follows the theme's light/dark; System clears the override.
    func applyAppearance() {
        NSApp?.appearance = theme == .system ? nil : NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        objectWillChange.send()
    }
}

extension NSColor {
    convenience init(hex: String) {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}
extension Color { init(hex: String) { self.init(nsColor: NSColor(hex: hex)) } }

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    var body: some View {
        Form {
            Picker("Theme", selection: $settings.theme) { ForEach(ThemeChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Stepper("Stale after \(settings.thresholdDays) days", value: $settings.thresholdDays, in: 1...3650)
        }.padding(20).frame(width: 340)
    }
}
#endif
