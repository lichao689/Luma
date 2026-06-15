import XCTest
@testable import OfficeWorkoutLogic

/// Pin the recommendation engine's priority order and edge cases.
final class RecommendationEngineTests: XCTestCase {
    private let engine = RecommendationEngine.default
    private let goal = UserGoalValues.default
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // Rule 1: back pain → recovery
    func testBackPainTodayRecommendsRecovery() {
        let stats = baseStats(recentBackPain: true, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .recovery)
    }

    // Rule 2: ran today → recovery
    func testRanTodayRecommendsRecovery() {
        let stats = baseStats(hasActivityToday: true, hasRunToday: true)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .recovery)
    }

    // Rule 3: strength met → run or recovery
    func testStrengthMetRunShortSuggestsRun() {
        let stats = baseStats(strengthCount: 3, runCount: 0, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .logRun)
    }
    func testStrengthMetRunMetSuggestsRecovery() {
        let stats = baseStats(strengthCount: 3, runCount: 2, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .recovery)
    }

    // Rule 4: A/B alternation
    func testLastWasA_RecommendsB() {
        let stats = baseStats(strengthCount: 1, lastStrengthType: .strengthA, daysSinceLastStrength: 1, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .startStrength(.strengthB))
    }
    func testLastWasB_RecommendsA() {
        let stats = baseStats(strengthCount: 1, lastStrengthType: .strengthB, daysSinceLastStrength: 1, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .startStrength(.strengthA))
    }
    func testNoPriorStrength_RecommendsA() {
        let stats = baseStats(hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .startStrength(.strengthA))
    }

    // Rule 5: two+ idle days → minimal
    func testTwoIdleDays_RecommendsMinimal() {
        let stats = baseStats(consecutiveInactiveDays: 2, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .minimal)
    }
    func testSingleIdleDay_StillStrength() {
        let stats = baseStats(consecutiveInactiveDays: 1, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .startStrength(.strengthA))
    }

    // Priority interactions
    func testBackPainBeatsAlternation() {
        let stats = baseStats(strengthCount: 1, lastStrengthType: .strengthA, daysSinceLastStrength: 1, consecutiveInactiveDays: 0, recentBackPain: true, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .recovery)
    }
    func testRanTodayBeatsAlternationEvenIfStrengthShort() {
        let stats = baseStats(strengthCount: 0, hasActivityToday: true, hasRunToday: true)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .recovery)
    }
    func testJustAtStrengthTargetDoesNotSuggestStrength() {
        let stats = baseStats(strengthCount: 3, hasActivityToday: false)
        XCTAssertNotEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .startStrength(.strengthA))
    }

    // Stats service integration
    func testStatsServiceFromSessions() {
        let svc = WorkoutStatsService(calendar: calendar, now: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let records = [
            SessionRecord(date: now, type: .strengthA),
            SessionRecord(date: yesterday, type: .strengthB),
            SessionRecord(date: yesterday, type: .run)
        ]
        let stats = svc.stats(sessions: records)
        XCTAssertGreaterThanOrEqual(stats.strengthCount, 1)
        XCTAssertTrue(stats.hasActivityToday)
        XCTAssertEqual(stats.lastStrengthType, .strengthA)
    }

    func testRecentBackPainDetectedFromFeeling() {
        let svc = WorkoutStatsService(calendar: calendar, now: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let records = [SessionRecord(date: yesterday, type: .strengthA, bodyFeeling: "backTight")]
        XCTAssertTrue(svc.stats(sessions: records).recentBackPain)
    }

    // MARK: - Helpers
    private func baseStats(
        strengthCount: Int = 0, runCount: Int = 0, recoveryCount: Int = 0,
        lastStrengthType: WorkoutType? = nil, daysSinceLastStrength: Int? = nil,
        consecutiveInactiveDays: Int = 0, recentBackPain: Bool = false,
        hasActivityToday: Bool = false, hasRunToday: Bool = false
    ) -> WorkoutStats {
        WorkoutStats(
            strengthCount: strengthCount, runCount: runCount, recoveryCount: recoveryCount,
            lastStrengthType: lastStrengthType, daysSinceLastStrength: daysSinceLastStrength,
            consecutiveInactiveDays: consecutiveInactiveDays, hasActivityToday: hasActivityToday,
            hasRunToday: hasRunToday, recentBackPain: recentBackPain
        )
    }
}
