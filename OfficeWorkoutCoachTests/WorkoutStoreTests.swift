import Foundation
import Testing
import OfficeWorkoutLogic

@MainActor
struct WorkoutStoreTests {
    private let now = Date(timeIntervalSinceReferenceDate: 817_200_000.123456)
    private enum SimulatedFailure: Error { case diskFull }

    private func actualSets() -> [ExecutedSet] {
        [ExecutedSet(exerciseID: "gobletSquat", setIndex: 1, reps: 12, isHold: false,
                     weightKg: 10, completedAt: now),
         ExecutedSet(exerciseID: "sidePlank", setIndex: 1, side: .left, reps: 30, isHold: true, completedAt: now)]
    }

    @Test func workoutAndEveryActualSetCommitTogetherAndRetryIsIdempotent() throws {
        let store = try WorkoutStore(inMemory: true)
        let id = UUID()
        for _ in 0..<2 {
            let result = try store.saveWorkout(id: id, type: .strengthA, durationMinutes: 15, date: now,
                plannedExerciseIDs: ["gobletSquat", "sidePlank", "pushUp"], sets: actualSets())
            #expect(result == id)
        }
        let value = try store.snapshot()
        #expect(value.sessions.count == 1)
        #expect(value.sets.count == 2)
        #expect(value.sets.allSatisfy { $0.sessionID == id })
        #expect(value.sets.first { $0.exerciseID == "sidePlank" }?.side == "left")
        #expect(value.sets.first { $0.exerciseID == "sidePlank" }?.isHold == true)
        #expect(value.sessions.first?.exerciseIDs.contains("pushUp") == true)
    }

