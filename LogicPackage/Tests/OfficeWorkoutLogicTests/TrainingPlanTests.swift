import XCTest
@testable import OfficeWorkoutLogic

final class TrainingPlanTests: XCTestCase {
    func testCustomPlanSplitsBothSidesAndHasStableStepIDs() throws {
        let plan = TrainingPlan(name: "侧向核心", baseType: .strengthB, exercises: [
            PlannedExercise(exerciseID: "sidePlank", sets: 2, reps: 25,
                            isHold: true, perSide: true, restSeconds: 40)
        ])
        let steps = try plan.executionSteps()
        XCTAssertEqual(steps.map(\.id), ["sidePlank#1#left", "sidePlank#1#right", "sidePlank#2#left", "sidePlank#2#right"])
        XCTAssertEqual(try plan.executionSteps(), steps)
    }

    func testRejectsDuplicateUnknownAndMismatchedUnits() {
        let exercise = PlannedExercise(exerciseID: "plank", sets: 1, reps: 30, isHold: true, restSeconds: 10)
        XCTAssertThrowsError(try TrainingPlan(name: "重复", baseType: .strengthA, exercises: [exercise, exercise]).validate())
        XCTAssertThrowsError(try TrainingPlan(name: "不存在", baseType: .strengthA, exercises: [
            .init(exerciseID: "missing", sets: 1, reps: 10, restSeconds: 30)
        ]).validate())
        XCTAssertThrowsError(try TrainingPlan(name: "单位错误", baseType: .strengthA, exercises: [
            .init(exerciseID: "plank", sets: 1, reps: 10, restSeconds: 30)
        ]).validate())
    }

    func testTimeOptionsProduceValidPlansWithIncreasingVolume() throws {
        let short = TrainingPlanFactory.make(for: .strengthA, minutes: 8)
        let medium = TrainingPlanFactory.make(for: .strengthA, minutes: 15)
        let full = TrainingPlanFactory.make(for: .strengthA, minutes: 25)
        for plan in [short, medium, full] { try plan.validate() }
        XCTAssertLessThan(try short.executionSteps().count, try medium.executionSteps().count)
        XCTAssertLessThan(try medium.executionSteps().count, try full.executionSteps().count)
        XCTAssertLessThanOrEqual(short.estimatedMinutes, 8)
        XCTAssertLessThanOrEqual(medium.estimatedMinutes, 15)
        XCTAssertLessThanOrEqual(full.estimatedMinutes, 25)
    }

    func testReplacementRespectsMovementAndExclusions() throws {
        let plan = TrainingPlan(name: "自选", baseType: .strengthB, exercises: [
            .init(exerciseID: "bentOverDumbbellRow", sets: 2, reps: 10, restSeconds: 60)
        ])
        let replaced = try plan.replacing(exerciseID: "bentOverDumbbellRow", with: "proneWRaise")
        XCTAssertEqual(replaced.exercises.first?.exerciseID, "proneWRaise")
        XCTAssertThrowsError(try plan.replacing(exerciseID: "bentOverDumbbellRow", with: "gobletSquat"))
        XCTAssertThrowsError(try plan.replacing(exerciseID: "bentOverDumbbellRow", with: "proneWRaise", avoiding: ["proneWRaise"]))
    }
}
