import Foundation

/// A portable, explicit format rather than a copy of the SwiftData database.
/// All quantities retain their units; importing never clears the current store.
public struct BackupSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var type: WorkoutType
    public var planCode: String?
    public var durationMinutes: Int
    public var completion: CompletionLevel
    public var intensity: Int
    public var bodyFeeling: String?
    public var notes: String?
    public var exerciseIDs: [String]

    public init(id: UUID = UUID(), date: Date, type: WorkoutType, planCode: String? = nil,
                durationMinutes: Int = 0, completion: CompletionLevel = .full, intensity: Int = 3,
                bodyFeeling: String? = nil, notes: String? = nil, exerciseIDs: [String] = []) {
        self.id = id; self.date = date; self.type = type; self.planCode = planCode
        self.durationMinutes = durationMinutes; self.completion = completion; self.intensity = intensity
        self.bodyFeeling = bodyFeeling; self.notes = notes; self.exerciseIDs = exerciseIDs
    }

    public var asRecord: SessionRecord {
        SessionRecord(id: id, date: date, type: type, bodyFeeling: bodyFeeling, note: notes,
                      durationMinutes: durationMinutes, completion: completion, intensity: intensity,
                      exerciseIDs: exerciseIDs)
    }
}

public struct BackupSet: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var exerciseID: String
    public var setIndex: Int
    /// Repetitions when isHold is false; seconds when isHold is true.
    public var reps: Int
    public var isHold: Bool
    public var side: String?
    public var weightKg: Double?
    public var recordedAt: Date

    public init(id: UUID = UUID(), sessionID: UUID, exerciseID: String, setIndex: Int,
                reps: Int, isHold: Bool = false, side: String? = nil, weightKg: Double? = nil,
                recordedAt: Date) {
        self.id = id; self.sessionID = sessionID; self.exerciseID = exerciseID
        self.setIndex = setIndex; self.reps = reps; self.isHold = isHold; self.side = side
        self.weightKg = weightKg; self.recordedAt = recordedAt
    }
}

public struct BackupTombstone: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case session, plan, health }
    public var kind: Kind
    public var id: UUID
    public var deletedAt: Date
    public var key: String { "\(kind.rawValue):\(id.uuidString)" }

    public init(kind: Kind, id: UUID, deletedAt: Date = .now) {
        self.kind = kind; self.id = id; self.deletedAt = deletedAt
    }
}

/// Keeps the original health export so non-running activities and missing data
/// are not silently converted into a Luma strength/recovery session.
public struct BackupHealthPacket: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var importedAt: Date
    public var json: Data

    public init(id: UUID, importedAt: Date = .now, json: Data) {
        self.id = id; self.importedAt = importedAt; self.json = json
    }
}

public struct BackupSnapshot: Codable, Equatable, Sendable {
    public var format: String = "luma-backup"
    public var version: Int = 1
    public var deviceID: UUID
    public var exportedAt: Date
    public var goal: UserGoalValues
    public var sessions: [BackupSession]
    public var sets: [BackupSet]
    public var plans: [TrainingPlan]
    public var healthPackets: [BackupHealthPacket]
    public var tombstones: [BackupTombstone]

    public init(deviceID: UUID, exportedAt: Date = .now, goal: UserGoalValues = .default,
                sessions: [BackupSession] = [], sets: [BackupSet] = [], plans: [TrainingPlan] = [],
                healthPackets: [BackupHealthPacket] = [], tombstones: [BackupTombstone] = []) {
        self.deviceID = deviceID; self.exportedAt = exportedAt; self.goal = goal
        self.sessions = sessions; self.sets = sets; self.plans = plans
        self.healthPackets = healthPackets; self.tombstones = tombstones
    }
}

public enum BackupError: Error, LocalizedError, Equatable {
    case unsupportedFormat
    case tooLarge
    case invalid(String)
    case conflict(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "不支持此备份格式或版本。 / Unsupported backup format or version."
        case .tooLarge: return "备份超过大小限制。 / Backup exceeds the size limit."
        case .invalid(let detail): return "备份校验失败 / Invalid backup: \(detail)"
        case .conflict(let detail): return "同一记录 ID 的内容冲突，未导入 / Conflicting record, import stopped: \(detail)"
        }
    }
}

public struct BackupMergePreview: Equatable, Sendable {
    public var addedSessions: Int
    public var updatedSessions: Int
    public var addedSets: Int
    public var changedPlans: Int
    public var addedHealthPackets: Int
    public var deletedSessions: Int
    public var deletedPlans: Int
    public var goalsDiffer: Bool
}

