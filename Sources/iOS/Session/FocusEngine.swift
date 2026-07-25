import Foundation

enum FocusPhase: Equatable, Sendable {
    case idle
    case focusing
    case breakSuggested
    case onBreak
    case complete
}

struct FocusPreset: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let focusMinutes: Int
    let breakMinutes: Int

    static let standard = FocusPreset(id: "25-5", title: "25 / 5", focusMinutes: 25, breakMinutes: 5)
    static let short = FocusPreset(id: "15-5", title: "15 / 5", focusMinutes: 15, breakMinutes: 5)
    static let deep = FocusPreset(id: "50-10", title: "50 / 10", focusMinutes: 50, breakMinutes: 10)
    static let demo = FocusPreset(id: "2-1", title: "Demo 2 / 1", focusMinutes: 2, breakMinutes: 1)

    static let all: [FocusPreset] = [.standard, .short, .deep, .demo]
}

struct FocusEpochSnapshot: Equatable, Sendable {
    let index: Int
    let phase: String
    let remainingMs: Double
    let fadeScore: Double?
    let hrBpm: Double?
    let arousal: Float?
    let motionEnergy: Double?
    let fadeSuggested: Bool
}

struct FocusRecap: Equatable, Sendable {
    let focusedSeconds: TimeInterval
    let breakSeconds: TimeInterval
    let fadeCount: Int
    let meanHrBpm: Double?
    let baselineReady: Bool
    let extendedOnce: Bool
    var focusedMinutesLabel: String {
        let m = Int(focusedSeconds / 60)
        let s = Int(focusedSeconds.truncatingRemainder(dividingBy: 60))
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}

/// Desk Focus: timed Pomodoro with soft fade suggestions (not Vision/Kinetic trials).
@Observable
@MainActor
final class FocusEngine {
    var phase: FocusPhase = .idle
    var isRunning = false
    var isPaused = false
    var focusMinutes = FocusPreset.standard.focusMinutes
    var breakMinutes = FocusPreset.standard.breakMinutes
    var remainingSeconds: TimeInterval = 0
    var fadeScore: Double?
    var fadeSuggested = false
    var fadeCount = 0
    var didExtend = false
    var statusText = "Ready"
    var baselineReady = false
    var lastHrBpm: Double?
    var lastArousal: Float?
    var lastMotionEnergy: Double?
    var epochIndex = 0

    private(set) var focusedElapsed: TimeInterval = 0
    private(set) var breakElapsed: TimeInterval = 0
    private var hrSamples: [Double] = []

    private var fadeDetector = FocusFadeDetector()
    private var tickTask: Task<Void, Never>?
    private var epochTask: Task<Void, Never>?
    private var phaseStartedAt: TimeInterval?
    private var remainingAtPhaseStart: TimeInterval = 0

    var onFadeSuggested: (() -> Void)?
    var onBreakStarted: (() -> Void)?
    var onComplete: ((FocusRecap) -> Void)?
    var onEpoch: ((FocusEpochSnapshot) -> Void)?
    var onBaselineReady: ((Double, Double) -> Void)?

    var phaseLabel: String {
        switch phase {
        case .idle: return "Idle"
        case .focusing: return "Focus"
        case .breakSuggested: return "Fade"
        case .onBreak: return "Break"
        case .complete: return "Done"
        }
    }

    func configure(preset: FocusPreset) {
        focusMinutes = preset.focusMinutes
        breakMinutes = preset.breakMinutes
    }

    func configure(focusMinutes: Int, breakMinutes: Int) {
        self.focusMinutes = max(1, focusMinutes)
        self.breakMinutes = max(1, breakMinutes)
    }

    func startSession(
        focusMinutes: Int? = nil,
        breakMinutes: Int? = nil,
        fadeDetector: FocusFadeDetector? = nil
    ) {
        stopSession(emitComplete: false)
        if let focusMinutes { self.focusMinutes = max(1, focusMinutes) }
        if let breakMinutes { self.breakMinutes = max(1, breakMinutes) }
        if let fadeDetector {
            self.fadeDetector = fadeDetector
        } else {
            // Demo blocks: shorten baseline so fade can fire within the block.
            let samples = self.focusMinutes <= 3 ? 4 : FocusFadeDetector.defaultBaselineSamples
            self.fadeDetector = FocusFadeDetector(baselineSamples: samples)
        }
        self.fadeDetector.reset()

        remainingSeconds = TimeInterval(self.focusMinutes * 60)
        remainingAtPhaseStart = remainingSeconds
        phaseStartedAt = ProcessInfo.processInfo.systemUptime
        focusedElapsed = 0
        breakElapsed = 0
        hrSamples = []
        fadeScore = nil
        fadeSuggested = false
        fadeCount = 0
        didExtend = false
        baselineReady = false
        epochIndex = 0
        isPaused = false
        isRunning = true
        phase = .focusing
        statusText = "Focus \(self.focusMinutes)m"
        startTick()
        startEpochWriter()
    }

    func stopSession(emitComplete: Bool = true) {
        tickTask?.cancel()
        tickTask = nil
        epochTask?.cancel()
        epochTask = nil
        isRunning = false
        isPaused = false
        let wasActive = phase == .focusing || phase == .breakSuggested || phase == .onBreak
        if wasActive {
            accumulateElapsed()
        }
        if emitComplete, wasActive || phase == .complete {
            finish(emit: true)
        } else {
            phase = .idle
            statusText = "Stopped"
        }
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        guard phase == .focusing || phase == .breakSuggested || phase == .onBreak else { return }
        accumulateElapsed()
        isPaused = true
        statusText = "Paused"
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        remainingAtPhaseStart = remainingSeconds
        phaseStartedAt = ProcessInfo.processInfo.systemUptime
        statusText = phase == .onBreak ? "Break" : "Focus"
    }

