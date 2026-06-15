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
public struct UserGoalValues: Equatable, Sendable {
    public var weeklyStrengthTarget: Int
    public var weeklyRunTarget: Int
    public var weeklyRecoveryTarget: Int
    public var sedentaryReminderMinutes: Int
    public var enableFlexibleReminder: Bool
    public var reminderMode: ReminderMode
    public var workStartMinutes: Int
    public var workEndMinutes: Int
    public var workWeekdays: [Int]

    public init(
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
        self.weeklyStrengthTarget = weeklyStrengthTarget
        self.weeklyRunTarget = weeklyRunTarget
        self.weeklyRecoveryTarget = weeklyRecoveryTarget
        self.sedentaryReminderMinutes = sedentaryReminderMinutes
        self.enableFlexibleReminder = enableFlexibleReminder
        self.reminderMode = reminderMode
        self.workStartMinutes = workStartMinutes
        self.workEndMinutes = workEndMinutes
        self.workWeekdays = workWeekdays
    }

    public static let `default` = UserGoalValues()
}
