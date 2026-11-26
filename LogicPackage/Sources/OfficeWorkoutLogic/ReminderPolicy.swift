import Foundation

/// Pure eligibility checks shared by initial notifications and every delayed
/// escalation. A captured decision must never outlive changed user context.
public enum ReminderPolicy {
    public static func permitsTrainingNudge(_ recommendation: Recommendation) -> Bool {
        switch recommendation.action {
        case .startStrength, .minimal: return true
        case .rest, .recovery, .logRun: return false
        }
    }

    public static func isWithinWorkWindow(goal: UserGoalValues, now: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: now)
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard goal.workStartMinutes != goal.workEndMinutes else { return false }
        if goal.workStartMinutes < goal.workEndMinutes {
            return goal.workWeekdays.contains(weekday) && minute >= goal.workStartMinutes && minute < goal.workEndMinutes
        }
        if minute >= goal.workStartMinutes { return goal.workWeekdays.contains(weekday) }
        let previous = weekday == 1 ? 7 : weekday - 1
        return minute < goal.workEndMinutes && goal.workWeekdays.contains(previous)
    }

    public static func canNotify(goal: UserGoalValues, now: Date, calendar: Calendar = .current,
                                 workoutInProgress: Bool, meetingInProgress: Bool,
                                 restToday: Bool, snoozeUntil: Date?) -> Bool {
        isWithinWorkWindow(goal: goal, now: now, calendar: calendar)
            && !workoutInProgress && !meetingInProgress && !restToday
            && (snoozeUntil == nil || now >= snoozeUntil!)
    }

    public static func canEscalate(goal: UserGoalValues, now: Date, calendar: Calendar = .current,
                                  workoutInProgress: Bool, meetingInProgress: Bool,
                                  restToday: Bool, snoozeUntil: Date?, idleSeconds: TimeInterval) -> Bool {
        goal.sedentaryReminderMinutes > 0 && goal.reminderMode != .light
            && idleSeconds.isFinite && idleSeconds >= 0 && idleSeconds < 600
            && canNotify(goal: goal, now: now, calendar: calendar, workoutInProgress: workoutInProgress,
                         meetingInProgress: meetingInProgress, restToday: restToday, snoozeUntil: snoozeUntil)
    }
}
