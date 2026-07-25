import Foundation
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
