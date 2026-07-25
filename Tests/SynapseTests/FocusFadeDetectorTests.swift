import XCTest
@testable import Synapse

final class FocusFadeDetectorTests: XCTestCase {
    func testBaselineThenFiresAboveTwoSigma() {
        var detector = FocusFadeDetector(
            baselineSamples: 5,
            cooldownSeconds: 0,
            sampleInterval: 0
        )

        // Stable low scores fill baseline.
        for i in 0..<5 {
            let fired = detector.ingestForced(
                now: TimeInterval(i),
                hrBpm: 60,
                arousal: 0.8,
                motionEnergy: 0.05
            )
            XCTAssertFalse(fired)
        }
        XCTAssertTrue(detector.isBaselineReady)
        XCTAssertEqual(detector.fadeCount, 0)

        // Spike: high HR + low arousal + motion → should exceed mean+2σ.
        let fired = detector.ingestForced(
            now: 10,
            hrBpm: 95,
            arousal: 0.05,
            motionEnergy: 0.9
        )
        XCTAssertTrue(fired)
        XCTAssertEqual(detector.fadeCount, 1)
    }

    func testCooldownSuppressesRapidRefire() {
        var detector = FocusFadeDetector(
            baselineSamples: 4,
            cooldownSeconds: 60,
            sampleInterval: 0
        )
        for i in 0..<4 {
            _ = detector.ingestForced(now: TimeInterval(i), hrBpm: 62, arousal: 0.75, motionEnergy: 0.1)
        }
        XCTAssertTrue(
            detector.ingestForced(now: 20, hrBpm: 100, arousal: 0.02, motionEnergy: 1.0)
        )
        // Within cooldown
        XCTAssertFalse(
            detector.ingestForced(now: 30, hrBpm: 100, arousal: 0.02, motionEnergy: 1.0)
        )
        // After cooldown
        XCTAssertTrue(
            detector.ingestForced(now: 90, hrBpm: 100, arousal: 0.02, motionEnergy: 1.0)
        )
        XCTAssertEqual(detector.fadeCount, 2)
    }

    func testWorksWithoutMotionEnergy() {
        var detector = FocusFadeDetector(
            baselineSamples: 4,
            cooldownSeconds: 0,
            sampleInterval: 0
        )
        for i in 0..<4 {
            _ = detector.ingestForced(now: TimeInterval(i), hrBpm: 60, arousal: 0.85, motionEnergy: nil)
        }
        let fired = detector.ingestForced(now: 10, hrBpm: 90, arousal: 0.05, motionEnergy: nil)
        XCTAssertTrue(fired)
    }

    func testFlatBaselineDoesNotFireOnTinyNoise() {
        var detector = FocusFadeDetector(
            baselineSamples: 5,
            cooldownSeconds: 0,
            sampleInterval: 0,
            minStd: 0.05
        )
        // Identical samples → σ ≈ 0; without a floor, any epsilon above mean would fire.
        for i in 0..<5 {
            let fired = detector.ingestForced(
                now: TimeInterval(i),
                hrBpm: 60,
                arousal: 0.8,
                motionEnergy: 0.05
            )
            XCTAssertFalse(fired)
        }
        XCTAssertTrue(detector.isBaselineReady)
        guard let threshold = detector.fadeThreshold, let mean = detector.baselineMean else {
            return XCTFail("baseline missing")
        }
        // Floor keeps threshold meaningfully above mean (2 × 0.05).
        XCTAssertGreaterThanOrEqual(threshold - mean, 0.099)

        // Tiny score bump still below floor-based threshold.
        let tiny = detector.ingestForced(
            now: 10,
            hrBpm: 61,
            arousal: 0.79,
            motionEnergy: 0.06
        )
        XCTAssertFalse(tiny)

        // Real spike still fires.
        let spike = detector.ingestForced(
            now: 20,
            hrBpm: 95,
            arousal: 0.05,
            motionEnergy: 0.9
        )
        XCTAssertTrue(spike)
    }
}
