import BorderCore
import XCTest

final class ColorPickerTests: XCTestCase {
    private let palette = Palette.defaultColors
    private let offPalette = RGBAColor(red: 0.01, green: 0.02, blue: 0.03)

    func testLeastUsedPrefersUnusedColorsInPaletteOrder() {
        XCTAssertEqual(ColorPicker.leastUsed(palette: palette, inUse: []), palette[0])
        XCTAssertEqual(ColorPicker.leastUsed(palette: palette, inUse: [palette[0], palette[2]]), palette[1])
    }

    func testLeastUsedPicksLowestCount() {
        var inUse = palette + palette
        inUse.remove(at: 6) // palette[6] is now used once, every other color twice
        XCTAssertEqual(ColorPicker.leastUsed(palette: palette, inUse: inUse), palette[6])
    }

    func testLeastUsedTiesGoToLowestPaletteIndex() {
        let inUse = Array(palette[0..<3]) + [palette[1]]
        XCTAssertEqual(ColorPicker.leastUsed(palette: palette, inUse: inUse), palette[3])
        XCTAssertEqual(ColorPicker.leastUsed(palette: palette, inUse: palette), palette[0])
    }

    func testLeastUsedIgnoresColorsNotInPalette() {
        XCTAssertEqual(ColorPicker.leastUsed(palette: palette, inUse: [offPalette, offPalette]), palette[0])
        XCTAssertEqual(ColorPicker.leastUsed(palette: palette, inUse: [offPalette, palette[0]]), palette[1])
    }

    func testLeastUsedWithEmptyPaletteFallsBackToFirstDefault() {
        XCTAssertEqual(ColorPicker.leastUsed(palette: [], inUse: [palette[0]]), Palette.defaultColors[0])
    }

    func testNextWrapsAndFallsBackToFirst() {
        XCTAssertEqual(ColorPicker.next(after: palette[0], in: palette), palette[1])
        XCTAssertEqual(ColorPicker.next(after: palette[9], in: palette), palette[0])
        XCTAssertEqual(ColorPicker.next(after: nil, in: palette), palette[0])
        XCTAssertEqual(ColorPicker.next(after: offPalette, in: palette), palette[0])
        XCTAssertEqual(ColorPicker.next(after: palette[0], in: [palette[0]]), palette[0])
        XCTAssertEqual(ColorPicker.next(after: palette[3], in: []), Palette.defaultColors[0])
    }
}

final class ColorAssignerTests: XCTestCase {
    private let palette = Palette.defaultColors

    /// Assigns fresh colors the way the app does: everything currently assigned counts as in use.
    @discardableResult
    private func assignFresh(_ ids: [ColorAssigner.WindowID], to assigner: inout ColorAssigner) -> [RGBAColor] {
        var assigned: [RGBAColor] = []
        for id in ids {
            let used = inUse(assigner)
            assigned.append(assigner.assign(id, palette: palette, inUse: used, remembered: nil))
        }
        return assigned
    }

    private func inUse(_ assigner: ColorAssigner) -> [RGBAColor] {
        assigner.assignments.values.map(\.color)
    }

    func testFiveWindowsGetFiveDistinctColors() {
        var assigner = ColorAssigner()
        let colors = assignFresh([1, 2, 3, 4, 5], to: &assigner)
        XCTAssertEqual(Set(colors).count, 5)
        XCTAssertEqual(colors, Array(palette[0..<5]))
        XCTAssertEqual(assigner.source(for: 3), .fresh)
    }

    func testEleventhWindowReusesLeastUsedColor() {
        var assigner = ColorAssigner()
        assignFresh(Array<ColorAssigner.WindowID>(1...10), to: &assigner)
        XCTAssertEqual(Set(inUse(assigner)).count, 10)

        // All ten used once: ties go to palette order.
        let eleventh = assignFresh([11], to: &assigner)
        let twelfth = assignFresh([12], to: &assigner)
        XCTAssertEqual(eleventh, [palette[0]])
        XCTAssertEqual(twelfth, [palette[1]])

        // Closing the windows holding palette[0] (once) and palette[2] makes palette[2] the only unused color.
        assigner.remove(1)
        assigner.remove(3)
        let thirteenth = assignFresh([13], to: &assigner)
        XCTAssertEqual(thirteenth, [palette[2]])
    }

