import Foundation

/// Eight-direction kinetic clock: watch strike timing always kept; spatialMatch flags accuracy.
@Observable
@MainActor
final class KineticClockEngine {
    static let strikeTimeoutMs: Double = 1500
    static let interTrialDelayMs: Double = 800
    /// 2 punches per octant by default.
    static let defaultTrialCount = 16

    var phase: TrialPhase = .idle
    var activeOctant: Int?
    var trialIndex = 0
    var trials: [TrialRecord] = []
    var statusText = "Ready"
    var sessionStart: PhoneTime?
    var isRunning = false
    var lastMotorRtMs: Double?
    var lastSpatialMatch: Bool?
    var spatialAccuracyPercent: Double?
    var breakPointTrial: Int?
    var baselineMeanMs: Double?
    var baselineStdMs: Double?

    private let displayClock = DisplayClock()
    private var current: TrialRecord?
    private var sessionOrigin: PhoneTime?
    private var timeoutTask: Task<Void, Never>?
    private var interTrialTask: Task<Void, Never>?
    private var breakPointDetector = BreakPointDetector()
    private var octantQueue: [Int] = []
    private var maxTrials = KineticClockEngine.defaultTrialCount

    var onTrialCompleted: ((TrialRecord) -> Void)?
    var onTargetArmed: ((Int) -> Void)?
    var onBreakPoint: ((Int, Double?, Double?) -> Void)?
    var onBaselineReady: ((Double, Double) -> Void)?
    var onSessionComplete: (() -> Void)?

    func startSession(trialCount: Int? = nil) {
        stopSession()
        let count = trialCount ?? Self.defaultTrialCount
        maxTrials = count
        octantQueue = Self.makeBalancedOctantQueue(count: count)
        let now = PhoneTime.now()
        sessionStart = now
        sessionOrigin = now
        trialIndex = 0
        trials = []
        breakPointTrial = nil
        baselineMeanMs = nil
        baselineStdMs = nil
        spatialAccuracyPercent = nil
        lastSpatialMatch = nil
        breakPointDetector.reset()
        isRunning = true
        statusText = "Kinetic Clock started"
        displayClock.start()
        scheduleNextTrial()
    }

    func stopSession() {
        isRunning = false
        timeoutTask?.cancel()
        interTrialTask?.cancel()
        displayClock.stop()
        phase = .idle
        activeOctant = nil
        current = nil
        statusText = "Session stopped"
    }

    func ingestStrike(_ event: StrikeEvent) {
        guard phase == .awaitingResponse, var trial = current, let origin = sessionOrigin else { return }
        guard trial.strikeMs == nil else { return }

        let strikeMs = TrialRecord.relativeMs(absolute: event.phoneTime, sessionStart: origin)
        trial.strikeMs = strikeMs
        trial.peakG = event.peakG
        trial.detectedOctant = event.detectedOctant
        if let target = trial.targetOctant, let detected = event.detectedOctant {
            trial.spatialMatch = (target == detected)
        } else {
            trial.spatialMatch = false
        }
        lastSpatialMatch = trial.spatialMatch
        finishTrial(trial)
    }

    /// Test seam: arm a trial in `.awaitingResponse` without CADisplayLink.
    func armAwaitingStrikeForTesting(
        targetOctant: Int,
        sessionStart: PhoneTime,
        targetOnsetMs: Double,
        trialIndex: Int = 0
    ) {
        self.sessionStart = sessionStart
        self.sessionOrigin = sessionStart
        self.trialIndex = trialIndex
        self.isRunning = true
        self.phase = .awaitingResponse
        self.activeOctant = targetOctant
        self.current = TrialRecord(
            index: trialIndex,
            targetCell: targetOctant,
            targetOnsetMs: targetOnsetMs,
            saccadeOnsetMs: nil,
            gazeSettleMs: nil,
            strikeMs: nil,
            visualRtMs: nil,
            motorRtMs: nil,
            cognitiveMotorGapMs: nil,
            peakG: nil,
            arousalIndex: nil,
            valid: true,
            invalidReason: nil,
            targetOctant: targetOctant,
            detectedOctant: nil,
            spatialMatch: nil
        )
    }

