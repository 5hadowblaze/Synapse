import Foundation

/// OpenAI Realtime WebSocket (text in / text out + function tools).
/// Spoken audio is ElevenLabs — this session never plays Realtime audio.
@MainActor
final class OpenAIRealtimeSession: NSObject {
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var receiveLoopRunning = false

    private var pendingAssistantText = ""
    private var awaitingToolFollowUp = false
    private var responseContinuation: CheckedContinuation<String, Error>?

    /// Bumped on each new `ask`, cancel, and disconnect. Stale hops compare against this.
    private var askGeneration: UInt64 = 0
    /// FIFO of ask-generations for each `response.create` we sent — absorbs late dones after cancel.
    private var outstandingResponseCreates: [UInt64] = []
    private var toolCallTask: Task<Void, Never>?
    private var askTimeoutTask: Task<Void, Never>?

    private static let askTimeoutNanoseconds: UInt64 = 30_000_000_000

    /// Connect handshake: wait for `session.created` then `session.updated`.
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var expectedConnectEvent: String?

    /// Execute a tool by name; return JSON/string output for the model.
    var onToolCall: ((String, String) async -> String)?

    private(set) var isConnected = false

    func connect() async throws {
        disconnect()
        let key = VoiceConfig.openAIKey
        guard !key.isEmpty else { throw VoiceAssistantError.missingOpenAIKey }

        let model = VoiceConfig.realtimeModel
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(model)") else {
            throw VoiceAssistantError.badURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let urlSession = URLSession(configuration: .default)
        self.urlSession = urlSession
        let task = urlSession.webSocketTask(with: request)
        webSocket = task

        do {
            // Arm waits before resume/send so early server events cannot race past us.
            async let created: Void = waitForConnectEvent("session.created")
            task.resume()
            startReceiveLoop()
            try await created

            async let updated: Void = waitForConnectEvent("session.updated")
            try await sendSessionUpdate()
            try await updated
            isConnected = true
        } catch {
            disconnect()
            throw error
        }
    }

    func disconnect() {
        receiveLoopRunning = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        expectedConnectEvent = nil
        invalidateAskState(resumeWith: CancellationError())
        outstandingResponseCreates.removeAll()
        if let cont = connectContinuation {
            connectContinuation = nil
            cont.resume(throwing: CancellationError())
        }
    }

    /// Cancel an in-flight `ask` without tearing down the socket.
    func cancelPendingAsk() {
        invalidateAskState(resumeWith: CancellationError())
        // Best-effort: stop an in-flight model response so fewer late events arrive.
        Task { @MainActor in
            try? await self.sendJSON(["type": "response.cancel"])
        }
    }

