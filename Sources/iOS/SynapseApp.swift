import SwiftUI

enum AppRoute: Equatable {
    case hub
    case visionSetup
    case visionLive
    /// Production Kinetic: cinematic front preview + 3D Batak clock.
    case kineticMainSetup
    case kineticMainLive
    /// Settings → Debug Kinetic (today’s mesh / arm / 2D clock UI).
    case kineticDebugSetup
    case kineticDebugLive
    case focusSetup
    case focusLive
    case focusBreak
    case focusRecap
}

enum KineticUIMode: Equatable {
    case main
    case debug
}

@Observable
@MainActor
final class AppModel {
    let phoneSession = PhoneSessionManager()
    let faceTracker = FaceTracker()
    let gazeMapper = GazeScreenMapper()
    let visionEngine = VisionPVTEngine()
    let kineticEngine = KineticClockEngine()
    let focusEngine = FocusEngine()
    let breathingCoach = BreathingCoach()
    let patternStore = FocusPatternStore()
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
    var showSettings = false
    /// Which Kinetic surface is active (main vs debug) for start/stop routing.
    private(set) var kineticUIMode: KineticUIMode = .main
    /// Last Focus recap (shown on focusRecap).
    var lastFocusRecap: FocusRecap?
    var selectedFocusPreset: FocusPreset = .standard
    /// Wall-clock start of the current Focus block (for pattern hour).
    private(set) var focusSessionStartedAt: Date?
    /// Show Lock-in CTA after a completed breathing reset.
    var showLockInTenCTA = false
    /// Floating voice assistant (Apple STT → OpenAI Realtime tools → ElevenLabs).
    let voiceAssistant = VoiceAssistantController()

    private static let kineticArmSideKey = "synapse.kineticArmSide"
    private static let showFaceMeshOnMainKey = "synapse.showFaceMeshOnMain"

    /// Athlete arm for Kinetic overlay + camera pointing (persisted). Default: right.
    var kineticArmSide: KineticArmSide = {
        if let raw = UserDefaults.standard.string(forKey: "synapse.kineticArmSide"),
           let side = KineticArmSide(rawValue: raw) {
            return side
        }
        return .right
    }() {
        didSet {
            guard oldValue != kineticArmSide else { return }
            UserDefaults.standard.set(kineticArmSide.rawValue, forKey: Self.kineticArmSideKey)
            faceTracker.setPreferredArmSide(kineticArmSide)
        }
    }

