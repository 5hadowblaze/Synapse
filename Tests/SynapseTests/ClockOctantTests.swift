import XCTest
@testable import Synapse

final class ClockOctantTests: XCTestCase {
    func testNearestAtBoundaries() {
        XCTAssertEqual(ClockOctant.nearest(angleRadians: 0), .twelve)
        XCTAssertEqual(ClockOctant.nearest(angleRadians: .pi / 4), .oneThirty)
        XCTAssertEqual(ClockOctant.nearest(angleRadians: .pi / 2), .three)
        XCTAssertEqual(ClockOctant.nearest(angleRadians: .pi), .six)
        XCTAssertEqual(ClockOctant.nearest(angleRadians: 3 * .pi / 2), .nine)
    }

    func testNearestWrapsNegativeAndOverTwoPi() {
        XCTAssertEqual(ClockOctant.nearest(angleRadians: -.pi / 8 + 1e-9), .twelve)
        XCTAssertEqual(ClockOctant.nearest(angleRadians: 2 * .pi - 1e-6), .twelve)
        // Just past half-sector toward 1:30
        XCTAssertEqual(ClockOctant.nearest(angleRadians: .pi / 8 + 1e-6), .oneThirty)
    }

    func testLabels() {
        XCTAssertEqual(ClockOctant.twelve.label, "12")
        XCTAssertEqual(ClockOctant.fourThirty.label, "4:30")
    }
}
