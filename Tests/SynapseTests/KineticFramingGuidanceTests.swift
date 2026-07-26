import XCTest
@testable import Synapse

final class KineticFramingGuidanceTests: XCTestCase {
    func testNilFaceAsksToFacePhone() {
        XCTAssertEqual(
            KineticFramingGuidance.prompt(facePositionCamera: nil),
            "Face the phone"
        )
    }

    func testTooCloseAsksToMoveFurther() {
        let face = SIMD3<Float>(0, 0, -0.4)
        XCTAssertEqual(
            KineticFramingGuidance.prompt(facePositionCamera: face, distanceMeters: 0.4),
            "Move further from the camera"
        )
    }

    func testTooFarAsksToMoveCloser() {
        let face = SIMD3<Float>(0, 0, -1.0)
        XCTAssertEqual(
            KineticFramingGuidance.prompt(facePositionCamera: face, distanceMeters: 1.0),
            "Move closer to the camera"
        )
    }

    func testPositiveXAsksToMoveLeft() {
        let face = SIMD3<Float>(0.12, 0, -0.7)
        XCTAssertEqual(
            KineticFramingGuidance.prompt(facePositionCamera: face, distanceMeters: 0.7),
            "Move left"
        )
    }

    func testNegativeXAsksToMoveRight() {
        let face = SIMD3<Float>(-0.12, 0, -0.7)
        XCTAssertEqual(
            KineticFramingGuidance.prompt(facePositionCamera: face, distanceMeters: 0.7),
            "Move right"
        )
    }

    func testInBandReturnsNil() {
        let face = SIMD3<Float>(0.02, -0.01, -0.7)
        XCTAssertNil(
            KineticFramingGuidance.prompt(facePositionCamera: face, distanceMeters: 0.7)
        )
    }

    func testDepthWinsOverLateral() {
        let face = SIMD3<Float>(0.2, 0, -0.4)
        XCTAssertEqual(
            KineticFramingGuidance.prompt(facePositionCamera: face, distanceMeters: 0.4),
            "Move further from the camera"
        )
    }

    func testLateralWinsOverVertical() {
        let face = SIMD3<Float>(0.12, 0.2, -0.7)
        XCTAssertEqual(
            KineticFramingGuidance.prompt(facePositionCamera: face, distanceMeters: 0.7),
            "Move left"
        )
    }

    func testVerticalPromptWhenCenteredLaterally() {
        let face = SIMD3<Float>(0.01, 0.15, -0.7)
        XCTAssertEqual(
            KineticFramingGuidance.prompt(facePositionCamera: face, distanceMeters: 0.7),
            "Move down"
        )
    }
}