    /// Soft fade: suggest break; user accepts via `startBreak()` or timer ends.
    func noteFadeSuggested() {
        guard phase == .focusing else { return }
        phase = .breakSuggested
        fadeSuggested = true
        fadeCount = fadeDetector.fadeCount
        statusText = "Fade detected — take a break?"
        onFadeSuggested?()
    }

    /// Soft-dismiss fade suggestion; stay in focus until next fade or timer.
    func dismissFadeSuggestion() {
        guard phase == .breakSuggested else { return }
        phase = .focusing
        fadeSuggested = false
        statusText = "Focus"
    }

    func startBreak() {
        guard isRunning else { return }
        guard phase == .focusing || phase == .breakSuggested else { return }
        accumulateElapsed()
        phase = .onBreak
        fadeSuggested = false
        remainingSeconds = TimeInterval(breakMinutes * 60)
        remainingAtPhaseStart = remainingSeconds
        phaseStartedAt = ProcessInfo.processInfo.systemUptime
        isPaused = false
        statusText = "Break \(breakMinutes)m"
        onBreakStarted?()
    }

    func skipBreak() {
        guard phase == .onBreak || phase == .breakSuggested else { return }
        if phase == .onBreak {
            accumulateElapsed()
        }
        finish(emit: true)
    }

    /// +5 minutes once per focus block. From break, returns to focusing with +5.
    @discardableResult
    func extendFocus(byMinutes minutes: Int = 5) -> Bool {
        guard !didExtend else { return false }
        guard phase == .focusing || phase == .breakSuggested || phase == .onBreak else { return false }
        let fromBreak = phase == .onBreak
        accumulateElapsed()
        didExtend = true
        if fromBreak || phase == .breakSuggested {
            phase = .focusing
            fadeSuggested = false
        }
        if fromBreak {
            remainingSeconds = TimeInterval(minutes * 60)
        } else {
            remainingSeconds += TimeInterval(minutes * 60)
        }
        remainingAtPhaseStart = remainingSeconds
        phaseStartedAt = ProcessInfo.processInfo.systemUptime
        isPaused = false
        statusText = "Extended +\(minutes)m"
        return true
    }

    func ingestHeartRate(_ bpm: Double) {
        guard isRunning else { return }
        lastHrBpm = bpm
        hrSamples.append(bpm)
        evaluateFade()
    }

    func ingestArousal(_ value: Float) {
        guard isRunning else { return }
        lastArousal = value
        evaluateFade()
    }

    func ingestMotionEnergy(_ energy: Double) {
        guard isRunning else { return }
        lastMotionEnergy = energy
        evaluateFade()
    }

    func makeRecap() -> FocusRecap {
        let meanHr = hrSamples.isEmpty
            ? nil
            : hrSamples.reduce(0, +) / Double(hrSamples.count)
        return FocusRecap(
            focusedSeconds: focusedElapsed,
            breakSeconds: breakElapsed,
            fadeCount: fadeCount,
            meanHrBpm: meanHr,
            baselineReady: baselineReady,
            extendedOnce: didExtend
        )
    }

    // MARK: - Private

    private func evaluateFade() {
        guard phase == .focusing || phase == .breakSuggested else { return }
        guard !isPaused else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let fired = fadeDetector.ingest(
            now: now,
            hrBpm: lastHrBpm,
            arousal: lastArousal,
            motionEnergy: lastMotionEnergy
        )
        fadeScore = fadeDetector.lastScore
        if fadeDetector.isBaselineReady, !baselineReady {
            baselineReady = true
            if let mean = fadeDetector.baselineMean, let std = fadeDetector.baselineStd {
                onBaselineReady?(mean, std)
            }
        }
        if fired {
            fadeCount = fadeDetector.fadeCount
            noteFadeSuggested()
        }
    }

    private func startTick() {
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            while !Task.isCancelled, self.isRunning {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func startEpochWriter() {
        epochTask?.cancel()
        epochTask = Task { @MainActor in
            while !Task.isCancelled, self.isRunning {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, self.isRunning else { return }
                self.emitEpoch()
            }
        }
    }

    private func tick() {
        guard isRunning, !isPaused else { return }
        guard let started = phaseStartedAt else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        remainingSeconds = max(0, remainingAtPhaseStart - elapsed)

        if remainingSeconds <= 0 {
            switch phase {
            case .focusing, .breakSuggested:
                startBreak()
            case .onBreak:
                accumulateElapsed()
                finish(emit: true)
            default:
                break
            }
        }
    }

    private func accumulateElapsed() {
        guard let started = phaseStartedAt else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let consumed = min(remainingAtPhaseStart, max(0, elapsed))
        switch phase {
        case .focusing, .breakSuggested:
            focusedElapsed += consumed
        case .onBreak:
            breakElapsed += consumed
        default:
            break
        }
        phaseStartedAt = nil
    }

    private func finish(emit: Bool) {
        tickTask?.cancel()
        tickTask = nil
        epochTask?.cancel()
        epochTask = nil
        isRunning = false
        isPaused = false
        phase = .complete
        remainingSeconds = 0
        statusText = "Complete"
        if emit {
            onComplete?(makeRecap())
        }
    }

    private func emitEpoch() {
        let snap = FocusEpochSnapshot(
            index: epochIndex,
            phase: phaseLabel.lowercased(),
            remainingMs: remainingSeconds * 1000,
            fadeScore: fadeScore,
            hrBpm: lastHrBpm,
            arousal: lastArousal,
            motionEnergy: lastMotionEnergy,
            fadeSuggested: fadeSuggested
        )
        epochIndex += 1
        onEpoch?(snap)
    }
}
