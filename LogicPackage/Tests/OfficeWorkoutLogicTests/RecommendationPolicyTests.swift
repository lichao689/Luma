import XCTest
@testable import OfficeWorkoutLogic

final class RecommendationPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        return value
    }
    private func stats(_ records: [SessionRecord]) -> WorkoutStats {
        WorkoutStatsService(calendar: calendar, now: now).stats(sessions: records)
    }

    func testFutureAndDuplicateSessionsDoNotFillGoals() {
        let record = SessionRecord(date: now, type: .strengthA)
        let result = stats([record, record, .init(date: now.addingTimeInterval(86_400), type: .strengthB, bodyFeeling: "pain")])
        XCTAssertEqual(result.strengthCountToday, 1)
        XCTAssertEqual(result.lastStrengthType, .strengthA)
        XCTAssertFalse(result.recentBackPain)
    }

    func testPartialTrainingRetainsLoadWithoutClaimingCompleteGoal() {
        let result = stats([.init(date: now.addingTimeInterval(-3600), type: .strengthA,
                                 durationMinutes: 20, completion: .partial, intensity: 3, exerciseIDs: ["pushUp"])])
        XCTAssertEqual(result.strengthCountToday, 0)
        XCTAssertTrue(result.hasActivityToday)
        XCTAssertEqual(result.recentActivities.first?.exerciseIDs, ["pushUp"])
        XCTAssertEqual(RecommendationEngine.default.recommend(stats: result, goal: .default, now: now).reasonKey, "rec.recovery.spacing")
    }

    func testPainStillPausesAfterUserAlreadyExercisedToday() {
        let result = stats([.init(date: now, type: .recovery, bodyFeeling: "pain")])
        let recommendation = RecommendationEngine.default.recommend(stats: result, goal: .default, now: now)
        XCTAssertEqual(recommendation.action, .rest)
        XCTAssertEqual(recommendation.reasonKey, "rec.pause.pain")
    }

    func testFatigueFeedbackAndLegSorenessChangeSuggestedTraining() {
        let tired = stats([.init(date: now.addingTimeInterval(-3600), type: .recovery, bodyFeeling: "fatigue")])
        let tiredRecommendation = RecommendationEngine.default.recommend(stats: tired, goal: .default, now: now)
        XCTAssertEqual(tiredRecommendation.action, .rest)
        XCTAssertEqual(tiredRecommendation.reasonKey, "rec.rest.fatigue")
        let sore = stats([.init(date: now.addingTimeInterval(-3600), type: .recovery, bodyFeeling: "legSore")])
        XCTAssertEqual(RecommendationEngine.default.recommend(stats: sore, goal: .default, now: now).reasonKey, "rec.recovery.soreness")
    }

    func testRunDoesNotKeepRequestingRecoveryWhenDailyRecoveryTargetIsMet() {
        let result = stats([.init(date: now.addingTimeInterval(-3600), type: .run),
                            .init(date: now.addingTimeInterval(-1800), type: .recovery),
                            .init(date: now, type: .recovery)])
        XCTAssertEqual(RecommendationEngine.default.recommend(stats: result, goal: .default, now: now).action, .rest)
    }

    func testExplicitRestWinsOverAnEmptyDailyTargetAndInactivity() {
        let result = stats([.init(date: now, type: .rest)])
        let recommendation = RecommendationEngine.default.recommend(stats: result, goal: .default, now: now)
        XCTAssertEqual(recommendation.action, .rest)
        XCTAssertEqual(recommendation.reasonKey, "rec.rest.planned")
    }

    func testRecentHighEffortAndAccumulatedLoadIndependentlyPermitRest() {
        let hard = stats([.init(date: now.addingTimeInterval(-3600), type: .run, durationMinutes: 10, intensity: 5)])
        XCTAssertEqual(RecommendationEngine.default.recommend(stats: hard, goal: .default, now: now).reasonKey, "rec.rest.highEffort")
        let loaded = stats([.init(date: now.addingTimeInterval(-3600), type: .run, durationMinutes: 90, intensity: 3)])
        XCTAssertEqual(RecommendationEngine.default.recommend(stats: loaded, goal: .default, now: now).reasonKey, "rec.rest.recentLoad")
    }

    func testUnknownImportedIntensityIsNotInventedAsHardOrEasy() {
        let result = stats([.init(date: now.addingTimeInterval(-3600), type: .run, durationMinutes: 90, intensity: 0)])
        let recommendation = RecommendationEngine.default.recommend(stats: result, goal: .default, now: now)
        XCTAssertEqual(recommendation.reasonKey, "rec.afterRun.reason")
        XCTAssertEqual(result.recentActivities.first?.intensity, 0)
    }

    func testExactTimeAcrossMidnightDoesNotBypassSpacing() {
        // Calendar day differences must not turn 47 hours into 48 hours.
        let result = stats([.init(date: now.addingTimeInterval(-47 * 3600), type: .strengthB)])
        XCTAssertEqual(RecommendationEngine.default.recommend(stats: result, goal: .default, now: now).reasonKey, "rec.recovery.spacing")
    }

    func testOneCompletedRestDayDoesNotBecomeTwoInactiveDaysBeforeTodayStarts() {
        let result = stats([.init(date: now.addingTimeInterval(-48 * 3600), type: .strengthA),
                            .init(date: now.addingTimeInterval(-24 * 3600), type: .rest)])
        XCTAssertEqual(result.consecutiveInactiveDays, 1)
        XCTAssertEqual(RecommendationEngine.default.recommend(stats: result, goal: .default, now: now).action, .startStrength(.strengthB))
    }

    func testActualMinimalExercisesAffectMuscleSpacing() {
        let result = stats([.init(date: now.addingTimeInterval(-3600), type: .minimal,
                                 durationMinutes: 8, completion: .minimal, exerciseIDs: ["gobletSquat"])])
        let recommendation = RecommendationEngine.default.recommend(stats: result, goal: .default, now: now)
        XCTAssertEqual(recommendation.reasonKey, "rec.recovery.muscles")
    }

    func testWeeklyGoalStopsStrengthEvenWhenTodayIsEmpty() {
        var goal = UserGoalValues.default
        goal.weeklyStrengthTarget = 1
        goal.weeklyRunTarget = 0
        // now is Tuesday, so use a completed Monday session and an injected
        // short spacing to isolate the weekly target behavior.
        let result = stats([.init(date: now.addingTimeInterval(-24 * 3600), type: .strengthA)])
        let engine = RecommendationEngine(policy: .init(strengthRecoveryHours: 0, sameMuscleRecoveryHours: 0))
        let recommendation = engine.recommend(stats: result, goal: goal, now: now)
        XCTAssertEqual(recommendation.reasonKey, "rec.recovery.weeklyMet")
        XCTAssertEqual(recommendation.action, .recovery)
    }

    func testDisablingStrengthDoesNotOfferMinimalStrengthAfterIdleDays() {
        let result = stats([])
        let goal = UserGoalValues(dailyStrengthTarget: 0, weeklyStrengthTarget: 0, weeklyRunTarget: 0)
        XCTAssertEqual(RecommendationEngine.default.recommend(stats: result, goal: goal, now: now).action, .recovery)
    }

    func testInjectedRecoveryPolicyCanChangeDecisionWithoutChangingHistory() {
        let result = stats([.init(date: now.addingTimeInterval(-30 * 3600), type: .strengthA)])
        let short = RecommendationEngine(policy: .init(strengthRecoveryHours: 24, sameMuscleRecoveryHours: 24))
        XCTAssertEqual(short.recommend(stats: result, goal: .default, now: now).action, .startStrength(.strengthB))
        XCTAssertEqual(RecommendationEngine.default.recommend(stats: result, goal: .default, now: now).action, .recovery)
    }
}
