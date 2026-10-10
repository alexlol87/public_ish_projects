import Foundation

/// Chooses palette colors; stateless so the rules are easy to test.
public enum ColorPicker {
    /// Palette color used least among `inUse`; ties -> lowest palette index. Colors not in palette are ignored.
    /// Empty palette -> Palette.defaultColors[0].
    public static func leastUsed(palette: [RGBAColor], inUse: [RGBAColor]) -> RGBAColor {
        guard let first = palette.first else { return Palette.defaultColors[0] }
        var counts: [RGBAColor: Int] = [:]
        for color in inUse {
            counts[color, default: 0] += 1
        }
        var best = first
        var bestCount = counts[first] ?? 0
        // Strictly-less comparison keeps the earliest palette entry on ties.
        for color in palette.dropFirst() {
            let count = counts[color] ?? 0
            if count < bestCount {
                best = color
                bestCount = count
            }
        }
        return best
    }

    /// Palette color after `current` (wrapping); `current` nil / not in palette -> palette[0].
    /// Empty palette -> Palette.defaultColors[0].
    public static func next(after current: RGBAColor?, in palette: [RGBAColor]) -> RGBAColor {
        guard let first = palette.first else { return Palette.defaultColors[0] }
        guard let current, let index = palette.firstIndex(of: current) else { return first }
        return palette[(index + 1) % palette.count]
    }
}
