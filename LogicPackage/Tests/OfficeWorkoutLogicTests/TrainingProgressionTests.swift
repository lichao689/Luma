import XCTest
@testable import OfficeWorkoutLogic

final class TrainingProgressionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let exercise = PlannedExercise(exerciseID: "gobletSquat", sets: 2, reps: 12, restSeconds: 60)

    private func performance(daysAgo: Double, reps: [Int] = [12, 12], weight: Double? = 20,
                             completion: CompletionLevel = .full, intensity: Int = 3,
                             discomfort: Bool = false, sessionID: UUID = UUID()) -> ExercisePerformance {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        let sets = reps.enumerated().map { index, value in
            ExecutedSet(exerciseID: "gobletSquat", setIndex: index + 1, reps: value,
                        isHold: false, weightKg: weight, completedAt: date)
        }
        return ExercisePerformance(sessionID: sessionID, date: date, completion: completion,
                                   intensity: intensity, hasDiscomfort: discomfort, sets: sets)
    }

    func testTwoCompleteModerateSessionsAtUpperBoundOfferBoundedIncrease() {
        let result = TrainingProgression.suggestion(for: exercise,
            history: [performance(daysAgo: 3), performance(daysAgo: 1)], now: now)
        XCTAssertEqual(result.change, .increaseWeight)
        XCTAssertEqual(result.weightKg, 20.5)
        XCTAssertTrue(result.requiresAcceptance)
    }

    func testOneBestSetCannotHideAnUnfinishedLastSet() {
        let result = TrainingProgression.suggestion(for: exercise,
            history: [performance(daysAgo: 1, reps: [12, 9]), performance(daysAgo: 3)], now: now)
        XCTAssertEqual(result.change, .maintain)
        XCTAssertFalse(result.requiresAcceptance)
    }

    func testMissingSetsNeverQualifyEvenIfSessionWasMarkedFull() {
        let result = TrainingProgression.suggestion(for: exercise,
            history: [performance(daysAgo: 1, reps: [12]), performance(daysAgo: 3)], now: now)
        XCTAssertEqual(result.change, .maintain)
    }

    func testLowTargetInShortPlanMustStillReachCatalogueUpperBound() {
        var short = exercise
        short.reps = 8
        let result = TrainingProgression.suggestion(for: short,
            history: [performance(daysAgo: 1, reps: [8, 8]), performance(daysAgo: 3, reps: [8, 8])], now: now)
        XCTAssertEqual(result.change, .maintain)
    }

    func testIncompleteLatestSessionInterruptsOlderSuccessfulSequence() {
        let result = TrainingProgression.suggestion(for: exercise,
            history: [performance(daysAgo: 1, reps: [8], completion: .partial),
                      performance(daysAgo: 3), performance(daysAgo: 5)], now: now)
        XCTAssertEqual(result.change, .reduceLoad)
        XCTAssertEqual(result.weightKg, 18)
        XCTAssertEqual(result.reasonKey, "progression.incomplete")
    }

    func testDiscomfortNeverTurnsIntoPermissionToContinueAtLighterWeight() {
        let result = TrainingProgression.suggestion(for: exercise,
            history: [performance(daysAgo: 1, discomfort: true), performance(daysAgo: 3)], now: now)
        XCTAssertEqual(result.change, .maintain)
        XCTAssertNil(result.weightKg)
        XCTAssertEqual(result.reasonKey, "progression.pausePain")
    }

    func testUnknownEffortAndMissingWeightDoNotTriggerProgression() {
        let unknownEffort = TrainingProgression.suggestion(for: exercise,
            history: [performance(daysAgo: 1, intensity: 0), performance(daysAgo: 3)], now: now)
        XCTAssertEqual(unknownEffort.change, .maintain)
        let unknownLoad = TrainingProgression.suggestion(for: exercise,
            history: [performance(daysAgo: 1, weight: nil), performance(daysAgo: 3, weight: nil)], now: now)
        XCTAssertEqual(unknownLoad.change, .maintain)
    }

    func testHardLatestSessionOffersReductionInsteadOfIncrease() {
        let result = TrainingProgression.suggestion(for: exercise,
            history: [performance(daysAgo: 1, intensity: 5), performance(daysAgo: 3)], now: now)
        XCTAssertEqual(result.change, .reduceLoad)
        XCTAssertEqual(result.weightKg, 18)
    }

    func testDuplicateSameSessionAndStaleHistoryDoNotCountAsTwoSuccesses() {
        let first = performance(daysAgo: 1)
        let duplicate = performance(daysAgo: 3, sessionID: first.sessionID)
        XCTAssertEqual(TrainingProgression.suggestion(for: exercise, history: [first, duplicate], now: now).change, .maintain)
        XCTAssertEqual(TrainingProgression.suggestion(for: exercise,
            history: [first, performance(daysAgo: 60)], now: now).change, .maintain)
        XCTAssertEqual(TrainingProgression.suggestion(for: exercise,
            history: [first, performance(daysAgo: 1.1)], now: now).change, .maintain)
    }

    func testUnavailableSmallEnoughWeightIncrementKeepsCurrentLoad() {
        let result = TrainingProgression.suggestion(for: exercise,
            history: [performance(daysAgo: 1, weight: 4), performance(daysAgo: 3, weight: 4)], now: now)
        XCTAssertEqual(result.change, .maintain)
        XCTAssertEqual(result.reasonKey, "progression.smallerIncrement")
    }

    func testChangedWeightsAcrossSessionsRequireMoreEvidence() {
        let result = TrainingProgression.suggestion(for: exercise,
            history: [performance(daysAgo: 1, weight: 20), performance(daysAgo: 3, weight: 18)], now: now)
        XCTAssertEqual(result.change, .maintain)
    }

    func testUnilateralExerciseNeedsBothSidesOfEverySet() {
        let target = PlannedExercise(exerciseID: "reverseLunge", sets: 2, reps: 10, perSide: true, restSeconds: 60)
        func session(daysAgo: Double, missingRight: Bool) -> ExercisePerformance {
            let date = now.addingTimeInterval(-daysAgo * 86_400)
            let sides: [WorkoutPlanStep.Side] = missingRight ? [.left, .left] : [.left, .right]
            let sets = (1...2).flatMap { index in
                sides.map { ExecutedSet(exerciseID: "reverseLunge", setIndex: index, side: $0,
                                        reps: 10, isHold: false, weightKg: 20, completedAt: date) }
            }
            return .init(sessionID: UUID(), date: date, completion: .full, intensity: 3, hasDiscomfort: false, sets: sets)
        }
        let bad = TrainingProgression.suggestion(for: target,
            history: [session(daysAgo: 1, missingRight: true), session(daysAgo: 3, missingRight: false)], now: now)
        XCTAssertEqual(bad.change, .maintain)
        let complete = TrainingProgression.suggestion(for: target,
            history: [session(daysAgo: 1, missingRight: false), session(daysAgo: 3, missingRight: false)], now: now)
        XCTAssertEqual(complete.change, .increaseWeight)
    }
}
