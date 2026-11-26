import XCTest
@testable import OfficeWorkoutLogic

final class WorkoutExecutionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func plan(hold: Bool = false, sets: Int = 2) -> TrainingPlan {
        TrainingPlan(name: "Test", baseType: .strengthA, exercises: [
            .init(exerciseID: hold ? "plank" : "pushUp", sets: sets, reps: hold ? 30 : 10,
                  isHold: hold, restSeconds: 45)
        ])
    }

    func testPauseDoesNotCountTimeAndResumeContinuesSameSet() throws {
        var execution = try WorkoutExecution(plan: plan(hold: true))
        execution.start(at: start)
        execution.pause(at: start.addingTimeInterval(10))
        execution.update(at: start.addingTimeInterval(100))
        XCTAssertEqual(execution.elapsedSeconds(at: start.addingTimeInterval(100)), 10)
        XCTAssertEqual(execution.phase, .paused)
        execution.resume(at: start.addingTimeInterval(100))
        execution.update(at: start.addingTimeInterval(120))
        XCTAssertEqual(execution.completedSets.count, 1)
        XCTAssertEqual(execution.completedSets.first?.reps, 30)
        XCTAssertEqual(execution.phase, .resting)
    }

    func testPauseBeforeFirstStartDoesNotSubtractPreviewTime() throws {
        var execution = try WorkoutExecution(plan: plan())
        execution.pause(at: start)
        execution.resume(at: start.addingTimeInterval(100))
        XCTAssertEqual(execution.phase, .ready)
        XCTAssertEqual(execution.durationSeconds(at: start.addingTimeInterval(100)), 0)
        execution.start(at: start.addingTimeInterval(120))
        execution.finish(at: start.addingTimeInterval(150))
        XCTAssertEqual(execution.durationSeconds(), 30)
    }

    func testRepeatedPausesPreserveFractionalTime() throws {
        var execution = try WorkoutExecution(plan: plan(hold: true))
        execution.start(at: start)
        execution.pause(at: start.addingTimeInterval(0.6))
        execution.resume(at: start.addingTimeInterval(10))
        execution.pause(at: start.addingTimeInterval(10.6))
        XCTAssertEqual(execution.elapsedSeconds(at: start.addingTimeInterval(100)), 1)
    }

    func testDelayedTimerCompletesOnlyCurrentHoldThenWaitsForUser() throws {
        var execution = try WorkoutExecution(plan: plan(hold: true))
        execution.start(at: start)
        execution.update(at: start.addingTimeInterval(600))
        XCTAssertEqual(execution.completedSets.count, 1)
        XCTAssertEqual(execution.phase, .ready)
        XCTAssertEqual(execution.currentStep?.setIndex, 2)
        execution.update(at: start.addingTimeInterval(1000))
        XCTAssertEqual(execution.completedSets.count, 1)
    }

    func testActualRepetitionsAndWeightSurvivePartialFinish() throws {
        var execution = try WorkoutExecution(plan: plan())
        execution.start(at: start)
        try execution.completeSet(reps: 7, weightKg: 6.5, at: start.addingTimeInterval(25))
        execution.finish(at: start.addingTimeInterval(30))
        XCTAssertEqual(execution.phase, .finished)
        XCTAssertEqual(execution.completion, .partial)
        XCTAssertEqual(execution.completedSets.first?.reps, 7)
        XCTAssertEqual(execution.completedSets.first?.weightKg, 6.5)
        XCTAssertEqual(execution.durationSeconds(at: start.addingTimeInterval(100)), 30)
    }

    func testInvalidInputDoesNotAdvanceOrDiscardCurrentSet() throws {
        var execution = try WorkoutExecution(plan: plan())
        execution.start(at: start)
        XCTAssertThrowsError(try execution.completeSet(reps: 0, weightKg: nil, at: start))
        XCTAssertThrowsError(try execution.completeSet(reps: 4, weightKg: -.infinity, at: start))
        XCTAssertEqual(execution.phase, .working)
        XCTAssertTrue(execution.completedSets.isEmpty)
    }

    func testRestPauseAndSkipCannotDuplicateCompletedSets() throws {
        var execution = try WorkoutExecution(plan: plan())
        execution.start(at: start)
        try execution.completeSet(reps: 8, weightKg: nil, at: start.addingTimeInterval(20))
        execution.pause(at: start.addingTimeInterval(30))
        XCTAssertEqual(execution.restRemaining(at: start.addingTimeInterval(300)), 35)
        execution.resume(at: start.addingTimeInterval(300))
        execution.addRest(seconds: 30, at: start.addingTimeInterval(305))
        XCTAssertEqual(execution.restRemaining(at: start.addingTimeInterval(305)), 60)
        execution.skipRest(at: start.addingTimeInterval(305))
        XCTAssertEqual(execution.phase, .ready)
        XCTAssertThrowsError(try execution.completeSet(reps: 8, weightKg: nil, at: start))
        execution.start(at: start.addingTimeInterval(310))
        try execution.completeSet(reps: 9, weightKg: nil, at: start.addingTimeInterval(340))
        XCTAssertEqual(execution.completion, .full)
        XCTAssertEqual(execution.completedSets.map(\.reps), [8, 9])
    }
}
