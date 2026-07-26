import Foundation

/// One heart-rate reading from HealthKit (or a test fixture). Pure data — no HealthKit types.
struct HeartRateSamplePoint: Equatable, Sendable {
    let date: Date
    let bpm: Double
}

/// Averaged bin for charting a long window without plotting every raw sample.
struct HeartRateBucket: Equatable, Sendable {
    /// Bucket centre (start + half width).
    let date: Date
    let bpm: Double
    let sampleCount: Int
}

/// Snapshot the UI / AppModel publish after a HealthKit query.
struct HeartRateHistorySnapshot: Equatable, Sendable {
    /// Requested lookback in hours (default 24).
    let windowHours: Int
    let queriedAt: Date
    let windowStart: Date
    let windowEnd: Date
    /// Raw samples in the window, oldest → newest.
    let samples: [HeartRateSamplePoint]
    /// Downsampled series for charts.
    let buckets: [HeartRateBucket]
    let latest: HeartRateSamplePoint?
    /// Minimum BPM among samples whose local hour is in 00:00–06:00 within the window.
    let overnightMinBpm: Double?

    var isEmpty: Bool { samples.isEmpty }

    var latestBpm: Double? { latest?.bpm }
}

/// Pure parsing / bucketing for historical HR — unit-testable without HealthKit.
enum HeartRateSeriesBucketer {
    /// Default: 5-minute bins over a 24h window (~288 points max).
    static let defaultBucketSeconds: TimeInterval = 5 * 60

    /// Average BPM into fixed-width bins covering `[from, to]`.
    static func bucket(
        samples: [HeartRateSamplePoint],
        bucketSeconds: TimeInterval = defaultBucketSeconds,
        from: Date,
        to: Date
    ) -> [HeartRateBucket] {
        guard to > from, bucketSeconds > 0 else { return [] }

        let width = bucketSeconds
        var totals: [Int: (sum: Double, count: Int)] = [:]

        for sample in samples {
            guard sample.date >= from, sample.date <= to, sample.bpm > 0, sample.bpm.isFinite else {
                continue
            }
            let offset = sample.date.timeIntervalSince(from)
            let index = Int(offset / width)
            let entry = totals[index] ?? (0, 0)
            totals[index] = (entry.sum + sample.bpm, entry.count + 1)
        }

        return totals.keys.sorted().compactMap { index in
            guard let entry = totals[index], entry.count > 0 else { return nil }
            let start = from.addingTimeInterval(TimeInterval(index) * width)
            let centre = start.addingTimeInterval(width / 2)
            return HeartRateBucket(
                date: centre,
                bpm: entry.sum / Double(entry.count),
                sampleCount: entry.count
            )
        }
    }

    /// Min BPM for samples whose local clock hour is in `[0, 6)` (overnight window).
    static func overnightMinimum(
        samples: [HeartRateSamplePoint],
        calendar: Calendar = .current
    ) -> Double? {
        var minBpm: Double?
        for sample in samples {
            guard sample.bpm > 0, sample.bpm.isFinite else { continue }
            let hour = calendar.component(.hour, from: sample.date)
            guard hour >= 0, hour < 6 else { continue }
            if let current = minBpm {
                minBpm = min(current, sample.bpm)
            } else {
                minBpm = sample.bpm
            }
        }
        return minBpm
    }

    /// Map wall-clock samples onto a Focus session’s elapsed-seconds axis.
    /// Only samples inside `[sessionStart, sessionEnd]` are kept.
    static func mapToSessionElapsed(
        samples: [HeartRateSamplePoint],
        sessionStart: Date,
        sessionEnd: Date
    ) -> [(elapsed: TimeInterval, value: Double)] {
        guard sessionEnd >= sessionStart else { return [] }
        return samples.compactMap { sample in
            guard sample.date >= sessionStart, sample.date <= sessionEnd,
                  sample.bpm > 0, sample.bpm.isFinite
            else { return nil }
            let elapsed = sample.date.timeIntervalSince(sessionStart)
            return (elapsed, sample.bpm)
        }
    }

    /// Build a snapshot from raw points (used by the HealthKit reader and tests).
    static func makeSnapshot(
        samples: [HeartRateSamplePoint],
        windowHours: Int,
        queriedAt: Date,
        windowStart: Date,
        windowEnd: Date,
        bucketSeconds: TimeInterval = defaultBucketSeconds,
        calendar: Calendar = .current
    ) -> HeartRateHistorySnapshot {
        let sorted = samples
            .filter { $0.bpm > 0 && $0.bpm.isFinite && $0.date >= windowStart && $0.date <= windowEnd }
            .sorted { $0.date < $1.date }
        return HeartRateHistorySnapshot(
            windowHours: windowHours,
            queriedAt: queriedAt,
            windowStart: windowStart,
            windowEnd: windowEnd,
            samples: sorted,
            buckets: bucket(
                samples: sorted,
                bucketSeconds: bucketSeconds,
                from: windowStart,
                to: windowEnd
            ),
            latest: sorted.last,
            overnightMinBpm: overnightMinimum(samples: sorted, calendar: calendar)
        )
    }
}
