import SwiftUI

enum AppRoute: Equatable {
    case hub
    case visionSetup
    case visionLive
    case kineticSetup
    case kineticLive
}

@Observable
@MainActor
final class AppModel {
    let phoneSession = PhoneSessionManager()
    let faceTracker = FaceTracker()
    let gazeMapper = GazeScreenMapper()
    let visionEngine = VisionPVTEngine()
    let kineticEngine = KineticClockEngine()
    let writer = SessionWriter()

    var athleteId = "athlete-1"
    var hudMessage = "Synapse"
    var showBreakPointFlash = false
    var route: AppRoute = .hub
    var lastDetectedOctant: Int?
    var isWatchCalibrating = false
    /// True after a successful Calibrate Watch on this phone session.
    var watchIMUCalibrated = false
    /// Live Watch pointing octant (optional corroboration / strike spatial).
    var watchLiveOctant: Int?

    /// Spoke highlight — prefer front-camera arm; Watch is optional fallback.
    var kineticPreviewOctant: Int? {
        faceTracker.armOctant ?? watchLiveOctant ?? phoneSession.lastLiveOctant
    }

    /// Watch is reachable for strike timestamps (not required for spoke lighting).
    var isWatchConnected: Bool {
        phoneSession.isReachable
    }

    func bootstrap() {
        wireCallbacks()
        faceTracker.start()
    }

    // MARK: - Hub

    func openVision() {
        faceTracker.setArmPoseEnabled(false)
        faceTracker.ensureStarted()
        route = .visionSetup
        hudMessage = "Vision PVT"
    }

    func openKinetic() {
        faceTracker.ensureStarted()
        faceTracker.setArmPoseEnabled(true)
        phoneSession.sendLiveDirectionStart()
        route = .kineticSetup
        hudMessage = isWatchConnected
            ? "Face + arm camera · Watch for strikes"
            : "Face + arm camera · Watch optional for strikes"
    }

    func returnToHub() {
        visionEngine.stopSession()
        kineticEngine.stopSession()
        phoneSession.sendLiveDirectionStop()
        watchLiveOctant = nil
        faceTracker.setArmPoseEnabled(false)
        faceTracker.ensureStarted()
        route = .hub
        hudMessage = "Synapse"
    }

    // MARK: - Vision PVT

    func startVisionSession() {
        faceTracker.setArmPoseEnabled(false)
        faceTracker.ensureStarted()
        _ = writer.startSession(
            athleteId: athleteId,
            module: .visionPvt,
            clockOffsetMs: phoneSession.lastSyncOffsetMs,
            clockRttMs: phoneSession.lastSyncRttMs
        )
        faceTracker.resetDetectors()
        visionEngine.startSession()
        route = .visionLive
        hudMessage = "Vision live"
    }

    func stopVisionSession() {
        visionEngine.stopSession()
        writer.completeSession()
        route = .visionSetup
        hudMessage = "Vision stopped"
    }

    func calibrateGaze() {
        guard let lookAt = faceTracker.latestGaze?.lookAt else {
            hudMessage = "Calibrate needs face"
            return
        }
        gazeMapper.calibrateToCenter(lookAt: lookAt)
        hudMessage = "Gaze calibrated"
    }

    // MARK: - Kinetic Clock

