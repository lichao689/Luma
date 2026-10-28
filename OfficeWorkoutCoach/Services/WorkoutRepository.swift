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
        let schema = Schema([WorkoutSession.self, UserGoal.self, SetRecord.self])
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
        goal.sedentaryCooldownMinutes = values.sedentaryCooldownMinutes
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

    /// 记一次训练。返回 session id,便于把各组明细挂上去。
    @discardableResult
    func log(
        type: WorkoutType,
        planCode: String? = nil,
        durationMinutes: Int = 0,
        completion: CompletionLevel = .full,
        intensity: Int = 3,
        bodyFeeling: String? = nil,
        notes: String? = nil,
        date: Date = .now
    ) -> UUID {
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
        return session.id
    }

    func delete(_ session: WorkoutSession) {
        let context = container.mainContext
        let id = session.id
        // 明细跟着一起删,避免孤儿记录。
        for set in sets(forSession: id) { context.delete(set) }
        context.delete(session)
        try? context.save()
        notifyChanged()
    }

    // MARK: - Set records

    /// 追加一组明细。
    func recordSet(
        sessionID: UUID,
        exerciseID: String,
        setIndex: Int,
        reps: Int,
        weightKg: Double? = nil,
        recordedAt: Date = .now
    ) {
        let context = container.mainContext
        let record = SetRecord(
            sessionID: sessionID,
            exerciseID: exerciseID,
            setIndex: setIndex,
            reps: reps,
            weightKg: weightKg,
            recordedAt: recordedAt
        )
        context.insert(record)
        try? context.save()
    }

    func sets(forSession id: UUID) -> [SetRecord] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<SetRecord>(
            predicate: #Predicate { $0.sessionID == id },
            sortBy: [SortDescriptor(\.setIndex)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 某个动作最近一次的表现(次数 + 重量),用于跟练时给个参照目标。
    func lastPerformance(exerciseID: String) -> LastPerformance? {
        let context = container.mainContext
        let descriptor = FetchDescriptor<SetRecord>(
            predicate: #Predicate { $0.exerciseID == exerciseID },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        guard let recent = (try? context.fetch(descriptor))?.first else { return nil }
        return LastPerformance(reps: recent.reps, weightKg: recent.weightKg, date: recent.recordedAt)
    }

    // MARK: - Stats convenience

    /// Current stats snapshot (uses the logic-layer service).
    func currentStats(now: Date = .now) -> WorkoutStats {
        WorkoutStatsService(now: now).stats(sessions: fetchAllRecords())
    }

    // MARK: - Export

    /// 导出为 CSV。有组次明细的按组展开,没有的每条训练一行。
    func exportCSV() -> String {
        let sessions = fetchAllSessions()
        var lines: [String] = [
            "date,time,type,plan,duration_min,completion,intensity,feeling,notes,exercise,set,reps,weight_kg"
        ]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"

        for session in sessions {
            let base = [
                df.string(from: session.date),
                tf.string(from: session.date),
                session.type.rawValue,
                session.planCode ?? "",
                "\(session.durationMinutes)",
                session.completion.rawValue,
                "\(session.intensity)",
                session.bodyFeeling ?? "",
                session.notes ?? ""
            ].map(csvEscape)

            let sets = sets(forSession: session.id)
            if sets.isEmpty {
                lines.append((base + ["", "", "", ""]).joined(separator: ","))
            } else {
                for set in sets {
                    let weight = set.weightKg.map { String(format: "%.1f", $0) } ?? ""
                    let row = base + [
                        set.exerciseID, "\(set.setIndex)", "\(set.reps)", weight
                    ].map(csvEscape)
                    lines.append(row.joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
