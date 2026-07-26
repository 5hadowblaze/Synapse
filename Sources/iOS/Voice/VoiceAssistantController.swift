import Foundation
import Observation

enum VoiceAssistantPhase: Equatable {
    case idle
    case connecting
    case listening
    case thinking
    case speaking
    case error
}

/// Facade for ElevenLabs Conversational Agent — Clawd pet, proactive lines, breath, reflect.
@Observable
@MainActor
final class VoiceAssistantController {
    private(set) var phase: VoiceAssistantPhase = .idle
    private(set) var transcriptSnippet = ""
    private(set) var lastError: String?
    private(set) var lastSpoken = ""
    private(set) var isReflecting = false
    private(set) var checkInSummary: String?
    /// True after a successful reflect check-in write (or explicit skip).
    private(set) var checkInResolved = false
    /// True while a proactive nudge is waking Clawd during Focus live (taps still ignored until idle ends).
    private(set) var isAwakeForNudge = false

    private weak var model: AppModel?
    private let session = ElevenLabsAgentSession()
    private var proactiveTask: Task<Void, Never>?
    private var lastProactiveKey: String?
    private var lastRoute: AppRoute?
    private var sessionTask: Task<Void, Never>?

    var isConfigured: Bool { VoiceConfig.isConfigured }

    /// Soft offline — recap still works; talk-through disabled in UI when false.
    var isVoiceOnline: Bool { isConfigured }

    /// During Focus live, user taps are ignored while asleep (Clawd stays quiet).
    var isFocusQuiet: Bool {
        model?.route == .focusLive
    }

    func attach(to model: AppModel) {
        self.model = model
        lastRoute = model.route
        session.onPhaseChange = { [weak self] phase in
            self?.phase = phase
        }
        session.onTranscript = { [weak self] text in
            self?.transcriptSnippet = text
        }
        session.onAgentText = { [weak self] text in
            self?.lastSpoken = text
            self?.transcriptSnippet = text
        }
        session.onError = { [weak self] message in
            self?.lastError = message
            self?.phase = .error
        }
        session.onEnded = { [weak self] in
            guard let self else { return }
            if self.isReflecting {
                // Agent ended without end_reflection — treat as soft leave.
                self.isReflecting = false
            }
            self.isAwakeForNudge = false
            if self.phase != .error {
                self.phase = .idle
            }
        }
        session.onToolCall = { [weak self] name, args in
            await self?.executeTool(name: name, arguments: args) ?? #"{"ok":false}"#
        }
    }

    func handleRouteChange(_ route: AppRoute) {
        guard route != lastRoute else { return }
        lastRoute = route
        // Hard disconnect during measurement + Focus live — an open agent session
        // keeps asking "are you still there" even when Clawd looks asleep.
        if route == .focusReactionCheck || route == .focusLive {
            cancel()
            return
        }
        switch route {
        case .focusSetup:
            speakProactive(
                key: "setup-focus",
                text: "Focus mode. Pick a duration, face the phone, and start when you're ready. I'll stay quiet while you work."
            )
        case .visionSetup:
            speakProactive(
                key: "setup-vision",
                text: "Vision PVT. Fixate the center pad, calibrate gaze, then start — flashes appear in the outer cells."
            )
        case .postureSetup:
            speakProactive(
                key: "setup-posture",
                text: "Posture check. Sit tall with shoulders relaxed, then start. I'll learn your baseline and nudge if you drift."
            )
        case .kineticMainSetup, .kineticDebugSetup:
            let watch = model?.isWatchConnected == true
            let tip = watch
                ? "Kinetic Clock. Calibrate the Watch if needed, then start. Air-punch toward the lit pad — no screen taps."
                : "Kinetic Clock. Connect your Apple Watch so punches register, then start."
            speakProactive(key: "setup-kinetic-\(route)", text: tip)
        default:
            break
        }
    }

    func notifySessionStarted(module: String) {
        // Focus live must stay fully silent after start — no countdown session
        // that can linger and ask "are you still there."
        if module == "Focus" { return }
        // Don't interrupt setup explanations — let in-flight proactive lines finish.
        speakProactive(
            key: "start-\(module)-\(Int(Date().timeIntervalSince1970))",
            text: "Starting \(module). Three, two, one — go."
        )
    }

    func notifySessionComplete(summary: String) {
        speakProactive(key: "complete-\(summary)", text: summary, interrupt: true)
    }

    func notifyBreakPoint(trial: Int) {
        speakProactive(
            key: "bp-\(trial)",
            text: "Break-point at trial \(trial + 1). You're drifting off baseline — ease up and re-center.",
            interrupt: true
        )
    }

