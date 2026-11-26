import Foundation

/// Rebuilds only source-proven Apple Health runs. Source updates use the export
/// observation time; hand-entered UUID conflicts are still rejected. Keeping the
/// original packets makes this projection reproducible after backup or sync.
public enum BackupHealthProjection {
    public static func reconcile(_ value: BackupSnapshot) throws -> BackupSnapshot {
        var packets: [HealthBridgePacket] = []
        for archive in value.healthPackets { packets.append(try HealthBridgeCodec.decode(archive.json)) }
        packets.sort { left, right in
            if left.generatedAt == right.generatedAt { return left.id.uuidString < right.id.uuidString }
            return left.generatedAt < right.generatedAt
        }
        var tombstones: [String: BackupTombstone] = [:]
        for item in value.tombstones {
            if let previous = tombstones[item.key], previous.deletedAt >= item.deletedAt { continue }
            tombstones[item.key] = item
        }
        var latest: [UUID: (workout: HealthWorkout, observedAt: Date)] = [:]
        var sourceVersions: [UUID: [BackupSession]] = [:]
        var sourceDeleted = Set<UUID>()
        for packet in packets {
            for id in packet.deletedWorkoutIDs {
                sourceDeleted.insert(id)
                let deleted = BackupTombstone(kind: .session, id: id, deletedAt: packet.generatedAt)
                if tombstones[deleted.key].map({ $0.deletedAt < deleted.deletedAt }) ?? true { tombstones[deleted.key] = deleted }
            }
        }
        let deletedIDs = Set(tombstones.values.filter { $0.kind == .session }.map(\.id))
        for packet in packets {
            for workout in packet.workouts where !deletedIDs.contains(workout.id) {
                if workout.activity == .running { sourceVersions[workout.id, default: []].append(try run(workout)) }
                if let previous = latest[workout.id] {
                    if previous.observedAt == packet.generatedAt, previous.workout != workout {
                        throw BackupError.conflict("Same-time health source update \(workout.id)")
                    }
                    if previous.observedAt < packet.generatedAt { latest[workout.id] = (workout, packet.generatedAt) }
                } else { latest[workout.id] = (workout, packet.generatedAt) }
            }
        }
        let sourceSessionIDs = Set(value.sessions.filter { $0.planCode == "apple-health" }.map(\.id))
        guard !value.sets.contains(where: { sourceSessionIDs.contains($0.sessionID) && !deletedIDs.contains($0.sessionID) }) else {
            throw BackupError.conflict("Apple Health run has locally entered set details")
        }
        var sessions: [UUID: BackupSession] = [:]
        for item in value.sessions {
            if sourceDeleted.contains(item.id), item.planCode != "apple-health" {
                throw BackupError.conflict("Health source deletion collides with a local session \(item.id)")
            }
            guard !deletedIDs.contains(item.id) else { continue }
            var candidate = item
            if item.planCode == "apple-health" {
                guard sourceVersions[item.id]?.contains(item) == true, let source = latest[item.id] else {
                    throw BackupError.conflict("Health run differs from its archived source \(item.id)")
                }
                // An explicit source correction from running to another activity
                // removes the derived run while retaining the original activity.
                guard source.workout.activity == .running else { continue }
                candidate = try run(source.workout)
            }
            if let existing = sessions[item.id], existing != candidate {
                throw BackupError.conflict("session \(item.id)")
            }
            sessions[item.id] = candidate
        }
        for (id, source) in latest where source.workout.activity == .running && !deletedIDs.contains(id) {
            let candidate = try run(source.workout)
            if let existing = sessions[id], existing != candidate { throw BackupError.conflict("Health/local session \(id)") }
            sessions[id] = candidate
        }
        var sets: [UUID: BackupSet] = [:]
        for item in value.sets where sessions[item.sessionID] != nil {
            if let existing = sets[item.id], existing != item { throw BackupError.conflict("set \(item.id)") }
            sets[item.id] = item
        }
        var result = value
        result.sessions = sessions.values.sorted { $0.id.uuidString < $1.id.uuidString }
        result.sets = sets.values.sorted { $0.id.uuidString < $1.id.uuidString }
        result.tombstones = tombstones.values.sorted { $0.key < $1.key }
        try BackupCodec.validate(result)
        return result
    }

    private static func run(_ workout: HealthWorkout) throws -> BackupSession {
        let minutes = (workout.durationSeconds / 60).rounded(.down)
        guard minutes.isFinite, (0...10_080).contains(minutes) else { throw BackupError.invalid("Health running duration") }
        return BackupSession(id: workout.id, date: workout.start, type: .run, planCode: "apple-health",
                             durationMinutes: Int(minutes), completion: .full, intensity: 0, notes: "Apple Health")
    }
}
