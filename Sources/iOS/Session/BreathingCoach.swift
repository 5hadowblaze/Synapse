import Foundation
import Observation

enum BreathPhase: Equatable, Sendable {
    case idle
    case intro
    case inhale
    case hold
    case exhale
    case complete
}

/// Guided inhale / hold / exhale with ElevenLabs TTS cues (~2–3 minutes).
@Observable
@MainActor
final class BreathingCoach {
    /// Default: intro + 8 cycles of 4/4/6 ≈ 2.3 min of timed breath + speech.
    nonisolated static let defaultCycles = 8
    nonisolated static let inhaleSeconds: TimeInterval = 4
    nonisolated static let holdSeconds: TimeInterval = 4
    nonisolated static let exhaleSeconds: TimeInterval = 6

    private(set) var phase: BreathPhase = .idle
    private(set) var cycleIndex = 0
    private(set) var totalCycles = BreathingCoach.defaultCycles
    private(set) var phaseRemaining: TimeInterval = 0
    private(set) var isRunning = false
    private(set) var statusText = "Ready"
    /// 0…1 progress through the full reset.
    private(set) var overallProgress: Double = 0

    var onComplete: (() -> Void)?

    private let tts = ElevenLabsSpeechSynthesizer()
    private var runTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var phaseDeadline: TimeInterval?

    var phaseLabel: String {
        switch phase {
        case .idle: return "Idle"
        case .intro: return "Settle"
        case .inhale: return "Inhale"
        case .hold: return "Hold"
        case .exhale: return "Exhale"
        case .complete: return "Done"
        }
    }

    func start(cycles: Int = BreathingCoach.defaultCycles) {
        stop()
        totalCycles = max(3, cycles)
        cycleIndex = 0
        overallProgress = 0
        isRunning = true
        phase = .intro
        statusText = "Breathing reset"
        runTask = Task { @MainActor in
            await self.runSequence()
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        tickTask?.cancel()
        tickTask = nil
        tts.stop()
        phaseDeadline = nil
        if phase != .complete {
            phase = .idle
        }
        isRunning = false
        phaseRemaining = 0
        statusText = phase == .complete ? "Reset complete" : "Ready"
    }

    // MARK: - Sequence

    private func runSequence() async {
        do {
            try await speakCue("Breathing reset. Find a soft gaze. We'll inhale, hold, and exhale together.")
            try Task.checkCancellation()

            for i in 0..<totalCycles {
                try Task.checkCancellation()
                cycleIndex = i
                updateOverallProgress(cycle: i, phaseFrac: 0)

                try await runTimedPhase(.inhale, seconds: Self.inhaleSeconds, cue: "Inhale")
                try await runTimedPhase(.hold, seconds: Self.holdSeconds, cue: "Hold")
                try await runTimedPhase(.exhale, seconds: Self.exhaleSeconds, cue: "Exhale")
            }

            try Task.checkCancellation()
            phase = .complete
            isRunning = false
            overallProgress = 1
            statusText = "Reset complete"
            try await speakCue("Nice. You're reset. Lock in another ten minutes when you're ready.")
            onComplete?()
        } catch is CancellationError {
            // stopped
        } catch {
            statusText = error.localizedDescription
            // Still mark complete so the Lock-in CTA can appear after a partial reset.
            phase = .complete
            isRunning = false
            onComplete?()
        }
    }

    private func runTimedPhase(_ next: BreathPhase, seconds: TimeInterval, cue: String) async throws {
        phase = next
        statusText = cue
        // Speak briefly, then hold the timed window (speech may overlap first second).
        Task { @MainActor in
            try? await self.speakCue(cue)
        }
        try await waitSeconds(seconds)
    }

    private func waitSeconds(_ seconds: TimeInterval) async throws {
        let start = ProcessInfo.processInfo.systemUptime
        phaseDeadline = start + seconds
        phaseRemaining = seconds
        let duration = seconds
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                let now = ProcessInfo.processInfo.systemUptime
                guard let deadline = self.phaseDeadline else { return }
                let left = max(0, deadline - now)
                self.phaseRemaining = left
                let phaseFrac = 1.0 - (left / max(0.001, duration))
                self.updateOverallProgress(cycle: self.cycleIndex, phaseFrac: phaseFrac)
                if left <= 0 { return }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try Task.checkCancellation()
        tickTask?.cancel()
        tickTask = nil
        phaseRemaining = 0
    }

    private func updateOverallProgress(cycle: Int, phaseFrac: Double = 0) {
        let total = Double(max(1, totalCycles))
        let phaseIndex: Double = {
            switch phase {
            case .inhale: return 0
            case .hold: return 1
            case .exhale: return 2
            default: return 0
            }
        }()
        let frac = (phaseIndex + min(1, max(0, phaseFrac))) / 3.0
        overallProgress = min(1, (Double(cycle) + frac) / total)
    }

    private func speakCue(_ text: String) async throws {
        guard !VoiceConfig.elevenLabsKey.isEmpty else {
            // No key — still advance the timer UX silently.
            return
        }
        try await tts.speak(text)
    }
}
