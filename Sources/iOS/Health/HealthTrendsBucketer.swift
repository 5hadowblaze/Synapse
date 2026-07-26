import Foundation

// MARK: - Pure models (no HealthKit)

/// One daily aggregated quantity (resting HR, HRV, steps, energy, stand hours).
struct DailyQuantityPoint: Equatable, Sendable {
    /// Start of the local calendar day.
    let dayStart: Date
    let value: Double
}

/// Latest + short daily trend for a single quantity metric.
struct QuantityTrendSummary: Equatable, Sendable {
    let latest: DailyQuantityPoint?
    /// Oldest → newest, one point per day that has data.
    let daily: [DailyQuantityPoint]
    /// True when fewer than `sparseThreshold` days have data (honest empty / sparse UI).
    let isSparse: Bool

    var isEmpty: Bool { daily.isEmpty }

    init(daily: [DailyQuantityPoint], sparseThreshold: Int = 2) {
        let sorted = daily.sorted { $0.dayStart < $1.dayStart }
        self.daily = sorted
        self.latest = sorted.last
        self.isSparse = sorted.count < sparseThreshold
    }
}

/// Full trends snapshot published after HealthKit queries — display / pacing context only.
struct HealthTrendsSnapshot: Equatable, Sendable {
    let queriedAt: Date
    let dayCount: Int
    let restingHeartRate: QuantityTrendSummary
    let hrvSDNN: QuantityTrendSummary
    let sleep: SleepTrendSummary
    let activeEnergyKcal: QuantityTrendSummary
    let standHours: QuantityTrendSummary
    let steps: QuantityTrendSummary

    var hasAnyData: Bool {
        !restingHeartRate.isEmpty
            || !hrvSDNN.isEmpty
            || !sleep.isEmpty
            || !activeEnergyKcal.isEmpty
            || !standHours.isEmpty
            || !steps.isEmpty
    }
}

/// Raw quantity sample for bucketing (date + value in the metric’s display unit).
struct TrendSamplePoint: Equatable, Sendable {
    let date: Date
    let value: Double
}

// MARK: - Bucketer

/// Pure daily / nightly aggregation — unit-testable without HealthKit.
enum HealthTrendsBucketer {
    /// Default lookback for recovery + activity daily trends.
    static let defaultDayCount = 14
    /// HRV is often sparse on Apple Watch — show honest empty below this many days.
    static let hrvSparseThreshold = 2
    /// Night window starts at local 18:00 on the evening before `wakeDay`.
    static let nightBoundaryHour = 18

    // MARK: Daily average (resting HR, HRV SDNN)

    /// One value per local day — mean of samples that fall on that day.
    static func dailyAverages(
        samples: [TrendSamplePoint],
        dayCount: Int,
        endingOn end: Date,
        calendar: Calendar = .current,
        sparseThreshold: Int = 2
    ) -> QuantityTrendSummary {
        let days = dayStarts(endingOn: end, count: dayCount, calendar: calendar)
        var sums: [Date: (sum: Double, count: Int)] = [:]
        for day in days {
            sums[day] = (0, 0)
        }

        for sample in samples {
            guard sample.value.isFinite, sample.value > 0 else { continue }
            let day = calendar.startOfDay(for: sample.date)
            guard var entry = sums[day] else { continue }
            entry.sum += sample.value
            entry.count += 1
            sums[day] = entry
        }

        let points = days.compactMap { day -> DailyQuantityPoint? in
            guard let entry = sums[day], entry.count > 0 else { return nil }
            return DailyQuantityPoint(dayStart: day, value: entry.sum / Double(entry.count))
        }
        return QuantityTrendSummary(daily: points, sparseThreshold: sparseThreshold)
    }

    // MARK: Daily sum (steps, active energy, stand hours)

