import XCTest
@testable import Synapse

/// Preset shape (Task: no "Demo 2 / 1" on the shipping picker) and the three-state HUD read.
@MainActor
final class FocusPresetAndSignalTests: XCTestCase {
    // MARK: - Presets

    func testShippingPickerHasNoDemoPreset() {
        XCTAssertFalse(FocusPreset.all.contains(FocusPreset.demo))
        XCTAssertTrue(FocusPreset.allIncludingDemo.contains(FocusPreset.demo))
    }

    func testQuickPresetIsTheShortBaselineOptionOnThePicker() {
        XCTAssertTrue(FocusPreset.all.contains(FocusPreset.quick))
        XCTAssertTrue(FocusPreset.quick.calibratesFast)
        XCTAssertEqual(FocusPreset.quick.baselineSamples, FocusFadeDetector.quickBaselineSamples)
        // Baseline has to land well inside the block, not after it.
        XCTAssertLessThan(FocusPreset.quick.baselineSeconds, FocusPreset.quick.focusMinutes * 60)
    }

    func testStandardPresetsKeepTheFullBaseline() {
        for preset in [FocusPreset.standard, .short, .deep] {
            XCTAssertEqual(preset.baselineSamples, FocusFadeDetector.defaultBaselineSamples, preset.name)
            XCTAssertFalse(preset.calibratesFast, preset.name)
        }
    }

    func testPresetTitleIsDerivedFromMinutes() {
        XCTAssertEqual(FocusPreset.standard.title, "25 / 5")
        XCTAssertEqual(FocusPreset.quick.title, "5 / 1")
        XCTAssertEqual(FocusPreset.demo.name, "Demo")
    }

    func testInferredBaselineShortensForShortBlocks() {
        XCTAssertEqual(
            FocusEngine.inferredBaselineSamples(focusMinutes: 2),
            FocusFadeDetector.quickBaselineSamples
        )
        XCTAssertEqual(
            FocusEngine.inferredBaselineSamples(focusMinutes: 5),
            FocusFadeDetector.quickBaselineSamples
        )
        XCTAssertEqual(
            FocusEngine.inferredBaselineSamples(focusMinutes: 25),
            FocusFadeDetector.defaultBaselineSamples
        )
    }

    func testConfiguringWithAPresetCarriesItsBaseline() {
        let engine = FocusEngine()
        engine.configure(preset: .quick)
        XCTAssertEqual(engine.baselineSamples, FocusFadeDetector.quickBaselineSamples)
        engine.configure(preset: .deep)
        XCTAssertEqual(engine.baselineSamples, FocusFadeDetector.defaultBaselineSamples)
    }

    func testQuickBlockReachesBaselineFromFewSamples() {
        var detector = FocusFadeDetector(
            baselineSamples: FocusPreset.quick.baselineSamples,
            cooldownSeconds: 0,
            sampleInterval: 0
        )
        for i in 0..<FocusPreset.quick.baselineSamples {
            _ = detector.ingestForced(now: TimeInterval(i), hrBpm: 62, arousal: 0.8, motionEnergy: 0.1)
        }
        XCTAssertTrue(detector.isBaselineReady)
        XCTAssertEqual(detector.baselineProgress, 1)
        // Two consecutive samples: fade fires on a sustained rise, not a single spike.
        _ = detector.ingestForced(now: 40, hrBpm: 98, arousal: 0.03, motionEnergy: 0.95)
        XCTAssertTrue(detector.ingestForced(now: 48, hrBpm: 98, arousal: 0.03, motionEnergy: 0.95))
    }

    /// The point of the short presets: everything standing between starting the block and
    /// a fade has to fit inside it, or the moment they exist to show can never happen.
    /// Worst case is the window filling, calibration deferring for a full extra window
    /// while heart rate settles, then the debounce waiting for consecutive exceedances.
    func testShortPresetsCanStillFadeInsideTheirOwnWindow() {
        for preset in [FocusPreset.quick, .demo] {
            let samples = preset.baselineSamples * 2 + FocusFadeDetector.defaultSamplesToFire
            let seconds = Double(samples) * FocusFadeDetector.defaultSampleIntervalSeconds
            let block = Double(preset.focusMinutes) * 60
            XCTAssertLessThan(seconds, block, preset.name)
            XCTAssertGreaterThanOrEqual(
                block - seconds,
                30,
                "\(preset.name) needs headroom to actually show the fade, not just reach it"
            )
        }
    }

