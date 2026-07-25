import Foundation

/// Abstraction for Cristian sync round-trips (WatchSessionManager in production; mock in tests).
protocol ClockSyncRoundTripPerforming: AnyObject {
    func performSyncRoundTrip() async -> ClockSyncSample?
}

/// Watch-side Cristian's algorithm client: burst N pings, keep lowest RTT, re-sync periodically.
@MainActor
final class ClockSyncClient {
    private(set) var offsetSeconds: Double?
    private(set) var bestRttSeconds: Double?
    private(set) var lastSyncDate: Date?
    private(set) var isSyncing = false

    var onSyncUpdated: ((ClockSyncSample) -> Void)?

    private weak var roundTrip: (any ClockSyncRoundTripPerforming)?
    private var resyncTask: Task<Void, Never>?

    /// Burst size / interval — overridable in tests.
    var burstSampleCount: Int = ClockSyncConfig.burstSampleCount
    var resyncIntervalSeconds: TimeInterval = ClockSyncConfig.resyncIntervalSeconds
    var interSampleDelayNanoseconds: UInt64 = 30_000_000

    func attach(roundTrip: any ClockSyncRoundTripPerforming) {
        self.roundTrip = roundTrip
    }

    func startPeriodicSync() {
        resyncTask?.cancel()
        resyncTask = Task { @MainActor in
            await runBurst()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(resyncIntervalSeconds * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await runBurst()
            }
        }
    }

    func stop() {
        resyncTask?.cancel()
        resyncTask = nil
    }

    @discardableResult
    func runBurst() async -> ClockSyncSample? {
        guard let roundTrip else { return nil }
        isSyncing = true
        defer { isSyncing = false }

        var best: ClockSyncSample?
        for _ in 0..<burstSampleCount {
            if Task.isCancelled { break }
            if let sample = await roundTrip.performSyncRoundTrip() {
                if best == nil || sample.rttSeconds < best!.rttSeconds {
                    best = sample
                }
            }
            if interSampleDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: interSampleDelayNanoseconds)
            }
        }

        if let best {
            offsetSeconds = best.offsetSeconds
            bestRttSeconds = best.rttSeconds
            lastSyncDate = Date()
            onSyncUpdated?(best)
        }
        return best
    }
}
