import Foundation
import os

/// Continuous fade score from HR drift + relative arousal (+ optional motion energy).
/// Soft multi-fire with cooldown after baseline (mean + 2σ), unlike one-shot trial BP.
///
/// Every term is scaled so **0 = sitting at your own baseline** and **1 = maximally faded**.
/// A channel that is missing — or that carried no usable signal during calibration — drops out
/// and the remaining weights renormalise, so the composite stays on one comparable 0…1 scale
/// however many channels are live.
struct FocusFadeDetector {
    /// ~2.4 min at 8s sample interval (18 × 8s).
    static let defaultBaselineSamples = 18
    /// ~32s at 8s sample interval — short blocks would otherwise end before a fade can fire.
    static let quickBaselineSamples = 4
    static let defaultCooldownSeconds: TimeInterval = 90
    static let defaultSampleIntervalSeconds: TimeInterval = 8
    /// Minimum σ for fade composite scores (~0…1) so flat baselines need a real spike.
    static let defaultMinStd: Double = 0.05

    /// Consecutive threshold-exceeding samples required before a fade fires (~16s at 8s).
    /// Standing up is one sample; genuine fade persists across several.
    static let defaultSamplesToFire = 2

    /// HR rise, in bpm, mapped onto the full 0…1 HR term.
    static let hrSpanBpm: Double = 20
    /// How far the HR term may go below baseline before flooring (−0.25 ≈ 5 bpm under anchor).
    /// Letting a decline read negative keeps the baseline σ honest — with a hard clamp at 0 the
    /// whole lower half of a median-anchored window collapses onto one value and σ collapses
    /// with it, which is what left `minStd` permanently in charge of the threshold.
    static let hrFloorTerm: Double = -0.25

    /// σ of `eyeWide` across the baseline window below which the channel is quantisation noise
    /// rather than signal, and the arousal term drops out entirely.
    ///
    /// Chosen from the static analysis of the old absolute term: an `eyeWide` movement of 0.01
    /// is worth 0.0040 of composite score, ≈0.18 bpm, ≈4% of the rise needed to fire. At σ =
    /// 0.010 a full-scale (2σ) droop moves `eyeWide` by only 0.020 — still under half a bpm of
    /// equivalent evidence. Below that, z-scoring would be multiplying blendshape jitter up to
    /// 40% of the composite weight, which is strictly worse than not having the channel.
    static let arousalNoiseFloor: Double = 0.010
    /// Baseline σ below the baseline mean that counts as fully faded.
    static let arousalSigmaSpan: Double = 2.0

    /// HR gap (bpm) between the first and second half of the calibration window above which the
    /// user is still settling, so freezing a baseline now would bake in a decaying trend.
    static let stationaryBandBpm: Double = 3.0

    /// Weights for composite fade score (higher = more faded).
    var hrWeight: Double = 0.45
    var arousalWeight: Double = 0.40
    var motionWeight: Double = 0.15

    private var baseline: RollingBaseline
    private(set) var lastScore: Double?
    private(set) var fadeCount = 0
    private(set) var lastFadeAt: TimeInterval?
    private var cooldownSeconds: TimeInterval
    private var sampleInterval: TimeInterval
    private var samplesToFire: Int
    private var lastSampleAt: TimeInterval?

    /// Raw inputs held until calibration, so the baseline can be recomputed with the anchor and
    /// arousal statistics that only exist once the window is complete.
    private var pending: [RawSample] = []
    private var isCalibrated = false
    private var consecutiveExceedances = 0

    private var hrAnchor: Double?
    private var recentHr: [Double] = []

    private var arousalBaselineMean: Double?
    private var arousalBaselineStd: Double?
    /// Nil until calibration; then whether the z-scored arousal term is contributing.
    private(set) var isArousalChannelActive: Bool?
    /// σ(eyeWide) measured across the calibration window (nil until calibrated).
    private(set) var arousalBaselineSpread: Double?

    private struct RawSample {
        let hrBpm: Double?
        let eyeWide: Double?
        let motionEnergy: Double?
    }

    init(
        baselineSamples: Int = FocusFadeDetector.defaultBaselineSamples,
        cooldownSeconds: TimeInterval = FocusFadeDetector.defaultCooldownSeconds,
        sampleInterval: TimeInterval = FocusFadeDetector.defaultSampleIntervalSeconds,
        minStd: Double = FocusFadeDetector.defaultMinStd,
        samplesToFire: Int = FocusFadeDetector.defaultSamplesToFire
    ) {
        self.baseline = RollingBaseline(
            capacity: baselineSamples,
            sigmaMultiplier: 2.0,
            minStd: minStd
        )
        self.cooldownSeconds = cooldownSeconds
        self.sampleInterval = sampleInterval
        self.samplesToFire = max(1, samplesToFire)
    }

