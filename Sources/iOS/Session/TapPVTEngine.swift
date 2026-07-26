import Foundation
import Observation

/// Where a reaction check sits relative to a Focus block.
enum TapPVTStage: String, Codable, Sendable, Equatable {
    case pre
    case post
    case standalone

    var title: String {
        switch self {
        case .pre: return "Before your block"
        case .post: return "After your block"
        case .standalone: return "Reaction check"
        }
    }

    var shortLabel: String {
        switch self {
        case .pre: return "Before"
        case .post: return "After"
        case .standalone: return "Check"
        }
    }
}

/// One stimulus presentation and whatever the user did about it.
struct TapPVTTrial: Codable, Equatable, Sendable, Identifiable {
    let index: Int
    /// Interval from the previous response to this stimulus (ms). Includes the RT
    /// feedback dwell, matching how PVT-B defines its 1–4 s interval.
    let isiMs: Double
    /// Reaction time from stimulus onset to touch-down. Kept on anticipations so the
    /// record shows how early the tap was; nil only when the tap preceded the stimulus
    /// entirely, or when nothing was tapped.
    let reactionMs: Double?
    /// Error of commission: a tap before the stimulus, or faster than human perception.
    let falseStart: Bool
    /// No tap inside the response window.
    let timedOut: Bool

    var id: Int { index }

    /// A trial that produced a usable reaction time. Basner et al.: "A response was
    /// regarded valid if RT was ≥ 100 ms."
    var isValid: Bool {
        guard !falseStart, !timedOut, let reactionMs else { return false }
        return reactionMs >= TapPVTResult.validRtFloorMs
    }

    /// Lapse (error of omission): a response at or beyond the PVT-B threshold, or no
    /// response at all. False starts are scored separately — a jumpy finger is a
    /// different failure from a lapsing one, and mixing them would flatter the user.
    var isLapse: Bool {
        if falseStart { return false }
        if timedOut { return true }
        guard let reactionMs, reactionMs >= TapPVTResult.validRtFloorMs else { return false }
        return reactionMs >= TapPVTResult.lapseThresholdMs
    }

    init(
        index: Int,
        isiMs: Double,
        reactionMs: Double? = nil,
        falseStart: Bool = false,
        timedOut: Bool = false
    ) {
        self.index = index
        self.isiMs = isiMs
        self.reactionMs = reactionMs
        self.falseStart = falseStart
        self.timedOut = timedOut
    }
}

/// Scored output of one reaction check. Pure value type — all stats are derived, not stored.
struct TapPVTResult: Codable, Equatable, Sendable {
    /// PVT-B lapse threshold. Basner et al. (2011) lowered the cutoff from the 10-minute
    /// PVT's 500 ms to 355 ms for the brief variant, chosen so PVT-B lapse frequency
    /// matches what the 10-minute test reports at 500 ms. Using 500 ms on a short test
    /// would undercount lapses, not be "more conservative".
    static let lapseThresholdMs: Double = 355
    /// Responses faster than this are anticipations, not perception (Basner et al.).
    static let validRtFloorMs: Double = 100

    let stage: TapPVTStage
    let startedAt: Date
    let durationSeconds: TimeInterval
    let trials: [TapPVTTrial]

    init(
        stage: TapPVTStage,
        startedAt: Date,
        durationSeconds: TimeInterval,
        trials: [TapPVTTrial]
    ) {
        self.stage = stage
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.trials = trials
    }

    var validReactionsMs: [Double] {
        trials.compactMap { $0.isValid ? $0.reactionMs : nil }
    }

    var medianRtMs: Double? { Self.median(validReactionsMs) }

