import XCTest
@testable import Synapse

final class HeartRateSeriesBucketerTests: XCTestCase {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func date(_ hour: Int, minute: Int = 0, dayOffset: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 25 + dayOffset
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps)!
    }

    func testBucketAveragesWithinBins() {
        let from = date(10)
        let to = from.addingTimeInterval(20 * 60)
        let samples = [
            HeartRateSamplePoint(date: from.addingTimeInterval(30), bpm: 60),
            HeartRateSamplePoint(date: from.addingTimeInterval(90), bpm: 80),
            HeartRateSamplePoint(date: from.addingTimeInterval(6 * 60), bpm: 100)
        ]

        let buckets = HeartRateSeriesBucketer.bucket(
            samples: samples,
            bucketSeconds: 5 * 60,
            from: from,
            to: to
        )

        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].bpm, 70, accuracy: 0.01)
        XCTAssertEqual(buckets[0].sampleCount, 2)
        XCTAssertEqual(buckets[1].bpm, 100, accuracy: 0.01)
        XCTAssertEqual(buckets[1].sampleCount, 1)
    }

    func testBucketSkipsInvalidAndOutOfWindow() {
        let from = date(12)
        let to = from.addingTimeInterval(10 * 60)
        let samples = [
            HeartRateSamplePoint(date: from.addingTimeInterval(-60), bpm: 55),
            HeartRateSamplePoint(date: from.addingTimeInterval(60), bpm: .nan),
            HeartRateSamplePoint(date: from.addingTimeInterval(120), bpm: 0),
            HeartRateSamplePoint(date: from.addingTimeInterval(180), bpm: 72),
            HeartRateSamplePoint(date: to.addingTimeInterval(1), bpm: 90)
        ]

        let buckets = HeartRateSeriesBucketer.bucket(
            samples: samples,
            bucketSeconds: 5 * 60,
            from: from,
            to: to
        )
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].bpm, 72, accuracy: 0.01)
    }

    func testOvernightMinimumUsesLocalHourWindow() {
        let samples = [
            HeartRateSamplePoint(date: date(23, minute: 30, dayOffset: -1), bpm: 58),
            HeartRateSamplePoint(date: date(2), bpm: 52),
            HeartRateSamplePoint(date: date(5, minute: 45), bpm: 49),
            HeartRateSamplePoint(date: date(6), bpm: 40), // hour 6 excluded
            HeartRateSamplePoint(date: date(14), bpm: 70)
        ]
        let min = HeartRateSeriesBucketer.overnightMinimum(samples: samples, calendar: calendar)
        XCTAssertEqual(min!, 49, accuracy: 0.01)
    }

    func testOvernightMinimumNilWhenNoOvernightSamples() {
        let samples = [
            HeartRateSamplePoint(date: date(9), bpm: 65),
            HeartRateSamplePoint(date: date(18), bpm: 72)
        ]
        XCTAssertNil(HeartRateSeriesBucketer.overnightMinimum(samples: samples, calendar: calendar))
    }

    func testMapToSessionElapsedKeepsInWindowOnly() {
        let start = date(15)
        let end = start.addingTimeInterval(600)
        let samples = [
            HeartRateSamplePoint(date: start.addingTimeInterval(-30), bpm: 60),
            HeartRateSamplePoint(date: start.addingTimeInterval(120), bpm: 68),
            HeartRateSamplePoint(date: start.addingTimeInterval(300), bpm: 70),
            HeartRateSamplePoint(date: end.addingTimeInterval(1), bpm: 80)
        ]
        let series = HeartRateSeriesBucketer.mapToSessionElapsed(
            samples: samples,
            sessionStart: start,
            sessionEnd: end
        )
        XCTAssertEqual(series.map(\.elapsed), [120, 300])
        XCTAssertEqual(series.map(\.value), [68, 70])
    }

    func testMakeSnapshotSortsAndSummarises() {
        let end = date(18)
        let start = end.addingTimeInterval(-24 * 3600)
        let samples = [
            HeartRateSamplePoint(date: date(14), bpm: 75),
            HeartRateSamplePoint(date: date(3), bpm: 51),
            HeartRateSamplePoint(date: date(16), bpm: 78)
        ]
        let snapshot = HeartRateSeriesBucketer.makeSnapshot(
            samples: samples,
            windowHours: 24,
            queriedAt: end,
            windowStart: start,
            windowEnd: end,
            calendar: calendar
        )
        XCTAssertEqual(snapshot.samples.map(\.bpm), [51, 75, 78])
        XCTAssertEqual(snapshot.latest?.bpm, 78)
        XCTAssertEqual(snapshot.overnightMinBpm!, 51, accuracy: 0.01)
        XCTAssertFalse(snapshot.buckets.isEmpty)
    }
}