    /// Send user text, run any tool loops, return final assistant text.
    func ask(_ userText: String) async throws -> String {
        if !isConnected {
            try await connect()
        }
        guard webSocket != nil else { throw VoiceAssistantError.realtimeNotConnected }

        // Supersede any prior ask; leave outstanding create gens so late dones drain as stale.
        askGeneration &+= 1
        let generation = askGeneration
        toolCallTask?.cancel()
        toolCallTask = nil
        askTimeoutTask?.cancel()
        askTimeoutTask = nil
        awaitingToolFollowUp = false
        pendingAssistantText = ""

        // Register continuation BEFORE response.create so an early response.done cannot race.
        return try await withCheckedThrowingContinuation { cont in
            if let previous = self.responseContinuation {
                self.responseContinuation = nil
                previous.resume(throwing: CancellationError())
            }
            self.responseContinuation = cont
            self.armAskTimeout(generation: generation)
            Task { @MainActor in
                do {
                    guard self.askGeneration == generation else { return }
                    try await self.sendJSON([
                        "type": "conversation.item.create",
                        "item": [
                            "type": "message",
                            "role": "user",
                            "content": [
                                ["type": "input_text", "text": userText],
                            ],
                        ] as [String: Any],
                    ])
                    try await self.beginResponseCreate(generation: generation)
                } catch {
                    guard self.askGeneration == generation else { return }
                    self.askTimeoutTask?.cancel()
                    self.askTimeoutTask = nil
                    guard let pending = self.responseContinuation else { return }
                    self.responseContinuation = nil
                    pending.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func waitForConnectEvent(_ type: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            if let previous = self.connectContinuation {
                self.connectContinuation = nil
                previous.resume(throwing: CancellationError())
            }
            self.expectedConnectEvent = type
            self.connectContinuation = cont
        }
    }

    private func sendSessionUpdate() async throws {
        let tools: [[String: Any]] = [
            tool("navigate_hub", "Return to the Synapse hub home screen."),
            tool("return_to_hub", "Alias for navigate_hub — return to hub."),
            tool("open_vision", "Open Vision PVT setup (eye / oculomotor lab module)."),
            tool("open_kinetic", "Open Kinetic Clock setup (Batak punch lab module)."),
            tool("open_focus", "Open Synapse Focus setup (health-aware Pomodoro)."),
            tool(
                "start_session",
                "Start the session for the current route (Vision, Kinetic, or Focus)."
            ),
            tool("stop_session", "Stop the active Vision, Kinetic, or Focus session."),
            tool(
                "start_focus",
                "Start a Focus block. Optional args: focusMinutes (number), breakMinutes (number).",
                properties: [
                    "focusMinutes": ["type": "number", "description": "Focus duration in minutes"],
                    "breakMinutes": ["type": "number", "description": "Break duration in minutes"],
                ]
            ),
            tool("end_focus", "End Focus early and show the recap."),
            tool("start_break", "Accept fade suggestion or start the Focus break now."),
            tool("skip_break", "Skip the current Focus break and finish to recap."),
            tool("extend_focus", "Extend the current Focus block by 5 minutes (once)."),
            tool("pause_focus", "Pause the Focus timer."),
            tool("resume_focus", "Resume a paused Focus timer."),
            tool(
                "get_focus_status",
                "Read Focus status: phase, remaining, fade score, HR, fade count, session."
            ),
            tool(
                "start_breathing",
                "Start the guided breathing reset on Focus break (ElevenLabs inhale/hold/exhale cues)."
            ),
            tool(
                "lock_in_ten",
                "After a break or breathing reset, lock in another 10-minute Focus block."
            ),
            tool("calibrate_watch", "Start Apple Watch IMU calibration (Kinetic)."),
            tool("calibrate_gaze", "Calibrate gaze to screen center (Vision)."),
            tool(
                "get_status",
                "Read live app status: route, watch, HR, sync, session, break-point, baseline, Focus."
            ),
        ]

        try await sendJSON([
            "type": "session.update",
            "session": [
                "modalities": ["text"],
                "instructions": Self.systemInstructions,
                "tools": tools,
                "tool_choice": "auto",
                // Prefer one tool at a time so we never need multiple response.create per hop.
                "parallel_tool_calls": false,
            ] as [String: Any],
        ])
    }

    private static let systemInstructions = """
    You are Synapse, a calm on-device coach for health-aware focus and a clinical / athletic lab on iPhone.
    Primary product: Focus (health-aware Pomodoro) — timed desk focus with face arousal + Watch HR \
    fade detection. Lab modules: Vision PVT (eye tracking) and Kinetic Clock (air-punch; Watch strikes).
    Keep replies short (1–2 sentences) — they are spoken aloud via TTS.
    Use tools to navigate and control sessions; call get_status or get_focus_status when unsure.
    During focusLive: stay quiet unless fade is suggested, the user speaks, or the timer ends. \
    Do not chatter mid-focus. Setup tips, countdown/start, fade nudge, break start, breathing reset, \
    lock-in-10, and recap are appropriate.
    Do not narrate every Kinetic target/octant during live trials.
    Never invent sensor values — use get_status / get_focus_status.
    """

    private func tool(
        _ name: String,
        _ description: String,
        properties: [String: Any] = [:]
    ) -> [String: Any] {
        [
            "type": "function",
            "name": name,
            "description": description,
            "parameters": [
                "type": "object",
                "properties": properties,
                "additionalProperties": false,
            ] as [String: Any],
        ]
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let webSocket else { throw VoiceAssistantError.realtimeNotConnected }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw VoiceAssistantError.badURL
        }
        try await webSocket.send(.string(text))
    }

    private func startReceiveLoop() {
        guard !receiveLoopRunning else { return }
        receiveLoopRunning = true
        receiveNext()
    }

    private func receiveNext() {
        guard receiveLoopRunning, let webSocket else { return }
        webSocket.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.isConnected = false
                    self.receiveLoopRunning = false
                    if let cont = self.connectContinuation {
                        self.connectContinuation = nil
                        self.expectedConnectEvent = nil
                        cont.resume(throwing: error)
                    }
                    self.invalidateAskState(resumeWith: error)
                case .success(let message):
                    self.handle(message)
                    if self.receiveLoopRunning {
                        self.receiveNext()
                    }
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String?
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8)
        @unknown default: text = nil
        }
        guard let text,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "error":
            let errMsg = (json["error"] as? [String: Any])?["message"] as? String ?? String(text.prefix(200))
            let error = VoiceAssistantError.realtimeError(errMsg)
            if let cont = connectContinuation {
                connectContinuation = nil
                expectedConnectEvent = nil
                cont.resume(throwing: error)
            }
            invalidateAskState(resumeWith: error)

        case "session.created", "session.updated":
            if expectedConnectEvent == type, let cont = connectContinuation {
                connectContinuation = nil
                expectedConnectEvent = nil
                cont.resume()
            }

        case "response.text.delta", "response.output_text.delta":
            // Only accumulate while the oldest outstanding create belongs to the current ask.
            guard outstandingResponseCreates.first == askGeneration,
                  let delta = json["delta"] as? String
            else { return }
            pendingAssistantText += delta

        case "response.done":
            handleResponseDone(json)

        default:
            break
        }
    }

    private func handleResponseDone(_ json: [String: Any]) {
        guard !outstandingResponseCreates.isEmpty else { return }
        let generation = outstandingResponseCreates.removeFirst()
        // Late done from a cancelled/superseded ask — do not touch the current continuation.
        guard generation == askGeneration else { return }

        let response = json["response"] as? [String: Any]
        let output = response?["output"] as? [[String: Any]] ?? []
        let functionCalls = output.filter { ($0["type"] as? String) == "function_call" }

        // Prefer text from this done event so stale deltas cannot pollute a later ask.
        var textFromDone = ""
        for item in output where (item["type"] as? String) == "message" {
            if let content = item["content"] as? [[String: Any]] {
                for part in content {
                    if let t = part["text"] as? String {
                        textFromDone += t
                    }
                }
            }
        }
        if !textFromDone.isEmpty {
            pendingAssistantText = textFromDone
        }

        if !functionCalls.isEmpty {
            // Tool execution batches all outputs, then sends a single response.create.
            awaitingToolFollowUp = true
            pendingAssistantText = ""
            toolCallTask?.cancel()
            toolCallTask = Task { @MainActor in
                await self.completeToolCalls(functionCalls, generation: generation)
            }
            return
        }

        // Final hop — always complete ask, even with empty text after a tool-only follow-up.
        awaitingToolFollowUp = false
        completeWithPendingText(generation: generation)
    }

    /// Run every function_call from one response, emit all outputs, then one response.create.
    private func completeToolCalls(_ calls: [[String: Any]], generation: UInt64) async {
        do {
            for call in calls {
                try Task.checkCancellation()
                guard askGeneration == generation else { return }
                let callId = call["call_id"] as? String ?? ""
                let name = call["name"] as? String ?? ""
                let arguments = call["arguments"] as? String ?? "{}"
                let output: String
                if let onToolCall {
                    output = await onToolCall(name, arguments)
                } else {
                    output = #"{"ok":false,"error":"no tool handler"}"#
                }
                guard askGeneration == generation else { return }
                try Task.checkCancellation()
                try await sendJSON([
                    "type": "conversation.item.create",
                    "item": [
                        "type": "function_call_output",
                        "call_id": callId,
                        "output": output,
                    ] as [String: Any],
                ])
            }
            try await beginResponseCreate(generation: generation)
        } catch is CancellationError {
            // Cancelled via toolCallTask / ask supersession — leave state to invalidateAskState.
            return
        } catch {
            guard askGeneration == generation else { return }
            awaitingToolFollowUp = false
            askTimeoutTask?.cancel()
            askTimeoutTask = nil
            if let cont = responseContinuation {
                responseContinuation = nil
                cont.resume(throwing: error)
            }
        }
    }

    private func completeWithPendingText(generation: UInt64) {
        guard askGeneration == generation else { return }
        guard let cont = responseContinuation else { return }
        askTimeoutTask?.cancel()
        askTimeoutTask = nil
        let text = pendingAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        responseContinuation = nil
        pendingAssistantText = ""
        cont.resume(returning: text)
    }

    /// Enqueue a create under `generation`, then send. Rolls back the queue entry if send fails.
    private func beginResponseCreate(generation: UInt64) async throws {
        guard askGeneration == generation else { throw CancellationError() }
        try Task.checkCancellation()
        outstandingResponseCreates.append(generation)
        do {
            try await sendJSON(["type": "response.create"])
        } catch {
            if outstandingResponseCreates.last == generation {
                outstandingResponseCreates.removeLast()
            }
            throw error
        }
    }

    private func armAskTimeout(generation: UInt64) {
        askTimeoutTask?.cancel()
        askTimeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: Self.askTimeoutNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, self.askGeneration == generation else { return }
            guard self.responseContinuation != nil else { return }
            self.invalidateAskState(resumeWith: VoiceAssistantError.realtimeError("Ask timed out"))
            try? await self.sendJSON(["type": "response.cancel"])
        }
    }

    /// Bump generation, cancel in-flight tool/timeout work, clear flags, fail the continuation.
    private func invalidateAskState(resumeWith error: Error) {
        askGeneration &+= 1
        toolCallTask?.cancel()
        toolCallTask = nil
        askTimeoutTask?.cancel()
        askTimeoutTask = nil
        awaitingToolFollowUp = false
        pendingAssistantText = ""
        // Keep `outstandingResponseCreates` so late `response.done` events dequeue as stale.
        if let cont = responseContinuation {
            responseContinuation = nil
            cont.resume(throwing: error)
        }
    }
}
