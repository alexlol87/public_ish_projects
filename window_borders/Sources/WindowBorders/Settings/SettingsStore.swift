import BorderCore
import Combine
import Foundation

/// How the border's corner radius is chosen.
enum CornerRadiusMode: String, Codable, CaseIterable {
    /// Follow the system window corner radius for the running macOS version.
    case auto
    /// Use `SettingsStore.customCornerRadius` (for apps with unusual corners, or a squarer look).
    case custom
}

/// Where border overlays sit in the window stack.
enum BorderLayering: String, Codable, CaseIterable {
    /// Ordered right above each window, so other windows cover the border like they cover the window.
    case attached
    /// Fallback above every normal window, for setups where attached ordering misbehaves.
    case floating
}

/// Every user setting, persisted to UserDefaults the moment it changes so a crash or force-quit loses nothing.
/// Values are clamped on load and on assignment, so the overlay never has to defend against odd stored data.
@MainActor
final class SettingsStore: ObservableObject {
    static let borderWidthRange: ClosedRange<Double> = 1...20
    static let customCornerRadiusRange: ClosedRange<Double> = 0...40
    static let inactiveOpacityRange: ClosedRange<Double> = 0.1...1
    static let activeWidthBoostRange: ClosedRange<Double> = 0...10

    /// UserDefaults keys, prefixed so they never collide with keys AppKit writes into the same domain.
    private enum Key {
        static let isEnabled = "wb.isEnabled"
        static let borderWidth = "wb.borderWidth"
        static let cornerRadiusMode = "wb.cornerRadiusMode"
        static let customCornerRadius = "wb.customCornerRadius"
        static let palette = "wb.palette"
        static let emphasizeActiveWindow = "wb.emphasizeActiveWindow"
        static let inactiveOpacity = "wb.inactiveOpacity"
        static let activeWidthBoost = "wb.activeWidthBoost"
        static let showInFullscreen = "wb.showInFullscreen"
        static let showInMissionControl = "wb.showInMissionControl"
        static let borderLayering = "wb.borderLayering"
        static let appFilter = "wb.appFilter"
        static let appColorOverrides = "wb.appColorOverrides"
        static let rememberColors = "wb.rememberColors"
        static let hotKeyEnabled = "wb.hotKeyEnabled"
        static let colorMemory = "wb.colorMemory"
    }

    private enum Default {
        static let isEnabled = true
        static let borderWidth: Double = 4
        static let cornerRadiusMode = CornerRadiusMode.auto
        static let customCornerRadius: Double = 10
        static let emphasizeActiveWindow = false
        static let inactiveOpacity = 0.6
        static let activeWidthBoost: Double = 2
        static let showInFullscreen = false
        static let showInMissionControl = true
        static let borderLayering = BorderLayering.attached
        static let rememberColors = true
        static let hotKeyEnabled = true
    }

    private let defaults: UserDefaults
    private var storedColorMemory: ColorMemory

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    @Published var borderWidth: Double {
        didSet {
            let valid = Self.clamped(borderWidth, to: Self.borderWidthRange, fallback: Default.borderWidth)
            if valid != borderWidth { borderWidth = valid }
            defaults.set(borderWidth, forKey: Key.borderWidth)
        }
    }

    @Published var cornerRadiusMode: CornerRadiusMode {
        didSet { defaults.set(cornerRadiusMode.rawValue, forKey: Key.cornerRadiusMode) }
    }

    @Published var customCornerRadius: Double {
        didSet {
            let valid = Self.clamped(customCornerRadius, to: Self.customCornerRadiusRange,
                                     fallback: Default.customCornerRadius)
            if valid != customCornerRadius { customCornerRadius = valid }
            defaults.set(customCornerRadius, forKey: Key.customCornerRadius)
        }
    }

    /// Never empty: color assignment needs at least one color, so an empty list snaps back to the defaults.
    @Published var palette: [RGBAColor] {
        didSet {
            if palette.isEmpty { palette = Palette.defaultColors }
            save(palette, forKey: Key.palette)
        }
    }

    @Published var emphasizeActiveWindow: Bool {
        didSet { defaults.set(emphasizeActiveWindow, forKey: Key.emphasizeActiveWindow) }
    }

    @Published var inactiveOpacity: Double {
        didSet {
            let valid = Self.clamped(inactiveOpacity, to: Self.inactiveOpacityRange, fallback: Default.inactiveOpacity)
            if valid != inactiveOpacity { inactiveOpacity = valid }
            defaults.set(inactiveOpacity, forKey: Key.inactiveOpacity)
        }
    }

    @Published var activeWidthBoost: Double {
        didSet {
            let valid = Self.clamped(activeWidthBoost, to: Self.activeWidthBoostRange,
                                     fallback: Default.activeWidthBoost)
            if valid != activeWidthBoost { activeWidthBoost = valid }
            defaults.set(activeWidthBoost, forKey: Key.activeWidthBoost)
        }
    }

    @Published var showInFullscreen: Bool {
        didSet { defaults.set(showInFullscreen, forKey: Key.showInFullscreen) }
    }

    /// Borders around the window thumbnails in Mission Control and App Exposé.
    @Published var showInMissionControl: Bool {
        didSet { defaults.set(showInMissionControl, forKey: Key.showInMissionControl) }
    }

    @Published var borderLayering: BorderLayering {
        didSet { defaults.set(borderLayering.rawValue, forKey: Key.borderLayering) }
    }

