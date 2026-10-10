import BorderCore
import CoreGraphics
import Foundation
import XCTest

final class AppFilterTests: XCTestCase {
    func testAllModeAllowsEverything() {
        let filter = AppFilter()
        XCTAssertEqual(filter.mode, .all)
        XCTAssertTrue(filter.allows(bundleID: "com.apple.Safari"))
        XCTAssertTrue(filter.allows(bundleID: nil))
        XCTAssertTrue(AppFilter(mode: .all, bundleIDs: ["com.apple.Safari"]).allows(bundleID: "com.apple.Safari"))
    }

    func testAllowlistAllowsOnlyListedApps() {
        let filter = AppFilter(mode: .allowlist, bundleIDs: ["com.apple.Safari"])
        XCTAssertTrue(filter.allows(bundleID: "com.apple.Safari"))
        XCTAssertFalse(filter.allows(bundleID: "com.apple.Terminal"))
        XCTAssertFalse(filter.allows(bundleID: nil))
        XCTAssertFalse(AppFilter(mode: .allowlist).allows(bundleID: "com.apple.Safari"))
    }

    func testBlocklistAllowsEverythingButListedApps() {
        let filter = AppFilter(mode: .blocklist, bundleIDs: ["com.apple.Safari"])
        XCTAssertFalse(filter.allows(bundleID: "com.apple.Safari"))
        XCTAssertTrue(filter.allows(bundleID: "com.apple.Terminal"))
        XCTAssertTrue(filter.allows(bundleID: nil))
    }

    func testInitKeepsOrderAndDropsDuplicates() {
        let filter = AppFilter(mode: .blocklist, bundleIDs: ["b", "a", "b", "c", "a"])
        XCTAssertEqual(filter.bundleIDs, ["b", "a", "c"])
    }

    func testCodableRoundTrip() throws {
        let filter = AppFilter(mode: .allowlist, bundleIDs: ["com.apple.Safari", "com.apple.Terminal"])
        let data = try JSONEncoder().encode(filter)
        XCTAssertEqual(try JSONDecoder().decode(AppFilter.self, from: data), filter)
        XCTAssertEqual(AppFilterMode.allCases, [.all, .allowlist, .blocklist])
    }
}

final class WindowEligibilityTests: XCTestCase {
    private func isStandard(
        role: String? = "AXWindow", subrole: String? = "AXStandardWindow",
        width: CGFloat = 800, height: CGFloat = 600, layer: Int? = 0
    ) -> Bool {
        WindowEligibility.isStandardWindow(
            role: role, subrole: subrole, size: CGSize(width: width, height: height), layer: layer
        )
    }

    func testStandardWindowIsEligible() {
        XCTAssertTrue(isStandard())
        XCTAssertTrue(isStandard(layer: nil))
    }

    func testOtherRolesAndSubrolesAreNot() {
        XCTAssertFalse(isStandard(role: nil))
        XCTAssertFalse(isStandard(role: "AXSheet"))
        XCTAssertFalse(isStandard(subrole: nil))
        XCTAssertFalse(isStandard(subrole: "AXDialog"))
        XCTAssertFalse(isStandard(subrole: "AXFloatingWindow"))
    }

    func testSizeThresholds() {
        XCTAssertTrue(isStandard(width: 60, height: 40))
        XCTAssertFalse(isStandard(width: 59.5, height: 40))
        XCTAssertFalse(isStandard(width: 60, height: 39))
        XCTAssertFalse(isStandard(width: 0, height: 0))
    }

    func testNonZeroLayersAreNot() {
        XCTAssertFalse(isStandard(layer: 3))
        XCTAssertFalse(isStandard(layer: 25))
    }
}
