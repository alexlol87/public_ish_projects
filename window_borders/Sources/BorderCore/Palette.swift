import Foundation

/// The built-in border colors: saturated hues that stay distinguishable next to each other and on light/dark windows.
public enum Palette {
    private static let named: [(name: String, color: RGBAColor)] = [
        ("Green", rgb(0x34, 0xC7, 0x59)),
        ("Red", rgb(0xFF, 0x3B, 0x30)),
        ("Blue", rgb(0x0A, 0x84, 0xFF)),
        ("Purple", rgb(0xAF, 0x52, 0xDE)),
        ("Orange", rgb(0xFF, 0x95, 0x00)),
        ("Yellow", rgb(0xFF, 0xD6, 0x0A)),
        ("Cyan", rgb(0x5A, 0xC8, 0xFA)),
        ("Pink", rgb(0xFF, 0x2D, 0x92)),
        ("Teal", rgb(0x00, 0x8C, 0x8C)),
        ("Brown", rgb(0xA2, 0x84, 0x5E)),
    ]

    /// green, red, blue, purple, orange, yellow, cyan, pink, teal, brown (in that order)
    public static let defaultColors: [RGBAColor] = named.map { $0.color }

    /// Human name for a color if it is one of the defaults ("Green"...), else its hex.
    /// Compared by hex so tiny floating-point differences (e.g. from a color panel) still match.
    public static func name(for color: RGBAColor) -> String {
        let hex = color.hex
        return named.first(where: { $0.color.hex == hex })?.name ?? hex
    }

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> RGBAColor {
        RGBAColor(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}
