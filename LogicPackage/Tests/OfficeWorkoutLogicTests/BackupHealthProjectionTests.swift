import XCTest
@testable import OfficeWorkoutLogic

final class BackupHealthProjectionTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 817_200_000.123456)
    private func workout(id: UUID = UUID(), activity: HealthActivity = .running, seconds: Double = 1200) -> HealthWorkout {
        HealthWorkout(id: id, activity: activity, sourceBundleIdentifier: "test.synthetic",
                      start: now.addingTimeInterval(-3600), end: now, durationSeconds: seconds)
    }
    private func archive(_ workouts: [HealthWorkout], offset: Double = 0, deleted: [UUID] = []) throws -> BackupHealthPacket {
        let packet = HealthBridgePacket(generatedAt: now.addingTimeInterval(offset),
            periodStart: now.addingTimeInterval(-86_400), periodEnd: now, timeZoneIdentifier: "UTC",
            workouts: workouts, deletedWorkoutIDs: deleted)
        return BackupHealthPacket(id: packet.id, importedAt: now, json: try HealthBridgeCodec.encode(packet))
    }
    private func snapshot(_ archives: [BackupHealthPacket]) throws -> BackupSnapshot {
        try BackupHealthProjection.reconcile(BackupSnapshot(deviceID: UUID(), exportedAt: now, healthPackets: archives))
    }

    func testOnlyRunningBecomesASessionAndAllSourceActivitiesSurviveBackup() throws {
        let originals = [workout(), workout(activity: .strength), workout(activity: .walking),
                         workout(activity: .cycling), workout(activity: .other)]
        let source = try archive(originals)
        let value = try snapshot([source])
        XCTAssertEqual(value.sessions.count, 1)
        XCTAssertEqual(value.sessions.first?.type, .run)
        XCTAssertEqual(value.sessions.first?.intensity, 0)
        XCTAssertEqual(value.sessions.first?.durationMinutes, 20)
        let portable = try BackupCodec.decode(BackupCodec.encode(value))
        XCTAssertEqual(try HealthBridgeCodec.decode(portable.healthPackets[0].json).workouts, originals)
        XCTAssertEqual(try BackupMerger.merge(local: value, incoming: portable), value)
    }

    func testNewerSourceCorrectionConvergesAcrossDevicesAndNeverRollsBack() throws {
        let id = UUID()
        let old = try snapshot([archive([workout(id: id)])])
        let newer = try snapshot([archive([workout(id: id, seconds: 1800)], offset: 10)])
        let a = try BackupMerger.merge(local: old, incoming: newer)
        let b = try BackupMerger.merge(local: newer, incoming: old)
        XCTAssertEqual(a.sessions, b.sessions)
        XCTAssertEqual(a.sessions.first?.durationMinutes, 30)
        XCTAssertEqual(a.healthPackets, b.healthPackets)
        XCTAssertEqual(try BackupMerger.preview(local: old, incoming: newer).updatedSessions, 1)
        XCTAssertEqual(try BackupMerger.merge(local: a, incoming: old), a)
    }

    func testSourceAndLocalDeletionsPreventRestorationEvenWithOldPackets() throws {
        let id = UUID()
        let old = try snapshot([archive([workout(id: id)])])
        let sourceDeletion = try snapshot([archive([], offset: 10, deleted: [id])])
        let merged = try BackupMerger.merge(local: old, incoming: sourceDeletion)
        XCTAssertTrue(merged.sessions.isEmpty)
        XCTAssertTrue(merged.tombstones.contains { $0.id == id && $0.kind == .session })
        XCTAssertTrue(try BackupMerger.merge(local: merged, incoming: old).sessions.isEmpty)
        var localDeletion = old
        localDeletion.sessions = []
        localDeletion.tombstones = [BackupTombstone(kind: .session, id: id, deletedAt: now)]
        XCTAssertTrue(try BackupMerger.merge(local: old, incoming: localDeletion).sessions.isEmpty)
    }

    func testLocalContentOrManualUUIDCannotBeOverwrittenBySourceProjection() throws {
        let run = workout()
        let imported = try snapshot([archive([run])])
        var manual = BackupSnapshot(deviceID: UUID(), exportedAt: now)
        manual.sessions = [BackupSession(id: run.id, date: now, type: .run, durationMinutes: 10)]
        XCTAssertThrowsError(try BackupMerger.merge(local: manual, incoming: imported))
        var edited = imported
        edited.sessions[0].notes = "My own edit"
        XCTAssertThrowsError(try BackupMerger.merge(local: edited, incoming: imported))
        let sourceDeletion = try snapshot([archive([], offset: 1, deleted: [run.id])])
        XCTAssertThrowsError(try BackupMerger.merge(local: manual, incoming: sourceDeletion))
    }

    func testSameTimeDifferentSourcePayloadIsRejectedInBothOrdersButDeleteWins() throws {
        let id = UUID()
        let first = try archive([workout(id: id)])
        let conflicting = try archive([workout(id: id, seconds: 1800)])
        XCTAssertThrowsError(try snapshot([first, conflicting]))
        XCTAssertThrowsError(try snapshot([conflicting, first]))
        let deletion = try archive([], offset: 1, deleted: [id])
        XCTAssertTrue(try snapshot([first, conflicting, deletion]).sessions.isEmpty)
    }

    func testActivityCorrectionRemovesDerivedRunWithoutMislabelingAnotherActivity() throws {
        let id = UUID()
        let old = try snapshot([archive([workout(id: id)])])
        let corrected = try snapshot([archive([workout(id: id, activity: .walking)], offset: 10)])
        let merged = try BackupMerger.merge(local: old, incoming: corrected)
        XCTAssertTrue(merged.sessions.isEmpty)
        XCTAssertTrue(try BackupMerger.merge(local: merged, incoming: old).sessions.isEmpty)
        XCTAssertEqual(merged.healthPackets.count, 2)
        XCTAssertFalse(merged.tombstones.contains { $0.id == id && $0.kind == .session })
        let runningAgain = try snapshot([archive([workout(id: id, seconds: 1800)], offset: 20)])
        let restored = try BackupMerger.merge(local: merged, incoming: runningAgain)
        XCTAssertEqual(restored.sessions.first?.id, id)
        XCTAssertEqual(restored.sessions.first?.durationMinutes, 30)
    }
}
