import Foundation

/// How strongly the user wants to be nudged.
public enum ReminderMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case light     // at most 1/day
    case standard  // sedentary + daily
    case strict    // sedentary + daily + weekly

    public var id: String { rawValue }
}

/// Value-type snapshot of the user's goals + reminder prefs. Decoupled from
/// SwiftData so the engine and stats stay pure-Swift testable.
///
/// Strength & recovery have BOTH a daily and a weekly target (daily drives the
/// recommendation engine + today's badge; weekly drives the summary rollup).
/// Run only has a weekly target.
public struct UserGoalValues: Equatable, Sendable {
    public var dailyStrengthTarget: Int
    public var weeklyStrengthTarget: Int
    public var dailyRecoveryTarget: Int
    public var weeklyRecoveryTarget: Int
    public var weeklyRunTarget: Int
    public var sedentaryReminderMinutes: Int
    /// 两次久坐提醒之间至少间隔多少分钟(旧版是硬编码 45)。
    public var sedentaryCooldownMinutes: Int
    public var enableFlexibleReminder: Bool
    public var reminderMode: ReminderMode
    public var workStartMinutes: Int
    public var workEndMinutes: Int
    public var workWeekdays: [Int]

    public init(
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
        self.dailyStrengthTarget = dailyStrengthTarget
        self.weeklyStrengthTarget = weeklyStrengthTarget
        self.dailyRecoveryTarget = dailyRecoveryTarget
        self.weeklyRecoveryTarget = weeklyRecoveryTarget
        self.weeklyRunTarget = weeklyRunTarget
        self.sedentaryReminderMinutes = sedentaryReminderMinutes
        self.sedentaryCooldownMinutes = sedentaryCooldownMinutes
        self.enableFlexibleReminder = enableFlexibleReminder
        self.reminderMode = reminderMode
        self.workStartMinutes = workStartMinutes
        self.workEndMinutes = workEndMinutes
        self.workWeekdays = workWeekdays
    }

    public static let `default` = UserGoalValues()
}
