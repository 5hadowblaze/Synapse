import XCTest
@testable import Synapse

/// Fade detection over realistic inputs.
///
/// `arousal` here is the raw ARKit `eyeWide` blendshape. On a real face it rests near 0 and
/// moves by hundredths — earlier versions of this suite swung it 0.8 → 0.05, roughly 25× more
/// than a face produces, which is how a permanently saturated arousal channel passed review.
/// Values below are kept in the range a TrueDepth camera actually reports.
final class FocusFadeDetectorTests: XCTestCase {
    /// A neutral face: `eyeWide` parked near zero with only blendshape jitter on top.
    private static let inertEyeWide: [Float] = [0.030, 0.032, 0.029, 0.031, 0.030, 0.032]
    /// A face whose lid aperture genuinely moves during the block.
    private static let liveEyeWide: [Float] = [0.08, 0.14, 0.10, 0.16, 0.09, 0.15]

    private func makeDetector(
        baselineSamples: Int = 6,
        cooldownSeconds: TimeInterval = 0,
        samplesToFire: Int = FocusFadeDetector.defaultSamplesToFire
    ) -> FocusFadeDetector {
        FocusFadeDetector(
            baselineSamples: baselineSamples,
            cooldownSeconds: cooldownSeconds,
            sampleInterval: 0,
            samplesToFire: samplesToFire
        )
    }

    /// Fills the baseline window, asserting nothing fires while calibrating.
    private func calibrate(
        _ detector: inout FocusFadeDetector,
        hr: [Double],
        eyeWide: [Float],
        motion: Double? = 0.05,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (index, bpm) in hr.enumerated() {
            let fired = detector.ingestForced(
                now: TimeInterval(index),
                hrBpm: bpm,
                arousal: eyeWide[index % eyeWide.count],
                motionEnergy: motion
            )
            XCTAssertFalse(fired, "calibration must not fire", file: file, line: line)
        }
    }

    // MARK: - Baseline and firing

    func testBaselineThenFiresOnSustainedHrRise() {
        var detector = makeDetector()
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.inertEyeWide)
        XCTAssertTrue(detector.isBaselineReady)
        XCTAssertEqual(detector.fadeCount, 0)

