import BorderCore
import Foundation
import XCTest

final class RGBAColorTests: XCTestCase {
    func testParsesSixDigitHexWithAndWithoutHash() {
        XCTAssertEqual(RGBAColor(hex: "#FF0000"), RGBAColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(RGBAColor(hex: "00FF00"), RGBAColor(red: 0, green: 1, blue: 0))
        XCTAssertEqual(RGBAColor(hex: "  #0000FF\n"), RGBAColor(red: 0, green: 0, blue: 1))
    }

    func testParsingIsCaseInsensitive() {
        XCTAssertEqual(RGBAColor(hex: "#ff8000"), RGBAColor(hex: "#FF8000"))
        XCTAssertEqual(RGBAColor(hex: "aBcDeF"), RGBAColor(hex: "ABCDEF"))
    }

    func testParsesEightDigitHexAlpha() throws {
        let color = try XCTUnwrap(RGBAColor(hex: "#0000FF80"))
        XCTAssertEqual(color.blue, 1)
        XCTAssertEqual(color.alpha, 128.0 / 255.0, accuracy: 1e-12)
        XCTAssertEqual(RGBAColor(hex: "#FF0000FF")?.alpha, 1)
    }

    func testRejectsInvalidStrings() {
        let invalid = [
            "", "#", "FFF", "#FFF", "#GG0000", "#FF00000", "#FF0000F", "#FF0000FF00", "##FF0000",
            "+FF00000", "-FFFFF", "#FF 000", "red", "0xFF0000",
        ]
        for string in invalid {
            XCTAssertNil(RGBAColor(hex: string), "\"\(string)\" should not parse")
        }
    }

    func testFormatsUppercaseSixDigitsWhenOpaque() {
        XCTAssertEqual(RGBAColor(red: 1, green: 0, blue: 0).hex, "#FF0000")
        XCTAssertEqual(RGBAColor(red: 1, green: 0.5, blue: 0).hex, "#FF8000")
        XCTAssertEqual(RGBAColor(hex: "#abcdef")?.hex, "#ABCDEF")
    }

    func testFormatsEightDigitsWhenTranslucent() {
        XCTAssertEqual(RGBAColor(hex: "#ff000080")?.hex, "#FF000080")
        XCTAssertEqual(RGBAColor(red: 0, green: 0, blue: 0, alpha: 0).hex, "#00000000")
        XCTAssertEqual(RGBAColor(hex: "#FF0000FF")?.hex, "#FF0000")
    }

    func testHexRoundTrip() {
        for hex in ["#123456", "#FEDCBA", "#00000000", "#7F7F7F40"] {
            XCTAssertEqual(RGBAColor(hex: hex)?.hex, hex)
        }
    }

    func testInitClampsComponents() {
        let color = RGBAColor(red: 2, green: -1, blue: 0.5, alpha: 3)
        XCTAssertEqual(color.red, 1)
        XCTAssertEqual(color.green, 0)
        XCTAssertEqual(color.blue, 0.5)
        XCTAssertEqual(color.alpha, 1)
    }

    func testCodableRoundTrip() throws {
        let color = RGBAColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        let data = try JSONEncoder().encode(color)
        XCTAssertEqual(try JSONDecoder().decode(RGBAColor.self, from: data), color)
    }
}

final class PaletteTests: XCTestCase {
    func testDefaultPaletteHasTenDistinctColors() {
        XCTAssertEqual(Palette.defaultColors.count, 10)
        XCTAssertEqual(Set(Palette.defaultColors).count, 10)
        XCTAssertEqual(Set(Palette.defaultColors.map(\.hex)).count, 10)
        XCTAssertTrue(Palette.defaultColors.allSatisfy { $0.alpha == 1 })
    }

    func testNamesFollowPaletteOrder() {
        let names = Palette.defaultColors.map { Palette.name(for: $0) }
        XCTAssertEqual(names, ["Green", "Red", "Blue", "Purple", "Orange", "Yellow", "Cyan", "Pink", "Teal", "Brown"])
    }

    func testNameMatchesSameHexAndFallsBackToHex() throws {
        let green = Palette.defaultColors[0]
        let nearlyGreen = RGBAColor(red: green.red + 1e-6, green: green.green, blue: green.blue)
        XCTAssertEqual(Palette.name(for: nearlyGreen), "Green")

        let custom = try XCTUnwrap(RGBAColor(hex: "#123456"))
        XCTAssertEqual(Palette.name(for: custom), "#123456")
    }
}