    func notifyFocusFade() {
        speakProactive(
            key: "focus-fade-\(Int(Date().timeIntervalSince1970))",
            text: "Your body is asking for a pause. Take a short break when you're ready.",
            interrupt: true
        )
    }

    /// Focus (and Lab) — spoken once while sit-tall baseline samples are collecting.
    func notifyPostureBaselineCollecting() {
        // Must play fully — never cut off an in-flight setup / start line.
        speakProactive(
            key: "posture-baseline-collect-\(Int(Date().timeIntervalSince1970))",
            text: "Sit tall while I learn your posture baseline."
        )
    }

    func notifyPostureBaselineSet() {
        speakProactive(
            key: "posture-baseline-\(Int(Date().timeIntervalSince1970))",
            text: "Baseline set. I'll watch your posture quietly from here."
        )
    }

    func notifyPostureDrift() {
        // Soft stack: if another proactive line is speaking or pending, skip — don't nag-cut.
        speakProactive(
            key: "posture-\(Int(Date().timeIntervalSince1970))",
            text: "Your posture is a bit off — can you sit back up straight?"
        )
    }

    func notifyFocusBreakStarted() {
        speakProactive(
            key: "focus-break-\(Int(Date().timeIntervalSince1970))",
            text: "Break time. Soften your gaze and reset.",
            interrupt: true
        )
    }

    /// Tap Clawd: wake + listen, or sleep if already awake.
    /// During Focus live while idle, taps are ignored (quiet coach) — nudges wake via speakProactive.
    func toggleListen() {
        if isFocusQuiet && (phase == .idle || phase == .error) && !isAwakeForNudge {
            return
        }
        if phase == .connecting || phase == .listening || phase == .thinking || phase == .speaking {
            cancel()
            return
        }
        guard phase == .idle || phase == .error else { return }
        startCoach()
    }

    func startCoach() {
        guard isConfigured else {
            phase = .error
            lastError = VoiceAssistantError.missingAgentID.localizedDescription
            return
        }
        lastError = nil
        isReflecting = false
        sessionTask?.cancel()
        sessionTask = Task { @MainActor in
            do {
                try await session.start(mode: .coach)
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .error
                lastError = error.localizedDescription
            }
        }
    }

    /// Break screen — agent guides breath; tools drive BreathingCoach phases.
    func startBreathMode() {
        guard isConfigured else {
            // UI still runs silent timed breath without voice.
            model?.breathingCoach.startLocalFallback()
            return
        }
        lastError = nil
        isReflecting = false
        sessionTask?.cancel()
        sessionTask = Task { @MainActor in
            do {
                model?.breathingCoach.prepareForAgent()
                try await session.start(
                    mode: .breath,
                    firstMessage: "Breathing reset. Soft gaze. We'll inhale, hold, and exhale together."
                )
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .error
                lastError = error.localizedDescription
                model?.breathingCoach.startLocalFallback()
            }
        }
    }

    /// Recap → Talk it through.
    func startReflectMode() {
        guard isConfigured else {
            phase = .error
            lastError = "Voice offline"
            return
        }
        lastError = nil
        isReflecting = true
        checkInResolved = false
        checkInSummary = nil
        sessionTask?.cancel()
        sessionTask = Task { @MainActor in
            do {
                try await session.start(
                    mode: .reflect,
                    firstMessage: "How did that block feel — in your body and in your head?"
                )
            } catch is CancellationError {
                isReflecting = false
                phase = .idle
            } catch {
                isReflecting = false
                phase = .error
                lastError = error.localizedDescription
            }
        }
    }

    /// Reset check-in UI state when a new Focus recap is shown.
    func resetCheckInState() {
        checkInResolved = false
        checkInSummary = nil
        isReflecting = false
    }

    func skipCheckIn() {
        guard let model else { return }
        if !checkInResolved {
            model.writer.writeFocusCheckIn(.skipped)
            checkInResolved = true
        }
        endReflection(returnToRecap: true)
    }

    func cancel() {
        sessionTask?.cancel()
        sessionTask = nil
        proactiveTask?.cancel()
        proactiveTask = nil
        isAwakeForNudge = false
        Task { @MainActor in
            await session.end()
        }
        if isReflecting {
            isReflecting = false
        }
        phase = .idle
    }

    // MARK: - Proactive (short agent utterance)

