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
    /// Human name shown above the minutes ("Classic", "Deep", "Quick").
    let name: String
    let focusMinutes: Int
    let breakMinutes: Int
    /// Fade-baseline samples this preset needs before a break can be suggested.
    /// Short blocks calibrate on fewer samples so the fade signal is usable inside the block.
    let baselineSamples: Int
    let note: String

    var title: String { "\(focusMinutes) / \(breakMinutes)" }

    /// True when the block reaches a usable baseline in well under a minute.
    var calibratesFast: Bool { baselineSamples < FocusFadeDetector.defaultBaselineSamples }

    /// Rough seconds until the fade baseline is ready on this preset.
    var baselineSeconds: Int {
        Int(Double(baselineSamples) * FocusFadeDetector.defaultSampleIntervalSeconds)
    }

    static let standard = FocusPreset(
        id: "25-5",
        name: "Classic",
        focusMinutes: 25,
        breakMinutes: 5,
        baselineSamples: FocusFadeDetector.defaultBaselineSamples,
        note: "The default Pomodoro, with fade watching underneath."
    )
    static let short = FocusPreset(
        id: "15-5",
        name: "Short",
        focusMinutes: 15,
        breakMinutes: 5,
        baselineSamples: FocusFadeDetector.defaultBaselineSamples,
        note: "One tight pass at a single task."
    )
    static let deep = FocusPreset(
        id: "50-10",
        name: "Deep",
        focusMinutes: 50,
        breakMinutes: 10,
        baselineSamples: FocusFadeDetector.defaultBaselineSamples,
        note: "Long block for work that needs a running start."
    )
    /// Short sprint that reaches a fade baseline in ~30 s — the block to open on when
    /// you want the fade signal live almost immediately.
    static let quick = FocusPreset(
        id: "5-1",
        name: "Quick",
        focusMinutes: 5,
        breakMinutes: 1,
        baselineSamples: FocusFadeDetector.quickBaselineSamples,
        note: "Sprint block. Reads your baseline in about 30 seconds."
    )
    /// Hidden behind Settings — same fast calibration as Quick, compressed for a stage run.
    static let demo = FocusPreset(
        id: "2-1",
        name: "Demo",
        focusMinutes: 2,
        breakMinutes: 1,
        baselineSamples: FocusFadeDetector.quickBaselineSamples,
        note: "Stage timing only. Two-minute block, one-minute break."
    )

    static let all: [FocusPreset] = [.standard, .short, .deep, .quick]
    static let allIncludingDemo: [FocusPreset] = all + [.demo]
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

/// Three legible states the Focus HUD can show, in escalation order.
/// Deliberately calm: `easing` is an observation, not a warning.
///
/// There is deliberately no absolute score threshold here. The composite fade score is
/// session-relative — its resting value depends on which channels calibrated and how
/// noisy they were — so any fixed cut point drifts out of order with the fade threshold
/// as the scoring changes underneath it. `FocusFadeDetector.easingThreshold` sits at the
/// midpoint between this session's baseline mean and its own fade threshold, which keeps
/// the three states in escalation order by construction.
enum FocusSignalState: Equatable, Sendable {
    /// Signals are holding near your baseline.
    case steady
    /// Fade score is drifting up but has not crossed the break threshold.
    case easing
    /// Threshold crossed — Synapse is asking for a break.
    case breakSuggested
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
    /// Fade-baseline samples for the next / current block (set from the chosen preset).
    var baselineSamples = FocusPreset.standard.baselineSamples
    var remainingSeconds: TimeInterval = 0
    var fadeScore: Double?
    var fadeSuggested = false
    var fadeCount = 0
    var didExtend = false
    var statusText = "Ready"
    var baselineReady = false
    /// 0…1 progress toward a usable fade baseline.
    var baselineProgress: Double = 0
    /// True once the sample window is full but the detector is still holding out for a
    /// settled heart rate. Progress stops climbing here, so the HUD needs to say why.
    var isSettlingBaseline = false
    /// Session-relative score above which the HUD reads `easing`. Nil until calibrated.
    var fadeEasingThreshold: Double?
    /// 0…1 from the baseline mean toward the fade threshold. Drives the HUD ring, which
    /// the raw score cannot: at rest the score sits near 0.01–0.05 and would look dead.
    var fadeProgress: Double?
    var lastHrBpm: Double?
    var lastArousal: Float?
    var lastMotionEnergy: Double?
    var epochIndex = 0
    /// Session HR reference used by the fade detector (and brief-mode HR spike wake).
    var hrAnchorBpm: Double? { fadeDetector.currentHrAnchor }

