import XCTest
@testable import Synapse

final class HorizontalOctantClassifierTests: XCTestCase {
    func testForwardPunchMapsToTwelve() {
        let classifier = HorizontalOctantClassifier(forwardXZ: (x: 0, z: 1))
        // Gravity down +Y; punch along +Z (forward).
        let octant = classifier.octant(
            vectorX: 0,
            vectorY: 0,
            vectorZ: 1,
            gravityX: 0,
            gravityY: 1,
            gravityZ: 0,
            mirrorLateral: false
        )
        XCTAssertEqual(octant, ClockOctant.twelve.rawValue)
    }

    func testRightPunchMapsToThree() {
        let classifier = HorizontalOctantClassifier(forwardXZ: (x: 0, z: 1))
        let octant = classifier.octant(
            vectorX: 1,
            vectorY: 0,
            vectorZ: 0,
            gravityX: 0,
            gravityY: 1,
            gravityZ: 0,
            mirrorLateral: false
        )
        XCTAssertEqual(octant, ClockOctant.three.rawValue)
    }

    func testLeftWristMirrorsLateral() {
        let classifier = HorizontalOctantClassifier(forwardXZ: (x: 0, z: 1))
        let octant = classifier.octant(
            vectorX: 1,
            vectorY: 0,
            vectorZ: 0,
            gravityX: 0,
            gravityY: 1,
            gravityZ: 0,
            mirrorLateral: true
        )
        XCTAssertEqual(octant, ClockOctant.nine.rawValue)
    }

    func testCalibrationBuildsUnitForward() {
        let built = HorizontalOctantClassifier.fromCalibration(
            gravitySumX: 0,
            gravitySumY: 10,
            gravitySumZ: 0,
            forwardSumX: 0,
            forwardSumZ: 5,
            sampleCount: 10
        )
        XCTAssertNotNil(built)
        XCTAssertEqual(built!.forwardXZ.z, 1, accuracy: 1e-9)
        XCTAssertEqual(built!.forwardXZ.x, 0, accuracy: 1e-9)
    }

    func testCalibrationFailsWithNoSamples() {
        XCTAssertNil(
            HorizontalOctantClassifier.fromCalibration(
                gravitySumX: 0,
                gravitySumY: 0,
                gravitySumZ: 0,
                forwardSumX: 0,
                forwardSumZ: 0,
                sampleCount: 0
            )
        )
    }
}