    var meanRtMs: Double? {
        let values = validReactionsMs
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var fastestRtMs: Double? { validReactionsMs.min() }
    var slowestRtMs: Double? { validReactionsMs.max() }

    var lapseCount: Int { trials.filter(\.isLapse).count }
    var falseStartCount: Int { trials.filter(\.falseStart).count }
    var validCount: Int { trials.filter(\.isValid).count }
    var attemptedCount: Int { trials.count }

    /// Enough clean trials that a median means something.
    var isUsable: Bool { validCount >= 3 }

    var medianLabel: String {
        guard let medianRtMs else { return "—" }
        return "\(Int(medianRtMs.rounded()))"
    }

    /// Median of an unsorted list; even counts average the two middle values.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}

/// Pre vs post comparison — the recap headline.
struct TapPVTComparison: Codable, Equatable, Sendable {
    /// Median moves under this are noise, not fatigue.
    static let deadBandMs: Double = 10

    enum Direction: String, Codable, Sendable {
        case slower
        case faster
        case steady
    }

    let pre: TapPVTResult
    let post: TapPVTResult

    /// Nil unless both sides cleared the usable-trial bar. A run dominated by false
    /// starts leaves too few valid taps to claim a direction from.
    var medianDeltaMs: Double? {
        guard pre.isUsable, post.isUsable,
              let a = pre.medianRtMs, let b = post.medianRtMs else { return nil }
        return b - a
    }

    var lapseDelta: Int { post.lapseCount - pre.lapseCount }

    var percentChange: Double? {
        guard let a = pre.medianRtMs, a > 0, let delta = medianDeltaMs else { return nil }
        return delta / a * 100
    }

    var direction: Direction {
        guard let delta = medianDeltaMs else { return .steady }
        if delta > Self.deadBandMs { return .slower }
        if delta < -Self.deadBandMs { return .faster }
        return .steady
    }

    /// One plain sentence a judge can read off the screen.
    var headline: String {
        guard let delta = medianDeltaMs else {
            return "Not enough clean taps to compare."
        }
        let ms = Int(abs(delta).rounded())
        switch direction {
        case .slower:
            return "You reacted \(ms) ms slower after the block."
        case .faster:
            return "You reacted \(ms) ms faster after the block."
        case .steady:
            return "Your reaction time held steady through the block."
        }
    }

    /// Secondary line — lapses are the part sleep medicine actually cares about.
    var lapseLine: String {
        switch lapseDelta {
        case 0 where post.lapseCount == 0:
            return "No lapses either side."
        case 0:
            return "Lapses unchanged at \(post.lapseCount)."
        case let d where d > 0:
            return "\(d) more \(d == 1 ? "lapse" : "lapses") than before."
        default:
            return "\(abs(lapseDelta)) fewer \(abs(lapseDelta) == 1 ? "lapse" : "lapses") than before."
        }
    }
}

/// Pure tap-response psychomotor vigilance task: neutral field, stimulus after a random
/// interval, tap as fast as you can. No camera, no Watch, no network — this is the path
/// that has to work on stage.
///
/// **Protocol: PVT-B**, the brief psychomotor vigilance test from Basner, Mollicone &
/// Dinges, *Validity and sensitivity of a brief psychomotor vigilance test (PVT-B) to
/// total and partial sleep deprivation*, Acta Astronautica 69 (2011) 949–959. PVT-B was
/// built for exactly this situation — settings where the 10-minute PVT is impractical.
/// It is a validated instrument, not a shortened improvisation. Against the 10-minute
/// standard it changes three things, all of which are implemented here:
///
/// | Parameter | 10-min PVT | PVT-B (this engine) |
/// | --- | --- | --- |
/// | Interval | 2–10 s | **1–4 s**, inclusive of the RT feedback dwell |
/// | Lapse | RT ≥ 500 ms | **RT ≥ 355 ms** |
/// | Valid response | RT ≥ 100 ms | RT ≥ 100 ms (faster = false start) |
///
/// The 355 ms cutoff is not a softer bar: Basner et al. chose it because PVT-B produces
/// faster RTs, and 355 ms restores lapse frequency to what the 10-minute test reports at
/// 500 ms. Reported effect size across the shortened protocol dropped ~23% for a 70% cut
/// in duration.
///
/// **Two honest deviations,** both in the direction of consumer practicality:
/// - Duration is 60 s, not the validated 3 min. Fewer trials means a noisier median, so
///   this is read as a within-person pre/post delta minutes apart — never as an absolute
///   score against population norms.
/// - The no-response window is 3 s rather than the paper's 30 s. A 30 s stall would eat
///   half a 60 s test; real lapses land far inside 3 s.
///
/// The saccade-based variant lives in `VisionPVTEngine` and stays in the Lab.
@Observable
@MainActor
final class TapPVTEngine {
    enum Phase: Equatable {
        case idle
        /// Neutral field, stimulus pending.
        case waiting
        /// Stimulus on screen, awaiting a tap.
        case stimulus
        /// Showing the outcome of the last trial.
        case feedback
        case complete
    }

    enum Feedback: Equatable {
        case reaction(Double)
        case lapse(Double)
        case falseStart
        case missed
    }

    nonisolated static let defaultDurationSeconds: TimeInterval = 60
    /// PVT-B interval, measured from the previous response and inclusive of the feedback
    /// dwell. At 60 s this samples roughly 20 trials — enough for a median to settle.
    nonisolated static let defaultIsiRangeMs: ClosedRange<Double> = 1000...4000
    /// A stimulus left untapped this long is scored as a no-response lapse.
    nonisolated static let responseWindowMs: Double = 3000
    /// How long the previous RT stays on screen. Sits inside the interval, not on top of it.
    nonisolated static let feedbackMs: Double = 700
    /// Neutral field guaranteed before any stimulus, so the shortest interval still has a
    /// settled moment to react from rather than reading as a rapid-fire drill.
    nonisolated static let minNeutralGapMs: Double = 400

    private(set) var phase: Phase = .idle
    private(set) var stage: TapPVTStage = .standalone
    private(set) var trials: [TapPVTTrial] = []
    private(set) var feedback: Feedback?
    private(set) var isRunning = false
    private(set) var elapsedSeconds: TimeInterval = 0
    private(set) var durationSeconds: TimeInterval = TapPVTEngine.defaultDurationSeconds
    private(set) var result: TapPVTResult?

    var onComplete: ((TapPVTResult) -> Void)?
    /// Fired when a stimulus appears — hook for a light haptic.
    var onStimulus: (() -> Void)?
    var onTrial: ((TapPVTTrial) -> Void)?

    var stimulusVisible: Bool { phase == .stimulus }
    var remainingSeconds: TimeInterval { max(0, durationSeconds - elapsedSeconds) }
    var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1, max(0, elapsedSeconds / durationSeconds))
    }

