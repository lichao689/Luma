import Foundation
import SwiftData
import OfficeWorkoutLogic

/// A singleton row holding the user's goals and reminder preferences.
///
/// Strength & recovery have BOTH daily and weekly targets; run is weekly only.
/// Always read the first row; the app seeds one on first launch. Bridges into
/// `UserGoalValues` (logic layer) for computation.
@Model
final class UserGoal {
    @Attribute(.unique) var id: UUID

    var dailyStrengthTarget: Int
    var weeklyStrengthTarget: Int
    var dailyRecoveryTarget: Int
    var weeklyRecoveryTarget: Int
    var weeklyRunTarget: Int
    var sedentaryReminderMinutes: Int
    /// 带默认值,老数据迁移时能自动补上。
    var sedentaryCooldownMinutes: Int = 45
    var enableFlexibleReminder: Bool
    var reminderModeRaw: String
    var workStartMinutes: Int
    var workEndMinutes: Int
    var workWeekdays: [Int]

    init(
        id: UUID = UUID(),
        dailyStrengthTarget: Int = 1,
        weeklyStrengthTarget: Int = 7,
        dailyRecoveryTarget: Int = 2,
        weeklyRecoveryTarget: Int = 14,
        weeklyRunTarget: Int = 2,
        sedentaryReminderMinutes: Int = 60,
        sedentaryCooldownMinutes: Int = 45,
        enableFlexibleReminder: Bool = true,
        reminderMode: ReminderMode = .standard,
        workStartMinutes: Int = 570,
        workEndMinutes: Int = 1110,
        workWeekdays: [Int] = [2, 3, 4, 5, 6]
    ) {
        self.id = id
        self.dailyStrengthTarget = dailyStrengthTarget
        self.weeklyStrengthTarget = weeklyStrengthTarget
        self.dailyRecoveryTarget = dailyRecoveryTarget
        self.weeklyRecoveryTarget = weeklyRecoveryTarget
        self.weeklyRunTarget = weeklyRunTarget
        self.sedentaryReminderMinutes = sedentaryReminderMinutes
        self.sedentaryCooldownMinutes = sedentaryCooldownMinutes
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
            dailyStrengthTarget: goal.dailyStrengthTarget,
            weeklyStrengthTarget: goal.weeklyStrengthTarget,
            dailyRecoveryTarget: goal.dailyRecoveryTarget,
            weeklyRecoveryTarget: goal.weeklyRecoveryTarget,
            weeklyRunTarget: goal.weeklyRunTarget,
            sedentaryReminderMinutes: goal.sedentaryReminderMinutes,
            sedentaryCooldownMinutes: goal.sedentaryCooldownMinutes,
            enableFlexibleReminder: goal.enableFlexibleReminder,
            reminderMode: goal.reminderMode,
            workStartMinutes: goal.workStartMinutes,
            workEndMinutes: goal.workEndMinutes,
            workWeekdays: goal.workWeekdays
        )
    }
}