    func testBaselineProgressClimbsWhileCalibrating() {
        var detector = FocusFadeDetector(baselineSamples: 4, cooldownSeconds: 0, sampleInterval: 0)
        XCTAssertEqual(detector.baselineProgress, 0)
        _ = detector.ingestForced(now: 0, hrBpm: 60, arousal: 0.8, motionEnergy: 0.1)
        _ = detector.ingestForced(now: 1, hrBpm: 60, arousal: 0.8, motionEnergy: 0.1)
        XCTAssertEqual(detector.baselineProgress, 0.5, accuracy: 0.001)
        XCTAssertFalse(detector.isBaselineReady)
    }

    // MARK: - Three-state HUD

    func testStateIsSteadyBeforeTheBaselineExists() {
        let engine = FocusEngine()
        engine.startSession(focusMinutes: 5, breakMinutes: 1)
        engine.fadeScore = 0.9
        engine.baselineReady = false
        XCTAssertEqual(engine.signalState, .steady, "no baseline means no claim about fading")
        engine.stopSession(emitComplete: false)
    }

    func testStateIsSteadyBelowTheEasingThreshold() {
        let engine = FocusEngine()
        engine.startSession(focusMinutes: 5, breakMinutes: 1)
        engine.baselineReady = true
        engine.fadeEasingThreshold = 0.05
        engine.fadeScore = 0.05
        XCTAssertEqual(engine.signalState, .steady)
        engine.stopSession(emitComplete: false)
    }

    func testStateEasesOffAboveTheThresholdBeforeAnyBreakRequest() {
        let engine = FocusEngine()
        engine.startSession(focusMinutes: 5, breakMinutes: 1)
        engine.baselineReady = true
        engine.fadeEasingThreshold = 0.05
        engine.fadeScore = 0.075
        XCTAssertEqual(engine.signalState, .easing)
        XCTAssertFalse(engine.fadeSuggested, "the middle state must not imply a break was requested")
        engine.stopSession(emitComplete: false)
    }

    /// A raw score has no fixed meaning any more — without a session threshold to compare
    /// against, the HUD must not guess that a big-looking number means fading.
    func testStateStaysSteadyWithoutASessionThreshold() {
        let engine = FocusEngine()
        engine.startSession(focusMinutes: 5, breakMinutes: 1)
        engine.baselineReady = true
        engine.fadeEasingThreshold = nil
        engine.fadeScore = 0.9
        XCTAssertEqual(engine.signalState, .steady)
        engine.stopSession(emitComplete: false)
    }

    /// The one that matters: all three states reachable in a single session, driven by a
    /// real detector rather than by poking `fadeScore`. Guards the regression where a
    /// fixed easing threshold sat above the fade threshold and `easing` was skipped.
    func testAllThreeStatesAreReachableInOneSession() {
        let engine = FocusEngine()
        engine.startSession(
            focusMinutes: 5,
            breakMinutes: 1,
            baselineSamples: 4,
            fadeDetector: FocusFadeDetector(
                baselineSamples: 4,
                cooldownSeconds: 0,
                sampleInterval: 0
            )
        )

        // Heart rate is the only live channel, so the composite is the HR term outright.
        // A flat 60 bpm calibrates to mean 0, which puts the fade threshold at 2 × minStd.
        for _ in 0..<4 { engine.ingestHeartRate(60) }
        XCTAssertTrue(engine.baselineReady)
        XCTAssertEqual(engine.signalState, .steady)

        guard let easing = engine.fadeEasingThreshold else {
            return XCTFail("a calibrated session must publish an easing threshold")
        }
        XCTAssertEqual(easing, 0.05, accuracy: 0.0001)
        XCTAssertEqual(engine.fadeProgress ?? -1, 0, accuracy: 0.0001)

        // Halfway between baseline and threshold: an observation, not a break request.
        engine.ingestHeartRate(61.5)
        XCTAssertEqual(engine.signalState, .easing)
        XCTAssertFalse(engine.fadeSuggested)
        XCTAssertGreaterThan(
            engine.fadeProgress ?? 0,
            0.5,
            "the ring is past half exactly when the label says easing"
        )

        // Sustained rise past the threshold, held long enough to clear the debounce.
        engine.ingestHeartRate(65)
        XCTAssertEqual(engine.signalState, .easing, "one spike is not a fade")
        engine.ingestHeartRate(65)
        XCTAssertEqual(engine.signalState, .breakSuggested)
        XCTAssertTrue(engine.fadeSuggested)

        engine.stopSession(emitComplete: false)
    }

