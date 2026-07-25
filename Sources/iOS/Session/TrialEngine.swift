import Foundation
import simd

struct TrialRecord: Identifiable, Sendable, Equatable {
    var id: Int { index }
    let index: Int
    let targetCell: Int
    var targetOnsetMs: Double?
    var saccadeOnsetMs: Double?
    var gazeSettleMs: Double?
    var strikeMs: Double?
    var visualRtMs: Double?
    var motorRtMs: Double?
    var cognitiveMotorGapMs: Double?
    var peakG: Double?
    var arousalIndex: Float?
    var valid: Bool
    var invalidReason: String?

    /// Session-relative ms from session start (phone clock).
    static func relativeMs(absolute: PhoneTime, sessionStart: PhoneTime) -> Double {
        absolute.milliseconds(since: sessionStart)
    }
}

struct GazeWindowSample: Sendable, Equatable {
    let dt: Double
    let x: Float
    let y: Float
    let z: Float
}

enum TrialPhase: Equatable {
    case idle
    case waitingForOnset
    case awaitingResponse
    case complete
}

@Observable
@MainActor
final class TrialEngine {
    static let gridSize = 9
    static let strikeTimeoutMs: Double = 1500
    static let interTrialDelayMs: Double = 800
    static let gazePreMs: Double = 200
    static let gazePostMs: Double = 800

    var phase: TrialPhase = .idle
    var activeCell: Int?
    var trialIndex = 0
    var trials: [TrialRecord] = []
    var statusText = "Ready"
    var sessionStart: PhoneTime?
    var isRunning = false
    var lastCognitiveMotorGapMs: Double?
    var breakPointTrial: Int?
    var baselineGapMs: Double?
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

    var onTrialCompleted: ((TrialRecord, [GazeWindowSample], Double) -> Void)?
    var onTargetArmed: ((Int) -> Void)?
    var onBreakPoint: ((Int, Double?, Double?) -> Void)?
    var onBaselineReady: ((Double, Double) -> Void)?

    private var breakPointDetector = BreakPointDetector()

    func startSession() {
        stopSession()
        let now = PhoneTime.now()
        sessionStart = now
        sessionOrigin = now
        trialIndex = 0
        trials = []
        breakPointTrial = nil
        baselineGapMs = nil
        baselineStdMs = nil
        breakPointDetector.reset()
        isRunning = true
        statusText = "Session started"
        displayClock.start()
        scheduleNextTrial()
    }

    func stopSession() {
        isRunning = false
        timeoutTask?.cancel()
        interTrialTask?.cancel()
        displayClock.stop()
        phase = .idle
        activeCell = nil
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

    func ingestStrike(_ event: StrikeEvent) {
        guard phase == .awaitingResponse, var trial = current, let origin = sessionOrigin else { return }
        guard trial.strikeMs == nil else { return }

        let strikeMs = TrialRecord.relativeMs(absolute: event.phoneTime, sessionStart: origin)
        trial.strikeMs = strikeMs
        trial.peakG = event.peakG
        finishTrial(trial)
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
        let cell = Int.random(in: 0..<Self.gridSize)
        var trial = TrialRecord(
            index: trialIndex,
            targetCell: cell,
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
            invalidReason: nil
        )
        current = trial
        pendingSaccadeOnset = nil
        pendingSettle = nil
        blinkContaminated = false
        phase = .waitingForOnset
        activeCell = cell
        onTargetArmed?(cell)
        statusText = "Trial \(trialIndex + 1) · cell \(cell)"

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
        // Ignore saccades that precede target onset.
        if saccadeMs < (trial.targetOnsetMs ?? 0) { return }
        trial.saccadeOnsetMs = saccadeMs
        if let settle = pendingSettle {
            trial.gazeSettleMs = TrialRecord.relativeMs(absolute: settle, sessionStart: origin)
        }
        current = trial
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
        }
        if let target = trial.targetOnsetMs, let strike = trial.strikeMs {
            trial.motorRtMs = strike - target
        }
        if let saccade = trial.saccadeOnsetMs, let strike = trial.strikeMs {
            trial.cognitiveMotorGapMs = strike - saccade
            lastCognitiveMotorGapMs = trial.cognitiveMotorGapMs
        }

        if trial.strikeMs == nil, trial.invalidReason == nil {
            trial.valid = false
            trial.invalidReason = "miss"
        }

        current = nil
        activeCell = nil
        phase = .complete
        trials.append(trial)
        trialIndex += 1

        let window = buildGazeWindow(for: trial)
        let t0 = (trial.targetOnsetMs ?? 0) - Self.gazePreMs
        onTrialCompleted?(trial, window, t0)

        if trial.valid, let gap = trial.cognitiveMotorGapMs {
            let hadBaseline = breakPointDetector.baselineMean != nil
            if let bp = breakPointDetector.ingest(trialIndex: trial.index, gapMs: gap) {
                breakPointTrial = bp
                baselineGapMs = breakPointDetector.baselineMean
                baselineStdMs = breakPointDetector.baselineStd
                onBreakPoint?(bp, baselineGapMs, baselineStdMs)
                statusText = "Break-point @ trial \(bp + 1)"
            } else if !hadBaseline,
                      let mean = breakPointDetector.baselineMean,
                      let std = breakPointDetector.baselineStd {
                baselineGapMs = mean
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
