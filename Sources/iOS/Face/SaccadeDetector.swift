import Foundation
import os
import simd

struct GazeSample: Sendable {
    let time: PhoneTime
    let lookAt: SIMD3<Float>
    let eyeBlinkLeft: Float
    let eyeBlinkRight: Float
    let eyeWideLeft: Float
    let eyeWideRight: Float

    var isBlinking: Bool {
        eyeBlinkLeft > 0.5 || eyeBlinkRight > 0.5
    }

    var eyeWide: Float {
        (eyeWideLeft + eyeWideRight) / 2
    }
}

struct SaccadeOnset: Sendable {
    let onset: PhoneTime
    let settle: PhoneTime?
}

/// Velocity-threshold saccade onset with hysteresis and sub-frame linear interpolation.
final class SaccadeDetector: @unchecked Sendable {
    private let onsetVelocity: Float
    private let offsetVelocity: Float
    private var previous: GazeSample?
    private var inSaccade = false
    private var lastOnset: PhoneTime?
    private var settleCandidate: PhoneTime?

    init(onsetVelocity: Float = 0.35, offsetVelocity: Float = 0.12) {
        self.onsetVelocity = onsetVelocity
        self.offsetVelocity = offsetVelocity
    }

    func reset() {
        previous = nil
        inSaccade = false
        lastOnset = nil
        settleCandidate = nil
    }

    func process(_ sample: GazeSample) -> SaccadeOnset? {
        defer { previous = sample }
        guard let previous else { return nil }

        let dt = sample.time.seconds - previous.time.seconds
        guard dt > 0 else { return nil }

        let delta = sample.lookAt - previous.lookAt
        let speed = length(delta) / Float(dt)

        if !inSaccade, speed >= onsetVelocity {
            // Sub-frame interpolate assuming speed rose linearly from ~0 at previous sample.
            let alpha = min(1, max(0, onsetVelocity / max(speed, 1e-4)))
            let onsetSeconds = previous.time.seconds + Double(alpha) * dt
            let onset = PhoneTime(seconds: onsetSeconds)
            inSaccade = true
            lastOnset = onset
            settleCandidate = nil
            return SaccadeOnset(onset: onset, settle: nil)
        }

        if inSaccade, speed <= offsetVelocity {
            if settleCandidate == nil {
                settleCandidate = sample.time
            } else if let settle = settleCandidate,
                      sample.time.seconds - settle.seconds >= 0.03 {
                inSaccade = false
                let onset = lastOnset ?? sample.time
                settleCandidate = nil
                return SaccadeOnset(onset: onset, settle: sample.time)
            }
        } else if inSaccade {
            settleCandidate = nil
        }

        return nil
    }
}

/// Blink-gated arousal from `eyeWide`, discarding ~100ms around each blink.
final class ArousalIndexer: @unchecked Sendable {
    private let blinkGateSeconds: Double = 0.1
    private var lastBlinkTime: PhoneTime?

    func reset() {
        lastBlinkTime = nil
    }

    func update(_ sample: GazeSample) -> Float? {
        if sample.isBlinking {
            lastBlinkTime = sample.time
            return nil
        }
        if let lastBlinkTime,
           abs(sample.time.seconds - lastBlinkTime.seconds) < blinkGateSeconds {
            return nil
        }
        return sample.eyeWide
    }
}

// MARK: - Arousal diagnostics (temporary — delete this section and its FaceTracker call sites)

