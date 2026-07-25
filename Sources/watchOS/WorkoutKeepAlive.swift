import Foundation
import HealthKit

/// Keeps the watch app alive under continuous motion via HKWorkoutSession.
@MainActor
final class WorkoutKeepAlive: NSObject {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private(set) var isActive = false

    func start() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let types: Set<HKSampleType> = [HKObjectType.workoutType()]
        try await store.requestAuthorization(toShare: types, read: types)

        let config = HKWorkoutConfiguration()
        config.activityType = .boxing
        config.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: store, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)

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