    mutating func reset() {
        baseline.reset()
        lastScore = nil
        fadeCount = 0
        lastFadeAt = nil
        lastSampleAt = nil
        pending = []
        isCalibrated = false
        deferredSamples = 0
        consecutiveExceedances = 0
        hrAnchor = nil
        recentHr = []
        arousalBaselineMean = nil
        arousalBaselineStd = nil
        isArousalChannelActive = nil
        arousalBaselineSpread = nil
    }

    var isBaselineReady: Bool { baseline.isReady }
    var baselineMean: Double? { baseline.mean }
    var baselineStd: Double? { baseline.std }
    var fadeThreshold: Double? { baseline.threshold }
    var baselineSampleCount: Int { isCalibrated ? baseline.samples.count : pending.count }
    var baselineCapacity: Int { baseline.capacity }
    /// Session HR reference the drift term measures against (median-derived, tracks downward).
    var currentHrAnchor: Double? { hrAnchor }

    /// 0…1 progress toward a usable baseline (drives the "calibrating" HUD state).
    /// Holds just short of 1 while the window is full but HR is still settling.
    var baselineProgress: Double {
        guard baseline.capacity > 0 else { return 1 }
        if baseline.isReady { return 1 }
        return min(0.95, Double(pending.count) / Double(baseline.capacity))
    }

    /// Midpoint between the baseline mean and the fade threshold.
    ///
    /// `FocusEngine.signalState` compares the live score against this to decide whether the HUD
    /// reads `easing`, which keeps the middle state strictly between calm and a break request.
    /// A fixed absolute cut point cannot: the score is session-relative, so any constant drifts
    /// out of order with the fade threshold as channels drop in and out.
    var easingThreshold: Double? {
        guard let mean = baseline.mean, let threshold = baseline.threshold else { return nil }
        return mean + (threshold - mean) / 2
    }

    /// 0…1 progress from the baseline mean toward the fade threshold (≥1 means over threshold).
    var fadeProgress: Double? {
        guard let mean = baseline.mean, let threshold = baseline.threshold, let score = lastScore
        else { return nil }
        let span = threshold - mean
        guard span > 0 else { return nil }
        return max(0, (score - mean) / span)
    }

    /// Returns true when a soft fade event fires (multi-fire with cooldown).
    mutating func ingest(
        now: TimeInterval,
        hrBpm: Double?,
        arousal: Float?,
        motionEnergy: Double?
    ) -> Bool {
        if let last = lastSampleAt, now - last < sampleInterval {
            return false
        }
        lastSampleAt = now

        let sample = RawSample(
            hrBpm: hrBpm,
            eyeWide: arousal.map(Double.init),
            motionEnergy: motionEnergy
        )

        guard isCalibrated else {
            collect(sample)
            return false
        }

        trackAnchorDownward(hrBpm: hrBpm)
        let score = compositeScore(for: sample)
        lastScore = score

        let exceeded = baseline.ingest(score)
        consecutiveExceedances = exceeded ? consecutiveExceedances + 1 : 0
        guard consecutiveExceedances >= samplesToFire else { return false }

        if let lastFade = lastFadeAt, now - lastFade < cooldownSeconds {
            // Stay armed through the cooldown so sustained fade re-fires the moment it lifts.
            return false
        }
        lastFadeAt = now
        fadeCount += 1
        consecutiveExceedances = 0
        return true
    }

    /// Test helper: force a sample without interval gating.
    mutating func ingestForced(
        now: TimeInterval,
        hrBpm: Double?,
        arousal: Float?,
        motionEnergy: Double?
    ) -> Bool {
        lastSampleAt = nil
        return ingest(now: now, hrBpm: hrBpm, arousal: arousal, motionEnergy: motionEnergy)
    }

    // MARK: - Calibration

    /// Slide a window of raw samples until HR looks settled, then freeze the baseline from it.
    private mutating func collect(_ sample: RawSample) {
        pending.append(sample)
        if pending.count > baseline.capacity {
            pending.removeFirst(pending.count - baseline.capacity)
        }
        // Provisional score so the HUD and epoch writer have something during calibration.
        lastScore = compositeScore(for: sample)

        guard pending.count == baseline.capacity else { return }
        // Cap the wait at one extra window: someone who never fully settles still gets a
        // working detector, just one built on a slightly warm baseline.
        guard isHrSettled || deferredSamples >= baseline.capacity else {
            deferredSamples += 1
            return
        }
        calibrate()
    }

    /// Samples consumed while waiting for HR to stop trending down.
    private var deferredSamples = 0

    /// True when the window's HR is not still trending down (a warm start is not a baseline).
    private var isHrSettled: Bool {
        let hrs = pending.compactMap(\.hrBpm)
        guard hrs.count >= 4 else { return true }
        let half = hrs.count / 2
        guard let early = Self.median(Array(hrs.prefix(half))),
              let late = Self.median(Array(hrs.suffix(hrs.count - half)))
        else { return true }
        return early - late <= Self.stationaryBandBpm
    }

