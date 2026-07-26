import Foundation
import HealthKit

/// Read-only HealthKit recovery / activity trends for Signals context.
/// Display only — never writes to Firebase and never feeds FocusFadeDetector.
@Observable
@MainActor
final class HealthTrendsStore {
    /// Lookback in calendar days (resting HR, HRV, activity). Sleep uses up to 7 nights.
    var dayCount: Int = HealthTrendsBucketer.defaultDayCount {
        didSet {
            let clamped = max(7, min(dayCount, 30))
            if clamped != dayCount { dayCount = clamped }
        }
    }

    private(set) var snapshot: HealthTrendsSnapshot?
    private(set) var isRefreshing = false
    private(set) var lastErrorMessage: String?
    private(set) var hasPromptedAuthorization: Bool =
        UserDefaults.standard.bool(forKey: HealthKitReadAccess.promptedKey)

    private let healthStore = HKHealthStore()

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Short Hub / Settings line — recovery context only, never clinical.
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
        guard let snapshot, snapshot.hasAnyData else {
            return hasPromptedAuthorization
                ? "No recovery or activity samples yet"
                : "Not enabled"
        }

        var parts: [String] = []
        if let rhr = snapshot.restingHeartRate.latest {
            parts.append(String(format: "Resting %.0f", rhr.value))
        }
        if let sleep = snapshot.sleep.lastNight {
            parts.append(String(format: "Sleep %.1fh", sleep.asleepHours))
        }
        if let steps = snapshot.steps.latest {
            parts.append(String(format: "%.0fk steps", steps.value / 1000))
        }
        if parts.isEmpty {
            return "Health connected · sparse data"
        }
        return parts.joined(separator: " · ")
    }

    /// Compact Hub chips (Resting · Sleep) when cheap context is available.
    var hubContextChips: [String] {
        guard let snapshot else { return [] }
        var chips: [String] = []
        if let rhr = snapshot.restingHeartRate.latest {
            chips.append(String(format: "Resting %.0f", rhr.value))
        }
        if let sleep = snapshot.sleep.lastNight {
            chips.append(String(format: "Sleep %.1fh", sleep.asleepHours))
            chips.append("Score \(sleep.score.value)")
        }
        return chips
    }

    /// Prompt for all Signals read types in one sheet (call from Signals / Settings).
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

    /// Re-query recovery + activity windows. Safe when permission denied — empty snapshot.
    func refreshTrends() async {
        guard isHealthDataAvailable else {
            snapshot = nil
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let end = Date()
        let days = dayCount
        let start = Calendar.current.startOfDay(for: end)
            .addingTimeInterval(-TimeInterval(days) * 24 * 3600)

        async let resting = fetchQuantitySamples(
            identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: start,
            end: end
        )
        async let hrv = fetchQuantitySamples(
            identifier: .heartRateVariabilitySDNN,
            unit: HKUnit.secondUnit(with: .milli),
            start: start,
            end: end
        )
        async let energy = fetchQuantitySamples(
            identifier: .activeEnergyBurned,
            unit: HKUnit.kilocalorie(),
            start: start,
            end: end
        )
        async let steps = fetchQuantitySamples(
            identifier: .stepCount,
            unit: HKUnit.count(),
            start: start,
            end: end
        )
        async let stand = fetchStandHourSamples(start: start, end: end)
        async let sleep = fetchSleepIntervals(start: start, end: end)

        do {
            let (
                restingPoints,
                hrvPoints,
                energyPoints,
                stepPoints,
                standPoints,
                sleepIntervals
            ) = try await (resting, hrv, energy, steps, stand, sleep)

            snapshot = HealthTrendsBucketer.makeSnapshot(
                queriedAt: end,
                dayCount: days,
                restingHR: restingPoints,
                hrvSDNN: hrvPoints,
                sleepIntervals: sleepIntervals,
                activeEnergyKcal: energyPoints,
                standHours: standPoints,
                steps: stepPoints
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Signals entry: prompt once if needed, then refresh.
    func ensureReadyForSignals() async {
        if !hasPromptedAuthorization {
            _ = await requestHealthReadAccess()
        }
        await refreshTrends()
    }

    /// Sync prompted flag when another store (historical HR) already authorized.
    func syncPromptedFromDefaults() {
        hasPromptedAuthorization = UserDefaults.standard.bool(forKey: HealthKitReadAccess.promptedKey)
    }

    // MARK: - Queries

    private func fetchQuantitySamples(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [TrendSamplePoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }
        let samples: [HKQuantitySample] = try await sampleQuery(
            sampleType: type,
            start: start,
            end: end
        )
        return samples.compactMap { sample in
            let value = sample.quantity.doubleValue(for: unit)
            guard value.isFinite else { return nil }
            return TrendSamplePoint(date: sample.startDate, value: value)
        }
    }

    /// Prefer Apple Stand Hour category (1 per stood hour). Fall back to appleStandTime → hours.
    private func fetchStandHourSamples(start: Date, end: Date) async throws -> [TrendSamplePoint] {
        if let standHourType = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
            let samples: [HKCategorySample] = try await sampleQuery(
                sampleType: standHourType,
                start: start,
                end: end
            )
            let stood = samples.compactMap { sample -> TrendSamplePoint? in
                guard sample.value == HKCategoryValueAppleStandHour.stood.rawValue else {
                    return nil
                }
                return TrendSamplePoint(date: sample.startDate, value: 1)
            }
            if !stood.isEmpty {
                return stood
            }
        }

        // Fallback: cumulative stand minutes → fractional hours for daily sum.
        return try await fetchQuantitySamples(
            identifier: .appleStandTime,
            unit: HKUnit.minute(),
            start: start,
            end: end
        ).map { TrendSamplePoint(date: $0.date, value: $0.value / 60) }
    }

    private func fetchSleepIntervals(start: Date, end: Date) async throws -> [SleepIntervalPoint] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }
        let samples: [HKCategorySample] = try await sampleQuery(
            sampleType: sleepType,
            start: start,
            end: end
        )
        return samples.compactMap { sample -> SleepIntervalPoint? in
            guard let stage = HealthKitReadAccess.sleepStage(forRawValue: sample.value) else {
                return nil
            }
            guard sample.endDate > sample.startDate else { return nil }
            let fromWatch = HealthKitReadAccess.isAppleWatchSource(sample.sourceRevision.source)
            return SleepIntervalPoint(
                start: sample.startDate,
                end: sample.endDate,
                stage: stage,
                fromWatch: fromWatch
            )
        }
    }

    private func sampleQuery<T: HKSample>(
        sampleType: HKSampleType,
        start: Date,
        end: Date
    ) async throws -> [T] {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let typed = (results as? [T]) ?? []
                continuation.resume(returning: typed)
            }
            healthStore.execute(query)
        }
    }

    private func markPrompted() {
        hasPromptedAuthorization = true
        UserDefaults.standard.set(true, forKey: HealthKitReadAccess.promptedKey)
    }
}
