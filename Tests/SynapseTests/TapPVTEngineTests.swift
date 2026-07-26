import XCTest
@testable import Synapse

/// Engine behaviour with timers off — trials advance only when the test drives them,
/// so nothing here depends on wall-clock scheduling.
@MainActor
final class TapPVTEngineTests: XCTestCase {
    /// Manually advanced clock shared with the engine.
    private final class TestClock {
        var seconds: TimeInterval = 0
        func advance(ms: Double) { seconds += ms / 1000 }
    }

    private func makeEngine(
        isiMs: Double = 4000,
        clock: TestClock
    ) -> TapPVTEngine {
        TapPVTEngine(
            clock: { clock.seconds },
            isiProvider: { isiMs },
            schedulesAutomatically: false
        )
    }

    // MARK: - Reaction timing

    func testTapAfterStimulusRecordsReactionTime() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.start(stage: .pre)
        XCTAssertEqual(engine.phase, .waiting)

        engine.presentStimulus()
        XCTAssertTrue(engine.stimulusVisible)

        clock.advance(ms: 284)
        engine.registerTap()

        XCTAssertEqual(engine.trials.count, 1)
        XCTAssertEqual(engine.trials[0].reactionMs ?? 0, 284, accuracy: 0.5)
        XCTAssertTrue(engine.trials[0].isValid)
        XCTAssertFalse(engine.trials[0].isLapse)
        XCTAssertEqual(engine.feedback, .reaction(engine.trials[0].reactionMs ?? 0))
    }

    func testSlowTapIsFlaggedAsLapse() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.start(stage: .pre)
        engine.presentStimulus()

        clock.advance(ms: 640)
        engine.registerTap()

        XCTAssertTrue(engine.trials[0].isLapse)
        XCTAssertTrue(engine.trials[0].isValid, "a slow response is still a real measurement")
        XCTAssertEqual(engine.lapseCount, 1)
    }

    func testMedianAcrossSeveralTrials() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.start(stage: .pre)

        for rt in [300.0, 260.0, 280.0] {
            engine.presentStimulus()
            clock.advance(ms: rt)
            engine.registerTap()
            clock.advance(ms: 500)
        }

        XCTAssertEqual(engine.trials.count, 3)
        XCTAssertEqual(engine.liveMedianMs ?? 0, 280, accuracy: 0.5)
    }

    // MARK: - PVT-B trial density

    func testDefaultIntervalMatchesPvtB() {
        XCTAssertEqual(TapPVTEngine.defaultIsiRangeMs.lowerBound, 1000)
        XCTAssertEqual(TapPVTEngine.defaultIsiRangeMs.upperBound, 4000)
    }

    /// The reason for the 1–4 s interval: a 60 s run has to sample enough trials for the
    /// median to mean something. Driven at the real cadence with a seeded interval draw.
    func testSixtySecondRunSamplesEnoughTrialsForAStableMedian() {
        var seed: UInt64 = 0x5eed
        let range = TapPVTEngine.defaultIsiRangeMs
        let drawIsi: () -> Double = {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double(seed >> 11) / Double(UInt64(1) << 53)
            return range.lowerBound + unit * (range.upperBound - range.lowerBound)
        }
        let clock = TestClock()
        let engine = TapPVTEngine(
            clock: { clock.seconds },
            isiProvider: drawIsi,
            schedulesAutomatically: false
        )
        engine.start(stage: .pre)

        var safety = 0
        while engine.isRunning && safety < 200 {
            clock.advance(ms: engine.pendingIsiMs)
            engine.presentStimulus()
            clock.advance(ms: 300)
            engine.registerTap()
            safety += 1
        }

        let scored = engine.result
        XCTAssertNotNil(scored)
        // Lands on 23 for this seed at a 300 ms RT. The band is wide enough to survive a
        // different draw but tight enough to catch a cadence regression.
        XCTAssertGreaterThanOrEqual(engine.trials.count, 18)
        XCTAssertLessThanOrEqual(engine.trials.count, 28)
        XCTAssertTrue(scored?.isUsable ?? false)
        XCTAssertEqual(scored?.medianRtMs ?? 0, 300, accuracy: 1)
    }

    // MARK: - False starts

    func testTapBeforeStimulusIsAFalseStart() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.start(stage: .pre)

        clock.advance(ms: 1200)
        engine.registerTap()

        XCTAssertEqual(engine.trials.count, 1)
        XCTAssertTrue(engine.trials[0].falseStart)
        XCTAssertNil(engine.trials[0].reactionMs)
        XCTAssertFalse(engine.trials[0].isLapse)
        XCTAssertEqual(engine.feedback, .falseStart)
    }

    func testFalseStartDoesNotBlockTheNextTrial() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.start(stage: .pre)

        engine.registerTap()
        XCTAssertEqual(engine.phase, .waiting, "the interval restarts after an early tap")

        engine.presentStimulus()
        clock.advance(ms: 310)
        engine.registerTap()

        XCTAssertEqual(engine.trials.count, 2)
        XCTAssertTrue(engine.trials[0].falseStart)
        XCTAssertTrue(engine.trials[1].isValid)
        XCTAssertEqual(engine.liveMedianMs ?? 0, 310, accuracy: 0.5)
    }

    /// A 1 s minimum interval invites anticipation. A tap that lands inside 100 ms of
    /// onset was already in flight, so it is scored as an error of commission rather
    /// than as a superhuman reaction.
    func testSubHundredMillisecondTapIsScoredAsAnticipation() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.start(stage: .pre)
        engine.presentStimulus()

        clock.advance(ms: 42)
        engine.registerTap()

        let trial = engine.trials[0]
        XCTAssertTrue(trial.falseStart)
        XCTAssertFalse(trial.isValid)
        XCTAssertEqual(trial.reactionMs ?? 0, 42, accuracy: 0.5, "kept for the record")
        XCTAssertEqual(engine.feedback, .falseStart)
        XCTAssertNil(engine.liveMedianMs, "an anticipation contributes nothing to the median")
    }

    /// The jumpy-user case at PVT-B cadence: mashing produces false starts, and the few
    /// honest taps still drive the median instead of being buried by 20 ms hits.
    func testMashingCannotProduceANonsenseMedian() {
        let clock = TestClock()
        let engine = makeEngine(isiMs: 1000, clock: clock)
        engine.start(stage: .pre)

        for _ in 0..<8 {
            engine.presentStimulus()
            clock.advance(ms: 30)
            engine.registerTap()
            clock.advance(ms: 200)
        }
        for rt in [295.0, 305.0, 300.0] {
            engine.presentStimulus()
            clock.advance(ms: rt)
            engine.registerTap()
            clock.advance(ms: 200)
        }

        let scored = engine.finish()
        XCTAssertEqual(scored?.falseStartCount, 8)
        XCTAssertEqual(scored?.validCount, 3)
        XCTAssertEqual(scored?.medianRtMs ?? 0, 300, accuracy: 0.5)
        XCTAssertEqual(scored?.lapseCount, 0, "false starts are not lapses")
    }

    func testExtraTapDuringFeedbackIsIgnored() {
        let clock = TestClock()
        let engine = TapPVTEngine(
            clock: { clock.seconds },
            isiProvider: { 4000 },
            schedulesAutomatically: true
        )
        engine.start(stage: .pre)
        engine.presentStimulus()
        clock.advance(ms: 290)
        engine.registerTap()
        XCTAssertEqual(engine.phase, .feedback)

        engine.registerTap()
        XCTAssertEqual(engine.trials.count, 1, "double taps must not invent a false start")
        engine.cancel()
    }

    // MARK: - No response

    func testExpiredStimulusIsANoResponseLapse() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.start(stage: .pre)
        engine.presentStimulus()

        clock.advance(ms: TapPVTEngine.responseWindowMs)
        engine.expireStimulus()

        XCTAssertEqual(engine.trials.count, 1)
        XCTAssertTrue(engine.trials[0].timedOut)
        XCTAssertTrue(engine.trials[0].isLapse)
        XCTAssertFalse(engine.trials[0].isValid)
        XCTAssertEqual(engine.feedback, .missed)
    }

    // MARK: - Lifecycle

    func testFinishScoresTheRunAndFiresOnce() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        var completions: [TapPVTResult] = []
        engine.onComplete = { completions.append($0) }
        engine.start(stage: .post)

        for rt in [270.0, 520.0, 300.0] {
            engine.presentStimulus()
            clock.advance(ms: rt)
            engine.registerTap()
            clock.advance(ms: 400)
        }
        engine.finish()
        engine.finish()

        XCTAssertEqual(completions.count, 1)
        guard let scored = completions.first else { return XCTFail("no result") }
        XCTAssertEqual(scored.stage, .post)
        XCTAssertEqual(scored.validCount, 3)
        XCTAssertEqual(scored.lapseCount, 1)
        XCTAssertEqual(scored.medianRtMs ?? 0, 300, accuracy: 0.5)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.phase, .complete)
    }

    func testRunEndsWhenTheDurationIsSpent() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        var completed: TapPVTResult?
        engine.onComplete = { completed = $0 }
        engine.start(stage: .pre, durationSeconds: 10)

        engine.presentStimulus()
        clock.advance(ms: 300)
        engine.registerTap()
        XCTAssertTrue(engine.isRunning)

        clock.advance(ms: 10_000)
        engine.presentStimulus()
        clock.advance(ms: 300)
        engine.registerTap()

        XCTAssertNotNil(completed, "a response past the duration closes the run")
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(completed?.trials.count, 2)
    }

    func testCancelDiscardsTheRunWithoutScoring() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        var completed: TapPVTResult?
        engine.onComplete = { completed = $0 }
        engine.start(stage: .pre)
        engine.presentStimulus()
        clock.advance(ms: 250)
        engine.registerTap()

        engine.cancel()

        XCTAssertNil(completed)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.finish(), "a cancelled run has nothing to score")
    }

    func testStartResetsPreviousTrials() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.start(stage: .pre)
        engine.presentStimulus()
        clock.advance(ms: 300)
        engine.registerTap()
        XCTAssertEqual(engine.trials.count, 1)

        engine.start(stage: .post)
        XCTAssertTrue(engine.trials.isEmpty)
        XCTAssertNil(engine.feedback)
        XCTAssertNil(engine.result)
        XCTAssertEqual(engine.stage, .post)
    }

    func testTapsBeforeStartAreIgnored() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.registerTap()
        engine.presentStimulus()
        XCTAssertTrue(engine.trials.isEmpty)
        XCTAssertEqual(engine.phase, .idle)
    }

    func testProgressAndRemainingTrackTheClock() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.start(stage: .pre, durationSeconds: 60)
        XCTAssertEqual(engine.remainingSeconds, 60, accuracy: 0.01)

        clock.advance(ms: 15_000)
        engine.presentStimulus()

        XCTAssertEqual(engine.progress, 0.25, accuracy: 0.01)
        XCTAssertEqual(engine.remainingSeconds, 45, accuracy: 0.01)
    }
}
