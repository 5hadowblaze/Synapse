import Foundation

/// Refractory + threshold gate for punch-peak detection (pure, testable).
struct StrikeGate: Sendable, Equatable {
    var spikeThresholdG: Double
    var refractorySeconds: Double
    private(set) var lastStrikeTime: Double = 0

    init(spikeThresholdG: Double = 3.5, refractorySeconds: Double = 0.35) {
        self.spikeThresholdG = spikeThresholdG
        self.refractorySeconds = refractorySeconds
    }

    /// Returns true when this sample should fire a strike.
    mutating func shouldFire(peakG: Double, at sampleTime: Double) -> Bool {
        guard peakG >= spikeThresholdG else { return false }
        guard sampleTime - lastStrikeTime >= refractorySeconds else { return false }
        lastStrikeTime = sampleTime
        return true
    }

    mutating func reset() {
        lastStrikeTime = 0
    }
}
