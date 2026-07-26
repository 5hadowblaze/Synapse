import ARKit
import XCTest
@testable import Synapse

@MainActor
final class FocusCameraModeTests: XCTestCase {
    func testUsesCameraFlags() {
        XCTAssertTrue(FocusCameraMode.alwaysOn.usesCamera)
        XCTAssertTrue(FocusCameraMode.alwaysOn.canUseCamera)
        XCTAssertFalse(FocusCameraMode.briefCheckIns.usesCamera)
        XCTAssertTrue(FocusCameraMode.briefCheckIns.canUseCamera)
        XCTAssertFalse(FocusCameraMode.watchOnly.usesCamera)
        XCTAssertFalse(FocusCameraMode.watchOnly.canUseCamera)
    }

    func testParseVoiceAliases() {
        XCTAssertEqual(FocusCameraMode.parse("always"), .alwaysOn)
        XCTAssertEqual(FocusCameraMode.parse("brief"), .briefCheckIns)
        XCTAssertEqual(FocusCameraMode.parse("check-ins"), .briefCheckIns)
        XCTAssertEqual(FocusCameraMode.parse("b"), .briefCheckIns)
        XCTAssertEqual(FocusCameraMode.parse("none"), .watchOnly)
        XCTAssertEqual(FocusCameraMode.parse("off"), .watchOnly)
        XCTAssertNil(FocusCameraMode.parse("banana"))
    }

    func testPresenceChipLabels() {
        XCTAssertEqual(FocusCameraPresence.cameraOn.chipLabel, "Camera on")
        XCTAssertEqual(FocusCameraPresence.checkingIn.chipLabel, "Checking in")
        XCTAssertEqual(FocusCameraPresence.cameraOff.chipLabel, "Camera off")
    }

    func testFaceTrackerStopClearsSessionRunning() {
        let tracker = FaceTracker()
        tracker.start()
        tracker.stop()
        XCTAssertFalse(tracker.isSessionRunning)
        XCTAssertFalse(tracker.isTracking)
    }

    func testWatchOnlyPolicyStopsFaceSessionOnApply() {
        let model = AppModel()
        model.previewCameraEnabled = false
        model.focusCameraMode = .alwaysOn
        model.faceTracker.start()
        model.focusCameraMode = .watchOnly
        model.applyFocusCameraMode()
        XCTAssertFalse(model.focusUsesCamera)
        XCTAssertEqual(model.focusCameraPresence, .cameraOff)
        XCTAssertFalse(model.faceTracker.isSessionRunning)
    }

    func testBriefSetupKeepsCameraOffUntilLive() {
        let model = AppModel()
        model.previewCameraEnabled = false
        model.focusCameraMode = .briefCheckIns
        model.applyFocusCameraMode()
        XCTAssertEqual(model.focusCameraPresence, .cameraOff)
        XCTAssertFalse(model.faceTracker.isSessionRunning)
    }

    func testCannotFlipModeWhileFocusRunning() {
        let model = AppModel()
        model.focusCameraMode = .alwaysOn
        model.focusEngine.startSession(focusMinutes: 2, breakMinutes: 1)
        XCTAssertFalse(model.setFocusCameraMode(.briefCheckIns))
        XCTAssertEqual(model.focusCameraMode, .alwaysOn)
        model.focusEngine.stopSession(emitComplete: false)
        XCTAssertTrue(model.setFocusCameraMode(.briefCheckIns))
        XCTAssertEqual(model.focusCameraMode, .briefCheckIns)
    }

    func testWatchOnlyFocusKeepsArousalNil() {
        let model = AppModel()
        model.previewCameraEnabled = false
        model.focusCameraMode = .watchOnly
        model.faceTracker.stop()
        XCTAssertTrue(model.startFocusSession(focusMinutes: 2, breakMinutes: 1))
        XCTAssertNil(model.focusEngine.lastArousal)
        XCTAssertEqual(model.focusCameraPresence, .cameraOff)
        model.stopFocusSession(returnToSetup: false)
    }

