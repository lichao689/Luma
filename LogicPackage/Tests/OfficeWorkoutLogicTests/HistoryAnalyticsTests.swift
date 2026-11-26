import XCTest
@testable import OfficeWorkoutLogic

final class HistoryAnalyticsTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testLocalMidnightAndDaylightSavingUseCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = date("2026-03-09T12:00:00Z")
        let sessions = [
            SessionRecord(date: date("2026-03-08T07:59:00Z"), type: .run, durationMinutes: 10), // March 7
            SessionRecord(date: date("2026-03-08T08:01:00Z"), type: .recovery, durationMinutes: 5), // March 8
            SessionRecord(date: date("2026-03-09T06:59:00Z"), type: .strengthA, durationMinutes: 20), // March 8 after DST
            SessionRecord(date: date("2026-03-09T07:01:00Z"), type: .minimal, durationMinutes: 8) // March 9
        ]
        let days = HistoryAnalytics.daily(sessions: sessions, days: 3, now: now, calendar: calendar)
        XCTAssertEqual(days.map(\.sessions), [1, 2, 1])
        XCTAssertEqual(days.map(\.minutes), [10, 25, 8])
        XCTAssertEqual(days[2].date.timeIntervalSince(days[1].date), 23 * 3600)
    }

    func testChangingTimeZoneRegroupsSameInstantAndKeepsTotals() {
        let instant = date("2026-11-25T17:00:00Z"), now = date("2026-11-26T04:00:00Z")
        let row = SessionRecord(date: instant, type: .run, durationMinutes: 20)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var shanghai = utc; shanghai.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let a = HistoryAnalytics.daily(sessions: [row], days: 2, now: now, calendar: utc)
        let b = HistoryAnalytics.daily(sessions: [row], days: 2, now: now, calendar: shanghai)
        XCTAssertEqual(a.map(\.sessions), [1, 0])
        XCTAssertEqual(b.map(\.sessions), [0, 1])
        XCTAssertEqual(a.reduce(0) { $0 + $1.minutes }, b.reduce(0) { $0 + $1.minutes })
    }

    func testEmptyDaysArePresentAndRestFutureAndDuplicateRecordsAreExcluded() {
        let now = date("2026-11-26T12:00:00Z")
        let row = SessionRecord(date: now, type: .strengthA, durationMinutes: 15)
        let items = [row, row, SessionRecord(date: now, type: .rest, durationMinutes: 99),
                     SessionRecord(date: now.addingTimeInterval(1), type: .run, durationMinutes: 20)]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let days = HistoryAnalytics.daily(sessions: items, days: 7, now: now, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.map(\.sessions), [0, 0, 0, 0, 0, 0, 1])
        XCTAssertEqual(days.last?.minutes, 15)
        XCTAssertEqual(HistoryAnalytics.daily(sessions: [], days: 90, now: now).count, 90)
    }

    func testExerciseHistorySeparatesHoldsRepsMissingWeightsAndOtherExercises() {
        let now = date("2026-11-26T12:00:00Z")
        let first = BackupSession(date: now.addingTimeInterval(-3600), type: .strengthA)
        let second = BackupSession(date: now, type: .strengthB)
        let a = BackupSet(sessionID: first.id, exerciseID: "gobletSquat", setIndex: 1, reps: 10,
                          weightKg: 12, recordedAt: now)
        let b = BackupSet(sessionID: first.id, exerciseID: "gobletSquat", setIndex: 2, reps: 8,
                          weightKg: 14, recordedAt: now)
        let c = BackupSet(sessionID: second.id, exerciseID: "gobletSquat", setIndex: 1, reps: 12,
                          recordedAt: now)
        let hold = BackupSet(sessionID: second.id, exerciseID: "plank", setIndex: 1, reps: 30,
                             isHold: true, recordedAt: now)
        let sets = [a, a, b, c, hold]
        let points = HistoryAnalytics.exerciseTrend(exerciseID: "gobletSquat", sessions: [first, second],
                                                    sets: sets, since: now.addingTimeInterval(-7200), now: now)
        XCTAssertEqual(points.map(\.setCount), [2, 1])
        XCTAssertEqual(points.map(\.repetitions), [18, 12])
        XCTAssertEqual(points.map(\.holdSeconds), [0, 0])
        XCTAssertEqual(points[0].maximumWeightKg, 14)
        XCTAssertNil(points[1].maximumWeightKg)
        let holds = HistoryAnalytics.exerciseTrend(exerciseID: "plank", sessions: [first, second],
                                                   sets: sets, since: now.addingTimeInterval(-7200), now: now)
        XCTAssertEqual(holds.first?.holdSeconds, 30)
        XCTAssertEqual(holds.first?.repetitions, 0)
    }
}
