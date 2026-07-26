import Foundation
import Observation

enum BreathPhase: Equatable, Sendable {
    case idle
    case intro
    case inhale
    case hold
    case exhale
    case complete

    static func parse(_ raw: String) -> BreathPhase? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "idle": return .idle
        case "intro", "settle": return .intro
        case "inhale", "in": return .inhale
        case "hold": return .hold
        case "exhale", "out": return .exhale
        case "complete", "done", "finished": return .complete
        default: return nil
        }
    }
}

/// Guided inhale / hold / exhale UI. Voice cues come from the ElevenLabs agent
/// (`set_breath_phase`); this coach owns ring timing only.
@Observable
@MainActor
final class BreathingCoach {
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

    private var tickTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var phaseDeadline: TimeInterval?
    private var agentDriven = false

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

    /// Prepare UI for agent-driven breath mode (no local timing loop).
    func prepareForAgent(cycles: Int = BreathingCoach.defaultCycles) {
        stop()
        agentDriven = true
        totalCycles = max(3, cycles)
        cycleIndex = 0
        overallProgress = 0
        isRunning = true
        phase = .intro
        statusText = "Breathing reset"
        phaseRemaining = 0
    }

    /// Agent tool `set_breath_phase` — sync UI + optional timed ring.
    func applyAgentPhase(_ next: BreathPhase, seconds: TimeInterval? = nil) {
        if !isRunning, next != .idle, next != .complete {
            prepareForAgent()
        }
        agentDriven = true

        switch next {
        case .idle:
            stop()
        case .intro:
            phase = .intro
            statusText = "Settle"
            phaseRemaining = 0
            tickTask?.cancel()
        case .inhale:
            beginTimedPhase(.inhale, seconds: seconds ?? Self.inhaleSeconds, cue: "Inhale")
        case .hold:
            beginTimedPhase(.hold, seconds: seconds ?? Self.holdSeconds, cue: "Hold")
        case .exhale:
            beginTimedPhase(.exhale, seconds: seconds ?? Self.exhaleSeconds, cue: "Exhale")
            // Advance cycle when an exhale starts (agent may not track index).
            if cycleIndex < totalCycles - 1 {
                // Count completed cycles after exhale finishes via deadline — bump on start of next inhale.
            }
        case .complete:
            finishComplete()
        }
    }

    /// Called when user taps Breathing reset without / before agent — silent timed fallback.
    func startLocalFallback(cycles: Int = BreathingCoach.defaultCycles) {
        stop()
        agentDriven = false
        totalCycles = max(3, cycles)
        cycleIndex = 0
        overallProgress = 0
        isRunning = true
        phase = .intro
        statusText = "Breathing reset"
        fallbackTask = Task { @MainActor in
            await self.runSilentSequence()
        }
    }

    /// Legacy entry used when agent will drive phases immediately after.
    func start(cycles: Int = BreathingCoach.defaultCycles) {
        prepareForAgent(cycles: cycles)
    }

    func stop() {
        fallbackTask?.cancel()
        fallbackTask = nil
        tickTask?.cancel()
        tickTask = nil
        phaseDeadline = nil
        agentDriven = false
        if phase != .complete {
            phase = .idle
        }
        isRunning = false
        phaseRemaining = 0
        statusText = phase == .complete ? "Reset complete" : "Ready"
    }

    // MARK: - Timed phases

    private func beginTimedPhase(_ next: BreathPhase, seconds: TimeInterval, cue: String) {
        if next == .inhale, phase == .exhale || phase == .intro {
            // New cycle after prior exhale / intro.
            if phase == .exhale {
                cycleIndex = min(totalCycles - 1, cycleIndex + 1)
            }
        }
        phase = next
        statusText = cue
        let start = ProcessInfo.processInfo.systemUptime
        phaseDeadline = start + seconds
        phaseRemaining = seconds
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            let duration = seconds
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
    }

    private func finishComplete() {
        tickTask?.cancel()
        tickTask = nil
        phase = .complete
        isRunning = false
        overallProgress = 1
        phaseRemaining = 0
        statusText = "Reset complete"
        onComplete?()
    }

    private func runSilentSequence() async {
        do {
            try await waitSeconds(2)
            try Task.checkCancellation()
            for i in 0..<totalCycles {
                try Task.checkCancellation()
                cycleIndex = i
                beginTimedPhase(.inhale, seconds: Self.inhaleSeconds, cue: "Inhale")
                try await waitSeconds(Self.inhaleSeconds)
                beginTimedPhase(.hold, seconds: Self.holdSeconds, cue: "Hold")
                try await waitSeconds(Self.holdSeconds)
                beginTimedPhase(.exhale, seconds: Self.exhaleSeconds, cue: "Exhale")
                try await waitSeconds(Self.exhaleSeconds)
            }
            try Task.checkCancellation()
            finishComplete()
        } catch is CancellationError {
            // stopped
        } catch {
            statusText = error.localizedDescription
            finishComplete()
        }
    }

    private func waitSeconds(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try Task.checkCancellation()
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
}