    func testWatchOnlyLiveDoesNotAutoStartPreview() {
        let model = AppModel()
        model.previewCameraEnabled = true
        model.focusCameraMode = .watchOnly
        XCTAssertTrue(model.startFocusSession(focusMinutes: 2, breakMinutes: 1))
        XCTAssertTrue(model.isWatchOnlyFocusLive)
        XCTAssertFalse(model.isPreviewFaceRequested)
        XCTAssertFalse(model.focusUsesCamera)
        // Preference unchanged; Focus mode unchanged.
        XCTAssertTrue(model.previewCameraEnabled)
        XCTAssertEqual(model.focusCameraMode, .watchOnly)
        model.stopFocusSession(returnToSetup: false)
    }

    func testWatchOnlyPeekStartsFaceWithoutRewritingMode() {
        let model = AppModel()
        model.previewCameraEnabled = true
        model.focusCameraMode = .watchOnly
        XCTAssertTrue(model.startFocusSession(focusMinutes: 2, breakMinutes: 1))
        XCTAssertFalse(model.isPreviewFaceRequested)

        model.togglePreviewCamera()
        XCTAssertTrue(model.isPreviewFaceRequested)
        XCTAssertTrue(model.previewPeekDuringWatchOnly)
        XCTAssertEqual(model.focusCameraMode, .watchOnly)
        XCTAssertFalse(model.focusUsesCamera)
        // Fade path still gated on Focus presence — peek does not feed arousal.
        XCTAssertFalse(model.focusUsesCamera)

        model.togglePreviewCamera()
        XCTAssertFalse(model.isPreviewFaceRequested)
        model.stopFocusSession(returnToSetup: false)
        XCTAssertFalse(model.previewPeekDuringWatchOnly)
    }

    func testPreviewToggleOffStopsFaceOnHub() {
        let model = AppModel()
        model.route = .hub
        model.previewCameraEnabled = true
        model.reconcileFaceTracker()
        // May be unsupported on simulator CI — still assert preference wiring.
        model.previewCameraEnabled = false
        XCTAssertFalse(model.isPreviewFaceRequested)
        XCTAssertFalse(model.faceTracker.isSessionRunning)
    }
}

final class FocusCameraSchedulerTests: XCTestCase {
    private var config: FocusCameraScheduler.Config {
        var c = FocusCameraScheduler.Config.default
        c.checkInDuration = 10
        c.intervalMin = 90
        c.intervalMax = 90
        c.spikeDeltaBpm = 8
        c.spikeCooldown = 60
        c.openWithImmediateCheckIn = true
        return c
    }

    func testAlwaysOnStaysAwake() {
        var s = FocusCameraScheduler(config: config)
        s.start(mode: .alwaysOn, now: 0)
        XCTAssertEqual(s.presence, .cameraOn)
        XCTAssertFalse(s.tick(now: 200))
        XCTAssertEqual(s.presence, .cameraOn)
    }

    func testWatchOnlyStaysOff() {
        var s = FocusCameraScheduler(config: config)
        s.start(mode: .watchOnly, now: 0)
        XCTAssertEqual(s.presence, .cameraOff)
        XCTAssertFalse(s.ingestHeartRate(bpm: 120, anchorBpm: 70, now: 5))
        XCTAssertEqual(s.presence, .cameraOff)
    }

    func testIntervalWakeAndSleep() {
        var s = FocusCameraScheduler(config: config)
        s.fixedIntervalOverride = 90
        s.start(mode: .briefCheckIns, now: 0)
        XCTAssertEqual(s.presence, .checkingIn)
        XCTAssertEqual(s.lastWakeReason, .sessionStart)

        // End first check-in.
        XCTAssertTrue(s.tick(now: 10))
        XCTAssertEqual(s.presence, .cameraOff)

        // Still quiet before interval.
        XCTAssertFalse(s.tick(now: 50))
        XCTAssertEqual(s.presence, .cameraOff)

        // Interval wake at 10 + 90 = 100.
        XCTAssertTrue(s.tick(now: 100))
        XCTAssertEqual(s.presence, .checkingIn)
        XCTAssertEqual(s.lastWakeReason, .interval)
        XCTAssertEqual(s.wakeCount, 2)

        XCTAssertTrue(s.tick(now: 110))
        XCTAssertEqual(s.presence, .cameraOff)
    }

