import Foundation

/// Rolling baseline over first 10 valid trials; fires when gap > mean + 2σ.
struct BreakPointDetector {
    static let baselineCount = 10
    static let sigmaMultiplier = 2.0

    private(set) var baselineGaps: [Double] = []
    private(set) var baselineMean: Double?
    private(set) var baselineStd: Double?
    private(set) var didFire = false

    mutating func reset() {
        baselineGaps = []
        baselineMean = nil
        baselineStd = nil
        didFire = false
    }

    /// Returns the trial index that triggered the break-point, if any.
    mutating func ingest(trialIndex: Int, gapMs: Double) -> Int? {
        if baselineGaps.count < Self.baselineCount {
            baselineGaps.append(gapMs)
            if baselineGaps.count == Self.baselineCount {
                let mean = baselineGaps.reduce(0, +) / Double(baselineGaps.count)
                let variance = baselineGaps.reduce(0) { $0 + pow($1 - mean, 2) } / Double(baselineGaps.count)
                baselineMean = mean
                baselineStd = sqrt(variance)
            }
            return nil
        }

        guard !didFire,
              let mean = baselineMean,
              let std = baselineStd
        else { return nil }

        let threshold = mean + Self.sigmaMultiplier * std
        if gapMs > threshold {
            didFire = true
            return trialIndex
        }
        return nil
    }
}