    /// One value per local day — sum of samples that fall on that day.
    static func dailySums(
        samples: [TrendSamplePoint],
        dayCount: Int,
        endingOn end: Date,
        calendar: Calendar = .current,
        sparseThreshold: Int = 2
    ) -> QuantityTrendSummary {
        let days = dayStarts(endingOn: end, count: dayCount, calendar: calendar)
        var totals: [Date: Double] = [:]
        for day in days {
            totals[day] = 0
        }

        for sample in samples {
            guard sample.value.isFinite, sample.value >= 0 else { continue }
            let day = calendar.startOfDay(for: sample.date)
            guard totals[day] != nil else { continue }
            totals[day, default: 0] += sample.value
        }

        let points = days.compactMap { day -> DailyQuantityPoint? in
            guard let total = totals[day], total > 0 else { return nil }
            return DailyQuantityPoint(dayStart: day, value: total)
        }
        return QuantityTrendSummary(daily: points, sparseThreshold: sparseThreshold)
    }

    // MARK: Sleep nights

    /// Group sleep intervals into 18:00→18:00 nights attributed to the wake calendar day.
    /// Prefers Apple Watch–sourced samples when stages are present.
    static func sleepNights(
        intervals: [SleepIntervalPoint],
        nightCount: Int,
        endingOn end: Date,
        calendar: Calendar = .current,
        sparseThreshold: Int = 2
    ) -> SleepTrendSummary {
        let preferred = SleepRecoveryAnalytics.preferWatchSources(intervals)
        let wakeDays = dayStarts(endingOn: end, count: nightCount, calendar: calendar)
        var buckets: [Date: [SleepIntervalPoint]] = [:]
        for day in wakeDays {
            buckets[day] = []
        }

        for interval in preferred {
            guard interval.durationSeconds > 0 else { continue }
            let wakeDay = wakeDayStart(for: interval.end, calendar: calendar)
            guard buckets[wakeDay] != nil else { continue }
            buckets[wakeDay, default: []].append(interval)
        }

        let nights = wakeDays.compactMap { wakeDay -> SleepNightSummary? in
            SleepRecoveryAnalytics.summarizeNight(
                wakeDayStart: wakeDay,
                intervals: buckets[wakeDay] ?? []
            )
        }
        return SleepTrendSummary(nights: nights, sparseThreshold: sparseThreshold)
    }

    /// Wake-day attribution: samples ending before local `nightBoundaryHour` belong to that calendar day;
    /// later evening samples belong to the next morning’s day.
    static func wakeDayStart(for date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let hour = calendar.component(.hour, from: date)
        if hour >= nightBoundaryHour {
            return calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return day
    }

    // MARK: Snapshot

    static func makeSnapshot(
        queriedAt: Date,
        dayCount: Int = defaultDayCount,
        restingHR: [TrendSamplePoint],
        hrvSDNN: [TrendSamplePoint],
        sleepIntervals: [SleepIntervalPoint],
        activeEnergyKcal: [TrendSamplePoint],
        standHours: [TrendSamplePoint],
        steps: [TrendSamplePoint],
        calendar: Calendar = .current
    ) -> HealthTrendsSnapshot {
        HealthTrendsSnapshot(
            queriedAt: queriedAt,
            dayCount: dayCount,
            restingHeartRate: dailyAverages(
                samples: restingHR,
                dayCount: dayCount,
                endingOn: queriedAt,
                calendar: calendar
            ),
            hrvSDNN: dailyAverages(
                samples: hrvSDNN,
                dayCount: dayCount,
                endingOn: queriedAt,
                calendar: calendar,
                sparseThreshold: hrvSparseThreshold
            ),
            sleep: sleepNights(
                intervals: sleepIntervals,
                nightCount: min(dayCount, 7),
                endingOn: queriedAt,
                calendar: calendar
            ),
            activeEnergyKcal: dailySums(
                samples: activeEnergyKcal,
                dayCount: dayCount,
                endingOn: queriedAt,
                calendar: calendar
            ),
            standHours: dailySums(
                samples: standHours,
                dayCount: dayCount,
                endingOn: queriedAt,
                calendar: calendar
            ),
            steps: dailySums(
                samples: steps,
                dayCount: dayCount,
                endingOn: queriedAt,
                calendar: calendar
            )
        )
    }

    // MARK: Helpers

    /// `count` day-starts ending on `end`’s local day (inclusive), oldest → newest.
    static func dayStarts(
        endingOn end: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        let last = calendar.startOfDay(for: end)
        guard count > 0 else { return [] }
        return (0..<count).compactMap { index in
            calendar.date(byAdding: .day, value: -(count - 1 - index), to: last)
        }
    }
}
