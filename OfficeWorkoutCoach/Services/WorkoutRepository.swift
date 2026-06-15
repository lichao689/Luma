import Foundation
import SwiftData
import SwiftUI
import OfficeWorkoutLogic

/// The single SwiftData container owner, created once at app launch and
/// injected into the environment via `.environmentObject`.
@MainActor
final class WorkoutStore: ObservableObject {
    let container: ModelContainer

    /// Bumped on every mutation (log/delete/goal edit) so SwiftUI views that
    /// derive display data from the store — like the menu-bar badge — refresh
    /// automatically. Without this, the badge wouldn't update after a log.
    @Published private(set) var changeToken: Int = 0

    init() throws {
        let schema = Schema([WorkoutSession.self, UserGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        self.container = try ModelContainer(for: schema, configurations: [config])
        seedDefaultGoalIfNeeded()
    }

    /// Signal that data changed so observing views recompute.
    private func notifyChanged() { changeToken &+= 1 }

    // MARK: - Goal

    private func seedDefaultGoalIfNeeded() {
        let context = container.mainContext
        let descriptor = FetchDescriptor<UserGoal>()
        if let existing = (try? context.fetch(descriptor))?.first {
            _ = existing
            return
        }
        context.insert(UserGoal())
        try? context.save()
    }

    func fetchGoal() -> UserGoal {
        let context = container.mainContext
        let descriptor = FetchDescriptor<UserGoal>()
        if let goal = (try? context.fetch(descriptor))?.first { return goal }
        // Defensive: create one if missing.
        let goal = UserGoal()
        context.insert(goal)
        try? context.save()
        return goal
    }

    func updateGoal(_ values: UserGoalValues) {
        let goal = fetchGoal()
        goal.dailyStrengthTarget = values.dailyStrengthTarget
        goal.weeklyStrengthTarget = values.weeklyStrengthTarget
        goal.dailyRecoveryTarget = values.dailyRecoveryTarget
        goal.weeklyRecoveryTarget = values.weeklyRecoveryTarget
        goal.weeklyRunTarget = values.weeklyRunTarget
        goal.sedentaryReminderMinutes = values.sedentaryReminderMinutes
        goal.enableFlexibleReminder = values.enableFlexibleReminder
        goal.reminderMode = values.reminderMode
        goal.workStartMinutes = values.workStartMinutes
        goal.workEndMinutes = values.workEndMinutes
        goal.workWeekdays = values.workWeekdays
        try? goal.modelContext?.save()
        notifyChanged()
    }

    // MARK: - Sessions

    func fetchAllSessions() -> [WorkoutSession] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Sessions bridged into the logic-layer value type.
    func fetchAllRecords() -> [SessionRecord] {
        fetchAllSessions().map { $0.asRecord }
    }

    func log(
        type: WorkoutType,
        planCode: String? = nil,
        durationMinutes: Int = 0,
        completion: CompletionLevel = .full,
        intensity: Int = 3,
        bodyFeeling: String? = nil,
        notes: String? = nil,
        date: Date = .now
    ) {
        let context = container.mainContext
        let session = WorkoutSession(
            date: date,
            type: type,
            planCode: planCode,
            durationMinutes: durationMinutes,
            completion: completion,
            intensity: intensity,
            bodyFeeling: bodyFeeling,
            notes: notes
        )
        context.insert(session)
        try? context.save()
        notifyChanged()
    }

    func delete(_ session: WorkoutSession) {
        let context = container.mainContext
        context.delete(session)
        try? context.save()
        notifyChanged()
    }

    // MARK: - Stats convenience

    /// Current stats snapshot (uses the logic-layer service).
    func currentStats(now: Date = .now) -> WorkoutStats {
        WorkoutStatsService(now: now).stats(sessions: fetchAllRecords())
    }
}
