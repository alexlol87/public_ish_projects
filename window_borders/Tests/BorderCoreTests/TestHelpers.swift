import CoreGraphics
import XCTest

/// Compares rects component-wise with a tolerance (layout math produces fractional values like 1/3).
func assertRectsEqual(
    _ actual: CGRect, _ expected: CGRect, accuracy: CGFloat = 1e-9,
    file: StaticString = #filePath, line: UInt = #line
) {
    let message = "\(actual) is not \(expected)"
    XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: accuracy, message, file: file, line: line)
    XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: accuracy, message, file: file, line: line)
    XCTAssertEqual(actual.size.width, expected.size.width, accuracy: accuracy, message, file: file, line: line)
    XCTAssertEqual(actual.size.height, expected.size.height, accuracy: accuracy, message, file: file, line: line)
}
