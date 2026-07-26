import XCTest
@testable import Synapse

/// Scoring rules for the tap PVT: median, lapses, false starts, pre/post delta.
final class TapPVTResultTests: XCTestCase {
    private func result(
        stage: TapPVTStage = .pre,
        _ trials: [TapPVTTrial]
    ) -> TapPVTResult {
        TapPVTResult(
            stage: stage,
            startedAt: Date(timeIntervalSince1970: 0),
            durationSeconds: 60,
            trials: trials
        )
    }

    private func responses(_ values: [Double]) -> [TapPVTTrial] {
        values.enumerated().map {
            TapPVTTrial(index: $0.offset, isiMs: 4000, reactionMs: $0.element)
        }
    }

    // MARK: - Median

    func testMedianOfOddCountIsMiddleValue() {
        XCTAssertEqual(TapPVTResult.median([300, 280, 320]), 300)
    }

    func testMedianOfEvenCountAveragesMiddlePair() {
        XCTAssertEqual(TapPVTResult.median([280, 300, 320, 340]), 310)
    }

    func testMedianOfEmptyIsNil() {
        XCTAssertNil(TapPVTResult.median([]))
    }

    func testMedianIgnoresInputOrder() {
        XCTAssertEqual(TapPVTResult.median([520, 271, 288, 301, 299]), 299)
    }

