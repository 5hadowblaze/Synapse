import Foundation
import Observation

enum VoiceAssistantPhase: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case error
}

/// Orchestrates Apple STT → OpenAI Realtime (tools) → ElevenLabs TTS,
/// plus proactive coaching lines for setup / start / complete / break-point.
@Observable
@MainActor
final class VoiceAssistantController {
    private(set) var phase: VoiceAssistantPhase = .idle
    private(set) var transcriptSnippet = ""
    private(set) var lastError: String?
    private(set) var lastSpoken = ""

    private weak var model: AppModel?
    private let listener = AppleSpeechListener()
    private let realtime = OpenAIRealtimeSession()
    private let tts = ElevenLabsSpeechSynthesizer()

    private var turnTask: Task<Void, Never>?
    private var proactiveTask: Task<Void, Never>?
    private var lastProactiveKey: String?
    private var lastRoute: AppRoute?

    var isConfigured: Bool { VoiceConfig.isConfigured }

    func attach(to model: AppModel) {
        self.model = model
        lastRoute = model.route
        realtime.onToolCall = { [weak self] name, args in
            await self?.executeTool(name: name, arguments: args) ?? #"{"ok":false}"#
        }
    }

    func handleRouteChange(_ route: AppRoute) {
        guard route != lastRoute else { return }
        lastRoute = route
        switch route {
        case .focusSetup:
            speakProactive(
                key: "setup-focus",
                text: "Focus mode. Pick a duration, face the phone, and start when you're ready. I'll stay quiet while you work."
            )
        case .visionSetup:
            speakProactive(
                key: "setup-vision",
                text: "Vision PVT. Look at the phone center, calibrate gaze, then start when the mesh looks stable."
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
        speakProactive(
            key: "start-\(module)-\(Int(Date().timeIntervalSince1970))",
            text: "Starting \(module). Three, two, one — go.",
            interrupt: true
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
            text: "Your body is fading off baseline. Take a short break when you're ready.",
            interrupt: true
        )
    }

    func notifyFocusBreakStarted() {
        speakProactive(
            key: "focus-break-\(Int(Date().timeIntervalSince1970))",
            text: "Break time. Soften your gaze and reset.",
            interrupt: true
        )
    }

    /// Tap orb: start listening, stop+send if listening, or cancel while thinking/speaking.
    func toggleListen() {
        if phase == .thinking || phase == .speaking {
            cancel()
            return
        }
        if phase == .listening {
            finishListeningAndRespond()
            return
        }
        guard phase == .idle || phase == .error else { return }
        startListening()
    }

    func cancel() {
        turnTask?.cancel()
        turnTask = nil
        proactiveTask?.cancel()
        proactiveTask = nil
        realtime.cancelPendingAsk()
        listener.stop()
        tts.stop()
        phase = .idle
    }

    // MARK: - Listen → Think → Speak

    private func startListening() {
        lastError = nil
        transcriptSnippet = ""
        turnTask?.cancel()
        turnTask = Task { @MainActor in
            do {
                if VoiceConfig.openAIKey.isEmpty {
                    throw VoiceAssistantError.missingOpenAIKey
                }
                if VoiceConfig.elevenLabsKey.isEmpty {
                    throw VoiceAssistantError.missingElevenLabsKey
                }
                let ok = await listener.requestAuthorization()
                guard ok else { throw VoiceAssistantError.speechPermissionDenied }

                listener.onPartial = { [weak self] text in
                    self?.transcriptSnippet = text
                }
                try listener.start()
                phase = .listening

                // Auto-finalize after a short utterance window if user doesn't tap again.
                try await Task.sleep(nanoseconds: 6_000_000_000)
                if !Task.isCancelled, self.phase == .listening {
                    self.finishListeningAndRespond()
                }
            } catch is CancellationError {
                // ignore
            } catch {
                self.phase = .error
                self.lastError = error.localizedDescription
            }
        }
    }

    private func finishListeningAndRespond() {
        turnTask?.cancel()
        turnTask = Task { @MainActor in
            do {
                phase = .thinking
                let spoken = try await listener.stopAndFinalize()
                transcriptSnippet = spoken
                guard !spoken.isEmpty else {
                    phase = .idle
                    return
                }

                let reply = try await realtime.ask(spoken)
                if !reply.isEmpty {
                    await speakAssistant(reply)
                } else {
                    phase = .idle
                }
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .error
                lastError = error.localizedDescription
            }
        }
    }

    private func speakAssistant(_ text: String) async {
        phase = .speaking
        lastSpoken = text
        transcriptSnippet = text
        do {
            try await tts.speak(text)
            phase = .idle
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .error
            lastError = error.localizedDescription
        }
    }

    private func speakProactive(key: String, text: String, interrupt: Bool = false) {
        // Don't steal the mic mid user-turn unless this is a high-priority cue.
        if phase == .listening || phase == .thinking {
            return
        }
        guard key != lastProactiveKey else { return }
        lastProactiveKey = key
        guard !VoiceConfig.elevenLabsKey.isEmpty else { return }

        if interrupt {
            proactiveTask?.cancel()
            tts.stop()
        } else if phase == .speaking {
            return
        }

        proactiveTask?.cancel()
        proactiveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: interrupt ? 150_000_000 : 350_000_000)
            guard !Task.isCancelled else { return }
            if self.phase == .listening || self.phase == .thinking { return }
            await self.speakAssistant(text)
        }
    }

