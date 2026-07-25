import Foundation
import simd

/// Classic single-flash PVT: saccade onset / settle / arousal. No punch, no grid.
@Observable
@MainActor
final class VisionPVTEngine {
    static let responseTimeoutMs: Double = 1500
    static let interTrialDelayMs: Double = 800
    static let gazePreMs: Double = 200
    static let gazePostMs: Double = 800
    /// Fixed center cell id for schema compatibility (retired 3×3).
    static let centerCell = 4

    var phase: TrialPhase = .idle
    var flashVisible = false
    var trialIndex = 0
    var trials: [TrialRecord] = []
    var statusText = "Ready"
    var sessionStart: PhoneTime?
    var isRunning = false
    var lastVisualRtMs: Double?
    var breakPointTrial: Int?
    var baselineMeanMs: Double?
    var baselineStdMs: Double?

    private let displayClock = DisplayClock()
    private var current: TrialRecord?
    private var sessionOrigin: PhoneTime?
    private var gazeBuffer: [(PhoneTime, SIMD3<Float>)] = []
    private var pendingSaccadeOnset: PhoneTime?
    private var pendingSettle: PhoneTime?
    private var pendingArousal: Float?
    private var blinkContaminated = false
    private var timeoutTask: Task<Void, Never>?
    private var interTrialTask: Task<Void, Never>?
    private var breakPointDetector = BreakPointDetector()

    var onTrialCompleted: ((TrialRecord, [GazeWindowSample], Double) -> Void)?
    var onFlashArmed: (() -> Void)?
    var onBreakPoint: ((Int, Double?, Double?) -> Void)?
    var onBaselineReady: ((Double, Double) -> Void)?

    func startSession() {
        stopSession()
        let now = PhoneTime.now()
        sessionStart = now
        sessionOrigin = now
        trialIndex = 0
        trials = []
        breakPointTrial = nil
        baselineMeanMs = nil
        baselineStdMs = nil
        breakPointDetector.reset()
        isRunning = true
        statusText = "Vision PVT started"
        displayClock.start()
        scheduleNextTrial()
    }

    func stopSession() {
        isRunning = false
        timeoutTask?.cancel()
        interTrialTask?.cancel()
        displayClock.stop()
        phase = .idle
        flashVisible = false
        current = nil
        statusText = "Session stopped"
    }

    func ingestGaze(_ sample: GazeSample) {
        guard isRunning else { return }
        gazeBuffer.append((sample.time, sample.lookAt))
        trimGazeBuffer(around: PhoneTime.now())
        if sample.isBlinking, phase == .awaitingResponse {
            blinkContaminated = true
        }
    }

    func ingestSaccade(_ saccade: SaccadeOnset) {
        guard phase == .awaitingResponse, current?.saccadeOnsetMs == nil else {
            if let settle = saccade.settle {
                pendingSettle = settle
            }
            return
        }
        if saccade.settle == nil {
            pendingSaccadeOnset = saccade.onset
            applySaccadeIfReady()
        } else {
            pendingSettle = saccade.settle
            applySaccadeIfReady()
        }
    }

    func ingestArousal(_ value: Float) {
        pendingArousal = value
    }

    private func scheduleNextTrial() {
        guard isRunning else { return }
        interTrialTask?.cancel()
        interTrialTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.interTrialDelayMs * 1_000_000))
            guard !Task.isCancelled, self.isRunning else { return }
            self.beginTrial()
        }
    }

    private func beginTrial() {
        guard isRunning, let origin = sessionOrigin else { return }
        let trial = TrialRecord(
            index: trialIndex,
            targetCell: Self.centerCell,
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
            targetOctant: nil,
            detectedOctant: nil,
            spatialMatch: nil
        )
        current = trial
        pendingSaccadeOnset = nil
        pendingSettle = nil
        blinkContaminated = false
        phase = .waitingForOnset
        flashVisible = true
        onFlashArmed?()
        statusText = "Trial \(trialIndex + 1) · flash"

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
            try? await Task.sleep(nanoseconds: UInt64(Self.responseTimeoutMs * 1_000_000))
            guard !Task.isCancelled, self.phase == .awaitingResponse, var trial = self.current else { return }
            trial.valid = false
            trial.invalidReason = "miss"
            self.finishTrial(trial)
        }
    }

    private func applySaccadeIfReady() {
        guard var trial = current,
              let origin = sessionOrigin,
              let onset = pendingSaccadeOnset,
              trial.saccadeOnsetMs == nil,
              trial.targetOnsetMs != nil
        else { return }

        let saccadeMs = TrialRecord.relativeMs(absolute: onset, sessionStart: origin)
        if saccadeMs < (trial.targetOnsetMs ?? 0) { return }
        trial.saccadeOnsetMs = saccadeMs
        if let settle = pendingSettle {
            trial.gazeSettleMs = TrialRecord.relativeMs(absolute: settle, sessionStart: origin)
        }
        current = trial
        // Complete on saccade — vision PVT does not wait for a punch.
        finishTrial(trial)
    }

    private func finishTrial(_ trialIn: TrialRecord) {
        timeoutTask?.cancel()
        var trial = trialIn
        trial.arousalIndex = pendingArousal

        if blinkContaminated {
            trial.valid = false
            trial.invalidReason = trial.invalidReason ?? "blink"
        }

        if let target = trial.targetOnsetMs, let saccade = trial.saccadeOnsetMs {
            trial.visualRtMs = saccade - target
            lastVisualRtMs = trial.visualRtMs
        }

        if trial.saccadeOnsetMs == nil, trial.invalidReason == nil {
            trial.valid = false
            trial.invalidReason = "miss"
        }

        current = nil
        flashVisible = false
        phase = .complete
        trials.append(trial)
        trialIndex += 1

        let window = buildGazeWindow(for: trial)
        let t0 = (trial.targetOnsetMs ?? 0) - Self.gazePreMs
        onTrialCompleted?(trial, window, t0)

        if trial.valid, let rt = trial.visualRtMs {
            let hadBaseline = breakPointDetector.baselineMean != nil
            if let bp = breakPointDetector.ingest(trialIndex: trial.index, gapMs: rt) {
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

    private func buildGazeWindow(for trial: TrialRecord) -> [GazeWindowSample] {
        guard let origin = sessionOrigin, let targetMs = trial.targetOnsetMs else { return [] }
        let startMs = targetMs - Self.gazePreMs
        let endMs = targetMs + Self.gazePostMs
        return gazeBuffer.compactMap { time, look in
            let ms = TrialRecord.relativeMs(absolute: time, sessionStart: origin)
            guard ms >= startMs, ms <= endMs else { return nil }
            return GazeWindowSample(dt: ms - startMs, x: look.x, y: look.y, z: look.z)
        }
    }

    private func trimGazeBuffer(around now: PhoneTime) {
        let keepSeconds = 2.0
        gazeBuffer.removeAll { now.seconds - $0.0.seconds > keepSeconds }
    }
}