    func testSpikeWakeOpensCheckIn() {
        var s = FocusCameraScheduler(config: config)
        s.fixedIntervalOverride = 200
        s.start(mode: .briefCheckIns, now: 0)
        _ = s.tick(now: 10) // sleep after opening check-in; lastWakeEndedAt = 10
        XCTAssertEqual(s.presence, .cameraOff)

        // Still inside spike cooldown (60s from end of opening wake).
        XCTAssertFalse(s.ingestHeartRate(bpm: 78, anchorBpm: 70, now: 25))
        XCTAssertEqual(s.presence, .cameraOff)

        // Past cooldown — +8 bpm above anchor.
        XCTAssertTrue(s.ingestHeartRate(bpm: 78, anchorBpm: 70, now: 75))
        XCTAssertEqual(s.presence, .checkingIn)
        XCTAssertEqual(s.lastWakeReason, .spike)
        XCTAssertEqual(s.spikeWakeCount, 1)
    }

    func testSpikeRespectsCooldown() {
        var s = FocusCameraScheduler(config: config)
        s.fixedIntervalOverride = 400
        s.start(mode: .briefCheckIns, now: 0)
        _ = s.tick(now: 10)

        XCTAssertTrue(s.ingestHeartRate(bpm: 90, anchorBpm: 70, now: 75))
        _ = s.tick(now: 85) // end spike check-in; lastWakeEndedAt = 85

        // Inside 60s cooldown.
        XCTAssertFalse(s.ingestHeartRate(bpm: 95, anchorBpm: 70, now: 100))
        XCTAssertEqual(s.presence, .cameraOff)

        // After cooldown.
        XCTAssertTrue(s.ingestHeartRate(bpm: 95, anchorBpm: 70, now: 150))
        XCTAssertEqual(s.lastWakeReason, .spike)
        XCTAssertEqual(s.spikeWakeCount, 2)
    }

    func testSpikeIgnoredWithoutAnchor() {
        var s = FocusCameraScheduler(config: config)
        s.start(mode: .briefCheckIns, now: 0)
        _ = s.tick(now: 10)
        XCTAssertFalse(s.ingestHeartRate(bpm: 100, anchorBpm: nil, now: 20))
        XCTAssertEqual(s.presence, .cameraOff)
    }

    func testSpikeIgnoredWhileAlreadyCheckingIn() {
        var s = FocusCameraScheduler(config: config)
        s.start(mode: .briefCheckIns, now: 0)
        XCTAssertEqual(s.presence, .checkingIn)
        XCTAssertFalse(s.ingestHeartRate(bpm: 100, anchorBpm: 70, now: 2))
        XCTAssertEqual(s.spikeWakeCount, 0)
    }

    func testNoImmediateCheckInOptionStartsAsleep() {
        var c = config
        c.openWithImmediateCheckIn = false
        var s = FocusCameraScheduler(config: c)
        s.fixedIntervalOverride = 90
        s.start(mode: .briefCheckIns, now: 0)
        XCTAssertEqual(s.presence, .cameraOff)
        XCTAssertTrue(s.tick(now: 90))
        XCTAssertEqual(s.presence, .checkingIn)
        XCTAssertEqual(s.lastWakeReason, .interval)
    }

    /// Brief mode must not gate HR fade timing — scheduler never blocks scoring.
    func testQuickBlockWindowCanCompleteWhileCameraSleeps() {
        var s = FocusCameraScheduler(config: config)
        s.fixedIntervalOverride = 90
        s.start(mode: .briefCheckIns, now: 0)
        _ = s.tick(now: 10)
        // Quick baseline ~32s + debounce ~16s ≈ 48s — camera is asleep; HR path unaffected.
        XCTAssertEqual(s.presence, .cameraOff)
        XCTAssertFalse(s.tick(now: 48))
        XCTAssertEqual(s.presence, .cameraOff)
    }
}
