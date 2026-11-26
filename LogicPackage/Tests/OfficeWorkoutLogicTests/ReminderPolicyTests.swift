import Foundation
import XCTest
@testable import OfficeWorkoutLogic

final class ReminderPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 23) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    private func allowed(goal: UserGoalValues = .default, at: Date? = nil, workout: Bool = false,
                         meeting: Bool = false, rest: Bool = false, snooze: Date? = nil, idle: Double = 0) -> Bool {
        ReminderPolicy.canEscalate(goal: goal, now: at ?? date(12), calendar: calendar,
            workoutInProgress: workout, meetingInProgress: meeting, restToday: rest,
            snoozeUntil: snooze, idleSeconds: idle)
    }

    func testEscalationRechecksChangedContext() {
        XCTAssertTrue(allowed())
        XCTAssertFalse(allowed(workout: true))
        XCTAssertFalse(allowed(meeting: true))
        XCTAssertFalse(allowed(rest: true))
        XCTAssertFalse(allowed(snooze: date(12, 10)))
        XCTAssertTrue(allowed(snooze: date(12)))
        XCTAssertFalse(allowed(idle: 600))
        XCTAssertFalse(allowed(idle: .infinity))
    }
    func testTrainingNudgesHonorRecoveryAndRestRecommendation() {
        for action in [Recommendation.Action.rest, .recovery, .logRun] {
            XCTAssertFalse(ReminderPolicy.permitsTrainingNudge(Recommendation(action: action, titleKey: "", reasonKey: "")))
        }
        for action in [Recommendation.Action.startStrength(.strengthA), .minimal] {
            XCTAssertTrue(ReminderPolicy.permitsTrainingNudge(Recommendation(action: action, titleKey: "", reasonKey: "")))
        }
    }
    func testDisableAndLightModeCancelEscalation() {
        var goal = UserGoalValues.default
        goal.sedentaryReminderMinutes = 0
        XCTAssertFalse(allowed(goal: goal))
        goal.sedentaryReminderMinutes = 60
        goal.reminderMode = .light
        XCTAssertFalse(allowed(goal: goal))
    }
    func testWorkWindowBoundariesAndWeekend() {
        XCTAssertFalse(allowed(at: date(9, 29)))
        XCTAssertTrue(allowed(at: date(9, 30)))
        XCTAssertFalse(allowed(at: date(18, 30)))
        XCTAssertFalse(allowed(at: date(12, day: 28)))
    }
    func testOvernightWindowBelongsToStartingWeekday() {
        var goal = UserGoalValues.default
        goal.workStartMinutes = 22 * 60
        goal.workEndMinutes = 6 * 60
        goal.workWeekdays = [6]
        XCTAssertTrue(allowed(goal: goal, at: date(23, day: 27)))
        XCTAssertTrue(allowed(goal: goal, at: date(2, day: 28)))
        XCTAssertFalse(allowed(goal: goal, at: date(6, day: 28)))
        XCTAssertFalse(allowed(goal: goal, at: date(23, day: 28)))
    }
}
