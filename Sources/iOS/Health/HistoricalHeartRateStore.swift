import Foundation
import HealthKit

/// Read-only HealthKit heart-rate history for Signals context.
/// Live Focus fade still prefers Watch workout samples via WatchConnectivity — this store
/// never writes to Firebase and never feeds the fade detector.
@Observable
@MainActor
final class HistoricalHeartRateStore {
    /// Lookback window in hours. Product default: 24.
    var windowHours: Int = 24 {
        didSet {
            let clamped = max(1, min(windowHours, 72))
            if clamped != windowHours {
                windowHours = clamped
            }
        }
    }

    private(set) var snapshot: HeartRateHistorySnapshot?
    private(set) var isRefreshing = false
    private(set) var lastErrorMessage: String?
    /// True after we have shown the system Health permission sheet at least once.
    private(set) var hasPromptedAuthorization: Bool =
        UserDefaults.standard.bool(forKey: HealthKitReadAccess.promptedKey)

    private let healthStore = HKHealthStore()

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Short status for Settings / Hub — wellness copy only, never clinical.
    var statusSummary: String {
        if !isHealthDataAvailable {
            return "Health unavailable on this device"
        }
        if !hasPromptedAuthorization {
            return "Not enabled · open Signals to allow"
        }
        if isRefreshing {
            return "Refreshing…"
        }
        if let snapshot, let latest = snapshot.latest {
            let overnight: String
            if let min = snapshot.overnightMinBpm {
                overnight = String(format: " · overnight low %.0f", min)
            } else {
                overnight = ""
            }
            return String(
                format: "Last 24h · %.0f bpm latest%@",
                latest.bpm,
                overnight
            )
        }
        if hasPromptedAuthorization {
            return "No heart-rate samples in the last \(windowHours)h"
        }
        return "Not enabled"
    }

    /// Samples from the last query that fall inside a Focus session window, as elapsed seconds.
    func sessionOverlaySeries(
        sessionStart: Date?,
        sessionEnd: Date = Date()
    ) -> [(elapsed: TimeInterval, value: Double)] {
        guard let sessionStart, let snapshot else { return [] }
        return HeartRateSeriesBucketer.mapToSessionElapsed(
            samples: snapshot.samples,
            sessionStart: sessionStart,
            sessionEnd: sessionEnd
        )
    }

    /// Prompt for all Signals Health read types in one authorize call.
    @discardableResult
    func requestHealthReadAccess() async -> Bool {
        guard isHealthDataAvailable else {
            lastErrorMessage = "Health data is not available on this device."
            return false
        }
        let types = HealthKitReadAccess.allReadTypes
        guard !types.isEmpty else {
            lastErrorMessage = "Health types unavailable."
            return false
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: types)
            markPrompted()
            lastErrorMessage = nil
            return true
        } catch {
            markPrompted()
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    /// Re-query the configured window. Safe to call when permission was denied — returns empty.
    func refreshHistoricalHeartRate() async {
        guard isHealthDataAvailable else {
            snapshot = nil
            return
        }
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            snapshot = nil
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let hours = windowHours
        let end = Date()
        let start = end.addingTimeInterval(-TimeInterval(hours) * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        do {
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: hrType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sort]
                ) { _, results, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let quantitySamples = (results as? [HKQuantitySample]) ?? []
                    continuation.resume(returning: quantitySamples)
                }
                healthStore.execute(query)
            }

            let unit = HKUnit.count().unitDivided(by: .minute())
            let points = samples.compactMap { sample -> HeartRateSamplePoint? in
                let bpm = sample.quantity.doubleValue(for: unit)
                guard bpm > 0, bpm.isFinite else { return nil }
                return HeartRateSamplePoint(date: sample.startDate, bpm: bpm)
            }

            snapshot = HeartRateSeriesBucketer.makeSnapshot(
                samples: points,
                windowHours: hours,
                queriedAt: end,
                windowStart: start,
                windowEnd: end
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            // Keep prior snapshot if any — a transient failure shouldn't wipe context.
        }
    }

    /// Signals entry: prompt once if needed, then refresh. Never call from cold launch.
    func ensureReadyForSignals() async {
        if !hasPromptedAuthorization {
            _ = await requestHealthReadAccess()
        }
        await refreshHistoricalHeartRate()
    }

    /// Sync prompted flag when trends store already authorized.
    func syncPromptedFromDefaults() {
        hasPromptedAuthorization = UserDefaults.standard.bool(forKey: HealthKitReadAccess.promptedKey)
    }

    private func markPrompted() {
        hasPromptedAuthorization = true
        UserDefaults.standard.set(true, forKey: HealthKitReadAccess.promptedKey)
    }
}