    /// No arousal update for this long means the face is gone, not that it stopped moving.
    /// Gaze arrives at frame rate while tracking, so this only trips on a real loss.
    static let arousalStaleAfter: TimeInterval = 8

    private(set) var focusedElapsed: TimeInterval = 0
    private(set) var breakElapsed: TimeInterval = 0
    private var hrSamples: [Double] = []
    private var lastArousalAt: TimeInterval?

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

    /// Three-state read for the HUD. `easing` sits between a calm block and a break request.
    /// The middle state is only claimable once the session has a baseline to be relative to.
    var signalState: FocusSignalState {
        if fadeSuggested || phase == .breakSuggested { return .breakSuggested }
        guard baselineReady, let score = fadeScore, let easing = fadeEasingThreshold else {
            return .steady
        }
        return score > easing ? .easing : .steady
    }

    func configure(preset: FocusPreset) {
        focusMinutes = preset.focusMinutes
        breakMinutes = preset.breakMinutes
        baselineSamples = preset.baselineSamples
    }

    func configure(focusMinutes: Int, breakMinutes: Int, baselineSamples: Int? = nil) {
        self.focusMinutes = max(1, focusMinutes)
        self.breakMinutes = max(1, breakMinutes)
        self.baselineSamples = baselineSamples ?? Self.inferredBaselineSamples(focusMinutes: self.focusMinutes)
    }

    /// Voice / lock-in paths pass raw minutes with no preset — keep short blocks usable.
    static func inferredBaselineSamples(focusMinutes: Int) -> Int {
        focusMinutes <= FocusPreset.quick.focusMinutes
            ? FocusFadeDetector.quickBaselineSamples
            : FocusFadeDetector.defaultBaselineSamples
    }

    func startSession(
        focusMinutes: Int? = nil,
        breakMinutes: Int? = nil,
        baselineSamples: Int? = nil,
        fadeDetector: FocusFadeDetector? = nil
    ) {
        stopSession(emitComplete: false)
        if let focusMinutes { self.focusMinutes = max(1, focusMinutes) }
        if let breakMinutes { self.breakMinutes = max(1, breakMinutes) }
        if let baselineSamples {
            self.baselineSamples = max(2, baselineSamples)
        } else if focusMinutes != nil {
            self.baselineSamples = Self.inferredBaselineSamples(focusMinutes: self.focusMinutes)
        }
        if let fadeDetector {
            self.fadeDetector = fadeDetector
        } else {
            self.fadeDetector = FocusFadeDetector(baselineSamples: self.baselineSamples)
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
        baselineProgress = 0
        isSettlingBaseline = false
        fadeEasingThreshold = nil
        fadeProgress = nil
        lastArousal = nil
        lastArousalAt = nil
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
        // Soft nudge only — timer still completes if the user dismisses or ignores.
        statusText = "Break suggested — take a pause?"
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

    /// Nil means the face was lost. It must propagate: the detector drops the arousal
    /// channel and renormalises the remaining weights, which is a truthful "we cannot see
    /// you" rather than a fade score built on a reading frozen at look-away time.
    func ingestArousal(_ value: Float?) {
        guard isRunning else { return }
        lastArousal = value
        lastArousalAt = value == nil ? nil : ProcessInfo.processInfo.systemUptime
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
        expireStaleArousal(now: now)
        let fired = fadeDetector.ingest(
            now: now,
            hrBpm: lastHrBpm,
            arousal: lastArousal,
            motionEnergy: lastMotionEnergy
        )
        fadeScore = fadeDetector.lastScore
        baselineProgress = fadeDetector.baselineProgress
        fadeEasingThreshold = fadeDetector.easingThreshold
        fadeProgress = fadeDetector.fadeProgress
        isSettlingBaseline = !fadeDetector.isBaselineReady
            && fadeDetector.baselineSampleCount >= fadeDetector.baselineCapacity
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

    /// Gaze callbacks stop entirely if the face anchor is dropped, so the last nil may
    /// never arrive. Age the value out rather than trusting the loss to be announced.
    /// Internal so tests can drive it with an explicit clock.
    func expireStaleArousal(now: TimeInterval) {
        guard lastArousal != nil else { return }
        guard let seenAt = lastArousalAt else {
            lastArousal = nil
            return
        }
        if now - seenAt > Self.arousalStaleAfter {
            lastArousal = nil
            lastArousalAt = nil
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