    private func scheduleNextTrial() {
        guard isRunning else { return }
        if trialIndex >= maxTrials || octantQueue.isEmpty {
            isRunning = false
            statusText = "Kinetic complete"
            onSessionComplete?()
            return
        }
        interTrialTask?.cancel()
        interTrialTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.interTrialDelayMs * 1_000_000))
            guard !Task.isCancelled, self.isRunning else { return }
            self.beginTrial()
        }
    }

    private func beginTrial() {
        guard isRunning, let origin = sessionOrigin, !octantQueue.isEmpty else { return }
        let octant = octantQueue.removeFirst()
        let trial = TrialRecord(
            index: trialIndex,
            targetCell: octant,
            targetOnsetMs: nil,
            saccadeOnsetMs: nil,
            gazeSettleMs: nil,
            strikeMs: nil,
            visualRtMs: nil,
            motorRtMs: nil,
            cognitiveMotorGapMs: nil,
            peakG: nil,
            arousalIndex: nil,
            valid: true,
            invalidReason: nil,
            targetOctant: octant,
            detectedOctant: nil,
            spatialMatch: nil
        )
        current = trial
        phase = .waitingForOnset
        activeOctant = octant
        onTargetArmed?(octant)
        let label = ClockOctant(rawValue: octant)?.label ?? "\(octant)"
        statusText = "Trial \(trialIndex + 1) · \(label)"

        displayClock.armOnsetCapture { [weak self] onset in
            Task { @MainActor in
                guard let self, var current = self.current else { return }
                let onsetMs = TrialRecord.relativeMs(absolute: onset, sessionStart: origin)
                current.targetOnsetMs = onsetMs
                self.current = current
                self.phase = .awaitingResponse
                self.armTimeout()
            }
        }
    }

    private func armTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.strikeTimeoutMs * 1_000_000))
            guard !Task.isCancelled, self.phase == .awaitingResponse, var trial = self.current else { return }
            trial.valid = false
            trial.invalidReason = "miss"
            trial.spatialMatch = false
            self.lastSpatialMatch = false
            self.finishTrial(trial)
        }
    }

    private func finishTrial(_ trialIn: TrialRecord) {
        timeoutTask?.cancel()
        var trial = trialIn

        // Timing always kept when a strike arrived — wrong direction is flagged, not discarded.
        if let target = trial.targetOnsetMs, let strike = trial.strikeMs {
            trial.motorRtMs = strike - target
            lastMotorRtMs = trial.motorRtMs
        }

        if trial.strikeMs == nil, trial.invalidReason == nil {
            trial.valid = false
            trial.invalidReason = "miss"
        }

        // Spatial miss does not invalidate timing.
        if trial.strikeMs != nil, trial.spatialMatch == false, trial.invalidReason == nil {
            // Keep valid=true so motor RT enters break-point / means; accuracy tracked separately.
            trial.valid = true
        }

        current = nil
        activeOctant = nil
        phase = .complete
        trials.append(trial)
        trialIndex += 1
        refreshSpatialAccuracy()

        onTrialCompleted?(trial)

        if trial.valid, let motor = trial.motorRtMs {
            let hadBaseline = breakPointDetector.baselineMean != nil
            if let bp = breakPointDetector.ingest(trialIndex: trial.index, gapMs: motor) {
                breakPointTrial = bp
                baselineMeanMs = breakPointDetector.baselineMean
                baselineStdMs = breakPointDetector.baselineStd
                onBreakPoint?(bp, baselineMeanMs, baselineStdMs)
                statusText = "Break-point @ trial \(bp + 1)"
            } else if !hadBaseline,
                      let mean = breakPointDetector.baselineMean,
                      let std = breakPointDetector.baselineStd {
                baselineMeanMs = mean
                baselineStdMs = std
                onBaselineReady?(mean, std)
            }
        }

        if isRunning {
            scheduleNextTrial()
        }
    }

    private func refreshSpatialAccuracy() {
        let scored = trials.filter { $0.strikeMs != nil && $0.spatialMatch != nil }
        guard !scored.isEmpty else {
            spatialAccuracyPercent = nil
            return
        }
        let matches = scored.filter { $0.spatialMatch == true }.count
        spatialAccuracyPercent = 100.0 * Double(matches) / Double(scored.count)
    }

    /// Two of each octant shuffled (truncated/padded to `count`).
    static func makeBalancedOctantQueue(count: Int) -> [Int] {
        var queue: [Int] = []
        while queue.count < count {
            queue.append(contentsOf: ClockOctant.allCases.map(\.rawValue))
        }
        queue = Array(queue.prefix(count))
        return queue.shuffled()
    }
}