    func testResultMedianAndMeanUseOnlyValidTrials() {
        let scored = result(responses([280, 300, 320]) + [
            TapPVTTrial(index: 3, isiMs: 4000, falseStart: true),
            TapPVTTrial(index: 4, isiMs: 4000, timedOut: true)
        ])
        XCTAssertEqual(scored.medianRtMs, 300)
        XCTAssertEqual(scored.meanRtMs ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(scored.validCount, 3)
        XCTAssertEqual(scored.attemptedCount, 5)
    }

    func testFastestAndSlowestComeFromValidTrials() {
        let scored = result(responses([412, 268, 355]))
        XCTAssertEqual(scored.fastestRtMs, 268)
        XCTAssertEqual(scored.slowestRtMs, 412)
    }

    // MARK: - Lapses

    func testLapseCountsResponsesAtOrOverThreshold() {
        let scored = result(responses([280, 354, 355, 640]))
        XCTAssertEqual(scored.lapseCount, 2, "355 ms is a lapse; 354 ms is not")
    }

    /// PVT-B lowers the cutoff from the 10-minute PVT's 500 ms. Pin the constant so a
    /// well-meaning "round it back to 500" is caught rather than silently undercounting.
    func testLapseThresholdFollowsPvtBNotTheTenMinuteProtocol() {
        XCTAssertEqual(TapPVTResult.lapseThresholdMs, 355)
        XCTAssertEqual(TapPVTResult.validRtFloorMs, 100)
        let scored = result(responses([400, 420, 440]))
        XCTAssertEqual(scored.lapseCount, 3, "responses in 355–500 ms are PVT-B lapses")
    }

    func testTimeoutCountsAsLapseButNotAsValidTrial() {
        let scored = result(responses([300]) + [TapPVTTrial(index: 1, isiMs: 3000, timedOut: true)])
        XCTAssertEqual(scored.lapseCount, 1)
        XCTAssertEqual(scored.validCount, 1)
        XCTAssertEqual(scored.medianRtMs, 300)
    }

    func testNoLapsesOnACleanRun() {
        XCTAssertEqual(result(responses([260, 275, 290, 310])).lapseCount, 0)
    }

    // MARK: - False starts

    func testFalseStartIsNotALapseAndNotValid() {
        let trial = TapPVTTrial(index: 0, isiMs: 5000, falseStart: true)
        XCTAssertFalse(trial.isLapse, "an anticipatory tap is an error of commission, not a lapse")
        XCTAssertFalse(trial.isValid)
    }

    /// Basner et al.: "A response was regarded valid if RT was ≥ 100 ms." A sub-100 ms
    /// hit is a finger already in motion, and must never be scorable as a fast reaction.
    func testSubHundredMillisecondResponseIsNeverValid() {
        let trial = TapPVTTrial(index: 0, isiMs: 1200, reactionMs: 40)
        XCTAssertFalse(trial.isValid, "40 ms is faster than perception")
        XCTAssertFalse(trial.isLapse)
        XCTAssertNil(result([trial]).medianRtMs)
    }

    func testAnticipationsCannotDragTheMedianDown() {
        let honest = result(responses([300, 320, 340]))
        let jumpy = result(responses([300, 320, 340]) + [
            TapPVTTrial(index: 3, isiMs: 1000, reactionMs: 20, falseStart: true),
            TapPVTTrial(index: 4, isiMs: 1000, reactionMs: 35, falseStart: true)
        ])
        XCTAssertEqual(jumpy.medianRtMs, honest.medianRtMs)
        XCTAssertEqual(jumpy.falseStartCount, 2)
        XCTAssertEqual(jumpy.validCount, 3)
    }

    /// A run mostly made of false starts leaves too few clean taps to claim a direction.
    func testComparisonStaysSilentWhenOneSideIsMostlyFalseStarts() {
        let clean = result(stage: .pre, responses([280, 290, 300, 310]))
        let jumpy = result(stage: .post, responses([300]) + (1...6).map {
            TapPVTTrial(index: $0, isiMs: 1000, reactionMs: 30, falseStart: true)
        })
        let comparison = TapPVTComparison(pre: clean, post: jumpy)
        XCTAssertNil(comparison.medianDeltaMs)
        XCTAssertNil(comparison.percentChange)
        XCTAssertEqual(comparison.direction, .steady)
        XCTAssertEqual(comparison.headline, "Not enough clean taps to compare.")
    }

    func testFalseStartsAreCountedSeparately() {
        let scored = result(responses([290, 305]) + [
            TapPVTTrial(index: 2, isiMs: 5000, falseStart: true),
            TapPVTTrial(index: 3, isiMs: 5000, falseStart: true)
        ])
        XCTAssertEqual(scored.falseStartCount, 2)
        XCTAssertEqual(scored.lapseCount, 0)
        XCTAssertEqual(scored.validCount, 2)
    }

    func testUsableNeedsThreeCleanTrials() {
        XCTAssertFalse(result(responses([300, 310])).isUsable)
        XCTAssertTrue(result(responses([300, 310, 295])).isUsable)
    }

    func testMedianLabelFallsBackWhenNothingIsValid() {
        let scored = result([TapPVTTrial(index: 0, isiMs: 4000, falseStart: true)])
        XCTAssertEqual(scored.medianLabel, "—")
    }

    // MARK: - Pre / post comparison

    func testComparisonReportsSlowdownAndLapseDelta() {
        let pre = result(stage: .pre, responses([275, 280, 285]))
        let post = result(stage: .post, responses([330, 340, 350, 620, 700]))
        let comparison = TapPVTComparison(pre: pre, post: post)

        XCTAssertEqual(comparison.pre.medianRtMs, 280)
        XCTAssertEqual(comparison.post.medianRtMs, 350)
        XCTAssertEqual(comparison.medianDeltaMs, 70)
        XCTAssertEqual(comparison.lapseDelta, 2)
        XCTAssertEqual(comparison.direction, .slower)
        XCTAssertEqual(comparison.percentChange ?? 0, 25, accuracy: 0.001)
        XCTAssertEqual(comparison.headline, "You reacted 70 ms slower after the block.")
        XCTAssertEqual(comparison.lapseLine, "2 more lapses than before.")
    }

    func testSmallMedianMoveReadsAsSteady() {
        let pre = result(stage: .pre, responses([300, 300, 300]))
        let post = result(stage: .post, responses([305, 305, 305]))
        let comparison = TapPVTComparison(pre: pre, post: post)
        XCTAssertEqual(comparison.direction, .steady, "moves inside the dead band are noise")
        XCTAssertEqual(comparison.headline, "Your reaction time held steady through the block.")
    }

    func testImprovementReadsAsFaster() {
        let pre = result(stage: .pre, responses([340, 340, 340]))
        let post = result(stage: .post, responses([300, 300, 300]))
        let comparison = TapPVTComparison(pre: pre, post: post)
        XCTAssertEqual(comparison.direction, .faster)
        XCTAssertEqual(comparison.medianDeltaMs, -40)
        XCTAssertEqual(comparison.headline, "You reacted 40 ms faster after the block.")
    }

    func testComparisonWithoutValidTrialsDegradesGracefully() {
        let pre = result(stage: .pre, [TapPVTTrial(index: 0, isiMs: 4000, falseStart: true)])
        let post = result(stage: .post, responses([320]))
        let comparison = TapPVTComparison(pre: pre, post: post)
        XCTAssertNil(comparison.medianDeltaMs)
        XCTAssertEqual(comparison.direction, .steady)
        XCTAssertEqual(comparison.headline, "Not enough clean taps to compare.")
    }

    func testSingleLapseLineUsesSingular() {
        let pre = result(stage: .pre, responses([280, 280, 280]))
        let post = result(stage: .post, responses([300, 300, 640]))
        XCTAssertEqual(TapPVTComparison(pre: pre, post: post).lapseLine, "1 more lapse than before.")
    }

    func testCleanBothSidesLapseLine() {
        let pre = result(stage: .pre, responses([280, 280, 280]))
        let post = result(stage: .post, responses([300, 300, 300]))
        XCTAssertEqual(TapPVTComparison(pre: pre, post: post).lapseLine, "No lapses either side.")
    }

    // MARK: - Codable (persistence + Firestore payloads)

    func testResultRoundTripsThroughCodable() throws {
        let original = result(responses([281, 305, 512]))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TapPVTResult.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.lapseCount, 1)
    }
}