    @Published var appFilter: AppFilter {
        didSet {
            // AppFilter promises unique IDs, but a direct `bundleIDs.append` bypasses its initializer.
            let unique = AppFilter(mode: appFilter.mode, bundleIDs: appFilter.bundleIDs)
            if unique != appFilter { appFilter = unique }
            save(appFilter, forKey: Key.appFilter)
        }
    }

    /// Bundle ID -> color every window of that app gets, instead of its assigned one.
    @Published var appColorOverrides: [String: RGBAColor] {
        didSet { save(appColorOverrides, forKey: Key.appColorOverrides) }
    }

    @Published var rememberColors: Bool {
        didSet { defaults.set(rememberColors, forKey: Key.rememberColors) }
    }

    /// ⌃⌥⌘B cycles the focused window's color.
    @Published var hotKeyEnabled: Bool {
        didSet { defaults.set(hotKeyEnabled, forKey: Key.hotKeyEnabled) }
    }

    /// Window colors remembered across restarts. Not @Published: it is app state the overlay writes, not a setting
    /// anyone needs to react to, and publishing it would rebuild every overlay on each write.
    var colorMemory: ColorMemory {
        get { storedColorMemory }
        set {
            storedColorMemory = newValue
            save(newValue, forKey: Key.colorMemory)
        }
    }

    /// Fires on the main run loop after any @Published setting changed (and was saved). `objectWillChange` fires
    /// before the new value is stored; hopping to the next run loop turn means subscribers read the new value.
    var changes: AnyPublisher<Void, Never> {
        objectWillChange
            .receive(on: RunLoop.main)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? Default.isEnabled
        borderWidth = SettingsStore.clamped(
            defaults.object(forKey: Key.borderWidth) as? Double ?? Default.borderWidth,
            to: SettingsStore.borderWidthRange, fallback: Default.borderWidth)
        cornerRadiusMode = defaults.string(forKey: Key.cornerRadiusMode).flatMap(CornerRadiusMode.init(rawValue:))
            ?? Default.cornerRadiusMode
        customCornerRadius = SettingsStore.clamped(
            defaults.object(forKey: Key.customCornerRadius) as? Double ?? Default.customCornerRadius,
            to: SettingsStore.customCornerRadiusRange, fallback: Default.customCornerRadius)
        let storedPalette = SettingsStore.load([RGBAColor].self, from: defaults, forKey: Key.palette) ?? []
        palette = storedPalette.isEmpty ? Palette.defaultColors : storedPalette
        emphasizeActiveWindow = defaults.object(forKey: Key.emphasizeActiveWindow) as? Bool
            ?? Default.emphasizeActiveWindow
        inactiveOpacity = SettingsStore.clamped(
            defaults.object(forKey: Key.inactiveOpacity) as? Double ?? Default.inactiveOpacity,
            to: SettingsStore.inactiveOpacityRange, fallback: Default.inactiveOpacity)
        activeWidthBoost = SettingsStore.clamped(
            defaults.object(forKey: Key.activeWidthBoost) as? Double ?? Default.activeWidthBoost,
            to: SettingsStore.activeWidthBoostRange, fallback: Default.activeWidthBoost)
        showInFullscreen = defaults.object(forKey: Key.showInFullscreen) as? Bool ?? Default.showInFullscreen
        showInMissionControl = defaults.object(forKey: Key.showInMissionControl) as? Bool
            ?? Default.showInMissionControl
        borderLayering = defaults.string(forKey: Key.borderLayering).flatMap(BorderLayering.init(rawValue:))
            ?? Default.borderLayering
        let storedFilter = SettingsStore.load(AppFilter.self, from: defaults, forKey: Key.appFilter) ?? AppFilter()
        appFilter = AppFilter(mode: storedFilter.mode, bundleIDs: storedFilter.bundleIDs)
        appColorOverrides = SettingsStore.load([String: RGBAColor].self, from: defaults,
                                               forKey: Key.appColorOverrides) ?? [:]
        rememberColors = defaults.object(forKey: Key.rememberColors) as? Bool ?? Default.rememberColors
        hotKeyEnabled = defaults.object(forKey: Key.hotKeyEnabled) as? Bool ?? Default.hotKeyEnabled
        storedColorMemory = SettingsStore.load(ColorMemory.self, from: defaults, forKey: Key.colorMemory)
            ?? ColorMemory()
    }

    /// Restores every setting to its default. Remembered window colors are kept: they are history, not a setting.
    func resetToDefaults() {
        isEnabled = Default.isEnabled
        borderWidth = Default.borderWidth
        cornerRadiusMode = Default.cornerRadiusMode
        customCornerRadius = Default.customCornerRadius
        palette = Palette.defaultColors
        emphasizeActiveWindow = Default.emphasizeActiveWindow
        inactiveOpacity = Default.inactiveOpacity
        activeWidthBoost = Default.activeWidthBoost
        showInFullscreen = Default.showInFullscreen
        showInMissionControl = Default.showInMissionControl
        borderLayering = Default.borderLayering
        appFilter = AppFilter()
        appColorOverrides = [:]
        rememberColors = Default.rememberColors
        hotKeyEnabled = Default.hotKeyEnabled
    }

    // MARK: - Persistence helpers

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    /// Nil when the key is missing or holds data an older/newer build wrote in another shape (then defaults apply).
    private static func load<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
