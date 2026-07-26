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

        XCTAssertEqual(completed?.motorRtMs ?? -1, 250, accuracy: 1e-6) // 350 - 100
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
        XCTAssertEqual(completed?.motorRtMs ?? -1, 150, accuracy: 1e-6)
    }

    func testIngestStrikeIgnoredOutsideAwaitingResponse() {
        let engine = KineticClockEngine()
        engine.ingestStrike(
            StrikeEvent(watchTimestamp: 1, peakG: 4, phoneTimestamp: 2, detectedOctant: 1)
        )
        XCTAssertTrue(engine.trials.isEmpty)
    }

    func testMakeRecapSummarizesMotorAndSpatial() {
        let engine = KineticClockEngine()
        let sessionStart = PhoneTime(seconds: 2_000)

        func punch(target: Int, detected: Int, onsetMs: Double, strikeOffset: Double) {
            engine.armAwaitingStrikeForTesting(
                targetOctant: target,
                sessionStart: sessionStart,
                targetOnsetMs: onsetMs,
                trialIndex: engine.trials.count
            )
            engine.ingestStrike(
                StrikeEvent(
                    watchTimestamp: 1,
                    peakG: 4,
                    phoneTimestamp: sessionStart.seconds + (onsetMs + strikeOffset) / 1_000,
                    detectedOctant: detected
                )
            )
        }

        punch(target: 1, detected: 1, onsetMs: 100, strikeOffset: 200)
        punch(target: 2, detected: 5, onsetMs: 400, strikeOffset: 300)
        punch(target: 3, detected: 3, onsetMs: 800, strikeOffset: 250)

        let recap = engine.makeRecap(completedNaturally: false)
        XCTAssertEqual(recap.trialCount, 3)
        XCTAssertEqual(recap.plannedTrials, KineticClockEngine.defaultTrialCount)
        XCTAssertEqual(recap.motorSampleCount, 3)
        XCTAssertEqual(recap.medianMotorRtMs ?? -1, 250, accuracy: 1e-6)
        XCTAssertEqual(recap.meanMotorRtMs ?? -1, 250, accuracy: 1e-6)
        XCTAssertEqual(recap.spatialMatchCount, 2)
        XCTAssertEqual(recap.spatialMissCount, 1)
        XCTAssertEqual(recap.spatialAccuracyPercent ?? -1, (2.0 / 3.0) * 100.0, accuracy: 0.01)
        XCTAssertFalse(recap.completedNaturally)
        XCTAssertTrue(recap.voiceSummary.contains("Kinetic complete"))
        XCTAssertFalse(recap.voiceSummary.lowercased().contains("fatigue"))
    }
}
