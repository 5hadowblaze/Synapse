import HealthKit
import XCTest
@testable import Synapse

final class HealthTrendsBucketerTests: XCTestCase {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func day(_ dayOffset: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 25 + dayOffset
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps)!
    }

    func testDayStartsOldestToNewestInclusive() {
        let end = day(0, hour: 15)
        let days = HealthTrendsBucketer.dayStarts(endingOn: end, count: 3, calendar: calendar)
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days[0], calendar.startOfDay(for: day(-2)))
        XCTAssertEqual(days[2], calendar.startOfDay(for: day(0)))
    }

    func testDailyAveragesMeansPerDay() {
        let end = day(0, hour: 20)
        let samples = [
            TrendSamplePoint(date: day(-1, hour: 8), value: 50),
            TrendSamplePoint(date: day(-1, hour: 18), value: 60),
            TrendSamplePoint(date: day(0, hour: 9), value: 55),
            TrendSamplePoint(date: day(-5, hour: 9), value: 40) // outside 3-day window
        ]
        let trend = HealthTrendsBucketer.dailyAverages(
            samples: samples,
            dayCount: 3,
            endingOn: end,
            calendar: calendar
        )
        XCTAssertEqual(trend.daily.count, 2)
        XCTAssertEqual(trend.daily[0].value, 55, accuracy: 0.01) // (50+60)/2
        XCTAssertEqual(trend.daily[1].value, 55, accuracy: 0.01)
        XCTAssertEqual(trend.latest!.value, 55, accuracy: 0.01)
        XCTAssertFalse(trend.isSparse)
    }

    func testDailySumsAndSparseFlag() {
        let end = day(0)
        let samples = [
            TrendSamplePoint(date: day(0, hour: 10), value: 1000),
            TrendSamplePoint(date: day(0, hour: 14), value: 500)
        ]
        let trend = HealthTrendsBucketer.dailySums(
            samples: samples,
            dayCount: 7,
            endingOn: end,
            calendar: calendar,
            sparseThreshold: 2
        )
        XCTAssertEqual(trend.daily.count, 1)
        XCTAssertEqual(trend.latest!.value, 1500, accuracy: 0.01)
        XCTAssertTrue(trend.isSparse)
    }

    func testWakeDayAttributionAcrossEveningBoundary() {
        // 22:00 on day -1 → attributed to wake day 0
        let evening = day(-1, hour: 22)
        XCTAssertEqual(
            HealthTrendsBucketer.wakeDayStart(for: evening, calendar: calendar),
            calendar.startOfDay(for: day(0))
        )
        // 07:00 on day 0 → wake day 0
        let morning = day(0, hour: 7)
        XCTAssertEqual(
            HealthTrendsBucketer.wakeDayStart(for: morning, calendar: calendar),
            calendar.startOfDay(for: day(0))
        )
    }

    func testSleepNightsSumAsleepIntervals() {
        let end = day(0, hour: 12)
        let intervals = [
            SleepIntervalPoint(start: day(-1, hour: 23), end: day(0, hour: 2), stage: .unspecified),
            SleepIntervalPoint(start: day(0, hour: 2, minute: 30), end: day(0, hour: 6), stage: .unspecified),
            SleepIntervalPoint(start: day(-2, hour: 23), end: day(-1, hour: 5), stage: .unspecified)
        ]
        let sleep = HealthTrendsBucketer.sleepNights(
            intervals: intervals,
            nightCount: 3,
            endingOn: end,
            calendar: calendar
        )
        XCTAssertEqual(sleep.nights.count, 2)
        XCTAssertNotNil(sleep.lastNight)
        // Last night (wake day 0): 3h + 3.5h = 6.5h
        XCTAssertEqual(sleep.lastNight!.asleepHours, 6.5, accuracy: 0.01)
        XCTAssertFalse(sleep.isSparse)
        XCTAssertGreaterThan(sleep.lastNight!.score.value, 0)
        XCTAssertFalse(sleep.lastNight!.pacingHint.title.isEmpty)
    }

    func testSleepStagesProduceBreakdownAndScore() throws {
        let end = day(0, hour: 12)
        let intervals = [
            SleepIntervalPoint(start: day(-1, hour: 22), end: day(0, hour: 6), stage: .inBed, fromWatch: true),
            SleepIntervalPoint(start: day(-1, hour: 23), end: day(0, hour: 1), stage: .core, fromWatch: true),
            SleepIntervalPoint(start: day(0, hour: 1), end: day(0, hour: 2), stage: .deep, fromWatch: true),
            SleepIntervalPoint(start: day(0, hour: 2), end: day(0, hour: 3), stage: .rem, fromWatch: true),
            SleepIntervalPoint(start: day(0, hour: 3), end: day(0, hour: 5), stage: .core, fromWatch: true),
            SleepIntervalPoint(start: day(0, hour: 5), end: day(0, hour: 5, minute: 20), stage: .awake, fromWatch: true),
            SleepIntervalPoint(start: day(0, hour: 5, minute: 20), end: day(0, hour: 6), stage: .rem, fromWatch: true)
        ]
        let sleep = HealthTrendsBucketer.sleepNights(
            intervals: intervals,
            nightCount: 2,
            endingOn: end,
            calendar: calendar
        )
        let night = try XCTUnwrap(sleep.lastNight)
        XCTAssertTrue(night.hasStageBreakdown)
        XCTAssertGreaterThan(night.deepSeconds, 0)
        XCTAssertGreaterThan(night.remSeconds, 0)
        XCTAssertTrue(night.score.usedStages)
        XCTAssertGreaterThanOrEqual(night.score.value, 40)
    }

    func testPreferWatchSourcesFiltersPhoneDuplicates() {
        let watch = SleepIntervalPoint(
            start: day(-1, hour: 23),
            end: day(0, hour: 6),
            stage: .core,
            fromWatch: true
        )
        let phone = SleepIntervalPoint(
            start: day(-1, hour: 23),
            end: day(0, hour: 6),
            stage: .unspecified,
            fromWatch: false
        )
        let preferred = SleepRecoveryAnalytics.preferWatchSources([watch, phone])
        XCTAssertEqual(preferred.count, 1)
        XCTAssertTrue(preferred[0].fromWatch)
    }

    func testSleepScoreIdealNightIsStrong() {
        // 8h asleep, high efficiency, good deep/REM mix
        let score = SleepRecoveryAnalytics.score(
            asleepSeconds: 8 * 3600,
            inBedSeconds: 8.5 * 3600,
            deepSeconds: 1.4 * 3600,
            remSeconds: 1.8 * 3600,
            hasStages: true
        )
        XCTAssertGreaterThanOrEqual(score.value, 80)
        XCTAssertEqual(score.band, "Strong")
    }

    func testPacingHintsAvoidBannedFatigueCopy() {
        // MASTER §13 — never claim fatigue detection / diagnosis. “Not a diagnosis” disclaimer is fine.
        let banned = [
            "fatigue", "tired", "cognitive load", "clinical-grade",
            "clinically validated", "productivity", "burnout", "diagnoses"
        ]
        for value in [90, 70, 55, 30] {
            let hint = SleepRecoveryAnalytics.pacingHint(
                for: SleepScore(value: value, band: "Test", usedStages: true)
            )
            let blob = (hint.title + " " + hint.detail).lowercased()
            for phrase in banned {
                XCTAssertFalse(
                    blob.contains(phrase),
                    "Pacing hint for score \(value) contains banned '\(phrase)': \(blob)"
                )
            }
            XCTAssertTrue(
                blob.contains("capacity") || blob.contains("envelope") || blob.contains("gentle") || blob.contains("pacing"),
                "Expected capacity/pacing framing for score \(value)"
            )
        }
    }

    func testMakeSnapshotWiresAllSeries() {
        let end = day(0, hour: 18)
        let snapshot = HealthTrendsBucketer.makeSnapshot(
            queriedAt: end,
            dayCount: 7,
            restingHR: [TrendSamplePoint(date: day(0, hour: 8), value: 52)],
            hrvSDNN: [],
            sleepIntervals: [
                SleepIntervalPoint(start: day(-1, hour: 23), end: day(0, hour: 6), stage: .unspecified)
            ],
            activeEnergyKcal: [TrendSamplePoint(date: day(0, hour: 12), value: 320)],
            standHours: [
                TrendSamplePoint(date: day(0, hour: 9), value: 1),
                TrendSamplePoint(date: day(0, hour: 11), value: 1)
            ],
            steps: [TrendSamplePoint(date: day(0, hour: 15), value: 4200)],
            calendar: calendar
        )
        XCTAssertTrue(snapshot.hasAnyData)
        XCTAssertEqual(snapshot.restingHeartRate.latest!.value, 52, accuracy: 0.01)
        XCTAssertTrue(snapshot.hrvSDNN.isEmpty)
        XCTAssertEqual(snapshot.sleep.lastNight!.asleepHours, 7, accuracy: 0.01)
        XCTAssertEqual(snapshot.activeEnergyKcal.latest!.value, 320, accuracy: 0.01)
        XCTAssertEqual(snapshot.standHours.latest!.value, 2, accuracy: 0.01)
        XCTAssertEqual(snapshot.steps.latest!.value, 4200, accuracy: 0.01)
    }

    func testIsAsleepValueRecognisesStages() {
        XCTAssertTrue(HealthKitReadAccess.isAsleepSleepAnalysisValue(HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue))
        XCTAssertTrue(HealthKitReadAccess.isAsleepSleepAnalysisValue(HKCategoryValueSleepAnalysis.asleepCore.rawValue))
        XCTAssertTrue(HealthKitReadAccess.isAsleepSleepAnalysisValue(HKCategoryValueSleepAnalysis.asleepDeep.rawValue))
        XCTAssertTrue(HealthKitReadAccess.isAsleepSleepAnalysisValue(HKCategoryValueSleepAnalysis.asleepREM.rawValue))
        XCTAssertFalse(HealthKitReadAccess.isAsleepSleepAnalysisValue(HKCategoryValueSleepAnalysis.inBed.rawValue))
        XCTAssertFalse(HealthKitReadAccess.isAsleepSleepAnalysisValue(HKCategoryValueSleepAnalysis.awake.rawValue))
    }
}
