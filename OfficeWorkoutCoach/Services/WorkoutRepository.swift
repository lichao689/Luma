import Foundation
import SwiftData
import SwiftUI
import OfficeWorkoutLogic

struct HealthImportPreview {
    let newRuns: Int
    let updatedRuns: Int
    let deletedRuns: Int
    let workoutCount: Int
    let stepDayCount: Int
    let sleepSampleCount: Int
}

/// One container, explicit saves, and one transaction per user action. A failed
/// save is rolled back; a session can never commit ahead of its actual sets.
@MainActor
final class WorkoutStore: ObservableObject {
    let container: ModelContainer
    @Published private(set) var changeToken = 0
    @Published var lastError: String?
    let deviceID: UUID
    private let beforeSave: (() throws -> Void)?

    init(inMemory: Bool = false, beforeSave: (() throws -> Void)? = nil) throws {
        self.beforeSave = beforeSave
        let schema = Schema([WorkoutSession.self, UserGoal.self, SetRecord.self,
                             SavedTrainingPlan.self, DataTombstone.self, HealthImportArchive.self])
        // Folder sync is explicit. Adding an iCloud entitlement must not turn
        // this private store into an implicit CloudKit upload.
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        container.mainContext.autosaveEnabled = false
        let key = "luma.sync.deviceID"
        if !inMemory, let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) {
            deviceID = id
        } else {
            deviceID = UUID()
            if !inMemory { UserDefaults.standard.set(deviceID.uuidString, forKey: key) }
        }
        if try container.mainContext.fetch(FetchDescriptor<UserGoal>()).isEmpty {
            container.mainContext.insert(UserGoal())
            do { try container.mainContext.save() }
            catch { container.mainContext.rollback(); throw error }
        }
    }

    private func transaction(_ change: () throws -> Void) throws {
        do {
            try change()
            try beforeSave?()
            try container.mainContext.save()
            lastError = nil
            changeToken &+= 1
        } catch {
            container.mainContext.rollback()
            lastError = userFacingError(error)
            throw error
        }
    }

    private func read<T>(_ fallback: T, _ operation: () throws -> T) -> T {
        do { return try operation() }
        catch {
            let message = userFacingError(error)
            if lastError != message { lastError = message }
            return fallback
        }
    }

    private func requiredGoal() throws -> UserGoal {
        guard let goal = try container.mainContext.fetch(FetchDescriptor<UserGoal>()).first else {
            throw BackupError.invalid("Missing local goal row")
        }
        return goal
    }

    func fetchGoal() -> UserGoal { read(UserGoal()) { try requiredGoal() } }

    func updateGoal(_ values: UserGoalValues) {
        do { try updateGoalSafely(values) }
        catch { lastError = userFacingError(error) }
    }

    func updateGoalSafely(_ values: UserGoalValues) throws {
        try BackupCodec.validate(BackupSnapshot(deviceID: deviceID, goal: values))
        let goal = try requiredGoal()
        try transaction { applyGoal(values, to: goal) }
    }

    private func applyGoal(_ values: UserGoalValues, to goal: UserGoal) {
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
    }

    // MARK: - Sessions and actual sets

    func fetchAllSessions() -> [WorkoutSession] {
        read([]) { try container.mainContext.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])) }
    }

    func fetchAllRecords() -> [SessionRecord] { fetchAllSessions().map(\.asRecord) }

    @discardableResult
    func saveWorkout(id: UUID = UUID(), type: WorkoutType, planCode: String? = nil,
                     durationMinutes: Int = 0, completion: CompletionLevel = .full, intensity: Int = 3,
                     bodyFeeling: String? = nil, notes: String? = nil, date: Date = .now,
                     plannedExerciseIDs: [String] = [], sets actualSets: [ExecutedSet] = []) throws -> UUID {
        guard Set(actualSets.map(\.id)).count == actualSets.count else {
            throw BackupError.invalid("Duplicate executed set identity")
        }
        let exerciseIDs = Array(Set(plannedExerciseIDs + actualSets.map(\.exerciseID))).sorted()
        let value = BackupSession(id: id, date: date, type: type, planCode: planCode,
            durationMinutes: durationMinutes, completion: completion, intensity: intensity,
            bodyFeeling: bodyFeeling, notes: notes, exerciseIDs: exerciseIDs)
        let rows = actualSets.map { item in
            BackupSet(sessionID: id, exerciseID: item.exerciseID, setIndex: item.setIndex,
                      reps: item.reps, isHold: item.isHold, side: item.side?.rawValue,
                      weightKg: item.weightKg, recordedAt: item.completedAt)
        }
        try BackupCodec.validate(BackupSnapshot(deviceID: deviceID, sessions: [value], sets: rows))
        let current = try snapshot()
        guard !current.tombstones.contains(where: { $0.kind == .session && $0.id == id }) else {
            throw BackupError.conflict("Session was previously deleted")
        }
        if let existing = current.sessions.first(where: { $0.id == id }) {
            // Retrying the same completed action is a no-op, including every set.
            let oldSets = current.sets.filter { $0.sessionID == id }.map(executedSet).sorted { $0.id < $1.id }
            guard existing == value, oldSets == actualSets.sorted(by: { $0.id < $1.id }) else {
                throw BackupError.conflict("session \(id)")
            }
            return id
        }
        try transaction {
            container.mainContext.insert(WorkoutSession(value))
            for row in rows { container.mainContext.insert(SetRecord(row)) }
        }
        return id
    }

    /// Compatibility for older callers; new flows use throwing saveWorkout.
    @discardableResult
    func log(type: WorkoutType, planCode: String? = nil, durationMinutes: Int = 0,
             completion: CompletionLevel = .full, intensity: Int = 3,
             bodyFeeling: String? = nil, notes: String? = nil, date: Date = .now) -> UUID {
        let id = UUID()
        do { try saveWorkout(id: id, type: type, planCode: planCode, durationMinutes: durationMinutes,
                             completion: completion, intensity: intensity, bodyFeeling: bodyFeeling,
                             notes: notes, date: date) }
        catch { lastError = userFacingError(error) }
        return id
    }

    func delete(_ session: WorkoutSession) {
        do { try deleteSession(id: session.id) }
        catch { lastError = userFacingError(error) }
    }

    func deleteSession(id: UUID) throws {
        var value = try snapshot()
        value.sessions.removeAll { $0.id == id }
        value.sets.removeAll { $0.sessionID == id }
        if !value.tombstones.contains(where: { $0.kind == .session && $0.id == id }) {
            value.tombstones.append(BackupTombstone(kind: .session, id: id))
        }
        try persist(value)
    }

    func sets(forSession id: UUID) -> [SetRecord] {
        read([]) {
            try container.mainContext.fetch(FetchDescriptor<SetRecord>(predicate: #Predicate { $0.sessionID == id },
                                                                       sortBy: [SortDescriptor(\.setIndex), SortDescriptor(\.recordedAt)]))
        }
    }

    func lastPerformance(exerciseID: String) -> LastPerformance? {
        read(nil) {
            var descriptor = FetchDescriptor<SetRecord>(predicate: #Predicate { $0.exerciseID == exerciseID },
                                                         sortBy: [SortDescriptor(\.recordedAt, order: .reverse)])
            descriptor.fetchLimit = 1
            guard let row = try container.mainContext.fetch(descriptor).first else { return nil }
            return LastPerformance(reps: row.reps, weightKg: row.weightKg, date: row.recordedAt)
        }
    }

    func exercisePerformances(exerciseID: String) -> [ExercisePerformance] {
        read([]) {
            let value = try snapshot()
            let groups = Dictionary(grouping: value.sets.filter { $0.exerciseID == exerciseID }, by: \.sessionID)
            return value.sessions.compactMap { session in
                guard groups[session.id] != nil || session.exerciseIDs.contains(exerciseID) else { return nil }
                let records = groups[session.id] ?? []
                return ExercisePerformance(sessionID: session.id, date: session.date,
                    completion: session.completion, intensity: session.intensity,
                    hasDiscomfort: BackPainMarkers.indicatesBackPain(feeling: session.bodyFeeling)
                        || BackPainMarkers.indicatesBackPain(note: session.notes)
                        || ["sore", "tight", "pain", "legsore", "fatigue", "discomfort"].contains(session.bodyFeeling?.lowercased() ?? ""),
                    sets: records.map(executedSet))
            }.sorted { $0.date > $1.date }
        }
    }

    private func executedSet(_ row: BackupSet) -> ExecutedSet {
        ExecutedSet(exerciseID: row.exerciseID, setIndex: row.setIndex,
                    side: row.side.flatMap(WorkoutPlanStep.Side.init(rawValue:)), reps: row.reps,
                    isHold: row.isHold, weightKg: row.weightKg, completedAt: row.recordedAt)
    }

    func currentStats(now: Date = .now) -> WorkoutStats {
        WorkoutStatsService(now: now).stats(sessions: fetchAllRecords())
    }

    // MARK: - Editable plans

    var customPlans: [TrainingPlan] { read([]) { try snapshot().plans.sorted { $0.updatedAt > $1.updatedAt } } }

    func savePlan(_ plan: TrainingPlan) throws {
        try plan.validate()
        var value = try snapshot()
        guard !value.tombstones.contains(where: { $0.kind == .plan && $0.id == plan.id }) else {
            throw BackupError.conflict("Plan was previously deleted; save a copy with a new ID")
        }
        value.plans.removeAll { $0.id == plan.id }
        value.plans.append(plan)
        try persist(value)
    }

    func deletePlan(id: UUID) throws {
        var value = try snapshot()
        value.plans.removeAll { $0.id == id }
        if !value.tombstones.contains(where: { $0.kind == .plan && $0.id == id }) {
            value.tombstones.append(BackupTombstone(kind: .plan, id: id))
        }
        try persist(value)
    }

    // MARK: - Portable backup / merge

    func snapshot(now: Date = .now) throws -> BackupSnapshot {
        let context = container.mainContext
        let plans = try context.fetch(FetchDescriptor<SavedTrainingPlan>()).map { row in
            let plan = try JSONDecoder().decode(TrainingPlan.self, from: row.json)
            guard plan.id == row.id else { throw BackupError.invalid("Saved plan ID mismatch") }
            return plan
        }
        let tombstones = try context.fetch(FetchDescriptor<DataTombstone>()).map { row in
            guard let value = row.value else { throw BackupError.invalid("Invalid local tombstone") }
            return value
        }
        let result = BackupSnapshot(deviceID: deviceID, exportedAt: now, goal: UserGoalValues(try requiredGoal()),
            sessions: try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.backupValue),
            sets: try context.fetch(FetchDescriptor<SetRecord>()).map(\.backupValue), plans: plans,
            healthPackets: try context.fetch(FetchDescriptor<HealthImportArchive>()).map {
                BackupHealthPacket(id: $0.id, importedAt: $0.importedAt, json: $0.json)
            }, tombstones: tombstones)
        try BackupCodec.validate(result)
        return result
    }

    func previewRestore(_ incoming: BackupSnapshot) throws -> BackupMergePreview {
        try BackupMerger.preview(local: snapshot(), incoming: incoming)
    }

    /// Recompute against the latest local state at confirmation, not a stale
    /// preview. New records made while the sheet was open are retained.
    func restore(_ incoming: BackupSnapshot, importGoals: Bool = false) throws {
        let merged = try BackupMerger.merge(local: snapshot(), incoming: incoming, importGoals: importGoals)
        try persist(merged)
    }

    /// The only path that applies a prepared snapshot. No blanket database
    /// deletion: remove just confirmed tombstones, upsert identified rows.
    private func persist(_ value: BackupSnapshot) throws {
        try BackupCodec.validate(value)
        let context = container.mainContext
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let sets = try context.fetch(FetchDescriptor<SetRecord>())
        let plans = try context.fetch(FetchDescriptor<SavedTrainingPlan>())
        let packets = try context.fetch(FetchDescriptor<HealthImportArchive>())
        let tombstones = try context.fetch(FetchDescriptor<DataTombstone>())
        let goal = try requiredGoal()
        let sessionValues = Dictionary(uniqueKeysWithValues: value.sessions.map { ($0.id, $0) })
        let setValues = Dictionary(uniqueKeysWithValues: value.sets.map { ($0.id, $0) })
        let planJSON = try Dictionary(uniqueKeysWithValues: value.plans.map { ($0.id, try JSONEncoder().encode($0)) })
        let sessionIDs = Set(sessions.map(\.id)), setIDs = Set(sets.map(\.id)), planIDs = Set(plans.map(\.id))
        let packetIDs = Set(packets.map(\.id)), tombstoneKeys = Set(tombstones.map(\.key))
        try transaction {
            for row in sessions {
                if let incoming = sessionValues[row.id] { row.apply(incoming) }
                else { context.delete(row) }
            }
            for item in value.sessions where !sessionIDs.contains(item.id) { context.insert(WorkoutSession(item)) }
            for row in sets where setValues[row.id] == nil { context.delete(row) }
            for item in value.sets where !setIDs.contains(item.id) { context.insert(SetRecord(item)) }
            for row in plans {
                if let incoming = value.plans.first(where: { $0.id == row.id }) {
                    row.json = planJSON[incoming.id]!
                    row.updatedAt = incoming.updatedAt
                } else { context.delete(row) }
            }
            for item in value.plans where !planIDs.contains(item.id) {
                context.insert(SavedTrainingPlan(id: item.id, json: planJSON[item.id]!, updatedAt: item.updatedAt))
            }
            for row in packets {
                if let incoming = value.healthPackets.first(where: { $0.id == row.id }) {
                    row.importedAt = incoming.importedAt; row.json = incoming.json
                } else { context.delete(row) }
            }
            for item in value.healthPackets where !packetIDs.contains(item.id) {
                context.insert(HealthImportArchive(id: item.id, importedAt: item.importedAt, json: item.json))
            }
            for row in tombstones {
                if let item = value.tombstones.first(where: { $0.key == row.key }) { row.deletedAt = item.deletedAt }
            }
            for item in value.tombstones where !tombstoneKeys.contains(item.key) { context.insert(DataTombstone(item)) }
            applyGoal(value.goal, to: goal)
        }
    }

    // MARK: - Explicit Apple Health bridge import

    func healthSnapshot() throws -> HealthBridgePacket? {
        try BackupHealthProjection.healthSnapshot(in: snapshot())
    }

    func previewHealthImport(_ packet: HealthBridgePacket) throws -> HealthImportPreview {
        let current = try snapshot()
        let target = try addingHealth(packet, to: current)
        let old = Dictionary(uniqueKeysWithValues: current.sessions.map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: target.sessions.map { ($0.id, $0) })
        return HealthImportPreview(newRuns: target.sessions.filter { old[$0.id] == nil }.count,
            updatedRuns: target.sessions.filter { old[$0.id] != nil && old[$0.id] != $0 }.count,
            deletedRuns: current.sessions.filter { new[$0.id] == nil }.count,
            workoutCount: packet.workouts.count, stepDayCount: packet.stepDays.count, sleepSampleCount: packet.sleepSamples.count)
    }

    func importHealth(_ packet: HealthBridgePacket) throws {
        try persist(addingHealth(packet, to: snapshot()))
    }

    private func addingHealth(_ packet: HealthBridgePacket, to current: BackupSnapshot) throws -> BackupSnapshot {
        try packet.validated()
        var value = current
        let data = try HealthBridgeCodec.encode(packet)
        if let existing = value.healthPackets.first(where: { $0.id == packet.id }) {
            guard try HealthBridgeCodec.decode(existing.json) == packet else {
                throw BackupError.conflict("health export \(packet.id)")
            }
        } else if !value.tombstones.contains(where: { $0.kind == .health && $0.id == packet.id }) {
            value.healthPackets.append(BackupHealthPacket(id: packet.id, json: data))
        }
        return try BackupHealthProjection.reconcile(value)
    }

    // MARK: - CSV with explicit units

    func exportCSV() throws -> String {
        let value = try snapshot()
        var lines = ["session_id,date_time,type,plan,duration_min,completion,intensity,feeling,notes,exercise,set,reps,hold_seconds,side,weight_kg"]
        let formatter = ISO8601DateFormatter()
        let groups = Dictionary(grouping: value.sets, by: \.sessionID)
        for session in value.sessions.sorted(by: { $0.date > $1.date }) {
            let base = [session.id.uuidString, formatter.string(from: session.date), session.type.rawValue,
                        session.planCode ?? "", "\(session.durationMinutes)", session.completion.rawValue,
                        session.intensity == 0 ? "" : "\(session.intensity)", session.bodyFeeling ?? "", session.notes ?? ""]
            let rows = (groups[session.id] ?? []).sorted { $0.recordedAt < $1.recordedAt }
            if rows.isEmpty { lines.append((base + Array(repeating: "", count: 6)).map(csvEscape).joined(separator: ",")) }
            for row in rows {
                let fields = [row.exerciseID, "\(row.setIndex)", row.isHold ? "" : "\(row.reps)",
                              row.isHold ? "\(row.reps)" : "", row.side ?? "", row.weightKg.map { String($0) } ?? ""]
                lines.append((base + fields).map(csvEscape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\r\n")
    }

    private func csvEscape(_ text: String) -> String {
        // Notes are plain text even when opened in a spreadsheet application.
        let value = ["=", "+", "-", "@", "\t", "\r"].contains(where: { text.hasPrefix($0) }) ? "'" + text : text
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

private extension WorkoutSession {
    convenience init(_ value: BackupSession) {
        self.init(id: value.id, date: value.date, type: value.type, planCode: value.planCode,
                  durationMinutes: value.durationMinutes, completion: value.completion, intensity: value.intensity,
                  bodyFeeling: value.bodyFeeling, notes: value.notes, exerciseIDs: value.exerciseIDs)
    }
    func apply(_ value: BackupSession) {
        date = value.date; type = value.type; planCode = value.planCode; durationMinutes = value.durationMinutes
        completion = value.completion; intensity = value.intensity; bodyFeeling = value.bodyFeeling
        notes = value.notes; exerciseIDs = value.exerciseIDs
    }
}

private extension SetRecord {
    convenience init(_ value: BackupSet) {
        self.init(id: value.id, sessionID: value.sessionID, exerciseID: value.exerciseID, setIndex: value.setIndex,
                  reps: value.reps, weightKg: value.weightKg, recordedAt: value.recordedAt,
                  isHold: value.isHold, sideRaw: value.side)
    }
}