        // Sustained rise: first sample arms the debounce, the second fires.
        XCTAssertFalse(detector.ingestForced(now: 10, hrBpm: 95, arousal: 0.030, motionEnergy: 0.9))
        XCTAssertTrue(detector.ingestForced(now: 18, hrBpm: 95, arousal: 0.030, motionEnergy: 0.9))
        XCTAssertEqual(detector.fadeCount, 1)
    }

    func testWorksWithoutMotionEnergy() {
        var detector = makeDetector()
        calibrate(
            &detector,
            hr: Array(repeating: 60, count: 6),
            eyeWide: Self.inertEyeWide,
            motion: nil
        )
        XCTAssertFalse(detector.ingestForced(now: 10, hrBpm: 90, arousal: 0.030, motionEnergy: nil))
        XCTAssertTrue(detector.ingestForced(now: 18, hrBpm: 90, arousal: 0.030, motionEnergy: nil))
    }

    func testCooldownSuppressesRapidRefire() {
        var detector = makeDetector(cooldownSeconds: 60)
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.inertEyeWide)

        _ = detector.ingestForced(now: 20, hrBpm: 100, arousal: 0.030, motionEnergy: 1.0)
        XCTAssertTrue(detector.ingestForced(now: 28, hrBpm: 100, arousal: 0.030, motionEnergy: 1.0))

        // Within cooldown, even though the signal stays over threshold.
        _ = detector.ingestForced(now: 36, hrBpm: 100, arousal: 0.030, motionEnergy: 1.0)
        XCTAssertFalse(detector.ingestForced(now: 44, hrBpm: 100, arousal: 0.030, motionEnergy: 1.0))

        // After cooldown, sustained fade re-fires immediately — the debounce stayed armed.
        XCTAssertTrue(detector.ingestForced(now: 120, hrBpm: 100, arousal: 0.030, motionEnergy: 1.0))
        XCTAssertEqual(detector.fadeCount, 2)
    }

    func testFlatBaselineDoesNotFireOnTinyNoise() {
        var detector = makeDetector()
        calibrate(&detector, hr: Array(repeating: 60, count: 6), eyeWide: Self.inertEyeWide)

        guard let threshold = detector.fadeThreshold, let mean = detector.baselineMean else {
            return XCTFail("baseline missing")
        }
        XCTAssertGreaterThanOrEqual(threshold - mean, 0.099, "σ floor must survive a flat window")

        // A 1 bpm wobble is not a fade, however many samples it lasts.
        for i in 0..<4 {
            XCTAssertFalse(
                detector.ingestForced(
                    now: TimeInterval(10 + i * 8),
                    hrBpm: 61,
                    arousal: 0.031,
                    motionEnergy: 0.06
                )
            )
        }
    }

    // MARK: - Debounce (FIX 2)

    func testSingleSpikeDoesNotFire() {
        var detector = makeDetector()
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.inertEyeWide)

        // One sample well over threshold — standing up, reaching for coffee.
        XCTAssertFalse(detector.ingestForced(now: 10, hrBpm: 105, arousal: 0.030, motionEnergy: 1.0))
        XCTAssertEqual(detector.fadeCount, 0, "a transient spike is a false catch, not an early one")
    }

    func testInterruptedExceedanceResetsTheDebounce() {
        var detector = makeDetector()
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.inertEyeWide)

        XCTAssertFalse(detector.ingestForced(now: 10, hrBpm: 105, arousal: 0.030, motionEnergy: 1.0))
        // Back to baseline — the run is broken.
        XCTAssertFalse(detector.ingestForced(now: 18, hrBpm: 62, arousal: 0.030, motionEnergy: 0.05))
        // A single high sample again must still not fire.
        XCTAssertFalse(detector.ingestForced(now: 26, hrBpm: 105, arousal: 0.030, motionEnergy: 1.0))
        XCTAssertTrue(detector.ingestForced(now: 34, hrBpm: 105, arousal: 0.030, motionEnergy: 1.0))
        XCTAssertEqual(detector.fadeCount, 1)
    }

    func testSustainedFadeStillSurvivesTheDebounce() {
        var detector = makeDetector()
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.inertEyeWide)

        var fired = false
        for i in 0..<4 where !fired {
            fired = detector.ingestForced(
                now: TimeInterval(10 + i * 8),
                hrBpm: 80,
                arousal: 0.030,
                motionEnergy: 0.5
            )
        }
        XCTAssertTrue(fired, "a real, sustained rise must still be caught")
    }

    func testDebounceIsConfigurableAndOneMeansImmediate() {
        var detector = makeDetector(samplesToFire: 1)
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.inertEyeWide)
        XCTAssertTrue(detector.ingestForced(now: 10, hrBpm: 95, arousal: 0.030, motionEnergy: 0.9))
    }

    // MARK: - HR anchor (FIX 1)

    func testWarmStartAnchorRecoversSensitivity() {
        var detector = makeDetector()
        // Sat down still warm from walking: HR decays for longer than the baseline window.
        let decay: [Double] = [98, 92, 87, 83, 80, 78, 76, 75, 74, 73, 72, 72]
        for (index, bpm) in decay.enumerated() {
            _ = detector.ingestForced(
                now: TimeInterval(index),
                hrBpm: bpm,
                arousal: Self.inertEyeWide[index % Self.inertEyeWide.count],
                motionEnergy: 0.05
            )
        }
        XCTAssertTrue(detector.isBaselineReady, "calibration must not be deferred forever")

        // Settle at rest so the anchor can track down onto the real resting HR.
        for i in 0..<8 {
            _ = detector.ingestForced(
                now: TimeInterval(20 + i * 8),
                hrBpm: 72,
                arousal: 0.030,
                motionEnergy: 0.05
            )
        }
        guard let anchor = detector.currentHrAnchor else { return XCTFail("no anchor") }
        XCTAssertLessThanOrEqual(anchor, 73, "anchor must follow HR down to the settled rest")

        // A modest rise above the settled rest now registers. The single-first-sample anchor
        // needed ~+30 bpm here, which made the whole session numb.
        XCTAssertFalse(detector.ingestForced(now: 200, hrBpm: 78, arousal: 0.030, motionEnergy: 0.05))
        XCTAssertTrue(detector.ingestForced(now: 208, hrBpm: 78, arousal: 0.030, motionEnergy: 0.05))
    }

    func testSettlingDownDoesNotItselfFire() {
        var detector = makeDetector()
        let decay: [Double] = [98, 92, 87, 83, 80, 78, 76, 75, 74, 73, 72, 72]
        for (index, bpm) in decay.enumerated() {
            _ = detector.ingestForced(
                now: TimeInterval(index),
                hrBpm: bpm,
                arousal: Self.inertEyeWide[index % Self.inertEyeWide.count],
                motionEnergy: 0.05
            )
        }
        // Anchor descent restores headroom; it must never read as fade on its own.
        for i in 0..<12 {
            XCTAssertFalse(
                detector.ingestForced(
                    now: TimeInterval(20 + i * 8),
                    hrBpm: 70,
                    arousal: 0.030,
                    motionEnergy: 0.05
                ),
                "calming down is not fading"
            )
        }
    }

    func testAnchorUsesTheWindowMedianNotTheFirstSample() {
        var detector = makeDetector()
        // One high opening reading followed by a settled block.
        calibrate(&detector, hr: [96, 64, 63, 64, 62, 63], eyeWide: Self.inertEyeWide)
        guard let anchor = detector.currentHrAnchor else { return XCTFail("no anchor") }
        XCTAssertEqual(anchor, 63.5, accuracy: 0.01, "one stray opening beat must not set the anchor")
    }

    func testHrBelowAnchorIsInformativeRatherThanClamped() {
        var detector = makeDetector()
        // Oscillating, not trending — a steady decline is a settling user, not a baseline.
        calibrate(&detector, hr: [66, 58, 62, 66, 58, 62], eyeWide: Self.inertEyeWide)
        // Half the median-anchored window sits below the anchor. With a hard clamp at 0 those
        // samples collapse onto one value and σ collapses with them.
        guard let std = detector.baselineStd else { return XCTFail("no σ") }
        XCTAssertGreaterThan(std, FocusFadeDetector.defaultMinStd, "σ must reflect real HR spread")
    }

    // MARK: - Arousal channel (FIX 3)

    func testInertEyeWideDropsTheArousalChannel() {
        var detector = makeDetector()
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.inertEyeWide)
        XCTAssertEqual(detector.isArousalChannelActive, false)
        guard let spread = detector.arousalBaselineSpread else { return XCTFail("no spread") }
        XCTAssertLessThan(spread, FocusFadeDetector.arousalNoiseFloor)
    }

    func testLiveEyeWideActivatesTheArousalChannel() {
        var detector = makeDetector()
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.liveEyeWide)
        XCTAssertEqual(detector.isArousalChannelActive, true)
        guard let spread = detector.arousalBaselineSpread else { return XCTFail("no spread") }
        XCTAssertGreaterThanOrEqual(spread, FocusFadeDetector.arousalNoiseFloor)
    }

    /// Regression guard: a saturated absolute term (`1 − eyeWide` on a face that rests near 0)
    /// parked the baseline near 0.40, almost all of it constant. Terms now rest at 0.
    func testSaturatedArousalCannotParkTheBaseline() {
        var detector = makeDetector()
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.inertEyeWide)
        guard let mean = detector.baselineMean else { return XCTFail("no baseline") }
        XCTAssertLessThan(mean, 0.15, "an inert channel must contribute nothing, not a constant")
    }

    func testNoiseFloorStopsJitterBeingAmplified() {
        var detector = makeDetector()
        // σ ≈ 0.0008 — pure blendshape quantisation. Z-scoring this would turn a 0.002 wobble
        // into a full-scale arousal term.
        calibrate(
            &detector,
            hr: Array(repeating: 62, count: 6),
            eyeWide: [0.0300, 0.0308, 0.0296, 0.0304, 0.0300, 0.0308]
        )
        XCTAssertEqual(detector.isArousalChannelActive, false)

        // An eyeWide collapse that would be many σ of "fade" if the channel were live.
        for i in 0..<4 {
            XCTAssertFalse(
                detector.ingestForced(
                    now: TimeInterval(10 + i * 8),
                    hrBpm: 62,
                    arousal: 0.0,
                    motionEnergy: 0.05
                ),
                "a disabled channel must not drive the score"
            )
        }
    }

    func testLidDroopBelowBaselineDrivesFadeWhenChannelIsLive() {
        var detector = makeDetector()
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.liveEyeWide)
        XCTAssertEqual(detector.isArousalChannelActive, true)

        // Lids settle well below their own baseline while HR and motion hold steady.
        var fired = false
        for i in 0..<4 where !fired {
            fired = detector.ingestForced(
                now: TimeInterval(10 + i * 8),
                hrBpm: 62,
                arousal: 0.03,
                motionEnergy: 0.05
            )
        }
        XCTAssertTrue(fired, "a real droop relative to this face's own baseline is fade evidence")
    }

    func testWideningEyesCannotSuppressAnHrFade() {
        var detector = makeDetector()
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.liveEyeWide)

        // Above-baseline eyeWide clamps the arousal term at 0 rather than going negative, so it
        // can withhold evidence but never cancel another channel's.
        var fired = false
        for i in 0..<4 where !fired {
            fired = detector.ingestForced(
                now: TimeInterval(10 + i * 8),
                hrBpm: 100,
                arousal: 0.40,
                motionEnergy: 0.9
            )
        }
        XCTAssertTrue(fired)
    }

    func testMissingFaceDropsArousalRatherThanInventingANeutralValue() {
        var detector = makeDetector()
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.liveEyeWide)

        // Face lost: nil arousal must not inject a constant into the composite.
        _ = detector.ingestForced(now: 10, hrBpm: 62, arousal: nil, motionEnergy: 0.05)
        guard let score = detector.lastScore, let threshold = detector.fadeThreshold else {
            return XCTFail("no score")
        }
        XCTAssertLessThan(score, threshold)
    }

    // MARK: - Score scale

    func testEasingThresholdSitsBetweenBaselineAndFade() {
        var detector = makeDetector()
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.inertEyeWide)
        guard let mean = detector.baselineMean,
              let easing = detector.easingThreshold,
              let fade = detector.fadeThreshold
        else { return XCTFail("baseline missing") }
        XCTAssertGreaterThan(easing, mean)
        XCTAssertLessThan(easing, fade, "the middle state has to be reachable before a break")
    }

    func testFadeProgressReachesOneAtTheThreshold() {
        var detector = makeDetector()
        calibrate(&detector, hr: Array(repeating: 62, count: 6), eyeWide: Self.inertEyeWide)
        _ = detector.ingestForced(now: 10, hrBpm: 62, arousal: 0.030, motionEnergy: 0.05)
        guard let calm = detector.fadeProgress else { return XCTFail("no progress") }
        XCTAssertLessThan(calm, 0.5, "sitting at baseline is not halfway to a break")

        _ = detector.ingestForced(now: 18, hrBpm: 110, arousal: 0.030, motionEnergy: 1.0)
        guard let faded = detector.fadeProgress else { return XCTFail("no progress") }
        XCTAssertGreaterThanOrEqual(faded, 1.0)
    }

    /// The composite must stay on one scale whether or not a channel is contributing, otherwise
    /// any absolute reader of `fadeScore` means different things in different sessions.
    func testRestingScoreIsNearZeroWhicheverChannelsAreLive() {
        for eyeWide in [Self.inertEyeWide, Self.liveEyeWide] {
            for motion in [0.05, nil] as [Double?] {
                var detector = makeDetector()
                calibrate(
                    &detector,
                    hr: Array(repeating: 62, count: 6),
                    eyeWide: eyeWide,
                    motion: motion
                )
                _ = detector.ingestForced(
                    now: 10,
                    hrBpm: 62,
                    arousal: eyeWide[1],
                    motionEnergy: motion
                )
                guard let score = detector.lastScore else { return XCTFail("no score") }
                XCTAssertLessThan(score, 0.35, "resting score must not be parked by a constant")
            }
        }
    }
}
