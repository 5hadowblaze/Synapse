import Foundation
import simd

/// Shared Vision PVT layout constants (nonisolated — safe from replay / tests).
enum VisionPVTLayout {
    /// 3×3 row-major: center is fixation only; flashes use the eight peripherals.
    static let centerCell = 4
    static let peripheralCells = [0, 1, 2, 3, 5, 6, 7, 8]
    static let defaultMaxTrials = 24
    static let responseTimeoutMs: Double = 1500
    /// Random ISI (ms), inclusive — vigilance-style unpredictability; shorter than Tap PVT-B’s 1–4 s.
    static let isiMinMs: Double = 1000
    static let isiMaxMs: Double = 3000
    static let gazePreMs: Double = 200
    static let gazePostMs: Double = 800

    /// Balanced shuffle of the eight peripheral cells (truncated/padded to `count`).
    static func makeBalancedPeripheralQueue(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var queue: [Int] = []
        while queue.count < count {
            queue.append(contentsOf: peripheralCells)
        }
        queue = Array(queue.prefix(count))
        return queue.shuffled()
    }

    /// Row-major 3×3 UV for a cell center (matches dashboard GazeField layout).
    static func cellCenterUV(_ cell: Int) -> SIMD2<Float> {
        let c = min(8, max(0, cell))
        let col = Float(c % 3)
        let row = Float(c / 3)
        return SIMD2((col + 0.5) / 3, (row + 0.5) / 3)
    }
}

/// Lab Vision PVT: peripheral single-flash → saccade onset / settle / arousal.
/// Fixation stays at center (cell 4); each trial flashes one of the eight surrounding cells
/// so a gaze shift is required. Not the Focus bookend Tap PVT-B.
@Observable
@MainActor
final class VisionPVTEngine {
    var phase: TrialPhase = .idle
    var flashVisible = false
    /// Soft center fixation during ISI / between flashes (and while a peripheral flash is up).
    var fixationVisible = false
    /// Peripheral cell currently flashing (nil when no stimulus).
    var activeCell: Int?
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
    private var cellQueue: [Int] = []
    private let maxTrials: Int

    var onTrialCompleted: ((TrialRecord, [GazeWindowSample], Double) -> Void)?
    var onFlashArmed: (() -> Void)?
    var onBreakPoint: ((Int, Double?, Double?) -> Void)?
    var onBaselineReady: ((Double, Double) -> Void)?

    init(maxTrials: Int = VisionPVTLayout.defaultMaxTrials) {
        self.maxTrials = maxTrials
    }

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
        cellQueue = VisionPVTLayout.makeBalancedPeripheralQueue(count: maxTrials)
        activeCell = nil
        flashVisible = false
        fixationVisible = true
        isRunning = true
        statusText = "Vision PVT started · fixate center"
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
        fixationVisible = false
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

    private func scheduleNextTrial() {
        guard isRunning else { return }
        if trialIndex >= maxTrials || cellQueue.isEmpty {
            isRunning = false
            flashVisible = false
            fixationVisible = false
            activeCell = nil
            phase = .idle
            statusText = "Vision PVT complete · \(trials.count) trials"
            return
        }
        interTrialTask?.cancel()
        fixationVisible = true
        flashVisible = false
        activeCell = nil
        phase = .idle
        let isi = Double.random(in: VisionPVTLayout.isiMinMs...VisionPVTLayout.isiMaxMs)
        interTrialTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(isi * 1_000_000))
            guard !Task.isCancelled, self.isRunning else { return }
            self.beginTrial()
        }
    }

    private func beginTrial() {
        guard isRunning, let origin = sessionOrigin, !cellQueue.isEmpty else { return }
        let cell = cellQueue.removeFirst()
        let trial = TrialRecord(
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
        activeCell = cell
        flashVisible = true
        fixationVisible = true
        onFlashArmed?()
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
            try? await Task.sleep(nanoseconds: UInt64(VisionPVTLayout.responseTimeoutMs * 1_000_000))
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
        // Complete on saccade onset — vision PVT does not wait for a punch or pixel landing.
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
        activeCell = nil
        phase = .complete
        trials.append(trial)
        trialIndex += 1

        let window = buildGazeWindow(for: trial)
        let t0 = (trial.targetOnsetMs ?? 0) - VisionPVTLayout.gazePreMs
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
        let startMs = targetMs - VisionPVTLayout.gazePreMs
        let endMs = targetMs + VisionPVTLayout.gazePostMs
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