    /// Live median across completed valid trials (shown only after the test).
    var liveMedianMs: Double? {
        TapPVTResult.median(trials.compactMap { $0.isValid ? $0.reactionMs : nil })
    }

    var lapseCount: Int { trials.filter(\.isLapse).count }

    private let isiRangeMs: ClosedRange<Double>
    private let clock: () -> TimeInterval
    private let isiProvider: () -> Double
    /// Off in tests so trials advance only when the test drives them.
    private let schedulesAutomatically: Bool

    private var startedAtUptime: TimeInterval = 0
    private var startedAtDate = Date()
    private var stimulusAtUptime: TimeInterval?
    /// Interval currently being waited out, in ms. Exposed so tests can drive the manual
    /// clock at the real cadence.
    private(set) var pendingIsiMs: Double = 0
    private var stimulusTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    init(
        isiRangeMs: ClosedRange<Double> = TapPVTEngine.defaultIsiRangeMs,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        isiProvider: (() -> Double)? = nil,
        schedulesAutomatically: Bool = true
    ) {
        self.isiRangeMs = isiRangeMs
        self.clock = clock
        self.isiProvider = isiProvider ?? { Double.random(in: isiRangeMs) }
        self.schedulesAutomatically = schedulesAutomatically
    }

    // MARK: - Lifecycle

    func start(
        stage: TapPVTStage,
        durationSeconds: TimeInterval = TapPVTEngine.defaultDurationSeconds
    ) {
        cancelTasks()
        self.stage = stage
        self.durationSeconds = max(1, durationSeconds)
        trials = []
        feedback = nil
        result = nil
        elapsedSeconds = 0
        stimulusAtUptime = nil
        startedAtUptime = clock()
        startedAtDate = Date()
        isRunning = true
        phase = .waiting
        scheduleStimulus()
        startTick()
    }

    /// Abandon without scoring (user backed out).
    func cancel() {
        cancelTasks()
        isRunning = false
        phase = .idle
        feedback = nil
        stimulusAtUptime = nil
    }

    // MARK: - Input

    /// Whole-screen tap. Resolves the current trial or records a false start.
    func registerTap() {
        guard isRunning else { return }
        refreshElapsed()
        switch phase {
        case .stimulus:
            guard let onset = stimulusAtUptime else { return }
            let rtMs = (clock() - onset) * 1000
            // Under 100 ms the finger was already moving — an anticipation, scored as a
            // false start so it can never pull the median down.
            if rtMs < TapPVTResult.validRtFloorMs {
                let trial = TapPVTTrial(
                    index: trials.count,
                    isiMs: pendingIsiMs,
                    reactionMs: rtMs,
                    falseStart: true
                )
                complete(trial, feedback: .falseStart)
                return
            }
            let trial = TapPVTTrial(index: trials.count, isiMs: pendingIsiMs, reactionMs: rtMs)
            complete(trial, feedback: trial.isLapse ? .lapse(rtMs) : .reaction(rtMs))
        case .waiting:
            // Anticipatory tap — the trial is void and the interval restarts.
            let trial = TapPVTTrial(index: trials.count, isiMs: pendingIsiMs, falseStart: true)
            complete(trial, feedback: .falseStart)
        case .idle, .feedback, .complete:
            break
        }
    }

