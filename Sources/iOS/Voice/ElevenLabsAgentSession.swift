import Combine
import ElevenLabs
import Foundation

/// Conversation modes for the single Synapse Coach agent (dashboard prompts in docs/ELEVENLABS_AGENT.md).
enum AgentVoiceMode: String, Sendable {
    case coach
    case breath
    case reflect
}

/// Thin wrapper around ElevenLabs `Conversation` — one active session at a time.
@MainActor
final class ElevenLabsAgentSession {
    private(set) var conversation: Conversation?
    private(set) var mode: AgentVoiceMode?
    private(set) var isConnected = false

    var onPhaseChange: ((VoiceAssistantPhase) -> Void)?
    var onTranscript: ((String) -> Void)?
    var onAgentText: ((String) -> Void)?
    var onToolCall: ((String, [String: Any]) async -> String)?
    var onEnded: (() -> Void)?
    var onError: ((String) -> Void)?

    private var toolTask: Task<Void, Never>?
    private var stateCancellable: AnyCancellable?
    private var agentStateCancellable: AnyCancellable?
    private var messagesCancellable: AnyCancellable?
    private var connectTask: Task<Void, Never>?
    /// Absolute cap so a one-shot never idles into "still there?"
    private var oneShotWatchdog: Task<Void, Never>?
    /// Ends after estimated speech duration when agent-state speaking events are missing.
    private var oneShotFallbackTask: Task<Void, Never>?
    /// Ends shortly after speaking → listening/idle.
    private var oneShotSpeechEndTask: Task<Void, Never>?
    private var isOneShot = false
    /// True once the agent has entered `.speaking` for this one-shot (ignore pre-speech listening).
    private var oneShotDidEnterSpeaking = false

    var isActive: Bool {
        guard let conversation else { return false }
        switch conversation.state {
        case .connecting, .active: return true
        default: return false
        }
    }

