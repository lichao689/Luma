import Foundation
import SwiftData
import OfficeWorkoutLogic

/// A singleton row holding the user's weekly targets and reminder preferences.
///
/// Always read the first row; the app seeds one on first launch. Bridges into
/// `UserGoalValues` (logic layer) for computation.
@Model
final class UserGoal {
    @Attribute(.unique) var id: UUID

    var weeklyStrengthTarget: Int
    var weeklyRunTarget: Int
    var weeklyRecoveryTarget: Int
    var sedentaryReminderMinutes: Int
    var enableFlexibleReminder: Bool
    var reminderModeRaw: String
    var workStartMinutes: Int
    var workEndMinutes: Int
    var workWeekdays: [Int]

    init(
        id: UUID = UUID(),
        weeklyStrengthTarget: Int = 3,
        weeklyRunTarget: Int = 2,
        weeklyRecoveryTarget: Int = 5,
        sedentaryReminderMinutes: Int = 60,
        enableFlexibleReminder: Bool = true,
        reminderMode: ReminderMode = .standard,
        workStartMinutes: Int = 570,
        workEndMinutes: Int = 1110,
        workWeekdays: [Int] = [2, 3, 4, 5, 6]
    ) {
        self.id = id
        self.weeklyStrengthTarget = weeklyStrengthTarget
        self.weeklyRunTarget = weeklyRunTarget
        self.weeklyRecoveryTarget = weeklyRecoveryTarget
        self.sedentaryReminderMinutes = sedentaryReminderMinutes
        self.enableFlexibleReminder = enableFlexibleReminder
        self.reminderModeRaw = reminderMode.rawValue
        self.workStartMinutes = workStartMinutes
        self.workEndMinutes = workEndMinutes
        self.workWeekdays = workWeekdays
    }

    var reminderMode: ReminderMode {
        get { ReminderMode(rawValue: reminderModeRaw) ?? .standard }
        set { reminderModeRaw = newValue.rawValue }
    }
}

extension UserGoalValues {
    init(_ goal: UserGoal) {
        self.init(
            weeklyStrengthTarget: goal.weeklyStrengthTarget,
            weeklyRunTarget: goal.weeklyRunTarget,
            weeklyRecoveryTarget: goal.weeklyRecoveryTarget,
            sedentaryReminderMinutes: goal.sedentaryReminderMinutes,
            enableFlexibleReminder: goal.enableFlexibleReminder,
            reminderMode: goal.reminderMode,
            workStartMinutes: goal.workStartMinutes,
            workEndMinutes: goal.workEndMinutes,
            workWeekdays: goal.workWeekdays
        )
    }
}