    /// Show the stimulus now. Called by the scheduler, and directly by tests.
    func presentStimulus() {
        guard isRunning, phase == .waiting else { return }
        refreshElapsed()
        stimulusAtUptime = clock()
        phase = .stimulus
        feedback = nil
        onStimulus?()
        armTimeout()
    }

    /// Response window elapsed with no tap — a no-response lapse.
    func expireStimulus() {
        guard isRunning, phase == .stimulus else { return }
        let trial = TapPVTTrial(index: trials.count, isiMs: pendingIsiMs, timedOut: true)
        complete(trial, feedback: .missed)
    }

    /// End the run and score it. Safe to call more than once.
    @discardableResult
    func finish() -> TapPVTResult? {
        guard isRunning else { return result }
        cancelTasks()
        refreshElapsed()
        isRunning = false
        phase = .complete
        feedback = nil
        stimulusAtUptime = nil
        let scored = TapPVTResult(
            stage: stage,
            startedAt: startedAtDate,
            durationSeconds: min(elapsedSeconds, durationSeconds),
            trials: trials
        )
        result = scored
        onComplete?(scored)
        return scored
    }

    // MARK: - Private

    private func complete(_ trial: TapPVTTrial, feedback newFeedback: Feedback) {
        timeoutTask?.cancel()
        timeoutTask = nil
        stimulusAtUptime = nil
        trials.append(trial)
        feedback = newFeedback
        phase = .feedback
        onTrial?(trial)
        refreshElapsed()

        if elapsedSeconds >= durationSeconds {
            finish()
            return
        }
        scheduleAfterFeedback()
    }

    /// PVT-B counts the interval from the previous response and folds the RT feedback
    /// into it, so showing feedback does not stretch the cadence.
    private func scheduleAfterFeedback() {
        pendingIsiMs = nextIsiMs()
        guard schedulesAutomatically else {
            // Driven directly by the caller — last feedback stays readable for assertions.
            phase = .waiting
            return
        }
        let isi = pendingIsiMs
        let dwell = max(0, min(Self.feedbackMs, isi - Self.minNeutralGapMs))
        stimulusTask?.cancel()
        stimulusTask = Task { @MainActor in
            if dwell > 0 {
                try? await Task.sleep(nanoseconds: UInt64(dwell * 1_000_000))
                guard !Task.isCancelled, self.isRunning else { return }
            }
            self.feedback = nil
            self.phase = .waiting
            let neutralMs = isi - dwell
            if neutralMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(neutralMs * 1_000_000))
                guard !Task.isCancelled, self.isRunning else { return }
            }
            self.presentStimulus()
        }
    }

    /// First stimulus of the run — no preceding response, so no feedback to absorb.
    private func scheduleStimulus() {
        pendingIsiMs = nextIsiMs()
        guard schedulesAutomatically else { return }
        stimulusTask?.cancel()
        let waitMs = pendingIsiMs
        stimulusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(waitMs * 1_000_000))
            guard !Task.isCancelled, self.isRunning else { return }
            self.presentStimulus()
        }
    }

    /// Random inside the configured range, shortened near the end so the last stimulus
    /// still leaves room for a response instead of dying with the clock.
    private func nextIsiMs() -> Double {
        let drawn = min(max(isiProvider(), isiRangeMs.lowerBound), isiRangeMs.upperBound)
        refreshElapsed()
        let remainingMs = (durationSeconds - elapsedSeconds) * 1000
        let latestUsableMs = remainingMs - Self.responseWindowMs * 0.35
        guard latestUsableMs > isiRangeMs.lowerBound else { return drawn }
        return min(drawn, latestUsableMs)
    }

    private func armTimeout() {
        guard schedulesAutomatically else { return }
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.responseWindowMs * 1_000_000))
            guard !Task.isCancelled, self.isRunning else { return }
            self.expireStimulus()
        }
    }

    private func startTick() {
        guard schedulesAutomatically else { return }
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            while !Task.isCancelled, self.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled, self.isRunning else { return }
                self.refreshElapsed()
                // A stimulus already on screen gets its full response window.
                if self.elapsedSeconds >= self.durationSeconds, self.phase != .stimulus {
                    self.finish()
                    return
                }
            }
        }
    }

    private func refreshElapsed() {
        guard isRunning else { return }
        elapsedSeconds = max(0, clock() - startedAtUptime)
    }

    private func cancelTasks() {
        stimulusTask?.cancel()
        stimulusTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        tickTask?.cancel()
        tickTask = nil
    }
}