    func testAssignIsLifetimeStable() {
        var assigner = ColorAssigner()
        let first = assigner.assign(7, palette: palette, inUse: [], remembered: nil)
        let again = assigner.assign(7, palette: palette, inUse: [first, first, first], remembered: palette[4])
        XCTAssertEqual(first, again)
        XCTAssertEqual(assigner.color(for: 7), first)
        XCTAssertEqual(assigner.source(for: 7), .fresh)
    }

    func testAssignUsesRememberedColor() {
        var assigner = ColorAssigner()
        let color = assigner.assign(1, palette: palette, inUse: [], remembered: palette[5])
        XCTAssertEqual(color, palette[5])
        XCTAssertEqual(assigner.source(for: 1), .remembered)
    }

    func testRemoveFreesColor() {
        var assigner = ColorAssigner()
        assignFresh([1, 2, 3], to: &assigner)
        assigner.remove(2)
        XCTAssertNil(assigner.color(for: 2))
        XCTAssertNil(assigner.source(for: 2))
        let fourth = assignFresh([4], to: &assigner)
        XCTAssertEqual(fourth, [palette[1]])
    }

    func testCycleIsManualAndWraps() {
        var assigner = ColorAssigner()
        assignFresh([1], to: &assigner)
        XCTAssertEqual(assigner.cycle(1, palette: palette), palette[1])
        XCTAssertEqual(assigner.source(for: 1), .manual)

        assigner.setManual(1, color: palette[9])
        XCTAssertEqual(assigner.cycle(1, palette: palette), palette[0])

        // Unknown window or off-palette color: start over at the first palette color.
        XCTAssertEqual(assigner.cycle(42, palette: palette), palette[0])
        assigner.setManual(5, color: RGBAColor(red: 0.3, green: 0.3, blue: 0.3))
        XCTAssertEqual(assigner.cycle(5, palette: palette), palette[0])
    }

    func testSetManual() {
        var assigner = ColorAssigner()
        assignFresh([1], to: &assigner)
        assigner.setManual(1, color: palette[8])
        XCTAssertEqual(assigner.assignments[1], ColorAssigner.Assignment(color: palette[8], source: .manual))
    }

    func testApplyRememberedOnlyReplacesFreshAssignments() {
        var assigner = ColorAssigner()
        assignFresh([1, 2, 3], to: &assigner)

        XCTAssertTrue(assigner.applyRemembered(1, color: palette[7]))
        XCTAssertEqual(assigner.color(for: 1), palette[7])
        XCTAssertEqual(assigner.source(for: 1), .remembered)

        // Already remembered: left alone.
        XCTAssertFalse(assigner.applyRemembered(1, color: palette[8]))
        XCTAssertEqual(assigner.color(for: 1), palette[7])

        // Manual choices win over memory.
        assigner.setManual(2, color: palette[9])
        XCTAssertFalse(assigner.applyRemembered(2, color: palette[8]))
        XCTAssertEqual(assigner.color(for: 2), palette[9])

        // Same color as the fresh one: nothing visible changes.
        XCTAssertFalse(assigner.applyRemembered(3, color: palette[2]))
        XCTAssertEqual(assigner.source(for: 3), .remembered)

        // Unknown window: no assignment is created.
        XCTAssertFalse(assigner.applyRemembered(99, color: palette[0]))
        XCTAssertNil(assigner.color(for: 99))
    }

    func testReplaceColorRecolorsWearersAndKeepsSource() {
        var assigner = ColorAssigner()
        assignFresh([1, 2], to: &assigner)
        assigner.setManual(3, color: palette[0])
        let darkerGreen = RGBAColor(red: 0.1, green: 0.5, blue: 0.2)

        assigner.replaceColor(palette[0], with: darkerGreen)

        XCTAssertEqual(assigner.assignments[1], ColorAssigner.Assignment(color: darkerGreen, source: .fresh))
        XCTAssertEqual(assigner.assignments[3], ColorAssigner.Assignment(color: darkerGreen, source: .manual))
        XCTAssertEqual(assigner.color(for: 2), palette[1])
    }
}