    func calibrateWatch() {
        isWatchCalibrating = true
        watchIMUCalibrated = false
        phoneSession.sendCalibrateStart(durationSeconds: 10)
        hudMessage = "Watch calibrating 10s — face phone, arms neutral"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard self.isWatchCalibrating else { return }
            // No ACK from Watch — do not falsely mark success.
            self.isWatchCalibrating = false
            self.hudMessage = "Watch calibrate timed out — retry"
        }
    }

    func startKineticSession() {
        faceTracker.ensureStarted()
        faceTracker.setArmPoseEnabled(true)
        phoneSession.sendLiveDirectionStart()
        _ = writer.startSession(
            athleteId: athleteId,
            module: .kineticClock,
            clockOffsetMs: phoneSession.lastSyncOffsetMs,
            clockRttMs: phoneSession.lastSyncRttMs
        )
        kineticEngine.startSession()
        route = .kineticLive
        hudMessage = "Kinetic live"
    }

    func stopKineticSession() {
        kineticEngine.stopSession()
        writer.completeSession()
        faceTracker.setArmPoseEnabled(true)
        phoneSession.sendLiveDirectionStart()
        route = .kineticSetup
        hudMessage = "Kinetic stopped · camera arm lights spokes"
    }

    func runCannedReplay() {
        let canned = CannedSessionFactory.makeDemo()
        writer.ingestCannedSession(canned)
        hudMessage = "Canned replay → \(writer.sessionId ?? "?")"
        if canned.breakPointTrial != nil {
            flashBreakPoint(trial: canned.breakPointTrial ?? 0)
            phoneSession.sendBreakPointHaptic()
        }
    }

    private func wireCallbacks() {
        phoneSession.onStrike = { [weak self] event in
            guard let self else { return }
            self.lastDetectedOctant = event.detectedOctant
            if self.kineticEngine.isRunning {
                self.kineticEngine.ingestStrike(event)
            }
        }

        phoneSession.onLiveDirection = { [weak self] octant in
            guard let self else { return }
            self.watchLiveOctant = octant
            self.watchIMUCalibrated = true
        }

        phoneSession.onCalibrateResult = { [weak self] success in
            guard let self else { return }
            self.isWatchCalibrating = false
            self.watchIMUCalibrated = success
            if success {
                self.phoneSession.sendLiveDirectionStart()
                self.hudMessage = "Watch calibrate done — strikes use IMU"
            } else {
                self.hudMessage = "Watch calibrate failed — retry"
            }
        }

        phoneSession.onSyncQuality = { [weak self] offsetMs, rttMs in
            self?.writer.updateClockQuality(offsetMs: offsetMs, rttMs: rttMs)
        }

        faceTracker.onGaze = { [weak self] sample in
            guard let self else { return }
            self.gazeMapper.update(lookAt: sample.lookAt)
            if self.visionEngine.isRunning {
                self.visionEngine.ingestGaze(sample)
                if let saccade = self.faceTracker.lastSaccade {
                    self.visionEngine.ingestSaccade(saccade)
                }
                if let arousal = self.faceTracker.lastArousal {
                    self.visionEngine.ingestArousal(arousal)
                }
            }
        }

        visionEngine.onTrialCompleted = { [weak self] trial, gaze, t0 in
            guard let self else { return }
            self.writer.writeTrial(trial, gaze: gaze, t0Ms: t0)
            self.hudMessage = trial.valid
                ? String(format: "Visual RT %.0f ms", trial.visualRtMs ?? 0)
                : "Invalid: \(trial.invalidReason ?? "?")"
        }

        visionEngine.onBaselineReady = { [weak self] mean, std in
            self?.writer.writeBaseline(meanMs: mean, stdMs: std)
        }

        visionEngine.onBreakPoint = { [weak self] index, mean, std in
            guard let self else { return }
            self.writer.writeBreakPoint(
                trialIndex: index,
                baselineGapMs: mean,
                baselineStdMs: std
            )
            self.phoneSession.sendBreakPointHaptic()
            self.flashBreakPoint(trial: index)
        }

        kineticEngine.onTrialCompleted = { [weak self] trial in
            guard let self else { return }
            self.writer.writeTrial(trial)
            let target = trial.targetOctant.flatMap { ClockOctant(rawValue: $0)?.label } ?? "?"
            let detected = trial.detectedOctant.flatMap { ClockOctant(rawValue: $0)?.label } ?? "—"
            let match = trial.spatialMatch == true ? "match" : "miss"
            if let motor = trial.motorRtMs {
                self.hudMessage = String(
                    format: "Target: %@ · Detected: %@ · %@ · %.0f ms",
                    target, detected, match, motor
                )
            } else {
                self.hudMessage = "Target: \(target) · Detected: \(detected) · \(match)"
            }
        }

        kineticEngine.onBaselineReady = { [weak self] mean, std in
            self?.writer.writeBaseline(meanMs: mean, stdMs: std)
        }

        kineticEngine.onBreakPoint = { [weak self] index, mean, std in
            guard let self else { return }
            self.writer.writeBreakPoint(
                trialIndex: index,
                baselineGapMs: mean,
                baselineStdMs: std
            )
            self.phoneSession.sendBreakPointHaptic()
            self.flashBreakPoint(trial: index)
        }

        kineticEngine.onSessionComplete = { [weak self] in
            guard let self else { return }
            self.writer.completeSession()
            self.faceTracker.setArmPoseEnabled(true)
            self.phoneSession.sendLiveDirectionStart()
            self.route = .kineticSetup
            let acc = self.kineticEngine.spatialAccuracyPercent.map { String(format: "%.0f%%", $0) } ?? "—"
            self.hudMessage = "Kinetic complete · spatial \(acc)"
        }
    }

    private func flashBreakPoint(trial: Int) {
        showBreakPointFlash = true
        hudMessage = "BREAK-POINT · trial \(trial + 1)"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showBreakPointFlash = false
        }
    }
}

@main
struct SynapseApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear { model.bootstrap() }
        }
    }
}
