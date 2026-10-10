import AppKit
import BorderCore

/// Decides which color each window wears: BorderCore's `ColorAssigner` (lifetime-stable, least-used) plus
/// `ColorMemory` (best-effort restore across restarts, keyed by bundle ID + normalized title) plus the settings
/// (palette, per-app pins, the "remember colors" switch).
///
/// Memory is written back to `SettingsStore.colorMemory` lazily: titles change constantly (editors, terminals), so
/// every change is recorded in memory here and flushed at most every couple of seconds, plus at quit.
@MainActor
final class ColorService {
    /// A window whose title becomes known this soon after it appeared still gets its remembered color (apps often
    /// create a window as "Untitled" and set the real title a moment later).
    private static let restoreGracePeriod: TimeInterval = 5
    private static let persistDelay: TimeInterval = 2
    private static let maxRememberedKeys = 500

    private let settings: SettingsStore
    private var assigner = ColorAssigner()
    private var memory: ColorMemory
    private var memoryIsDirty = false
    private var persistTimer: Timer?
    /// The palette as of the last `paletteDidChange()`, to tell an in-place color edit from an add/remove/reorder.
    private var lastPalette: [RGBAColor]

    init(settings: SettingsStore) {
        self.settings = settings
        memory = settings.colorMemory
        lastPalette = settings.palette
    }

    /// When a palette color is edited in place, windows wearing the old value switch to the new one. Otherwise they
    /// would keep an off-palette color that least-used counting ignores, so the next window would duplicate it.
    /// Adding, removing or reordering colors leaves existing windows alone.
    func paletteDidChange() {
        let old = lastPalette
        let new = settings.palette
        lastPalette = new
        guard old.count == new.count else { return }
        for (oldColor, newColor) in zip(old, new) where oldColor != newColor && !new.contains(oldColor) {
            assigner.replaceColor(oldColor, with: newColor)
        }
    }

    /// The window's own color (ignoring per-app pins), nil if it has none yet.
    func assignedColor(for id: CGWindowID) -> RGBAColor? {
        assigner.color(for: id)
    }

    /// What the border shows: a pinned app color wins over the window's own color.
    func effectiveColor(for window: TrackedWindow) -> RGBAColor? {
        if let bundleID = window.bundleID, let pinned = settings.appColorOverrides[bundleID] {
            return pinned
        }
        return assigner.color(for: window.id)
    }

    /// Gives a new window its lifetime color: a remembered one if memory has an unclaimed match, else the palette
    /// color least used by `inUse` (effective colors of the borders currently on screen). No-op if it has a color.
    /// - Parameter liveWindows: all tracked windows, so a remembered color already worn by a sibling window of the
    ///   same app is not handed out twice.
    @discardableResult
    func assign(_ window: TrackedWindow, inUse: [RGBAColor], liveWindows: [TrackedWindow]) -> RGBAColor {
        if let existing = assigner.color(for: window.id) {
            return existing
        }
        let color = assigner.assign(
            window.id,
            palette: settings.palette,
            inUse: inUse,
            remembered: rememberedColor(for: window, liveWindows: liveWindows)
        )
        record(window, color: color)
        return color
    }

    /// Call after the tracker reported a new title. Within the grace period a still-`.fresh` color is swapped for a
    /// remembered one; either way the (possibly new) title is remembered with the window's color.
    func titleDidChange(_ window: TrackedWindow, liveWindows: [TrackedWindow]) {
        if assigner.source(for: window.id) == .fresh,
           Date().timeIntervalSince(window.firstSeen) <= Self.restoreGracePeriod,
           let remembered = rememberedColor(for: window, liveWindows: liveWindows) {
            assigner.applyRemembered(window.id, color: remembered)
        }
        if let color = assigner.color(for: window.id) {
            record(window, color: color)
        }
    }

    /// Manual color choice (menu swatch).
    func setColor(_ color: RGBAColor, of window: TrackedWindow) {
        assigner.setManual(window.id, color: color)
        record(window, color: color)
    }

    /// Manual: next palette color (hotkey / "Recolor Focused Window").
    @discardableResult
    func cycleColor(of window: TrackedWindow) -> RGBAColor {
        let color = assigner.cycle(window.id, palette: settings.palette)
        record(window, color: color)
        return color
    }

    /// Forgets a closed window, remembering its final title/color first so reopening it restores the color.
    /// - Parameter lastKnown: the window as last reported (the tracker no longer has it).
    func remove(_ id: CGWindowID, lastKnown: TrackedWindow?) {
        if let window = lastKnown, let color = assigner.color(for: id) {
            record(window, color: color)
        }
        assigner.remove(id)
    }

    /// Writes pending memory changes to settings now (quit, stop).
    func persistNow() {
        persistTimer?.invalidate()
        persistTimer = nil
        guard memoryIsDirty else { return }
        memoryIsDirty = false
        memory.prune(maxKeys: Self.maxRememberedKeys)
        settings.colorMemory = memory
    }

    // MARK: - Private

    private func rememberedColor(for window: TrackedWindow, liveWindows: [TrackedWindow]) -> RGBAColor? {
        guard settings.rememberColors, let bundleID = window.bundleID else { return nil }
        // Every sibling of the same app counts, not only those whose title still has this key: a terminal that
        // opened as "alex — -zsh" and now runs vim still wears that key's color, and a second "alex — -zsh" window
        // must not get it too.
        let claimed = liveWindows.compactMap { (other: TrackedWindow) -> RGBAColor? in
            guard other.id != window.id, other.bundleID == bundleID else { return nil }
            return assigner.color(for: other.id)
        }
        return memory.lookup(bundleID: bundleID, title: window.title, excluding: claimed)
    }

    /// Only windows with a bundle ID and a title that normalizes to something stable are worth remembering.
    private func record(_ window: TrackedWindow, color: RGBAColor) {
        guard settings.rememberColors, let bundleID = window.bundleID,
              ColorMemory.normalizedTitle(window.title, bundleID: bundleID) != nil else { return }
        memory.record(bundleID: bundleID, title: window.title, color: color, now: Date())
        memoryIsDirty = true
        schedulePersist()
    }

    /// Coalesces bursts of title changes into one UserDefaults write; a pending flush is not pushed back by
    /// further changes, so a constantly retitling window still gets saved every couple of seconds.
    private func schedulePersist() {
        guard persistTimer == nil else { return }
        let timer = Timer(timeInterval: Self.persistDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.persistNow()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        persistTimer = timer
    }
}