public enum BackupCodec {
    public static let maximumBytes = 25 * 1_024 * 1_024

    public static func encode(_ snapshot: BackupSnapshot) throws -> Data {
        try validate(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Foundation reference-date seconds preserve fractional Date values losslessly.
        encoder.dateEncodingStrategy = .deferredToDate
        let data = try encoder.encode(snapshot)
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> BackupSnapshot {
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let snapshot = try decoder.decode(BackupSnapshot.self, from: data)
        try validate(snapshot)
        return snapshot
    }

    public static func validate(_ value: BackupSnapshot) throws {
        guard value.format == "luma-backup", value.version == 1 else { throw BackupError.unsupportedFormat }
        guard value.sessions.count <= 100_000, value.sets.count <= 500_000,
              value.plans.count <= 2_000, value.healthPackets.count <= 2_000,
              value.tombstones.count <= 200_000 else { throw BackupError.tooLarge }
        try unique(value.sessions.map(\.id), "sessions")
        try unique(value.sets.map(\.id), "sets")
        try unique(value.plans.map(\.id), "plans")
        try unique(value.healthPackets.map(\.id), "healthPackets")
        try unique(value.tombstones.map(\.key), "tombstones")
        guard value.exportedAt.timeIntervalSince1970.isFinite else { throw BackupError.invalid("exportedAt") }
        let sessionIDs = Set(value.sessions.map(\.id))
        let deletedSessions = Set(value.tombstones.filter { $0.kind == .session }.map(\.id))
        for session in value.sessions {
            guard session.date.timeIntervalSince1970.isFinite,
                  (0...10_080).contains(session.durationMinutes), (0...5).contains(session.intensity),
                  (session.notes?.count ?? 0) <= 10_000, (session.bodyFeeling?.count ?? 0) <= 500,
                  (session.planCode?.count ?? 0) <= 200,
                  session.exerciseIDs.count <= 100, Set(session.exerciseIDs).count == session.exerciseIDs.count,
                  session.exerciseIDs.allSatisfy({ ExerciseLibrary.exercise(id: $0) != nil }) else {
                throw BackupError.invalid("session \(session.id)")
            }
        }
        for item in value.sets {
            guard sessionIDs.contains(item.sessionID) || deletedSessions.contains(item.sessionID),
                  ExerciseLibrary.exercise(id: item.exerciseID) != nil,
                  item.isHold == ExerciseAlternatives.isHold(item.exerciseID),
                  item.side == nil || ExerciseAlternatives.isPerSide(item.exerciseID),
                  (1...1_000).contains(item.setIndex), (1...86_400).contains(item.reps),
                  item.side == nil || item.side == "left" || item.side == "right",
                  item.recordedAt.timeIntervalSince1970.isFinite,
                  item.weightKg.map({ $0.isFinite && $0 >= 0 && $0 <= 1_000 }) ?? true else {
                throw BackupError.invalid("set \(item.id)")
            }
        }
        for plan in value.plans {
            guard plan.updatedAt.timeIntervalSince1970.isFinite else { throw BackupError.invalid("plan date") }
            try plan.validate()
        }
        for item in value.healthPackets {
            guard item.importedAt.timeIntervalSince1970.isFinite else {
                throw BackupError.invalid("health packet date \(item.id)")
            }
            let packet = try HealthBridgeCodec.decode(item.json)
            guard packet.id == item.id else { throw BackupError.invalid("health packet ID mismatch") }
        }
        for item in value.tombstones where !item.deletedAt.timeIntervalSince1970.isFinite {
            throw BackupError.invalid("tombstone \(item.id)")
        }
        let goal = value.goal
        guard (0...14).contains(goal.weeklyStrengthTarget), (0...21).contains(goal.weeklyRecoveryTarget),
              (0...7).contains(goal.weeklyRunTarget), (0...3).contains(goal.dailyStrengthTarget),
              (0...5).contains(goal.dailyRecoveryTarget), (0...240).contains(goal.sedentaryReminderMinutes),
              (1...240).contains(goal.sedentaryCooldownMinutes),
              (0...1_439).contains(goal.workStartMinutes), (1...1_440).contains(goal.workEndMinutes),
              goal.workStartMinutes < goal.workEndMinutes,
              goal.workWeekdays.allSatisfy({ (1...7).contains($0) }),
              Set(goal.workWeekdays).count == goal.workWeekdays.count else { throw BackupError.invalid("goals") }
    }

    private static func unique<T: Hashable>(_ ids: [T], _ label: String) throws {
        guard Set(ids).count == ids.count else { throw BackupError.invalid("duplicate \(label) IDs") }
    }
}

/// Hand-entered sessions/sets are immutable records. A conflicting payload is an error,
/// never a silent overwrite. Plans are editable: newer edits win; same-time
/// divergent edits are reported. Source-proven Health runs follow the latest source
/// observation. Tombstones always win over stale copies.
public enum BackupMerger {
    public static func merge(local: BackupSnapshot, incoming: BackupSnapshot,
                             importGoals: Bool = false) throws -> BackupSnapshot {
        try BackupCodec.validate(local); try BackupCodec.validate(incoming)
        var deleted = Dictionary(uniqueKeysWithValues: local.tombstones.map { ($0.key, $0) })
        for item in incoming.tombstones {
            if deleted[item.key].map({ $0.deletedAt < item.deletedAt }) ?? true { deleted[item.key] = item }
        }
        let planTombstones = Set(deleted.values.filter { $0.kind == .plan }.map(\.id))
        let healthTombstones = Set(deleted.values.filter { $0.kind == .health }.map(\.id))
        var plans = Dictionary(uniqueKeysWithValues: local.plans.filter { !planTombstones.contains($0.id) }.map { ($0.id, $0) })
        for plan in incoming.plans where !planTombstones.contains(plan.id) {
            if let old = plans[plan.id] {
                if old.updatedAt == plan.updatedAt, old != plan { throw BackupError.conflict("plan \(plan.id)") }
                if old.updatedAt < plan.updatedAt { plans[plan.id] = plan }
            } else { plans[plan.id] = plan }
        }
        var packets = Dictionary(uniqueKeysWithValues: local.healthPackets.filter { !healthTombstones.contains($0.id) }.map { ($0.id, $0) })
        for packet in incoming.healthPackets where !healthTombstones.contains(packet.id) {
            if let old = packets[packet.id] {
                guard try HealthBridgeCodec.decode(old.json) == HealthBridgeCodec.decode(packet.json) else {
                    throw BackupError.conflict("health packet \(packet.id)")
                }
                if packet.importedAt < old.importedAt { packets[packet.id] = packet }
            } else { packets[packet.id] = packet }
        }
        let result = BackupSnapshot(deviceID: local.deviceID, exportedAt: local.exportedAt,
                                    goal: importGoals ? incoming.goal : local.goal,
                                    sessions: local.sessions + incoming.sessions, sets: local.sets + incoming.sets,
                                    plans: plans.values.sorted { $0.id.uuidString < $1.id.uuidString },
                                    healthPackets: packets.values.sorted { $0.id.uuidString < $1.id.uuidString },
                                    tombstones: deleted.values.sorted { $0.key < $1.key })
        return try BackupHealthProjection.reconcile(result)
    }

    public static func preview(local: BackupSnapshot, incoming: BackupSnapshot) throws -> BackupMergePreview {
        let merged = try merge(local: local, incoming: incoming)
        let currentSessions = Set(local.sessions.map(\.id)), currentSets = Set(local.sets.map(\.id))
        let sessionValues = Dictionary(uniqueKeysWithValues: local.sessions.map { ($0.id, $0) })
        let currentPackets = Set(local.healthPackets.map(\.id))
        let currentPlans = Dictionary(uniqueKeysWithValues: local.plans.map { ($0.id, $0) })
        return BackupMergePreview(addedSessions: merged.sessions.filter { !currentSessions.contains($0.id) }.count,
                                  updatedSessions: merged.sessions.filter { sessionValues[$0.id] != nil && sessionValues[$0.id] != $0 }.count,
                                  addedSets: merged.sets.filter { !currentSets.contains($0.id) }.count,
                                  changedPlans: merged.plans.filter { currentPlans[$0.id] != $0 }.count,
                                  addedHealthPackets: merged.healthPackets.filter { !currentPackets.contains($0.id) }.count,
                                  deletedSessions: currentSessions.subtracting(merged.sessions.map(\.id)).count,
                                  deletedPlans: Set(currentPlans.keys).subtracting(merged.plans.map(\.id)).count,
                                  goalsDiffer: local.goal != incoming.goal)
    }

}