    func start(
        mode: AgentVoiceMode,
        firstMessage: String? = nil,
        muteMicrophone: Bool = false,
        endAfterFirstAgentReply: Bool = false
    ) async throws {
        guard VoiceConfig.isConfigured else {
            throw VoiceAssistantError.missingAgentID
        }

        await end()

        self.mode = mode
        self.isOneShot = endAfterFirstAgentReply
        self.oneShotDidEnterSpeaking = false
        onPhaseChange?(.connecting)

        let prompt = Self.prompt(for: mode)
        var config = ConversationConfig(
            agentOverrides: AgentOverrides(
                prompt: prompt,
                firstMessage: firstMessage
            ),
            ttsOverrides: TTSOverrides(voiceId: VoiceConfig.elevenLabsVoiceID),
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.onError?(error.localizedDescription)
                    self?.onPhaseChange?(.error)
                }
            },
            onAgentResponse: { [weak self] text, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.onAgentText?(text)
                    self.onTranscript?(text)
                    // Do not end on first transcript — TTS is still playing.
                    // Wait for speaking → listening, with a text-length fallback.
                    if endAfterFirstAgentReply {
                        self.scheduleOneShotFallbackEnd(for: text)
                    }
                }
            },
            onUserTranscript: { [weak self] text, _ in
                Task { @MainActor in
                    self?.onTranscript?(text)
                }
            },
            onAgentStateChange: { [weak self] state in
                Task { @MainActor in
                    self?.mapAgentState(state)
                }
            }
        )
        // Prefer event-based agent state when available.
        config.agentStateConfiguration = AgentStateConfiguration()

        let agentId = VoiceConfig.elevenLabsAgentID
        let conversation = try await ElevenLabs.startConversation(
            agentId: agentId,
            config: config
        )
        self.conversation = conversation
        isConnected = true
        bind(conversation)
        observeTools(conversation)

        if muteMicrophone {
            try? await conversation.setMuted(true)
        } else {
            try? await conversation.setMuted(false)
        }

        mapAgentState(conversation.agentState)

        if endAfterFirstAgentReply {
            // Also schedule fallback from the scripted first message in case
            // onAgentResponse is delayed or duplicates the same line.
            if let firstMessage, !firstMessage.isEmpty {
                scheduleOneShotFallbackEnd(for: firstMessage)
            }
            oneShotWatchdog?.cancel()
            oneShotWatchdog = Task { @MainActor [weak self] in
                let nanos = Self.oneShotAbsoluteMaxNanos(for: firstMessage)
                try? await Task.sleep(nanoseconds: nanos)
                guard let self, !Task.isCancelled, self.isOneShot else { return }
                await self.end()
            }
        }
    }

    /// Start a short one-shot spoken line (proactive coaching) without leaving mic open.
    func speakLine(_ text: String, mode: AgentVoiceMode = .coach) async throws {
        try await start(
            mode: mode,
            firstMessage: text,
            muteMicrophone: true,
            endAfterFirstAgentReply: true
        )
    }

    func end() async {
        connectTask?.cancel()
        connectTask = nil
        toolTask?.cancel()
        toolTask = nil
        cancelOneShotTasks()
        isOneShot = false
        oneShotDidEnterSpeaking = false
        stateCancellable = nil
        agentStateCancellable = nil
        messagesCancellable = nil

        if let conversation {
            await conversation.endConversation()
        }
        conversation = nil
        mode = nil
        isConnected = false
        onEnded?()
        onPhaseChange?(.idle)
    }

    private func cancelOneShotTasks() {
        oneShotWatchdog?.cancel()
        oneShotWatchdog = nil
        oneShotFallbackTask?.cancel()
        oneShotFallbackTask = nil
        oneShotSpeechEndTask?.cancel()
        oneShotSpeechEndTask = nil
    }

    /// After TTS finishes (speaking → listening), end with a short trail so the last phoneme isn't clipped.
    private func scheduleOneShotEndAfterSpeech() {
        guard isOneShot, oneShotDidEnterSpeaking else { return }
        oneShotSpeechEndTask?.cancel()
        oneShotSpeechEndTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled, self.isOneShot else { return }
            await self.end()
        }
    }

    /// If agent-state speaking events never arrive, end after an estimated utterance duration.
    private func scheduleOneShotFallbackEnd(for text: String) {
        guard isOneShot else { return }
        oneShotFallbackTask?.cancel()
        oneShotFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.estimatedSpeechNanos(for: text))
            guard let self, !Task.isCancelled, self.isOneShot else { return }
            if self.oneShotDidEnterSpeaking, let conversation = self.conversation {
                if case .speaking = conversation.agentState {
                    // Still mid-utterance — speaking→listening or absolute watchdog will end.
                    return
                }
            }
            await self.end()
        }
    }

    /// Floor 15s / cap 20s, scaled by text length (connect + TTS headroom).
    private static func oneShotAbsoluteMaxNanos(for text: String?) -> UInt64 {
        let chars = Double(text?.count ?? 48)
        let seconds = min(20, max(15, 3.0 + chars * 0.08))
        return UInt64(seconds * 1_000_000_000)
    }

    private static func estimatedSpeechNanos(for text: String) -> UInt64 {
        let chars = Double(max(text.count, 8))
        // ~12 chars/s plus 1.5s TTFB; generous so missing speaking events don't clip.
        let seconds = min(18, max(4, 1.5 + chars * 0.085))
        return UInt64(seconds * 1_000_000_000)
    }

    // MARK: - Binding

    private func bind(_ conversation: Conversation) {
        stateCancellable = conversation.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .connecting:
                    self.onPhaseChange?(.connecting)
                case .active:
                    self.isConnected = true
                    self.mapAgentState(conversation.agentState)
                case .ended, .idle:
                    self.isConnected = false
                    self.onPhaseChange?(.idle)
                    self.onEnded?()
                case .error(let error):
                    self.isConnected = false
                    self.onError?(error.localizedDescription)
                    self.onPhaseChange?(.error)
                }
            }

        agentStateCancellable = conversation.$agentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.mapAgentState(state)
            }

        messagesCancellable = conversation.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                guard let last = messages.last else { return }
                self?.onTranscript?(last.content)
                if last.role == .agent {
                    self?.onAgentText?(last.content)
                }
            }
    }

    private func observeTools(_ conversation: Conversation) {
        toolTask?.cancel()
        toolTask = Task { [weak self] in
            for await calls in conversation.$pendingToolCalls.values {
                guard let self, !Task.isCancelled else { return }
                for call in calls {
                    await self.handleTool(call, conversation: conversation)
                }
            }
        }
    }

    private func handleTool(_ call: ClientToolCallEvent, conversation: Conversation) async {
        let params = (try? call.getParameters()) ?? [:]
        let name = call.toolName
        let result: String
        if let onToolCall {
            result = await onToolCall(name, params)
        } else {
            result = #"{"ok":false,"error":"no tool handler"}"#
        }
        do {
            try await conversation.sendToolResult(for: call.toolCallId, result: result)
        } catch {
            try? await conversation.sendToolResult(
                for: call.toolCallId,
                result: #"{"ok":false,"error":"\#(error.localizedDescription)"}"#,
                isError: true
            )
            conversation.markToolCallCompleted(call.toolCallId)
        }
    }

    private func mapAgentState(_ state: ElevenLabs.AgentState) {
        switch state {
        case .listening:
            onPhaseChange?(.listening)
            // One-shot: wait until TTS leaves speaking, then end (not on first text chunk).
            scheduleOneShotEndAfterSpeech()
        case .speaking:
            oneShotDidEnterSpeaking = true
            // Cancel a premature post-speech end if the agent starts another phrase.
            oneShotSpeechEndTask?.cancel()
            oneShotSpeechEndTask = nil
            onPhaseChange?(.speaking)
        case .thinking:
            onPhaseChange?(.thinking)
        @unknown default:
            onPhaseChange?(.listening)
            scheduleOneShotEndAfterSpeech()
        }
    }

    // MARK: - Mode prompts

    private static func prompt(for mode: AgentVoiceMode) -> String {
        let base = """
        You are Synapse, a calm iPhone + Apple Watch coach for cognitive pacing.
        Primary product: Focus — timed desk pacing with Watch HR (+ optional face), \
        PVT-B reaction checks, and break nudges. Lab modules: Vision PVT, Kinetic Clock, \
        and Posture Check (sit-tall baseline + drift).
        Keep replies short (1–2 sentences) unless guiding a lab step-by-step, breath, or reflect.
        Use client tools to navigate and control the app; call get_status, get_focus_status, \
        get_posture_status, get_kinetic_status, or get_vision_status when unsure. \
        Never invent sensor, reaction, or accuracy numbers — quote tools only.
        If the user asks whether their posture is okay / straight / slumped, call get_posture_status \
        and answer from postureOkay + spokenHint. Wellness signal only — never diagnose.
        Never claim to detect, diagnose, or measure fatigue or cognitive load.
        Never say clinical or diagnostic language. Wellness signal and a nudge only.
        Stay silent during a reaction check (timed measurement).
        During focusLive: stay quiet unless a break is suggested, the user speaks, or the timer ends.
        """

        switch mode {
        case .coach:
            return base + """

            MODE=coach
            You may navigate hub / focus / labs (including posture) and control Focus with tools.
            Camera: set_camera_mode or start_focus with camera always|brief|none.
            Posture: open_posture / start_session on posture setup; get_posture_status for live checks.
            Kinetic Clock: if user asks how to do Kinetic, why Watch isn't connecting, or for a walkthrough, \
            call get_kinetic_status and coach from coachNextStep + spokenHint (Watch connected? calibrating?). \
            Use open_kinetic / start_kinetic / stop_kinetic / calibrate_watch. Guide: connect Watch app, \
            calibrate arms-neutral, then air-punch toward the lit pad — no screen taps.
            Vision PVT: if user asks how Vision PVT works or wants a walkthrough, call get_vision_status \
            and coach from coachNextStep + spokenHint. Use open_vision / start_vision / stop_vision / \
            calibrate_gaze. Guide: face camera, look at center, calibrate gaze, then look toward flashes.
            Prefer tools over long explanations. Answer from tool JSON — never invent Watch or gaze state.
            """
        case .breath:
            return base + """

            MODE=breath
            Guide a short inhale/hold/exhale reset. Before each timed segment, call set_breath_phase \
            with phase intro|inhale|hold|exhale|complete so the on-screen ring stays in sync.
            Speak the cue as you call the tool. After several cycles, set phase complete, \
            then invite lock-in ten or skip. Call start_breathing once at the beginning if UI is idle.
            Do not diagnose. Keep language soft.
            """
        case .reflect:
            return base + """

            MODE=reflect
            Optional post-block check-in. Ask how the block felt (body + head), whether the \
            break nudge matched how they felt, and whether they'd stop earlier next time.
            3–5 turns max. End by paraphrasing what THEY said — never invent physiology.
            Call submit_check_in with structured fields, then end_reflection.
            Never say fatigue detected / diagnosis / clinical load.
            If they want to leave, call end_reflection immediately.
            """
        }
    }
}