    /// Escalation order has to hold on the session's own scale, or a state gets skipped.
    func testEasingThresholdSitsBelowTheFadeThreshold() {
        let engine = FocusEngine()
        engine.startSession(
            focusMinutes: 5,
            breakMinutes: 1,
            baselineSamples: 4,
            fadeDetector: FocusFadeDetector(
                baselineSamples: 4,
                cooldownSeconds: 0,
                sampleInterval: 0
            )
        )
        for _ in 0..<4 { engine.ingestHeartRate(60) }

        guard let easing = engine.fadeEasingThreshold else {
            return XCTFail("missing easing threshold")
        }
        // A score at the fade threshold must already have read as easing on the way up.
        engine.fadeScore = easing + 0.0001
        XCTAssertEqual(engine.signalState, .easing)
        engine.stopSession(emitComplete: false)
    }

    // MARK: - Calibration pre-roll

    /// Calibration can defer while heart rate is still settling, so the window is no
    /// longer a fixed length. The pre-roll must never claim 100% during that wait — and
    /// must never stall there either.
    func testDeferredCalibrationHoldsShortOfCompleteThenFinishes() {
        let engine = FocusEngine()
        engine.startSession(
            focusMinutes: 5,
            breakMinutes: 1,
            baselineSamples: 4,
            fadeDetector: FocusFadeDetector(
                baselineSamples: 4,
                cooldownSeconds: 0,
                sampleInterval: 0
            )
        )

        // A window that is still trending down is a warm start, not a baseline.
        for hr in [80.0, 78.0, 70.0, 68.0] { engine.ingestHeartRate(hr) }
        XCTAssertFalse(engine.baselineReady)
        XCTAssertTrue(engine.isSettlingBaseline, "window is full, detector is holding out")
        XCTAssertLessThan(engine.baselineProgress, 1, "must not read 100% while deferred")
        XCTAssertGreaterThan(engine.baselineProgress, 0.9, "and must not read as barely started")

        // The wait is capped at one extra window, so this always resolves.
        for _ in 0..<8 where !engine.baselineReady { engine.ingestHeartRate(60) }
        XCTAssertTrue(engine.baselineReady)
        XCTAssertFalse(engine.isSettlingBaseline)
        XCTAssertEqual(engine.baselineProgress, 1)
        engine.stopSession(emitComplete: false)
    }

    func testPreRollReportsPartialProgressBeforeTheWindowIsFull() {
        let engine = FocusEngine()
        engine.startSession(
            focusMinutes: 5,
            breakMinutes: 1,
            baselineSamples: 4,
            fadeDetector: FocusFadeDetector(
                baselineSamples: 4,
                cooldownSeconds: 0,
                sampleInterval: 0
            )
        )
        engine.ingestHeartRate(60)
        engine.ingestHeartRate(60)
        XCTAssertEqual(engine.baselineProgress, 0.5, accuracy: 0.001)
        XCTAssertFalse(engine.isSettlingBaseline, "still filling, not yet waiting on settle")
        engine.stopSession(emitComplete: false)
    }

    // MARK: - Stale arousal

    func testLosingTheFaceClearsArousalRatherThanHoldingIt() {
        let engine = FocusEngine()
        engine.startSession(focusMinutes: 5, breakMinutes: 1)

        engine.ingestArousal(0.42)
        XCTAssertEqual(engine.lastArousal ?? 0, 0.42, accuracy: 0.0001)

        engine.ingestArousal(nil)
        XCTAssertNil(engine.lastArousal, "a lost face must not leave a stale reading behind")
        engine.stopSession(emitComplete: false)
    }

    /// If the face anchor is dropped the gaze callback stops firing, so the nil never
    /// arrives. The value has to age out on its own.
    func testArousalAgesOutWhenGazeUpdatesStopArriving() {
        let engine = FocusEngine()
        engine.startSession(focusMinutes: 5, breakMinutes: 1)
        engine.ingestArousal(0.42)

        let now = ProcessInfo.processInfo.systemUptime
        engine.expireStaleArousal(now: now + FocusEngine.arousalStaleAfter / 2)
        XCTAssertNotNil(engine.lastArousal, "a fresh reading must survive")

        engine.expireStaleArousal(now: now + FocusEngine.arousalStaleAfter + 1)
        XCTAssertNil(engine.lastArousal)
        engine.stopSession(emitComplete: false)
    }

    func testFadeSuggestionOutranksTheScore() {
        let engine = FocusEngine()
        engine.startSession(focusMinutes: 5, breakMinutes: 1)
        engine.baselineReady = true
        engine.fadeScore = 0.1
        engine.noteFadeSuggested()
        XCTAssertEqual(engine.signalState, .breakSuggested)
        engine.dismissFadeSuggestion()
        XCTAssertEqual(engine.signalState, .steady)
        engine.stopSession(emitComplete: false)
    }
}