    private mutating func calibrate() {
        let hrValues = pending.compactMap(\.hrBpm)
        if let median = Self.median(hrValues) {
            hrAnchor = median
            recentHr = hrValues
        }

        let eyeValues = pending.compactMap(\.eyeWide)
        let spread = Self.standardDeviation(eyeValues)
        arousalBaselineSpread = spread
        if let spread, spread >= Self.arousalNoiseFloor, let mean = Self.mean(eyeValues) {
            arousalBaselineMean = mean
            arousalBaselineStd = spread
            isArousalChannelActive = true
        } else {
            arousalBaselineMean = nil
            arousalBaselineStd = nil
            isArousalChannelActive = false
        }

        // Rescore the whole window with the final anchor and arousal statistics, so the frozen
        // mean/σ are on exactly the same scale as every score compared against them later.
        baseline.reseed(pending.map { compositeScore(for: $0) })
        isCalibrated = true
        lastScore = baseline.samples.last
        logCalibration()
    }

    private func logCalibration() {
        let log = Logger(subsystem: "com.dzak.synapse", category: "fade-detector")
        let spread = arousalBaselineSpread ?? 0
        if isArousalChannelActive == true {
            log.notice("""
            fade calibrated — arousal ACTIVE (z-scored): eyeWide sd=\(spread, format: .fixed(precision: 4)) \
            ≥ floor \(Self.arousalNoiseFloor, format: .fixed(precision: 3)) \
            mean=\(self.arousalBaselineMean ?? 0, format: .fixed(precision: 4)) \
            | hrAnchor=\(self.hrAnchor ?? 0, format: .fixed(precision: 1)) \
            | baseline mean=\(self.baseline.mean ?? 0, format: .fixed(precision: 4)) \
            sd=\(self.baseline.std ?? 0, format: .fixed(precision: 4)) \
            threshold=\(self.baseline.threshold ?? 0, format: .fixed(precision: 4))
            """)
        } else {
            log.notice("""
            fade calibrated — arousal DROPPED OUT: eyeWide sd=\(spread, format: .fixed(precision: 4)) \
            < floor \(Self.arousalNoiseFloor, format: .fixed(precision: 3)); \
            weights renormalised across HR + motion \
            | hrAnchor=\(self.hrAnchor ?? 0, format: .fixed(precision: 1)) \
            | baseline mean=\(self.baseline.mean ?? 0, format: .fixed(precision: 4)) \
            sd=\(self.baseline.std ?? 0, format: .fixed(precision: 4)) \
            threshold=\(self.baseline.threshold ?? 0, format: .fixed(precision: 4))
            """)
        }
    }

    /// A warm start decays for longer than the calibration window, so let the anchor follow HR
    /// down. It only ever descends: the point is to restore headroom, never to claim more fade.
    ///
    /// This cannot itself trip the threshold. The anchor is the median of its window, so the
    /// frozen baseline already sits at an HR term of ~0, and the anchor only moves down when HR
    /// has already moved down with it — the term returns toward 0 rather than climbing past it.
    private mutating func trackAnchorDownward(hrBpm: Double?) {
        guard let hr = hrBpm, let anchor = hrAnchor else { return }
        recentHr.append(hr)
        if recentHr.count > baseline.capacity {
            recentHr.removeFirst(recentHr.count - baseline.capacity)
        }
        guard recentHr.count >= baseline.capacity,
              let median = Self.median(recentHr),
              median < anchor
        else { return }
        hrAnchor = median
    }

    // MARK: - Scoring

    private func compositeScore(for sample: RawSample) -> Double {
        var total = 0.0
        var weightSum = 0.0

        // HR drift: elevation above the session anchor, with a small allowance below it.
        if let hr = sample.hrBpm, let anchor = hrAnchor {
            let term = min(1.0, max(Self.hrFloorTerm, (hr - anchor) / Self.hrSpanBpm))
            total += hrWeight * term
            weightSum += hrWeight
        }

        // Arousal: how far `eyeWide` has fallen below its own baseline, in σ. Absolute `eyeWide`
        // rests near 0 on most faces, so only movement relative to this user carries meaning.
        if isArousalChannelActive == true,
           let eyeWide = sample.eyeWide,
           let mean = arousalBaselineMean,
           let std = arousalBaselineStd, std > 0 {
            let sigmasBelowBaseline = (mean - eyeWide) / std
            let term = min(1.0, max(0.0, sigmasBelowBaseline / Self.arousalSigmaSpan))
            total += arousalWeight * term
            weightSum += arousalWeight
        }

        // Motion energy: higher wrist motion → restlessness / fade.
        if let motionEnergy = sample.motionEnergy {
            total += motionWeight * min(1.0, max(0.0, motionEnergy))
            weightSum += motionWeight
        }

        return total / max(0.001, weightSum)
    }

    // MARK: - Statistics

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count > 1, let m = mean(values) else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count)
        return sqrt(variance)
    }
}
