import Foundation

/// Per-window color assignments. A window keeps its color for its whole lifetime: assigning again is a no-op, so
/// windows never change color just because others opened or closed.
public struct ColorAssigner: Sendable {
    public typealias WindowID = UInt32

    /// Why a window has its color: picked as least used, restored from `ColorMemory`, or chosen by the user.
    public enum Source: String, Codable, Sendable {
        case fresh, remembered, manual
    }

    public struct Assignment: Equatable, Sendable {
        public let color: RGBAColor
        public let source: Source

        public init(color: RGBAColor, source: Source) {
            self.color = color
            self.source = source
        }
    }

    public private(set) var assignments: [WindowID: Assignment]

    public init() {
        assignments = [:]
    }

    public func color(for id: WindowID) -> RGBAColor? {
        assignments[id]?.color
    }

    public func source(for id: WindowID) -> Source? {
        assignments[id]?.source
    }

    /// Lifetime-stable: returns the existing color if `id` already has one. Otherwise uses `remembered` if non-nil
    /// (source .remembered) else ColorPicker.leastUsed(palette:inUse:) (source .fresh).
    @discardableResult
    public mutating func assign(
        _ id: WindowID, palette: [RGBAColor], inUse: [RGBAColor], remembered: RGBAColor?
    ) -> RGBAColor {
        if let existing = assignments[id] {
            return existing.color
        }
        let assignment: Assignment
        if let remembered {
            assignment = Assignment(color: remembered, source: .remembered)
        } else {
            assignment = Assignment(color: ColorPicker.leastUsed(palette: palette, inUse: inUse), source: .fresh)
        }
        assignments[id] = assignment
        return assignment.color
    }

    public mutating func setManual(_ id: WindowID, color: RGBAColor) {
        assignments[id] = Assignment(color: color, source: .manual)
    }

    /// Manual: next palette color after the current one (palette[0] when the window has none or an off-palette color).
    @discardableResult
    public mutating func cycle(_ id: WindowID, palette: [RGBAColor]) -> RGBAColor {
        let next = ColorPicker.next(after: color(for: id), in: palette)
        setManual(id, color: next)
        return next
    }

    /// Replaces the color only if the current assignment is .fresh (title became known right after creation).
    /// The source becomes .remembered either way; returns true only if the color actually changed.
    /// Unknown windows are left alone (returns false).
    @discardableResult
    public mutating func applyRemembered(_ id: WindowID, color: RGBAColor) -> Bool {
        guard let current = assignments[id], current.source == .fresh else { return false }
        assignments[id] = Assignment(color: color, source: .remembered)
        return current.color != color
    }

    public mutating func remove(_ id: WindowID) {
        assignments[id] = nil
    }

    /// A palette color was edited in place: every window wearing `old` switches to `new`, keeping its source.
    public mutating func replaceColor(_ old: RGBAColor, with new: RGBAColor) {
        for (id, assignment) in assignments where assignment.color == old {
            assignments[id] = Assignment(color: new, source: assignment.source)
        }
    }
}
