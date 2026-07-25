import XCTest
@testable import Synapse

final class StrikeGateAndDeliveryTests: XCTestCase {
    func testSpikeGateThresholdAndRefractory() {
        var gate = StrikeGate(spikeThresholdG: 3.5, refractorySeconds: 0.35)
        XCTAssertFalse(gate.shouldFire(peakG: 3.0, at: 1.0))
        XCTAssertTrue(gate.shouldFire(peakG: 4.0, at: 1.0))
        XCTAssertFalse(gate.shouldFire(peakG: 5.0, at: 1.2))
        XCTAssertTrue(gate.shouldFire(peakG: 5.0, at: 1.4))
    }

    func testStrikeDeliveryNeedsClockSync() {
        let outcome = StrikeDelivery.prepare(
            watchTime: WatchTime(seconds: 10),
            peakG: 4.0,
            detectedOctant: 2,
            offsetSeconds: nil
        )
        XCTAssertEqual(outcome, .needsClockSync)
    }

    func testStrikeDeliveryAppliesOffset() {
        let outcome = StrikeDelivery.prepare(
            watchTime: WatchTime(seconds: 10),
            peakG: 4.0,
            detectedOctant: 2,
            offsetSeconds: 1.25
        )
        guard case .deliver(let event) = outcome else {
            return XCTFail("expected deliver")
        }
        XCTAssertEqual(event.phoneTimestamp, 11.25, accuracy: 1e-12)
        XCTAssertEqual(event.peakG, 4.0)
        XCTAssertEqual(event.detectedOctant, 2)
    }
}
