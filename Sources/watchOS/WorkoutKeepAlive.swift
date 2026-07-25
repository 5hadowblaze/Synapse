import Foundation
import HealthKit

/// Keeps the watch app alive under continuous motion via HKWorkoutSession.
/// Also streams workout heart rate (~1 BPM sample every few seconds on Series 5).
@MainActor
final class WorkoutKeepAlive: NSObject {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private(set) var isActive = false
    private(set) var lastHeartRateBpm: Double?

    /// `(bpm, hkStart, hkEnd)` — HealthKit window dates as `timeIntervalSinceReferenceDate`.
    var onHeartRate: (@MainActor (Double, Date?, Date?) -> Void)?

    func start() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), heartRateType]
        try await store.requestAuthorization(toShare: share, read: read)

        let config = HKWorkoutConfiguration()
        config.activityType = .boxing
        config.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: store, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        let dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        dataSource.enableCollection(for: heartRateType, predicate: nil)
        builder.dataSource = dataSource
        builder.delegate = self

        self.session = session
        self.builder = builder
        session.delegate = self

        session.startActivity(with: Date())
        try await builder.beginCollection(at: Date())
        isActive = true
    }

    func stop() async {
        session?.end()
        do {
            try await builder?.endCollection(at: Date())
            try await builder?.finishWorkout()
        } catch {
            // Best-effort teardown.
        }
        session = nil
        builder = nil
        isActive = false
        lastHeartRateBpm = nil
    }

    private func publishHeartRate(from builder: HKLiveWorkoutBuilder) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let statistics = builder.statistics(for: hrType),
              let quantity = statistics.mostRecentQuantity()
        else { return }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = quantity.doubleValue(for: unit)
        guard bpm > 0, bpm.isFinite else { return }

        let interval = statistics.mostRecentQuantityDateInterval()
        lastHeartRateBpm = bpm
        onHeartRate?(bpm, interval?.start, interval?.end)
    }
}

extension WorkoutKeepAlive: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            isActive = (toState == .running)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            isActive = false
        }
    }
}

extension WorkoutKeepAlive: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType)
        else { return }
        Task { @MainActor in
            self.publishHeartRate(from: workoutBuilder)
        }
    }
}
