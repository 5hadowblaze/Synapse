import XCTest
@testable import Synapse

@MainActor
final class KineticClockEngineTests: XCTestCase {
    func testIngestStrikeRecordsMotorRTAndSpatialMatch() {
        let engine = KineticClockEngine()
        let sessionStart = PhoneTime(seconds: 1_000)
        engine.armAwaitingStrikeForTesting(
            targetOctant: 2,
            sessionStart: sessionStart,
            targetOnsetMs: 100
        )

        var completed: TrialRecord?
        engine.onTrialCompleted = { completed = $0 }

        let event = StrikeEvent(
            watchTimestamp: 10,
            peakG: 4.5,
            phoneTimestamp: sessionStart.seconds + 0.350, // 350ms from session start
            detectedOctant: 2
        )
        engine.ingestStrike(event)

        XCTAssertEqual(completed?.motorRtMs, 250, accuracy: 1e-6) // 350 - 100
        XCTAssertEqual(completed?.spatialMatch, true)
        XCTAssertEqual(completed?.detectedOctant, 2)
        XCTAssertEqual(completed?.peakG, 4.5)
        XCTAssertEqual(completed?.valid, true)
    }

    func testIngestStrikeSpatialMissKeepsTimingValid() {
        let engine = KineticClockEngine()
        let sessionStart = PhoneTime(seconds: 500)
        engine.armAwaitingStrikeForTesting(
            targetOctant: 0,
            sessionStart: sessionStart,
            targetOnsetMs: 50
        )

        var completed: TrialRecord?
        engine.onTrialCompleted = { completed = $0 }

        engine.ingestStrike(
            StrikeEvent(
                watchTimestamp: 1,
                peakG: 5,
                phoneTimestamp: sessionStart.seconds + 0.200,
                detectedOctant: 4
            )
        )

        XCTAssertEqual(completed?.spatialMatch, false)
        XCTAssertEqual(completed?.valid, true)
        XCTAssertEqual(completed?.motorRtMs, 150, accuracy: 1e-6)
    }

    func testIngestStrikeIgnoredOutsideAwaitingResponse() {
        let engine = KineticClockEngine()
        engine.ingestStrike(
            StrikeEvent(watchTimestamp: 1, peakG: 4, phoneTimestamp: 2, detectedOctant: 1)
        )
        XCTAssertTrue(engine.trials.isEmpty)
    }
}
