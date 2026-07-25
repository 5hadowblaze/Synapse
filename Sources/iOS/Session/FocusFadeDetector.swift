import Foundation

/// Continuous fade score from HR drift + low arousal (+ optional motion energy).
/// Soft multi-fire with cooldown after baseline (mean + 2σ), unlike one-shot trial BP.
struct FocusFadeDetector {
    /// ~2.4 min at 8s sample interval (18 × 8s).
    static let defaultBaselineSamples = 18
    static let defaultCooldownSeconds: TimeInterval = 90
    static let defaultSampleIntervalSeconds: TimeInterval = 8
    /// Minimum σ for fade composite scores (~0…1) so flat baselines need a real spike.
    static let defaultMinStd: Double = 0.05

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
    private var lastSampleAt: TimeInterval?
    private var hrAnchor: Double?

    init(
        baselineSamples: Int = FocusFadeDetector.defaultBaselineSamples,
        cooldownSeconds: TimeInterval = FocusFadeDetector.defaultCooldownSeconds,
        sampleInterval: TimeInterval = FocusFadeDetector.defaultSampleIntervalSeconds,
        minStd: Double = FocusFadeDetector.defaultMinStd
    ) {
        self.baseline = RollingBaseline(
            capacity: baselineSamples,
            sigmaMultiplier: 2.0,
            minStd: minStd
        )
        self.cooldownSeconds = cooldownSeconds
        self.sampleInterval = sampleInterval
    }

    mutating func reset() {
        baseline.reset()
        lastScore = nil
        fadeCount = 0
        lastFadeAt = nil
        lastSampleAt = nil
        hrAnchor = nil
    }

    var isBaselineReady: Bool { baseline.isReady }
    var baselineMean: Double? { baseline.mean }
    var baselineStd: Double? { baseline.std }
    var fadeThreshold: Double? { baseline.threshold }

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

        let score = compositeScore(hrBpm: hrBpm, arousal: arousal, motionEnergy: motionEnergy)
        lastScore = score

        let exceeded = baseline.ingest(score)
        guard exceeded, baseline.isReady else { return false }

        if let lastFade = lastFadeAt, now - lastFade < cooldownSeconds {
            return false
        }
        lastFadeAt = now
        fadeCount += 1
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

    private mutating func compositeScore(
        hrBpm: Double?,
        arousal: Float?,
        motionEnergy: Double?
    ) -> Double {
        // HR drift: elevation above session anchor (normalized ~0…1 for ~20 bpm rise).
        var hrTerm = 0.0
        if let hrBpm {
            if hrAnchor == nil { hrAnchor = hrBpm }
            if let anchor = hrAnchor {
                hrTerm = min(1.0, max(0.0, (hrBpm - anchor) / 20.0))
            }
        }

        // Low arousal → higher fade (1 − arousal).
        let arousalTerm: Double
        if let arousal {
            arousalTerm = Double(1.0 - min(1, max(0, arousal)))
        } else {
            arousalTerm = 0.35 // neutral when face lost
        }

        // Motion energy: higher wrist motion → restlessness / fade.
        let motionTerm: Double
        if let motionEnergy {
            motionTerm = min(1.0, max(0.0, motionEnergy))
        } else {
            // No stillness stream — redistribute weight to HR + arousal.
            return (hrWeight * hrTerm + arousalWeight * arousalTerm)
                / max(0.001, hrWeight + arousalWeight)
        }

        let wSum = hrWeight + arousalWeight + motionWeight
        return (hrWeight * hrTerm + arousalWeight * arousalTerm + motionWeight * motionTerm)
            / max(0.001, wSum)
    }
}
