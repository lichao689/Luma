import XCTest
@testable import OfficeWorkoutLogic

final class BackupTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 817_200_000.123456)
    private func snapshot(sessions: [BackupSession] = [], sets: [BackupSet] = [], plans: [TrainingPlan] = [],
                          tombstones: [BackupTombstone] = []) -> BackupSnapshot {
        BackupSnapshot(deviceID: UUID(), exportedAt: now, sessions: sessions, sets: sets, plans: plans, tombstones: tombstones)
    }
    private func session(id: UUID = UUID(), minutes: Int = 12) -> BackupSession {
        BackupSession(id: id, date: now, type: .strengthA, durationMinutes: minutes,
                      bodyFeeling: "normal", notes: "Test, \"quoted\"\nline", exerciseIDs: ["gobletSquat", "sidePlank"])
    }
    private func set(_ sessionID: UUID, hold: Bool = false) -> BackupSet {
        BackupSet(sessionID: sessionID, exerciseID: hold ? "sidePlank" : "gobletSquat", setIndex: 1,
                  reps: hold ? 30 : 12, isHold: hold, side: hold ? "left" : nil,
                  weightKg: hold ? nil : 10.5, recordedAt: now)
    }

    func testLosslessRoundTripIncludesAllDataAndFractionalDates() throws {
        let workout = session()
        let plan = TrainingPlanFactory.make(for: .strengthB, minutes: 15, now: now)
        let health = HealthBridgePacket(generatedAt: now, periodStart: now.addingTimeInterval(-86_400),
            periodEnd: now, timeZoneIdentifier: "UTC")
        var value = snapshot(sessions: [workout], sets: [set(workout.id), set(workout.id, hold: true)],
                             plans: [plan], tombstones: [BackupTombstone(kind: .session, id: UUID(), deletedAt: now)])
        value.goal.weeklyStrengthTarget = 5
        value.healthPackets = [BackupHealthPacket(id: health.id, importedAt: now, json: try HealthBridgeCodec.encode(health))]
        let decoded = try BackupCodec.decode(BackupCodec.encode(value))
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.sets.last?.side, "left")
        XCTAssertEqual(decoded.sets.last?.isHold, true)
        XCTAssertEqual(decoded.sets.first?.weightKg, 10.5)
        XCTAssertEqual(try BackupMerger.merge(local: value, incoming: decoded),
                       try BackupMerger.merge(local: value, incoming: value))
    }

    func testRestoreIsIdempotentAndDoesNotClearUnrelatedRecords() throws {
        let a = session(), b = session()
        let local = snapshot(sessions: [a], sets: [set(a.id)])
        let incoming = snapshot(sessions: [b], sets: [set(b.id)])
        let first = try BackupMerger.merge(local: local, incoming: incoming)
        let second = try BackupMerger.merge(local: first, incoming: incoming)
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first.sessions.map(\.id)), [a.id, b.id])
        XCTAssertEqual(first.sets.count, 2)
        XCTAssertEqual(try BackupMerger.preview(local: first, incoming: incoming).addedSessions, 0)
    }

    func testTombstonesWinInBothDirectionsAndCascadeActualSets() throws {
        let row = session()
        let plan = TrainingPlanFactory.make(for: .strengthA, now: now)
        let old = snapshot(sessions: [row], sets: [set(row.id)], plans: [plan])
        let deleted = snapshot(tombstones: [BackupTombstone(kind: .session, id: row.id, deletedAt: now),
                                          BackupTombstone(kind: .plan, id: plan.id, deletedAt: now)])
        let a = try BackupMerger.merge(local: old, incoming: deleted)
        let b = try BackupMerger.merge(local: deleted, incoming: old)
        XCTAssertTrue(a.sessions.isEmpty); XCTAssertTrue(a.sets.isEmpty); XCTAssertTrue(a.plans.isEmpty)
        XCTAssertEqual(a.sessions, b.sessions)
        XCTAssertEqual(a.tombstones, b.tombstones)
        XCTAssertTrue(try BackupMerger.merge(local: a, incoming: old).sessions.isEmpty)
    }

    func testSameRecordIDDifferentPayloadRejectsWithoutChangingInputs() throws {
        let row = session()
        let local = snapshot(sessions: [row])
        var changed = row; changed.durationMinutes += 1
        let incoming = snapshot(sessions: [changed])
        XCTAssertThrowsError(try BackupMerger.merge(local: local, incoming: incoming)) { error in
            guard case BackupError.conflict = error else { return XCTFail("Expected explicit UUID conflict") }
        }
        XCTAssertEqual(local.sessions, [row])
        XCTAssertThrowsError(try BackupMerger.preview(local: local, incoming: incoming))
    }

    func testGoalsRequireExplicitOptInAndPlansUseNewerEditOrRejectTie() throws {
        var plan = TrainingPlanFactory.make(for: .strengthA, now: now)
        let local = snapshot(plans: [plan])
        plan.name = "Updated"; plan.updatedAt = now.addingTimeInterval(1)
        var incoming = snapshot(plans: [plan]); incoming.goal.weeklyRunTarget = 5
        let merged = try BackupMerger.merge(local: local, incoming: incoming)
        XCTAssertEqual(merged.goal, local.goal)
        XCTAssertEqual(merged.plans, [plan])
        XCTAssertTrue(try BackupMerger.preview(local: local, incoming: incoming).goalsDiffer)
        XCTAssertEqual(try BackupMerger.merge(local: local, incoming: incoming, importGoals: true).goal, incoming.goal)
        var tied = plan; tied.name = "Divergent edit"
        XCTAssertThrowsError(try BackupMerger.merge(local: merged, incoming: snapshot(plans: [tied])))
    }

    func testValidationRejectsDuplicateIDsOrphansUnsupportedVersionAndWrongUnits() throws {
        let row = session()
        XCTAssertThrowsError(try BackupCodec.decode(JSONEncoder().encode(snapshot(sessions: [row, row]))))
        XCTAssertThrowsError(try BackupCodec.encode(snapshot(sets: [set(UUID())])))
        var future = snapshot(); future.version = 2
        XCTAssertThrowsError(try BackupCodec.decode(JSONEncoder().encode(future)))
        var plan = TrainingPlanFactory.make(for: .strengthA, now: now)
        plan.exercises[0].isHold.toggle()
        XCTAssertThrowsError(try BackupCodec.encode(snapshot(plans: [plan])))
        var wrongUnits = set(row.id, hold: true); wrongUnits.isHold = false
        XCTAssertThrowsError(try BackupCodec.encode(snapshot(sessions: [row], sets: [wrongUnits])))
        var wrongSide = set(row.id); wrongSide.side = "left"
        XCTAssertThrowsError(try BackupCodec.encode(snapshot(sessions: [row], sets: [wrongSide])))
        var legacySide = set(row.id, hold: true); legacySide.side = nil
        XCTAssertNoThrow(try BackupCodec.encode(snapshot(sessions: [row], sets: [legacySide])))
        var unsafe = row; unsafe.intensity = -1
        XCTAssertThrowsError(try BackupCodec.encode(snapshot(sessions: [unsafe])))
        unsafe = row; unsafe.intensity = 0
        XCTAssertNoThrow(try BackupCodec.encode(snapshot(sessions: [unsafe])))
    }

    func testHealthPayloadMustBeValidatedAndItsIDMustMatch() throws {
        var value = snapshot()
        value.healthPackets = [BackupHealthPacket(id: UUID(), json: Data("{}".utf8))]
        XCTAssertThrowsError(try BackupCodec.encode(value))
        let packet = HealthBridgePacket(generatedAt: now, periodStart: now.addingTimeInterval(-3600),
                                        periodEnd: now, timeZoneIdentifier: "UTC")
        value.healthPackets = [BackupHealthPacket(id: UUID(), json: try HealthBridgeCodec.encode(packet))]
        XCTAssertThrowsError(try BackupCodec.encode(value))
    }

    func testFolderExchangeUsesSeparateFilesIsRepeatableAndRetainsDeletes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = session(), b = session()
        var deviceA = snapshot(sessions: [a], sets: [set(a.id)])
        let deviceB = snapshot(sessions: [b], sets: [set(b.id)])
        try BackupFolderSync.publish(deviceA, to: folder)
        try BackupFolderSync.publish(deviceB, to: folder)
        let review = try BackupFolderSync.review(folder: folder, local: deviceA)
        XCTAssertEqual(review.deviceCount, 2)
        XCTAssertEqual(review.preview.addedSessions, 1)
        deviceA = review.merged
        try BackupFolderSync.publish(deviceA, to: folder)
        let repeatReview = try BackupFolderSync.review(folder: folder, local: deviceA)
        XCTAssertEqual(repeatReview.preview.addedSessions, 0)
        deviceA.sessions.removeAll { $0.id == b.id }
        deviceA.sets.removeAll { $0.sessionID == b.id }
        deviceA.tombstones.append(BackupTombstone(kind: .session, id: b.id, deletedAt: now))
        try BackupFolderSync.publish(deviceA, to: folder)
        let returning = try BackupFolderSync.review(folder: folder, local: deviceB)
        XCTAssertEqual(returning.merged.sessions.map(\.id), [a.id])
        XCTAssertEqual(returning.preview.deletedSessions, 1)
    }

    func testMalformedPeerStopsSyncBeforePublishAndLeavesLocalFileIntact() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let local = snapshot(sessions: [session()])
        try BackupFolderSync.publish(local, to: folder)
        let path = folder.appendingPathComponent(BackupFolderSync.fileName(deviceID: local.deviceID))
        let original = try Data(contentsOf: path)
        try Data("{ incomplete".utf8).write(to: folder.appendingPathComponent(BackupFolderSync.fileName(deviceID: UUID())))
        XCTAssertThrowsError(try BackupFolderSync.review(folder: folder, local: local))
        XCTAssertEqual(try Data(contentsOf: path), original)
    }
}