/// Measures the real dynamic range of `eyeWide` / the derived fade arousal term on device.
///
/// Off unless the scheme sets `SYNAPSE_AROUSAL_DIAG=1`, and compiled inert in release, so it
/// cannot reach the demo build. Read output with:
/// `log stream --predicate 'subsystem == "com.dzak.synapse"' --style compact`
/// or just watch the Xcode console.
final class ArousalDiagnostics {
    /// Single switch. Xcode → Edit Scheme → Run → Arguments → Environment Variables.
    static let isEnabled: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SYNAPSE_AROUSAL_DIAG"] == "1"
        #else
        return false
        #endif
    }()

    /// Nil unless diagnostics are on, so call sites stay a single optional-chain.
    static func makeIfEnabled() -> ArousalDiagnostics? {
        isEnabled ? ArousalDiagnostics() : nil
    }

    private let log = Logger(subsystem: "com.dzak.synapse", category: "arousal-diag")
    private let summaryInterval: TimeInterval = 10

    /// Every ARKit frame — a fine-grained picture of the signal.
    private var eyeWideStats = Stats()
    /// Subsampled at the fade detector's own cadence, so σ here is what actually decides
    /// whether the arousal channel clears `FocusFadeDetector.arousalNoiseFloor` on device.
    private var cadenceStats = Stats()
    private var lastCadenceSampleAt: Double?

    private var totalFrames = 0
    private var blinkDiscards = 0
    private var gateDiscards = 0
    private var accepted = 0

    private var blinkEpisodes = 0
    private var blinkDurationSum = 0.0
    private var blinkDurationMax = 0.0
    private var blinkStartedAt: Double?

    private var trackedSeconds = 0.0
    private var closedSeconds = 0.0
    private var previousSampleTime: Double?
    private var startTime: Double?
    private var lastSummaryAt: Double?

    func begin() {
        eyeWideStats = Stats()
        cadenceStats = Stats()
        lastCadenceSampleAt = nil
        totalFrames = 0
        blinkDiscards = 0
        gateDiscards = 0
        accepted = 0
        blinkEpisodes = 0
        blinkDurationSum = 0
        blinkDurationMax = 0
        blinkStartedAt = nil
        trackedSeconds = 0
        closedSeconds = 0
        previousSampleTime = nil
        startTime = nil
        lastSummaryAt = nil
        log.notice("arousal-diag armed — capturing eyeWide dynamic range")
    }

    /// `acceptedValue` is exactly what `ArousalIndexer.update` returned for this sample.
    func record(sample: GazeSample, acceptedValue: Float?) {
        let now = sample.time.seconds
        if startTime == nil {
            startTime = now
            lastSummaryAt = now
        }
        // Cap dt so a backgrounded gap doesn't poison the time-weighted PERCLOS figure.
        let dt = min(max(now - (previousSampleTime ?? now), 0), 0.2)
        previousSampleTime = now
        trackedSeconds += dt

        totalFrames += 1

        let eyeWide = Double(sample.eyeWide)
        eyeWideStats.add(eyeWide)
        if now - (lastCadenceSampleAt ?? -.greatestFiniteMagnitude)
            >= FocusFadeDetector.defaultSampleIntervalSeconds {
            lastCadenceSampleAt = now
            cadenceStats.add(eyeWide)
        }

        if acceptedValue != nil {
            accepted += 1
        } else if sample.isBlinking {
            blinkDiscards += 1
        } else {
            gateDiscards += 1
        }

        // PERCLOS-70: share of tracked time with the eyelid ≥70% closed.
        let closure = Double(max(sample.eyeBlinkLeft, sample.eyeBlinkRight))
        if closure >= 0.7 {
            closedSeconds += dt
        }

        if sample.isBlinking {
            if blinkStartedAt == nil { blinkStartedAt = now }
        } else if let began = blinkStartedAt {
            let duration = now - began
            blinkStartedAt = nil
            // Ignore single-frame flickers; a real blink is ≥ ~50ms.
            if duration >= 0.05 {
                blinkEpisodes += 1
                blinkDurationSum += duration
                blinkDurationMax = max(blinkDurationMax, duration)
            }
        }

        if let last = lastSummaryAt, now - last >= summaryInterval {
            lastSummaryAt = now
            emit(final: false)
        }
    }

    func finish() {
        guard totalFrames > 0 else { return }
        emit(final: true)
    }

    private func emit(final: Bool) {
        let elapsed = max(0.001, (previousSampleTime ?? 0) - (startTime ?? 0))
        let label = final ? "FINAL" : "10s"

        // σ at the detector's own cadence is the number that decides the branch; the noise
        // floor is expressed in exactly these units.
        let floor = FocusFadeDetector.arousalNoiseFloor
        let cadenceSpread = cadenceStats.standardDeviation
        let willEngage = cadenceStats.count > 1 && cadenceSpread >= floor
        // If the channel does engage, this is the eyeWide drop that reads as maximum fade.
        let fullScaleDroop = cadenceSpread * FocusFadeDetector.arousalSigmaSpan

        log.notice("""
        [\(label, privacy: .public)] \(elapsed, format: .fixed(precision: 1))s \
        frames=\(self.totalFrames) \
        eyeWide mean=\(self.eyeWideStats.mean, format: .fixed(precision: 4)) \
        sd=\(self.eyeWideStats.standardDeviation, format: .fixed(precision: 4)) \
        min=\(self.eyeWideStats.minimum, format: .fixed(precision: 4)) \
        max=\(self.eyeWideStats.maximum, format: .fixed(precision: 4)) \
        p5=\(self.eyeWideStats.percentile(0.05), format: .fixed(precision: 4)) \
        p95=\(self.eyeWideStats.percentile(0.95), format: .fixed(precision: 4))
        """)

        log.notice("""
        [\(label, privacy: .public)] at detector cadence (8s): \
        n=\(self.cadenceStats.count) \
        sd=\(cadenceSpread, format: .fixed(precision: 4)) vs floor \(floor, format: .fixed(precision: 3)) \
        → arousal channel would \(willEngage ? "ENGAGE (z-scored)" : "DROP OUT (renormalise)", privacy: .public)\
        \(willEngage ? ", full-scale droop = \(String(format: "%.4f", fullScaleDroop)) eyeWide" : "", privacy: .public)
        """)

        let blinkRatePerMinute = Double(blinkEpisodes) / max(elapsed / 60, 0.001)
        let meanBlink = blinkEpisodes > 0 ? blinkDurationSum / Double(blinkEpisodes) : 0
        let perclos = trackedSeconds > 0 ? closedSeconds / trackedSeconds * 100 : 0

        log.notice("""
        [\(label, privacy: .public)] gating accepted=\(self.accepted) \
        blinkDiscard=\(self.blinkDiscards) postBlinkGate=\(self.gateDiscards) \
        discarded=\(Double(self.blinkDiscards + self.gateDiscards) / Double(max(self.totalFrames, 1)) * 100, format: .fixed(precision: 1))% \
        | blinks=\(self.blinkEpisodes) rate=\(blinkRatePerMinute, format: .fixed(precision: 1))/min \
        meanDur=\(meanBlink * 1000, format: .fixed(precision: 0))ms \
        maxDur=\(self.blinkDurationMax * 1000, format: .fixed(precision: 0))ms \
        PERCLOS70=\(perclos, format: .fixed(precision: 2))%
        """)

        // Nothing calls FaceTracker.stop(), so the verdict has to land on rolling summaries too.
        if final || elapsed >= 60 {
            let verdict = willEngage
                ? "eyeWide carries real range — arousal contributes as a z-score"
                : "eyeWide is inert — arousal self-disables, fade runs on HR + motion"
            log.notice("[\(label, privacy: .public)] verdict: \(verdict, privacy: .public)")
        }
    }

    /// Min/max/mean/σ plus a 200-bin histogram for outlier-resistant percentiles.
    private struct Stats {
        private(set) var count = 0
        private(set) var minimum = 0.0
        private(set) var maximum = 0.0
        private var sum = 0.0
        private var sumSquares = 0.0
        private var histogram = [Int](repeating: 0, count: 200)

        var mean: Double { count > 0 ? sum / Double(count) : 0 }

        var standardDeviation: Double {
            guard count > 1 else { return 0 }
            let variance = sumSquares / Double(count) - mean * mean
            return variance > 0 ? sqrt(variance) : 0
        }

        mutating func add(_ value: Double) {
            if count == 0 {
                minimum = value
                maximum = value
            } else {
                minimum = Swift.min(minimum, value)
                maximum = Swift.max(maximum, value)
            }
            count += 1
            sum += value
            sumSquares += value * value
            let bin = Swift.min(histogram.count - 1, Swift.max(0, Int(value * Double(histogram.count))))
            histogram[bin] += 1
        }

        func percentile(_ fraction: Double) -> Double {
            guard count > 0 else { return 0 }
            let target = Double(count) * fraction
            var cumulative = 0.0
            for (index, binCount) in histogram.enumerated() {
                cumulative += Double(binCount)
                if cumulative >= target {
                    return (Double(index) + 0.5) / Double(histogram.count)
                }
            }
            return 1
        }
    }
}