    @Test func failedCommitRollsBackBothSessionAndSetsAndCanBeRetried() throws {
        var fail = true
        let store = try WorkoutStore(inMemory: true, beforeSave: { if fail { throw SimulatedFailure.diskFull } })
        let id = UUID()
        #expect(throws: SimulatedFailure.self) {
            try store.saveWorkout(id: id, type: .strengthA, durationMinutes: 15, date: now, sets: actualSets())
        }
        #expect(try store.snapshot().sessions.isEmpty)
        #expect(try store.snapshot().sets.isEmpty)
        #expect(store.lastError != nil)
        fail = false
        try store.saveWorkout(id: id, type: .strengthA, durationMinutes: 15, date: now, sets: actualSets())
        #expect(try store.snapshot().sessions.count == 1)
        #expect(try store.snapshot().sets.count == 2)
        #expect(store.lastError == nil)
    }

    @Test func invalidActualSetDoesNotCreatePartialWorkout() throws {
        let store = try WorkoutStore(inMemory: true)
        let invalid = ExecutedSet(exerciseID: "gobletSquat", setIndex: 1, reps: -1, isHold: false, completedAt: now)
        #expect(throws: BackupError.self) {
            try store.saveWorkout(type: .strengthA, durationMinutes: 15, date: now, sets: [invalid])
        }
        #expect(try store.snapshot().sessions.isEmpty)
        #expect(try store.snapshot().sets.isEmpty)
    }

    @Test func conflictingRestoreCannotMutateExistingDataOrGoals() throws {
        let store = try WorkoutStore(inMemory: true)
        let id = try store.saveWorkout(type: .strengthA, durationMinutes: 15, date: now, sets: actualSets())
        let original = try store.snapshot(now: now)
        var conflict = original
        conflict.sessions[0].durationMinutes = 99
        conflict.goal.weeklyRunTarget = 7
        #expect(throws: BackupError.self) { try store.restore(conflict, importGoals: true) }
        let after = try store.snapshot(now: now)
        #expect(after == original)
        #expect(after.sessions.first?.id == id)
    }

    @Test func deleteRollsBackOnFailureAndTombstoneStopsStaleRestore() throws {
        var fail = false
        let store = try WorkoutStore(inMemory: true, beforeSave: { if fail { throw SimulatedFailure.diskFull } })
        let id = try store.saveWorkout(type: .strengthA, durationMinutes: 15, date: now, sets: actualSets())
        let old = try store.snapshot()
        fail = true
        #expect(throws: SimulatedFailure.self) { try store.deleteSession(id: id) }
        #expect(try store.snapshot().sessions.count == 1)
        #expect(try store.snapshot().sets.count == 2)
        #expect(try store.snapshot().tombstones.isEmpty)
        fail = false
        try store.deleteSession(id: id)
        try store.restore(old)
        let value = try store.snapshot()
        #expect(value.sessions.isEmpty)
        #expect(value.sets.isEmpty)
        #expect(value.tombstones.contains { $0.kind == .session && $0.id == id })
    }

    @Test func planAndGoalBackupRoundTripAndDeletedPlanCannotReappear() throws {
        let first = try WorkoutStore(inMemory: true)
        let plan = TrainingPlanFactory.make(for: .strengthB, minutes: 15, now: now)
        try first.savePlan(plan)
        var goals = UserGoalValues.default; goals.weeklyRunTarget = 4
        try first.updateGoalSafely(goals)
        let portable = try BackupCodec.decode(BackupCodec.encode(first.snapshot()))
        let second = try WorkoutStore(inMemory: true)
        try second.restore(portable)
        #expect(second.customPlans == [plan])
        #expect(try second.snapshot().goal == .default)
        try second.restore(portable, importGoals: true)
        #expect(try second.snapshot().goal == goals)
        try second.deletePlan(id: plan.id)
        try second.restore(portable)
        #expect(second.customPlans.isEmpty)
        #expect(try second.snapshot().tombstones.contains { $0.kind == .plan && $0.id == plan.id })
    }

    @Test func zeroSetPartialPlanInterruptsExerciseProgressionHistory() throws {
        let store = try WorkoutStore(inMemory: true)
        try store.saveWorkout(type: .strengthA, durationMinutes: 1, completion: .partial, date: now,
                              plannedExerciseIDs: ["pushUp"], sets: [])
        let history = store.exercisePerformances(exerciseID: "pushUp")
        #expect(history.count == 1)
        #expect(history.first?.completion == .partial)
        #expect(history.first?.sets.isEmpty == true)
    }

    @Test func healthReimportIsIdempotentAndLocalDeleteSurvivesOldExport() throws {
        let store = try WorkoutStore(inMemory: true)
        let id = UUID()
        let packet = HealthBridgePacket(generatedAt: now, periodStart: now.addingTimeInterval(-3600),
            periodEnd: now, timeZoneIdentifier: "UTC", workouts: [
                HealthWorkout(id: id, activity: .running, sourceBundleIdentifier: "test.synthetic",
                    start: now.addingTimeInterval(-1800), end: now, durationSeconds: 1200)
            ])
        try store.importHealth(packet)
        try store.importHealth(packet)
        #expect(try store.snapshot().sessions.count == 1)
        #expect(try store.snapshot().healthPackets.count == 1)
        #expect(try store.snapshot().sessions.first?.intensity == 0)
        #expect(try store.snapshot().sessions.first?.durationMinutes == 20)
        try store.deleteSession(id: id)
        try store.importHealth(packet)
        #expect(try store.snapshot().sessions.isEmpty)
        #expect(try store.healthSnapshot()?.workouts.isEmpty == true)
    }

    @Test func sourceDeletionAndHealthArchivesConvergeThroughBackup() throws {
        let first = try WorkoutStore(inMemory: true)
        let id = UUID()
        let run = HealthWorkout(id: id, activity: .running, sourceBundleIdentifier: "test.synthetic",
                                start: now.addingTimeInterval(-1800), end: now, durationSeconds: 1200)
        let strength = HealthWorkout(id: UUID(), activity: .strength, sourceBundleIdentifier: "test.synthetic",
                                     start: now.addingTimeInterval(-1800), end: now, durationSeconds: 600)
        let packet = HealthBridgePacket(generatedAt: now, periodStart: now.addingTimeInterval(-3600),
            periodEnd: now, timeZoneIdentifier: "UTC", workouts: [run, strength])
        try first.importHealth(packet)
        #expect(try first.snapshot().sessions.count == 1)
        #expect(try first.healthSnapshot()?.workouts.count == 2)
        let second = try WorkoutStore(inMemory: true)
        try second.restore(BackupCodec.decode(BackupCodec.encode(first.snapshot())))
        #expect(try second.snapshot().sessions.count == 1)
        let deletion = HealthBridgePacket(generatedAt: now.addingTimeInterval(10),
            periodStart: now.addingTimeInterval(-3600), periodEnd: now, timeZoneIdentifier: "UTC",
            deletedWorkoutIDs: [id])
        try second.importHealth(deletion)
        try first.restore(second.snapshot())
        try first.importHealth(packet)
        #expect(try first.snapshot().sessions.isEmpty)
        #expect(try first.snapshot().healthPackets.count == 2)
        #expect(try first.healthSnapshot()?.workouts == [strength])
        #expect(try first.snapshot().tombstones.contains { $0.id == id && $0.kind == .session })
    }

    @Test func csvSeparatesRepetitionsAndSecondsAndPreservesSides() throws {
        let store = try WorkoutStore(inMemory: true)
        try store.saveWorkout(type: .strengthA, notes: "=SUM(1,2)", date: now, sets: actualSets())
        let csv = try store.exportCSV()
        #expect(csv.contains("reps,hold_seconds,side,weight_kg"))
        #expect(csv.contains("\"sidePlank\",\"1\",\"\",\"30\",\"left\",\"\""))
        #expect(csv.contains("\"gobletSquat\",\"1\",\"12\",\"\",\"\",\"10.0\""))
        #expect(csv.contains("'=SUM(1,2)"))
    }
}
