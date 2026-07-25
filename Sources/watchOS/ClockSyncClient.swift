import Foundation
import WatchConnectivity

/// Watch-side Cristian's algorithm client: burst 20 sync pings, keep lowest RTT, re-sync every 30s.
@MainActor
final class ClockSyncClient {
    private(set) var offsetSeconds: Double?
    private(set) var bestRttSeconds: Double?
    private(set) var lastSyncDate: Date?
    private(set) var isSyncing = false

    var onSyncUpdated: ((ClockSyncSample) -> Void)?

    private weak var sessionManager: WatchSessionManager?
    private var resyncTask: Task<Void, Never>?

    func attach(sessionManager: WatchSessionManager) {
        self.sessionManager = sessionManager
    }

    func startPeriodicSync() {
        resyncTask?.cancel()
        resyncTask = Task { @MainActor in
            await runBurst()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(ClockSyncConfig.resyncIntervalSeconds * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await runBurst()
            }
        }
    }

    func stop() {
        resyncTask?.cancel()
        resyncTask = nil
    }

    func runBurst() async {
        guard let sessionManager else { return }
        isSyncing = true
        defer { isSyncing = false }

        var best: ClockSyncSample?
        for _ in 0..<ClockSyncConfig.burstSampleCount {
            if let sample = await sessionManager.performSyncRoundTrip() {
                if best == nil || sample.rttSeconds < best!.rttSeconds {
                    best = sample
                }
            }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }

        if let best {
            offsetSeconds = best.offsetSeconds
            bestRttSeconds = best.rttSeconds
            lastSyncDate = Date()
            onSyncUpdated?(best)
        }
    }
}
