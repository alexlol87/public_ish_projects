import BorderCore
import CoreGraphics
import XCTest

/// Layouts use a 1920×1080 primary display. Each case states a secondary display's AppKit frame and the AX frame
/// macOS reports for it, then converts a window on that display both ways.
final class CoordinateConverterTests: XCTestCase {
    private let primaryHeight: CGFloat = 1080

    private func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    private func toAppKit(_ rect: CGRect) -> CGRect {
        CoordinateConverter.appKitRect(fromAX: rect, primaryScreenHeight: primaryHeight)
    }

    private func toAX(_ rect: CGRect) -> CGRect {
        CoordinateConverter.axRect(fromAppKit: rect, primaryScreenHeight: primaryHeight)
    }

    private func assertConverts(
        ax: CGRect, appKit: CGRect, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(toAppKit(ax), appKit, file: file, line: line)
        XCTAssertEqual(toAX(appKit), ax, file: file, line: line)
    }

    func testSingleDisplay() {
        assertConverts(ax: rect(0, 0, 1920, 1080), appKit: rect(0, 0, 1920, 1080))
        assertConverts(ax: rect(100, 50, 800, 600), appKit: rect(100, 430, 800, 600))
        // A window flush with the top of the screen (below a 25 pt menu bar in AX terms).
        assertConverts(ax: rect(0, 25, 400, 300), appKit: rect(0, 755, 400, 300))
    }

    func testSecondDisplayToTheRight() {
        // 2560×1440, bottoms aligned: it reaches 360 pt above the primary's top, so its AX top is negative.
        assertConverts(ax: rect(1920, -360, 2560, 1440), appKit: rect(1920, 0, 2560, 1440))
        assertConverts(ax: rect(2000, -300, 1000, 800), appKit: rect(2000, 580, 1000, 800))
    }

    func testDisplayAbovePrimary() {
        assertConverts(ax: rect(0, -1200, 1920, 1200), appKit: rect(0, 1080, 1920, 1200))
        assertConverts(ax: rect(100, -1100, 600, 400), appKit: rect(100, 1780, 600, 400))
    }

    func testDisplayToTheLeft() {
        assertConverts(ax: rect(-1440, 180, 1440, 900), appKit: rect(-1440, 0, 1440, 900))
        assertConverts(ax: rect(-1400, 200, 500, 300), appKit: rect(-1400, 580, 500, 300))
    }

    func testTallerDisplayBelowLeft() {
        // Portrait 1200×1920 whose top edge touches the primary's bottom edge.
        assertConverts(ax: rect(-1200, 1080, 1200, 1920), appKit: rect(-1200, -1920, 1200, 1920))
        assertConverts(ax: rect(-1100, 1200, 800, 1500), appKit: rect(-1100, -1620, 800, 1500))
    }

    func testRoundTrip() {
        let rects = [
            CGRect(x: 0, y: 0, width: 1, height: 1),
            CGRect(x: 12.5, y: -333.25, width: 640.75, height: 480.5),
            CGRect(x: -2000, y: 1500, width: 300, height: 200),
            CGRect(x: 5000, y: -5000, width: 0, height: 0),
        ]
        for rect in rects {
            assertRectsEqual(toAX(toAppKit(rect)), rect)
            assertRectsEqual(toAppKit(toAX(rect)), rect)
        }
    }

    func testNegativeSizeRectsAreStandardized() {
        let flipped = CGRect(x: 900, y: 650, width: -800, height: -600) // same as (100, 50, 800, 600)
        XCTAssertEqual(toAppKit(flipped), CGRect(x: 100, y: 430, width: 800, height: 600))
    }

    func testPoints() {
        func appKit(_ point: CGPoint) -> CGPoint {
            CoordinateConverter.appKitPoint(fromAX: point, primaryScreenHeight: primaryHeight)
        }
        func ax(_ point: CGPoint) -> CGPoint {
            CoordinateConverter.axPoint(fromAppKit: point, primaryScreenHeight: primaryHeight)
        }
        XCTAssertEqual(appKit(CGPoint(x: 10, y: 20)), CGPoint(x: 10, y: 1060))
        XCTAssertEqual(appKit(CGPoint(x: 0, y: 0)), CGPoint(x: 0, y: 1080))
        XCTAssertEqual(appKit(CGPoint(x: 2000, y: -300)), CGPoint(x: 2000, y: 1380))
        XCTAssertEqual(appKit(CGPoint(x: -1100, y: 2700)), CGPoint(x: -1100, y: -1620))
        XCTAssertEqual(ax(CGPoint(x: 10, y: 1060)), CGPoint(x: 10, y: 20))

        let point = CGPoint(x: -123.5, y: 456.25)
        XCTAssertEqual(ax(appKit(point)), point)
    }
}