    // MARK: - Tools

    private func executeTool(name: String, arguments: String) async -> String {
        guard let model else {
            return #"{"ok":false,"error":"no app model"}"#
        }

        let args = Self.parseArgs(arguments)

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

        case "start_focus":
            if model.focusEngine.isRunning {
                return #"{"ok":false,"error":"already live"}"#
            }
            let focusMin = Self.intArg(args, "focusMinutes")
            let breakMin = Self.intArg(args, "breakMinutes")
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

        case "start_breathing":
            model.startBreathingReset()
            return ok([
                "breathing": true,
                "running": model.breathingCoach.isRunning,
                "phase": model.breathingCoach.phaseLabel,
            ])

        case "lock_in_ten":
            model.lockInTenMinutes()
            return ok(["lockedIn": true, "focusMinutes": 10])

        case "start_session":
            return startSession(model)

        case "stop_session":
            return stopSession(model)

        case "calibrate_watch":
            model.calibrateWatch()
            return ok(["action": "calibrate_watch"])

        case "calibrate_gaze":
            model.calibrateGaze()
            return ok(["action": "calibrate_gaze", "calibrated": model.gazeMapper.isCalibrated])

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
        case .kineticMainSetup, .kineticDebugSetup:
            model.startKineticSession()
            return ok(["started": "kinetic"])
        case .focusSetup, .focusRecap:
            model.startFocusSession()
            return ok(["started": "focus"])
        case .visionLive, .kineticMainLive, .kineticDebugLive, .focusLive, .focusBreak:
            return #"{"ok":false,"error":"already live"}"#
        case .hub:
            return #"{"ok":false,"error":"open focus, vision, or kinetic first"}"#
        }
    }

    private func stopSession(_ model: AppModel) -> String {
        switch model.route {
        case .visionLive:
            model.stopVisionSession()
            return ok(["stopped": "vision"])
        case .kineticMainLive, .kineticDebugLive:
            model.stopKineticSession()
            return ok(["stopped": "kinetic"])
        case .focusLive, .focusBreak:
            model.stopFocusSession()
            return ok(["stopped": "focus"])
        default:
            return #"{"ok":false,"error":"no live session"}"#
        }
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
        return jsonString(dict)
    }

    private func statusJSON(_ model: AppModel) -> String {
        let useVision = model.route == .visionLive || model.route == .visionSetup || model.visionEngine.isRunning
        var dict: [String: Any] = [
            "ok": true,
            "route": String(describing: model.route),
            "watchConnected": model.isWatchConnected,
            "watchIMUCalibrated": model.watchIMUCalibrated,
            "gazeCalibrated": model.gazeMapper.isCalibrated,
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

        let mean = useVision ? model.visionEngine.baselineMeanMs : model.kineticEngine.baselineMeanMs
        let std = useVision ? model.visionEngine.baselineStdMs : model.kineticEngine.baselineStdMs
        let bp = useVision ? model.visionEngine.breakPointTrial : model.kineticEngine.breakPointTrial
        if let mean { dict["baselineMeanMs"] = mean }
        if let std { dict["baselineStdMs"] = std }
        if let bp { dict["breakPointTrial"] = bp }
        if let acc = model.kineticEngine.spatialAccuracyPercent {
            dict["spatialAccuracyPercent"] = acc
        }
        return jsonString(dict)
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

    private static func parseArgs(_ arguments: String) -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func intArg(_ args: [String: Any], _ key: String) -> Int? {
        if let i = args[key] as? Int { return i }
        if let d = args[key] as? Double { return Int(d) }
        if let n = args[key] as? NSNumber { return n.intValue }
        return nil
    }
}
