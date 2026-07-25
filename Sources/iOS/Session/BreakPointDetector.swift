import Foundation

/// Rolling baseline over first 10 valid trials; fires when gap > mean + 2σ.
struct BreakPointDetector {
    static let baselineCount = 10
    static let sigmaMultiplier = 2.0

    private var baseline = RollingBaseline(
        capacity: BreakPointDetector.baselineCount,
        sigmaMultiplier: BreakPointDetector.sigmaMultiplier
    )
    private(set) var didFire = false

    var baselineGaps: [Double] { baseline.samples }
    var baselineMean: Double? { baseline.mean }
    var baselineStd: Double? { baseline.std }

    mutating func reset() {
        baseline.reset()
        didFire = false
    }

    /// Returns the trial index that triggered the break-point, if any.
    mutating func ingest(trialIndex: Int, gapMs: Double) -> Int? {
        if !baseline.isReady {
            _ = baseline.ingest(gapMs)
            return nil
        }

        guard !didFire else { return nil }

        if baseline.ingest(gapMs) {
            didFire = true
            return trialIndex
        }
        return nil
    }
}