    /// Low-opacity face mesh on main Kinetic (persisted). Full white mesh stays in Debug.
    var showFaceMeshOnMain: Bool = UserDefaults.standard.object(forKey: "synapse.showFaceMeshOnMain") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showFaceMeshOnMain, forKey: Self.showFaceMeshOnMainKey)
        }
    }

    /// Spoke highlight — prefer front-camera arm; Watch is optional fallback.
    var kineticPreviewOctant: Int? {
        faceTracker.armOctant ?? watchLiveOctant ?? phoneSession.lastLiveOctant
    }

    /// Watch is reachable for strike timestamps (not required for spoke lighting).
    var isWatchConnected: Bool {
        phoneSession.isReachable
    }

    var isKineticRoute: Bool {
        switch route {
        case .kineticMainSetup, .kineticMainLive, .kineticDebugSetup, .kineticDebugLive:
            return true
        default:
            return false
        }
    }

    var isKineticLiveRoute: Bool {
        route == .kineticMainLive || route == .kineticDebugLive
    }

    var isFocusRoute: Bool {
        switch route {
        case .focusSetup, .focusLive, .focusBreak, .focusRecap:
            return true
        default:
            return false
        }
    }

    func bootstrap() {
        wireCallbacks()
        voiceAssistant.attach(to: self)
        faceTracker.setPreferredArmSide(kineticArmSide)
        faceTracker.start()
        breathingCoach.onComplete = { [weak self] in
            guard let self else { return }
            self.showLockInTenCTA = true
            self.hudMessage = "Reset complete · lock in 10?"
            // Natural complete left the break paused for breathing — resume so the timer continues.
            if self.focusEngine.phase == .onBreak, self.focusEngine.isPaused {
                self.focusEngine.resume()
            }
        }
    }

    // MARK: - Hub

    /// Stop Focus/breathing before leaving so fade/break/complete callbacks cannot hijack another module.
    private func stopFocusBeforeRouteChange() {
        breathingCoach.stop()
        showLockInTenCTA = false
        stopFocusSession(returnToSetup: false)
    }

    func openVision() {
        stopFocusBeforeRouteChange()
        faceTracker.setArmPoseEnabled(false)
        faceTracker.ensureStarted()
        route = .visionSetup
        hudMessage = "Vision PVT"
        voiceAssistant.handleRouteChange(route)
    }

    /// Production Kinetic (cinematic Batak clock).
    func openKinetic() {
        stopFocusBeforeRouteChange()
        kineticUIMode = .main
        faceTracker.ensureStarted()
        faceTracker.setArmPoseEnabled(true)
        phoneSession.sendLiveDirectionStart()
        route = .kineticMainSetup
        hudMessage = isWatchConnected
            ? "Punch the lit pad · Watch for strikes"
            : "Punch the lit pad · connect Watch for strikes"
        voiceAssistant.handleRouteChange(route)
    }

    /// Settings → Debug Kinetic (unchanged mesh / arm / 2D clock UI).
    func openKineticDebug() {
        stopFocusBeforeRouteChange()
        showSettings = false
        kineticUIMode = .debug
        faceTracker.ensureStarted()
        faceTracker.setArmPoseEnabled(true)
        phoneSession.sendLiveDirectionStart()
        route = .kineticDebugSetup
        hudMessage = isWatchConnected
            ? "Debug · face + arm · Watch for strikes"
            : "Debug · face + arm · Watch optional for strikes"
        voiceAssistant.handleRouteChange(route)
    }

    func openFocus() {
        stopFocusBeforeRouteChange()
        faceTracker.setArmPoseEnabled(false)
        faceTracker.ensureStarted()
        phoneSession.sendLiveDirectionStop()
        route = .focusSetup
        hudMessage = "Focus · health-aware Pomodoro"
        voiceAssistant.handleRouteChange(route)
    }

    func returnToHub() {
        visionEngine.stopSession()
        kineticEngine.stopSession()
        breathingCoach.stop()
        showLockInTenCTA = false
        stopFocusSession(returnToSetup: false)
        phoneSession.sendLiveDirectionStop()
        phoneSession.sendMotionEnergyStop()
        watchLiveOctant = nil
        faceTracker.setArmPoseEnabled(false)
        faceTracker.ensureStarted()
        route = .hub
        hudMessage = "Synapse"
        voiceAssistant.handleRouteChange(route)
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
        voiceAssistant.handleRouteChange(route)
        voiceAssistant.notifySessionStarted(module: "Vision PVT")
    }

    func stopVisionSession() {
        visionEngine.stopSession()
        writer.completeSession()
        route = .visionSetup
        hudMessage = "Vision stopped"
        voiceAssistant.handleRouteChange(route)
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
        route = kineticUIMode == .debug ? .kineticDebugLive : .kineticMainLive
        hudMessage = "Kinetic live"
        voiceAssistant.handleRouteChange(route)
        voiceAssistant.notifySessionStarted(module: "Kinetic Clock")
    }

    func stopKineticSession() {
        kineticEngine.stopSession()
        writer.completeSession()
        faceTracker.setArmPoseEnabled(true)
        phoneSession.sendLiveDirectionStart()
        route = kineticUIMode == .debug ? .kineticDebugSetup : .kineticMainSetup
        hudMessage = kineticUIMode == .debug
            ? "Kinetic stopped · camera arm lights spokes"
            : "Kinetic stopped · air-punch the lit pad"
        voiceAssistant.handleRouteChange(route)
    }

    // MARK: - Focus (desk Pomodoro)

    /// Starts Focus. Returns `false` if a session is already live (no restart / no orphaned Firestore write).
    @discardableResult
    func startFocusSession(focusMinutes: Int? = nil, breakMinutes: Int? = nil) -> Bool {
        if focusEngine.isRunning {
            hudMessage = "Focus already live"
            return false
        }
        breathingCoach.stop()
        showLockInTenCTA = false
        faceTracker.setArmPoseEnabled(false)
        faceTracker.ensureStarted()
        faceTracker.resetDetectors()
        phoneSession.sendLiveDirectionStop()
        phoneSession.sendMotionEnergyStart()

        let focus = focusMinutes ?? selectedFocusPreset.focusMinutes
        let brk = breakMinutes ?? selectedFocusPreset.breakMinutes
        focusEngine.configure(focusMinutes: focus, breakMinutes: brk)

        _ = writer.startSession(
            athleteId: athleteId,
            module: .focusDesk,
            clockOffsetMs: phoneSession.lastSyncOffsetMs,
            clockRttMs: phoneSession.lastSyncRttMs
        )
        lastFocusRecap = nil
        focusSessionStartedAt = Date()
        focusEngine.startSession(focusMinutes: focus, breakMinutes: brk)
        if let bpm = phoneSession.lastHeartRateBpm {
            focusEngine.ingestHeartRate(bpm)
        }
        route = .focusLive
        hudMessage = "Focus live"
        voiceAssistant.handleRouteChange(route)
        voiceAssistant.notifySessionStarted(module: "Focus")
        return true
    }

    func stopFocusSession(returnToSetup: Bool = true) {
        breathingCoach.stop()
        showLockInTenCTA = false
        phoneSession.sendMotionEnergyStop()
        if focusEngine.isRunning || focusEngine.phase == .complete {
            // Suppress recap when leaving to hub / setup cancel.
            focusEngine.onComplete = nil
            focusEngine.stopSession(emitComplete: false)
            writer.completeSession()
            wireFocusCallbacks()
        }
        if returnToSetup {
            route = .focusSetup
            hudMessage = "Focus stopped"
            voiceAssistant.handleRouteChange(route)
        }
    }

    /// Ends a live Focus block into recap. No-ops if nothing is running (avoids fake-zero recaps).
    @discardableResult
    func endFocusToRecap() -> Bool {
        breathingCoach.stop()
        showLockInTenCTA = false
        phoneSession.sendMotionEnergyStop()
        guard focusEngine.isRunning else {
            hudMessage = "No focus session"
            return false
        }
        focusEngine.stopSession(emitComplete: true)
        return true
    }

    func acceptFocusBreak() {
        focusEngine.startBreak()
    }

    func skipFocusBreak() {
        breathingCoach.stop()
        focusEngine.skipBreak()
    }

    func extendFocusBlock() {
        breathingCoach.stop()
        showLockInTenCTA = false
        let wasBreak = focusEngine.phase == .onBreak
        if focusEngine.extendFocus() {
            if wasBreak || route == .focusBreak {
                route = .focusLive
                voiceAssistant.handleRouteChange(route)
            }
            hudMessage = "Extended +5m"
        }
    }

    func pauseFocus() {
        focusEngine.pause()
        hudMessage = "Paused"
    }

    func resumeFocus() {
        focusEngine.resume()
        hudMessage = focusEngine.phase == .onBreak ? "Break" : "Focus live"
    }

    /// ElevenLabs-guided inhale/hold/exhale on the break screen (~2–3 min).
    func startBreathingReset() {
        if focusEngine.phase == .focusing || focusEngine.phase == .breakSuggested {
            acceptFocusBreak()
        }
        guard focusEngine.phase == .onBreak || route == .focusBreak else { return }
        route = .focusBreak
        showLockInTenCTA = false
        focusEngine.pause()
        voiceAssistant.cancel()
        breathingCoach.start()
        hudMessage = "Breathing reset"
    }

    func stopBreathingReset() {
        breathingCoach.stop()
        if focusEngine.phase == .onBreak, focusEngine.isPaused {
            focusEngine.resume()
        }
    }

    /// Finish current Focus stats, then start a fresh 10-minute block.
    func lockInTenMinutes() {
        breathingCoach.stop()
        showLockInTenCTA = false
        if focusEngine.isRunning {
            focusEngine.onComplete = nil
            focusEngine.stopSession(emitComplete: false)
            let recap = focusEngine.makeRecap()
            let started = focusSessionStartedAt ?? Date()
            patternStore.record(recap: recap, startedAt: started)
            writer.writeFocusRecap(recap)
            writer.completeSession()
            wireFocusCallbacks()
        }
        startFocusSession(focusMinutes: 10, breakMinutes: 5)
        hudMessage = "Locked in · 10 min"
    }

    func finishFocusToRecap(_ recap: FocusRecap) {
        breathingCoach.stop()
        showLockInTenCTA = false
        lastFocusRecap = recap
        let started = focusSessionStartedAt ?? Date()
        patternStore.record(recap: recap, startedAt: started)
        writer.writeFocusRecap(recap)
        writer.completeSession()
        phoneSession.sendMotionEnergyStop()
        route = .focusRecap
        hudMessage = "Focus complete"
        voiceAssistant.handleRouteChange(route)
        let hr = recap.meanHrBpm.map { String(format: "%.0f bpm mean HR", $0) } ?? "no HR"
        voiceAssistant.notifySessionComplete(
            summary: "Focus done. \(recap.focusedMinutesLabel) focused, \(recap.fadeCount) fades, \(hr)."
        )
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
            // Spatial: prefer camera arm octant, then Watch strike octant, then live aim.
            let spatial = self.faceTracker.armOctant
                ?? event.detectedOctant
                ?? self.watchLiveOctant
                ?? self.phoneSession.lastLiveOctant
            let enriched = StrikeEvent(
                watchTimestamp: event.watchTimestamp,
                peakG: event.peakG,
                phoneTimestamp: event.phoneTimestamp,
                detectedOctant: spatial
            )
            self.lastDetectedOctant = spatial
            if self.kineticEngine.isRunning {
                self.kineticEngine.ingestStrike(enriched)
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

        phoneSession.onHeartRate = { [weak self] event in
            guard let self else { return }
            self.writer.updateHeartRate(event)
            if self.focusEngine.isRunning {
                self.focusEngine.ingestHeartRate(event.bpm)
            }
            if self.route == .hub || self.isKineticRoute {
                // Soft HUD — don't clobber trial result lines during live kinetic scoring.
                if !self.isKineticLiveRoute || self.hudMessage.hasPrefix("HR") || self.hudMessage == "Kinetic live" {
                    self.hudMessage = String(format: "HR %.0f bpm", event.bpm)
                }
            }
        }

        phoneSession.onMotionEnergy = { [weak self] energy in
            guard let self, self.focusEngine.isRunning else { return }
            self.focusEngine.ingestMotionEnergy(energy)
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
            if self.focusEngine.isRunning, let arousal = self.faceTracker.lastArousal {
                self.focusEngine.ingestArousal(arousal)
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
            self.route = self.kineticUIMode == .debug ? .kineticDebugSetup : .kineticMainSetup
            let acc = self.kineticEngine.spatialAccuracyPercent.map { String(format: "%.0f%%", $0) } ?? "—"
            self.hudMessage = "Kinetic complete · spatial \(acc)"
            self.voiceAssistant.handleRouteChange(self.route)
            self.voiceAssistant.notifySessionComplete(
                summary: "Kinetic complete. Spatial accuracy \(acc)."
            )
        }

        wireFocusCallbacks()
    }

    private func wireFocusCallbacks() {
        focusEngine.onFadeSuggested = { [weak self] in
            guard let self else { return }
            self.phoneSession.sendBreakPointHaptic()
            self.hudMessage = "Fade · take a break?"
            self.voiceAssistant.notifyFocusFade()
        }

        focusEngine.onBreakStarted = { [weak self] in
            guard let self else { return }
            self.phoneSession.sendBreakPointHaptic()
            if self.route != .focusBreak {
                self.route = .focusBreak
                self.voiceAssistant.handleRouteChange(self.route)
                self.voiceAssistant.notifyFocusBreakStarted()
            }
            self.hudMessage = "Break"
        }

        focusEngine.onComplete = { [weak self] recap in
            self?.finishFocusToRecap(recap)
        }

        focusEngine.onEpoch = { [weak self] epoch in
            self?.writer.writeFocusEpoch(epoch)
        }

        focusEngine.onBaselineReady = { [weak self] mean, std in
            self?.writer.writeBaseline(meanMs: mean, stdMs: std)
        }
    }

    private func flashBreakPoint(trial: Int) {
        showBreakPointFlash = true
        hudMessage = "BREAK-POINT · trial \(trial + 1)"
        voiceAssistant.notifyBreakPoint(trial: trial)
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
