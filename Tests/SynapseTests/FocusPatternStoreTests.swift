import XCTest
@testable import Synapse

final class FocusPatternStoreTests: XCTestCase {
    func testEmptySessionsEncourageLogging() {
        let tips = FocusPatternStore.heuristicTips(from: [])
        XCTAssertEqual(tips.count, 1)
        XCTAssertTrue(tips[0].localizedCaseInsensitiveContains("focus"))
    }

    func testAfternoonFadeTip() {
        var sessions: [FocusSessionStat] = []
        // Morning: low fades
        for day in 0..<3 {
            sessions.append(
                FocusSessionStat(
                    startedAt: date(dayOffset: day, hour: 9),
                    focusedMinutes: 25,
                    fadeCount: 0,
                    meanHrBpm: 68
                )
            )
        }
        // Afternoon: higher fades
        for day in 0..<3 {
            sessions.append(
                FocusSessionStat(
                    startedAt: date(dayOffset: day, hour: 15),
                    focusedMinutes: 20,
                    fadeCount: 2,
                    meanHrBpm: 78
                )
            )
        }
        let tips = FocusPatternStore.heuristicTips(from: sessions)
        XCTAssertFalse(tips.isEmpty)
        XCTAssertTrue(
            tips.contains { $0.localizedCaseInsensitiveContains("14:00") || $0.localizedCaseInsensitiveContains("afternoon") }
        )
    }

    func testCapsAtThreeTips() {
        var sessions: [FocusSessionStat] = []
        for day in 0..<5 {
            sessions.append(
                FocusSessionStat(
                    startedAt: date(dayOffset: day, hour: 9),
                    focusedMinutes: 12,
                    fadeCount: 3,
                    meanHrBpm: 85
                )
            )
            sessions.append(
                FocusSessionStat(
                    startedAt: date(dayOffset: day, hour: 15),
                    focusedMinutes: 12,
                    fadeCount: 3,
                    meanHrBpm: 90
                )
            )
            sessions.append(
                FocusSessionStat(
                    startedAt: date(dayOffset: day, hour: 10),
                    focusedMinutes: 25,
                    fadeCount: 0,
                    meanHrBpm: 70
                )
            )
        }
        let tips = FocusPatternStore.heuristicTips(from: sessions)
        XCTAssertLessThanOrEqual(tips.count, 3)
        XCTAssertFalse(tips.isEmpty)
    }

    private func date(dayOffset: Int, hour: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 10 + dayOffset
        comps.hour = hour
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
}
