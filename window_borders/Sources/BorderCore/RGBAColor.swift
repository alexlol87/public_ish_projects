import Foundation

/// A color as plain numbers so it can be stored in settings (JSON) and compared without AppKit.
/// Components are in 0...1, sRGB.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    /// Components are clamped to 0...1.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    /// Parses "#RRGGBB" or "#RRGGBBAA", with or without the '#', case-insensitive; surrounding whitespace is ignored.
    public init?(hex: String) {
        var digits = Substring(hex.trimmingCharacters(in: .whitespacesAndNewlines))
        if digits.hasPrefix("#") {
            digits = digits.dropFirst()
        }
        // Check the characters ourselves: UInt64(_:radix:) would also accept a leading "+" or "-".
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let value = UInt64(digits, radix: 16)
        else { return nil }

        let rgb: UInt64 = digits.count == 8 ? value >> 8 : value
        let alphaByte: UInt64 = digits.count == 8 ? value & 0xFF : 0xFF
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: Double(alphaByte) / 255
        )
    }

    /// "#RRGGBB", or "#RRGGBBAA" when the alpha byte is below FF; uppercase.
    public var hex: String {
        let r = Self.byte(red)
        let g = Self.byte(green)
        let b = Self.byte(blue)
        let a = Self.byte(alpha)
        let rgb = "#" + Self.hexPair(r) + Self.hexPair(g) + Self.hexPair(b)
        return a < 255 ? rgb + Self.hexPair(a) : rgb
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    private static func byte(_ component: Double) -> Int {
        Int((clamp(component) * 255).rounded())
    }

    private static func hexPair(_ byte: Int) -> String {
        let digits = String(byte, radix: 16, uppercase: true)
        return digits.count == 1 ? "0" + digits : digits
    }
}
