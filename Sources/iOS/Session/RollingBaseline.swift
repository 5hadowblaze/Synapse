import Foundation

/// Shared mean + kσ threshold helper used by trial break-point and Focus fade.
struct RollingBaseline {
    let capacity: Int
    let sigmaMultiplier: Double
    /// Floor for σ so near-flat baselines don't fire on tiny noise (threshold stays mean + k·max(σ, floor)).
    let minStd: Double

    private(set) var samples: [Double] = []
    private(set) var mean: Double?
    private(set) var std: Double?

    var isReady: Bool { mean != nil && std != nil }
    var threshold: Double? {
        guard let mean, let std else { return nil }
        return mean + sigmaMultiplier * max(std, minStd)
    }

    init(capacity: Int, sigmaMultiplier: Double = 2.0, minStd: Double = 0) {
        self.capacity = capacity
        self.sigmaMultiplier = sigmaMultiplier
        self.minStd = max(0, minStd)
    }

    mutating func reset() {
        samples = []
        mean = nil
        std = nil
    }

    /// While collecting: append until capacity, then compute stats.
    /// After ready: return whether `value` exceeds mean + kσ (does not mutate further).
    @discardableResult
    mutating func ingest(_ value: Double) -> Bool {
        if samples.count < capacity {
            samples.append(value)
            if samples.count == capacity {
                recompute()
            }
            return false
        }
        guard let threshold else { return false }
        return value > threshold
    }

    private mutating func recompute() {
        guard !samples.isEmpty else {
            mean = nil
            std = nil
            return
        }
        let m = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0) { $0 + pow($1 - m, 2) } / Double(samples.count)
        mean = m
        std = sqrt(variance)
    }
}
