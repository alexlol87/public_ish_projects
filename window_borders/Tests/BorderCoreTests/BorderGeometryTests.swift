import BorderCore
import CoreGraphics
import XCTest

final class BorderGeometryTests: XCTestCase {
    private let window = CGRect(x: 100, y: 200, width: 800, height: 600)

    func testOutsideLayoutGrowsByLineWidthAndOverlapsOnePoint() {
        let layout = BorderGeometry.layout(
            windowFrame: window, lineWidth: 4, windowCornerRadius: 10, placement: .outside
        )
        XCTAssertEqual(layout.overlayFrame, CGRect(x: 96, y: 196, width: 808, height: 608))
        // Center line 1 pt outside the window edge: band from 1 pt inside to 3 pt outside.
        XCTAssertEqual(layout.strokeRect, CGRect(x: 3, y: 3, width: 802, height: 602))
        XCTAssertEqual(layout.cornerRadius, 11, accuracy: 1e-9)
        XCTAssertEqual(layout.lineWidth, 4)

        // The band, measured from the window edge (which sits `lineWidth` in from the overlay edge).
        let windowEdge: CGFloat = 4
        let innerEdge = layout.strokeRect.minX + layout.lineWidth / 2
        let outerEdge = layout.strokeRect.minX - layout.lineWidth / 2
        XCTAssertEqual(innerEdge - windowEdge, 1, accuracy: 1e-9)
        XCTAssertEqual(windowEdge - outerEdge, 3, accuracy: 1e-9)
    }

    func testOutsideCornerRadiusIsConcentric() {
        // The stroke's center line is offset (lineWidth / 2 - overlap) from the window edge, so the radius grows
        // by exactly that offset.
        for lineWidth: CGFloat in [2, 4, 8, 20] {
            let layout = BorderGeometry.layout(
                windowFrame: window, lineWidth: lineWidth, windowCornerRadius: 10, placement: .outside
            )
            let centerOffset = lineWidth - layout.strokeRect.minX // outward distance from the window edge
            XCTAssertEqual(layout.cornerRadius, 10 + centerOffset, accuracy: 1e-9)
            XCTAssertEqual(layout.cornerRadius, 10 + lineWidth / 2 - 1, accuracy: 1e-9)
        }
    }

    func testThinLinesOverlapHalfTheirWidth() {
        let one = BorderGeometry.layout(windowFrame: window, lineWidth: 1, windowCornerRadius: 10, placement: .outside)
        XCTAssertEqual(one.overlayFrame, CGRect(x: 99, y: 199, width: 802, height: 602))
        // Overlap 0.5: the stroke is centered exactly on the window edge.
        XCTAssertEqual(one.strokeRect, CGRect(x: 1, y: 1, width: 800, height: 600))
        XCTAssertEqual(one.cornerRadius, 10, accuracy: 1e-9)

        let oneAndHalf = BorderGeometry.layout(
            windowFrame: window, lineWidth: 1.5, windowCornerRadius: 10, placement: .outside
        )
        assertRectsEqual(oneAndHalf.strokeRect, CGRect(x: 1.5, y: 1.5, width: 800, height: 600))
        XCTAssertEqual(oneAndHalf.cornerRadius, 10, accuracy: 1e-9)
    }

    func testInsideLayoutStaysWithinTheWindow() {
        let layout = BorderGeometry.layout(
            windowFrame: window, lineWidth: 4, windowCornerRadius: 10, placement: .inside
        )
        XCTAssertEqual(layout.overlayFrame, window)
        XCTAssertEqual(layout.strokeRect, CGRect(x: 2, y: 2, width: 796, height: 596))
        XCTAssertEqual(layout.cornerRadius, 8, accuracy: 1e-9)
        XCTAssertEqual(layout.lineWidth, 4)

        let square = BorderGeometry.layout(windowFrame: window, lineWidth: 6, windowCornerRadius: 1, placement: .inside)
        XCTAssertEqual(square.cornerRadius, 0)
    }

    func testDefaultWindowCornerRadius() {
        XCTAssertEqual(BorderGeometry.defaultWindowCornerRadius(osMajorVersion: 14), 10)
        XCTAssertEqual(BorderGeometry.defaultWindowCornerRadius(osMajorVersion: 15), 10)
        XCTAssertEqual(BorderGeometry.defaultWindowCornerRadius(osMajorVersion: 26), 16)
        XCTAssertEqual(BorderGeometry.defaultWindowCornerRadius(osMajorVersion: 27), 16)
    }

    func testIndexOfBestScreen() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 2560, height: 1440),
        ]
        func best(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, in frames: [CGRect]) -> Int? {
            let rect = CGRect(x: x, y: y, width: width, height: height)
            return BorderGeometry.indexOfBestScreen(for: rect, screenFrames: frames)
        }
        XCTAssertEqual(best(1800, 100, 400, 300, in: screens), 1) // mostly on the second screen
        XCTAssertEqual(best(1600, 100, 400, 300, in: screens), 0) // mostly on the first
        XCTAssertEqual(best(1820, 100, 200, 100, in: screens), 0) // equal split: lower index wins
        XCTAssertEqual(best(1900, 0, 20, 10, in: screens), 0)     // only touching screen 1's edge counts for nothing
        XCTAssertNil(best(9000, 9000, 10, 10, in: screens))       // off every screen
        XCTAssertNil(best(0, 0, 10, 10, in: []))                  // no screens
    }

    func testPixelAligned() {
        XCTAssertEqual(BorderGeometry.pixelAligned(1.3, scale: 1), 1)
        XCTAssertEqual(BorderGeometry.pixelAligned(1.6, scale: 1), 2)
        XCTAssertEqual(BorderGeometry.pixelAligned(1.3, scale: 2), 1.5)
        XCTAssertEqual(BorderGeometry.pixelAligned(4, scale: 2), 4)
        XCTAssertEqual(BorderGeometry.pixelAligned(1.3, scale: 3), 4.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(BorderGeometry.pixelAligned(2, scale: 3), 2, accuracy: 1e-9)
    }

    func testPixelAlignedNeverGoesBelowOnePixel() {
        XCTAssertEqual(BorderGeometry.pixelAligned(0, scale: 1), 1)
        XCTAssertEqual(BorderGeometry.pixelAligned(0.1, scale: 2), 0.5)
        XCTAssertEqual(BorderGeometry.pixelAligned(0.2, scale: 3), 1.0 / 3.0, accuracy: 1e-9)
        // Nonsense scale: treated as 1.
        XCTAssertEqual(BorderGeometry.pixelAligned(1.4, scale: 0), 1)
    }
}