    private func speakProactive(key: String, text: String, interrupt: Bool = false) {
        if phase == .listening || phase == .thinking || phase == .connecting {
            return
        }
        guard key != lastProactiveKey else { return }
        lastProactiveKey = key
        guard isConfigured else { return }

        if interrupt {
            proactiveTask?.cancel()
            sessionTask?.cancel()
            Task { await session.end() }
        } else if phase == .speaking || session.isActive || proactiveTask != nil {
            // Let the current one-shot finish; posture/setup must not stack-cut.
            return
        }

        // Nudges (fade / break / posture) wake Clawd even during Focus quiet.
        let wakeDuringFocus = isFocusQuiet
        proactiveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: interrupt ? 150_000_000 : 350_000_000)
            guard !Task.isCancelled else { return }
            if self.phase == .listening || self.phase == .thinking { return }
            if wakeDuringFocus {
                self.isAwakeForNudge = true
            }
            do {
                try await self.session.speakLine(text, mode: .coach)
            } catch {
                // Soft fail — don't surface proactive errors on the pet.
            }
            self.isAwakeForNudge = false
            // Don't clear if we were cancelled/replaced by a higher-priority interrupt.
            guard !Task.isCancelled else { return }
            self.proactiveTask = nil
        }
    }

    private func endReflection(returnToRecap: Bool) {
        isReflecting = false
        Task { await session.end() }
        phase = .idle
        if returnToRecap {
            // Stay on focusRecap — UI dismisses reflect overlay via isReflecting.
        }
    }

    // MARK: - Tools

    private func executeTool(name: String, arguments: [String: Any]) async -> String {
        guard let model else {
            return #"{"ok":false,"error":"no app model"}"#
        }

        switch name {
        case "navigate_hub", "return_to_hub":
            model.returnToHub()
            return ok(["route": "hub"])

        case "open_vision":
            model.openVision()
            return ok(["route": "visionSetup"])

        case "open_kinetic":
            model.openKinetic()
            return ok(["route": "kineticMainSetup"])

        case "open_focus":
            model.openFocus()
            return ok(["route": "focusSetup"])

        case "open_posture":
            model.openPosture()
            return ok(["route": "postureSetup"])

        case "start_focus":
            if model.focusEngine.isRunning {
                return #"{"ok":false,"error":"already live"}"#
            }
            let focusMin = Self.intArg(arguments, "focusMinutes")
            let breakMin = Self.intArg(arguments, "breakMinutes")
            if let cameraRaw = Self.stringArg(arguments, "camera"),
               let mode = FocusCameraMode.parse(cameraRaw) {
                guard model.setFocusCameraMode(mode) else {
                    return #"{"ok":false,"error":"cannot change camera mid-block"}"#
                }
            }
            if model.route != .focusSetup && model.route != .focusRecap && !model.isFocusRoute {
                model.openFocus()
            }
            guard model.startFocusSession(focusMinutes: focusMin, breakMinutes: breakMin) else {
                return #"{"ok":false,"error":"already live"}"#
            }
            return ok([
                "started": "focus",
                "focusMinutes": model.focusEngine.focusMinutes,
                "breakMinutes": model.focusEngine.breakMinutes,
                "cameraMode": model.focusCameraMode.rawValue,
                "usesCamera": model.focusUsesCamera,
                "cameraPresence": model.focusCameraPresence.rawValue,
            ])

        case "set_camera_mode":
            guard let raw = Self.stringArg(arguments, "mode") ?? Self.stringArg(arguments, "camera"),
                  let mode = FocusCameraMode.parse(raw) else {
                return #"{"ok":false,"error":"mode must be always, brief, or none/watchOnly"}"#
            }
            guard model.setFocusCameraMode(mode) else {
                return #"{"ok":false,"error":"end focus to change camera mode"}"#
            }
            return ok([
                "cameraMode": mode.rawValue,
                "usesCamera": mode.canUseCamera,
                "presence": model.focusCameraPresence.rawValue,
                "honesty": mode.honestyLine,
            ])

        case "end_focus":
            guard model.endFocusToRecap() else {
                return #"{"ok":false,"error":"no focus session"}"#
            }
            return ok(["ended": "focus", "route": "focusRecap"])

        case "start_break":
            model.acceptFocusBreak()
            return ok(["break": true])

        case "skip_break":
            model.skipFocusBreak()
            return ok(["skippedBreak": true])

        case "extend_focus":
            let already = model.focusEngine.didExtend
            model.extendFocusBlock()
            return ok(["extended": model.focusEngine.didExtend, "wasAlreadyExtended": already])

        case "pause_focus":
            model.pauseFocus()
            return ok(["paused": true])

        case "resume_focus":
            model.resumeFocus()
            return ok(["resumed": true])

        case "get_focus_status":
            return focusStatusJSON(model)

        case "get_posture_status":
            return postureStatusJSON(model)

        case "get_kinetic_status":
            return kineticStatusJSON(model)

        case "get_vision_status":
            return visionStatusJSON(model)

        case "start_kinetic":
            return startKinetic(model)

        case "stop_kinetic":
            return stopKinetic(model)

        case "start_vision":
            return startVision(model)

        case "stop_vision":
            return stopVision(model)

        case "start_reaction_check":
            guard model.startStandaloneReactionCheck() else {
                return #"{"ok":false,"error":"end the focus block first"}"#
            }
            return ok(["started": "reactionCheck", "durationSeconds": 60])

        case "get_reaction_check":
            return reactionCheckJSON(model)

        case "start_breathing":
            let cycles = Self.intArg(arguments, "cycles")
            model.startBreathingReset(startAgent: false, cycles: cycles)
            return ok([
                "breathing": true,
                "running": model.breathingCoach.isRunning,
                "phase": model.breathingCoach.phaseLabel,
            ])

        case "set_breath_phase":
            guard let raw = Self.stringArg(arguments, "phase"),
                  let phase = BreathPhase.parse(raw) else {
                return #"{"ok":false,"error":"phase must be intro|inhale|hold|exhale|complete"}"#
            }
            let seconds = Self.doubleArg(arguments, "seconds")
            model.breathingCoach.applyAgentPhase(phase, seconds: seconds)
            return ok([
                "phase": model.breathingCoach.phaseLabel,
                "running": model.breathingCoach.isRunning,
                "remaining": model.breathingCoach.phaseRemaining,
            ])

        case "stop_breathing":
            model.stopBreathingReset()
            return ok(["stopped": true])

        case "lock_in_ten":
            model.lockInTenMinutes()
            return ok(["lockedIn": true, "focusMinutes": 10])

        case "submit_check_in":
            let payload = FocusCheckIn(
                skipped: false,
                feltEnergy: Self.intArg(arguments, "feltEnergy"),
                feltClarity: Self.intArg(arguments, "feltClarity"),
                nudgeMatched: Self.boolArg(arguments, "nudgeMatched"),
                wouldStopEarlier: Self.boolArg(arguments, "wouldStopEarlier"),
                summary: Self.stringArg(arguments, "summary")
            )
            model.writer.writeFocusCheckIn(payload)
            checkInSummary = payload.summary
            checkInResolved = true
            return ok(["saved": true])

        case "end_reflection":
            endReflection(returnToRecap: true)
            return ok(["ended": "reflection"])

        case "start_session":
            return startSession(model)

        case "stop_session":
            return stopSession(model)

        case "calibrate_watch":
            guard model.isWatchConnected else {
                return #"{"ok":false,"error":"watch not connected","watchConnected":false,"spokenHint":"Open the Synapse Watch app and keep the Watch unlocked near the phone."}"#
            }
            model.calibrateWatch()
            return ok([
                "action": "calibrate_watch",
                "watchConnected": true,
                "watchCalibrating": model.isWatchCalibrating,
                "spokenHint": "Hold still for about 10 seconds — arms neutral, face the phone.",
            ])

        case "calibrate_gaze":
            model.calibrateGaze()
            return ok([
                "action": "calibrate_gaze",
                "calibrated": model.gazeMapper.isCalibrated,
                "faceTracking": model.faceTracker.isTracking,
                "spokenHint": model.gazeMapper.isCalibrated
                    ? "Gaze calibrated — look soft at center."
                    : "Calibrate needs your face in frame — look at the phone center and try again.",
            ])

        case "get_status":
            return statusJSON(model)

        default:
            return #"{"ok":false,"error":"unknown tool"}"#
        }
    }

    private func startSession(_ model: AppModel) -> String {
        switch model.route {
        case .visionSetup:
            model.startVisionSession()
            return ok(["started": "vision"])
        case .postureSetup:
            model.startPostureSession()
            return ok(["started": "posture"])
        case .kineticMainSetup, .kineticDebugSetup:
            model.startKineticSession()
            return ok(["started": "kinetic"])
        case .focusSetup, .focusRecap:
            model.beginFocusFlow()
            return ok(["started": "focus"])
        case .visionLive, .kineticMainLive, .kineticDebugLive, .postureLive, .focusLive, .focusBreak:
            return #"{"ok":false,"error":"already live"}"#
        case .focusReactionCheck:
            return #"{"ok":false,"error":"reaction check running"}"#
        case .hub, .kineticRecap:
            return #"{"ok":false,"error":"open focus, vision, kinetic, or posture first"}"#
        }
    }

    private func stopSession(_ model: AppModel) -> String {
        switch model.route {
        case .visionLive:
            model.stopVisionSession()
            return ok(["stopped": "vision"])
        case .postureLive:
            model.stopPostureSession()
            return ok(["stopped": "posture"])
        case .kineticMainLive, .kineticDebugLive:
            model.stopKineticSession()
            return ok(["stopped": "kinetic"])
        case .focusLive, .focusBreak:
            model.stopFocusSession()
            return ok(["stopped": "focus"])
        case .focusReactionCheck:
            model.cancelReactionCheck()
            return ok(["stopped": "reactionCheck"])
        default:
            return #"{"ok":false,"error":"no live session"}"#
        }
    }

    private func startKinetic(_ model: AppModel) -> String {
        if model.isKineticLiveRoute || model.kineticEngine.isRunning {
            return #"{"ok":false,"error":"already live"}"#
        }
        if model.route == .kineticRecap {
            // Keep main vs debug mode from the session that just finished.
        } else if !model.isKineticRoute {
            model.openKinetic()
        }
        model.startKineticSession()
        return ok([
            "started": "kinetic",
            "route": String(describing: model.route),
            "watchConnected": model.isWatchConnected,
            "watchIMUCalibrated": model.watchIMUCalibrated,
            "spokenHint": model.isWatchConnected
                ? "Air-punch toward the lit pad — no screen taps."
                : "Watch not connected — punches may not register until the Watch app is open.",
        ])
    }

    private func stopKinetic(_ model: AppModel) -> String {
        guard model.isKineticLiveRoute || model.kineticEngine.isRunning else {
            return #"{"ok":false,"error":"no live kinetic session"}"#
        }
        model.stopKineticSession()
        var payload: [String: Any] = [
            "stopped": "kinetic",
            "route": String(describing: model.route),
        ]
        if let recap = model.lastKineticRecap {
            payload["trialCount"] = recap.trialCount
            if let acc = recap.spatialAccuracyPercent {
                payload["spatialAccuracyPercent"] = acc
            }
            if let median = recap.medianMotorRtMs { payload["medianMotorRtMs"] = median }
        }
        return ok(payload)
    }

    private func startVision(_ model: AppModel) -> String {
        if model.isVisionLiveRoute || model.visionEngine.isRunning {
            return #"{"ok":false,"error":"already live"}"#
        }
        if !model.isVisionRoute {
            model.openVision()
        }
        model.startVisionSession()
        return ok([
            "started": "vision",
            "route": String(describing: model.route),
            "gazeCalibrated": model.gazeMapper.isCalibrated,
            "faceTracking": model.faceTracker.isTracking,
            "spokenHint": model.gazeMapper.isCalibrated
                ? "Soft gaze at center — look toward each flash when it appears."
                : "Gaze not calibrated yet — look at center and calibrate if flashes feel off.",
        ])
    }

    private func stopVision(_ model: AppModel) -> String {
        guard model.isVisionLiveRoute || model.visionEngine.isRunning else {
            return #"{"ok":false,"error":"no live vision session"}"#
        }
        model.stopVisionSession()
        return ok(["stopped": "vision", "route": String(describing: model.route)])
    }

    private func focusStatusJSON(_ model: AppModel) -> String {
        var dict: [String: Any] = [
            "ok": true,
            "route": String(describing: model.route),
            "phase": model.focusEngine.phaseLabel,
            "remainingSeconds": model.focusEngine.remainingSeconds,
            "fadeSuggested": model.focusEngine.fadeSuggested,
            "fadeCount": model.focusEngine.fadeCount,
            "isPaused": model.focusEngine.isPaused,
            "isRunning": model.focusEngine.isRunning,
            "didExtend": model.focusEngine.didExtend,
            "baselineReady": model.focusEngine.baselineReady,
            "focusMinutes": model.focusEngine.focusMinutes,
            "breakMinutes": model.focusEngine.breakMinutes,
        ]
        if let score = model.focusEngine.fadeScore { dict["fadeScore"] = score }
        if let bpm = model.focusEngine.lastHrBpm ?? model.phoneSession.lastHeartRateBpm {
            dict["hrBpm"] = bpm
        }
        if let arousal = model.focusEngine.lastArousal { dict["arousal"] = Double(arousal) }
        if let energy = model.focusEngine.lastMotionEnergy ?? model.phoneSession.lastMotionEnergy {
            dict["motionEnergy"] = energy
        }
        if let sid = model.writer.sessionId { dict["sessionId"] = sid }
        dict["breathingRunning"] = model.breathingCoach.isRunning
        dict["breathingPhase"] = model.breathingCoach.phaseLabel
        dict["patternTips"] = model.patternStore.tips
        dict["cameraMode"] = model.focusCameraMode.rawValue
        dict["usesCamera"] = model.focusUsesCamera
        dict["cameraPresence"] = model.focusCameraPresence.rawValue
        return jsonString(dict)
    }

    private func reactionCheckJSON(_ model: AppModel) -> String {
        var dict: [String: Any] = [
            "ok": true,
            "bookendEnabled": model.reactionCheckBookendEnabled,
            "running": model.tapPVTEngine.isRunning,
            "lapseThresholdMs": TapPVTResult.lapseThresholdMs,
        ]
        if let comparison = model.lastReactionComparison ?? model.pvtStore.latestBookend?.comparison {
            dict["preMedianMs"] = comparison.pre.medianRtMs ?? 0
            dict["postMedianMs"] = comparison.post.medianRtMs ?? 0
            dict["preLapses"] = comparison.pre.lapseCount
            dict["postLapses"] = comparison.post.lapseCount
            dict["direction"] = comparison.direction.rawValue
            dict["headline"] = comparison.headline
            if let delta = comparison.medianDeltaMs { dict["medianDeltaMs"] = delta }
        } else if let single = model.lastStandaloneReaction ?? model.pvtStore.latestStandalone {
            dict["medianMs"] = single.medianRtMs ?? 0
            dict["lapses"] = single.lapseCount
            dict["falseStarts"] = single.falseStartCount
        } else {
            dict["hasResults"] = false
        }
        return jsonString(dict)
    }

    private func statusJSON(_ model: AppModel) -> String {
        let useVision = model.route == .visionLive || model.route == .visionSetup || model.visionEngine.isRunning
        var dict: [String: Any] = [
            "ok": true,
            "route": String(describing: model.route),
            "watchConnected": model.isWatchConnected,
            "watchIMUCalibrated": model.watchIMUCalibrated,
            "watchCalibrating": model.isWatchCalibrating,
            "watchReachableStatus": model.phoneSession.statusText,
            "gazeCalibrated": model.gazeMapper.isCalibrated,
            "faceTracking": model.faceTracker.isTracking,
            "hud": model.hudMessage,
        ]
        if let bpm = model.phoneSession.lastHeartRateBpm { dict["hrBpm"] = bpm }
        if let offset = model.phoneSession.lastSyncOffsetMs { dict["syncOffsetMs"] = offset }
        if let rtt = model.phoneSession.lastSyncRttMs { dict["syncRttMs"] = rtt }
        if let sid = model.writer.sessionId { dict["sessionId"] = sid }
        if let energy = model.phoneSession.lastMotionEnergy { dict["motionEnergy"] = energy }

        if model.isFocusRoute || model.focusEngine.isRunning {
            dict["focusPhase"] = model.focusEngine.phaseLabel
            dict["focusRemainingSeconds"] = model.focusEngine.remainingSeconds
            dict["focusFadeCount"] = model.focusEngine.fadeCount
            if let score = model.focusEngine.fadeScore { dict["fadeScore"] = score }
        }

        // Always include posture snapshot so "is my posture okay?" works from any route.
        dict["postureBaselineReady"] = model.postureBaselineReady
        dict["postureScore"] = model.postureLiveScore
        dict["postureNudgeVisible"] = model.postureNudgeVisible
        dict["postureTracking"] = model.faceTracker.isPostureTracking
        if model.postureBaselineReady {
            let score = model.postureLiveScore
            let okish = score < PostureDriftDetector.defaultScoreThreshold && !model.postureNudgeVisible
            dict["postureOkay"] = okish
            dict["postureHint"] = okish
                ? "Near your sit-tall baseline."
                : "Drifting from your sit-tall baseline — sit back up straight."
        } else {
            dict["postureOkay"] = NSNull()
            dict["postureHint"] = "Baseline not ready yet — keep sitting tall while it learns."
        }

        let mean = useVision ? model.visionEngine.baselineMeanMs : model.kineticEngine.baselineMeanMs
        let std = useVision ? model.visionEngine.baselineStdMs : model.kineticEngine.baselineStdMs
        let bp = useVision ? model.visionEngine.breakPointTrial : model.kineticEngine.breakPointTrial
        if let mean { dict["baselineMeanMs"] = mean }
        if let std { dict["baselineStdMs"] = std }
        if let bp { dict["breakPointTrial"] = bp }
        if let acc = model.kineticEngine.spatialAccuracyPercent {
            dict["spatialAccuracyPercent"] = acc
        }
        if model.isKineticRoute || model.kineticEngine.isRunning {
            dict["kineticRunning"] = model.kineticEngine.isRunning
            dict["kineticPhase"] = Self.trialPhaseLabel(model.kineticEngine.phase)
            dict["kineticTrialIndex"] = model.kineticEngine.trialIndex
            dict["hint"] = "For Kinetic coaching details call get_kinetic_status."
        }
        if model.isVisionRoute || model.visionEngine.isRunning {
            dict["visionRunning"] = model.visionEngine.isRunning
            dict["visionPhase"] = Self.trialPhaseLabel(model.visionEngine.phase)
            dict["visionFlashVisible"] = model.visionEngine.flashVisible
            dict["hint"] = "For Vision PVT coaching details call get_vision_status."
        }
        return jsonString(dict)
    }

    private func postureStatusJSON(_ model: AppModel) -> String {
        var dict: [String: Any] = [
            "ok": true,
            "route": String(describing: model.route),
            "baselineReady": model.postureBaselineReady,
            "baselineProgress": model.postureBaselineProgress,
            "score": model.postureLiveScore,
            "nudgeVisible": model.postureNudgeVisible,
            "tracking": model.faceTracker.isPostureTracking,
            "statusText": model.faceTracker.postureStatusText,
            "remindersEnabled": model.postureRemindersEnabled,
        ]
        if model.postureBaselineReady {
            let score = model.postureLiveScore
            let okay = score < PostureDriftDetector.defaultScoreThreshold && !model.postureNudgeVisible
            dict["postureOkay"] = okay
            dict["spokenHint"] = okay
                ? "Your posture looks close to the sit-tall baseline you set."
                : "Your posture is a bit off from baseline — sit back up straight."
        } else {
            dict["postureOkay"] = false
            dict["spokenHint"] = "I'm still learning your sit-tall baseline — keep facing the camera."
        }
        return jsonString(dict)
    }

    private func kineticStatusJSON(_ model: AppModel) -> String {
        let engine = model.kineticEngine
        let phase = Self.trialPhaseLabel(engine.phase)
        var dict: [String: Any] = [
            "ok": true,
            "route": String(describing: model.route),
            "onKineticRoute": model.isKineticRoute,
            "isLive": model.isKineticLiveRoute || engine.isRunning,
            "isRunning": engine.isRunning,
            "phase": phase,
            "trialIndex": engine.trialIndex,
            "trialsCompleted": engine.trials.count,
            "totalTrials": KineticClockEngine.defaultTrialCount,
            "statusText": engine.statusText,
            "hud": model.hudMessage,
            "watchConnected": model.isWatchConnected,
            "watchReachableStatus": model.phoneSession.statusText,
            "watchIMUCalibrated": model.watchIMUCalibrated,
            "watchCalibrating": model.isWatchCalibrating,
            "armSide": model.kineticArmSide.rawValue,
            "faceTracking": model.faceTracker.isTracking,
            "armTracking": model.faceTracker.isArmTracking,
        ]
        if let octant = engine.activeOctant {
            dict["activeOctant"] = octant
            dict["activeOctantLabel"] = ClockOctant(rawValue: octant)?.label ?? "\(octant)"
        }
        if let preview = model.kineticPreviewOctant {
            dict["previewOctant"] = preview
            dict["previewOctantLabel"] = ClockOctant(rawValue: preview)?.label ?? "\(preview)"
        }
        if let match = engine.lastSpatialMatch { dict["lastSpatialMatch"] = match }
        if let acc = engine.spatialAccuracyPercent { dict["spatialAccuracyPercent"] = acc }
        if let rt = engine.lastMotorRtMs { dict["lastMotorRtMs"] = rt }
        if let mean = engine.baselineMeanMs { dict["baselineMeanMs"] = mean }
        if let std = engine.baselineStdMs { dict["baselineStdMs"] = std }
        if let bp = engine.breakPointTrial { dict["breakPointTrial"] = bp }
        if let sid = model.writer.sessionId { dict["sessionId"] = sid }
        if let offset = model.phoneSession.lastSyncOffsetMs { dict["syncOffsetMs"] = offset }
        if let rtt = model.phoneSession.lastSyncRttMs { dict["syncRttMs"] = rtt }

        let (next, hint) = Self.kineticCoachHints(model: model, phase: phase)
        dict["coachNextStep"] = next
        dict["spokenHint"] = hint
        return jsonString(dict)
    }

    private func visionStatusJSON(_ model: AppModel) -> String {
        let engine = model.visionEngine
        let phase = Self.trialPhaseLabel(engine.phase)
        var dict: [String: Any] = [
            "ok": true,
            "route": String(describing: model.route),
            "onVisionRoute": model.isVisionRoute,
            "isLive": model.isVisionLiveRoute || engine.isRunning,
            "isRunning": engine.isRunning,
            "phase": phase,
            "flashVisible": engine.flashVisible,
            "trialIndex": engine.trialIndex,
            "trialsCompleted": engine.trials.count,
            "statusText": engine.statusText,
            "hud": model.hudMessage,
            "gazeCalibrated": model.gazeMapper.isCalibrated,
            "faceTracking": model.faceTracker.isTracking,
        ]
        if let rt = engine.lastVisualRtMs { dict["lastVisualRtMs"] = rt }
        if let mean = engine.baselineMeanMs { dict["baselineMeanMs"] = mean }
        if let std = engine.baselineStdMs { dict["baselineStdMs"] = std }
        if let bp = engine.breakPointTrial { dict["breakPointTrial"] = bp }
        if let sid = model.writer.sessionId { dict["sessionId"] = sid }

        let (next, hint) = Self.visionCoachHints(model: model, phase: phase)
        dict["coachNextStep"] = next
        dict["spokenHint"] = hint
        return jsonString(dict)
    }

    private static func trialPhaseLabel(_ phase: TrialPhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .waitingForOnset: return "waitingForOnset"
        case .awaitingResponse: return "awaitingResponse"
        case .complete: return "complete"
        }
    }

    private static func kineticCoachHints(model: AppModel, phase: String) -> (String, String) {
        if !model.isKineticRoute {
            return (
                "open_kinetic",
                "Open Kinetic Clock. Connect your Apple Watch so punches register, then start."
            )
        }
        if model.isWatchCalibrating {
            return (
                "wait_calibrate",
                "Hold still — Watch is calibrating. Arms neutral, face the phone."
            )
        }
        if !model.isWatchConnected {
            return (
                "connect_watch",
                "Watch isn't reachable. Open the Synapse app on your Watch and keep it unlocked near the phone."
            )
        }
        if !model.watchIMUCalibrated && !model.isKineticLiveRoute {
            return (
                "calibrate_watch",
                "Calibrate the Watch first — arms neutral, face the phone for about 10 seconds."
            )
        }
        if model.isKineticLiveRoute || model.kineticEngine.isRunning {
            if phase == "awaitingResponse",
               let octant = model.kineticEngine.activeOctant,
               let label = ClockOctant(rawValue: octant)?.label {
                return (
                    "air_punch",
                    "Air-punch toward the lit pad at \(label) — no screen taps."
                )
            }
            if phase == "waitingForOnset" {
                return ("wait_pad", "Wait for the next pad to light, then air-punch toward it.")
            }
            let progress = "\(model.kineticEngine.trials.count)/\(KineticClockEngine.defaultTrialCount)"
            return (
                "continue",
                "Keep going — trial \(progress). Air-punch toward each lit pad."
            )
        }
        return (
            "start_kinetic",
            "Watch looks ready. Start when you want — air-punch toward the lit pad, no taps."
        )
    }

    private static func visionCoachHints(model: AppModel, phase: String) -> (String, String) {
        if !model.isVisionRoute {
            return (
                "open_vision",
                "Open Vision PVT. Face the phone, calibrate gaze at center, then start."
            )
        }
        if !model.faceTracker.isTracking {
            return (
                "face_camera",
                "I need your face in frame — face the front camera with soft lighting."
            )
        }
        if !model.gazeMapper.isCalibrated && !model.isVisionLiveRoute {
            return (
                "calibrate_gaze",
                "Look at the phone center, then calibrate gaze so the mesh feels stable."
            )
        }
        if model.isVisionLiveRoute || model.visionEngine.isRunning {
            if model.visionEngine.flashVisible || phase == "awaitingResponse" {
                return (
                    "look_flash",
                    "Flash is up — look toward the flash at center. No taps needed."
                )
            }
            if phase == "waitingForOnset" {
                return ("wait_flash", "Stay soft on center — wait for the next flash.")
            }
            return (
                "continue",
                "Keep soft gaze near center between flashes. Trial \(model.visionEngine.trials.count + 1)."
            )
        }
        return (
            "start_vision",
            "Gaze looks ready. Start when you want — look toward each flash; no taps."
        )
    }

    private func ok(_ extra: [String: Any] = [:]) -> String {
        var dict = extra
        dict["ok"] = true
        return jsonString(dict)
    }

    private func jsonString(_ dict: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8)
        else {
            return #"{"ok":true}"#
        }
        return s
    }

    private static func intArg(_ args: [String: Any], _ key: String) -> Int? {
        if let i = args[key] as? Int { return i }
        if let d = args[key] as? Double { return Int(d) }
        if let n = args[key] as? NSNumber { return n.intValue }
        if let s = args[key] as? String { return Int(s) }
        return nil
    }

    private static func doubleArg(_ args: [String: Any], _ key: String) -> Double? {
        if let d = args[key] as? Double { return d }
        if let i = args[key] as? Int { return Double(i) }
        if let n = args[key] as? NSNumber { return n.doubleValue }
        if let s = args[key] as? String { return Double(s) }
        return nil
    }

    private static func stringArg(_ args: [String: Any], _ key: String) -> String? {
        if let s = args[key] as? String { return s }
        if let n = args[key] as? NSNumber { return n.stringValue }
        return nil
    }

    private static func boolArg(_ args: [String: Any], _ key: String) -> Bool? {
        if let b = args[key] as? Bool { return b }
        if let n = args[key] as? NSNumber { return n.boolValue }
        if let s = args[key] as? String {
            switch s.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }
}
