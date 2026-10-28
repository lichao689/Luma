import XCTest
@testable import OfficeWorkoutLogic

/// Pin the recommendation engine's priority order and edge cases.
final class RecommendationEngineTests: XCTestCase {
    private let engine = RecommendationEngine.default
    private let goal = UserGoalValues.default  // dailyStrength 1, weeklyRun 2, ...
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

    // Rule 3: today's strength met → run or recovery
    func testStrengthMetTodayRunShortSuggestsRun() {
        // dailyStrengthTarget default = 1; today's strength = 1 → met → run short → run
        let stats = baseStats(runCount: 0, strengthCountToday: 1, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .logRun)
    }
    func testStrengthMetTodayRunMetSuggestsRecovery() {
        let stats = baseStats(runCount: 2, strengthCountToday: 1, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .recovery)
    }

    // Rule 4: A/B alternation (today's strength NOT met yet → strength)
    func testLastWasA_RecommendsB() {
        let stats = baseStats(strengthCountToday: 0, lastStrengthType: .strengthA, daysSinceLastStrength: 1, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .startStrength(.strengthB))
    }
    func testLastWasB_RecommendsA() {
        let stats = baseStats(strengthCountToday: 0, lastStrengthType: .strengthB, daysSinceLastStrength: 1, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .startStrength(.strengthA))
    }
    func testNoPriorStrength_RecommendsA() {
        let stats = baseStats(strengthCountToday: 0, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .startStrength(.strengthA))
    }

    // Rule 5: two+ idle days → minimal
    func testTwoIdleDays_RecommendsMinimal() {
        let stats = baseStats(strengthCountToday: 0, consecutiveInactiveDays: 2, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .minimal)
    }
    func testSingleIdleDay_StillStrength() {
        let stats = baseStats(strengthCountToday: 0, consecutiveInactiveDays: 1, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .startStrength(.strengthA))
    }

    // Priority interactions
    func testBackPainBeatsAlternation() {
        let stats = baseStats(strengthCountToday: 0, lastStrengthType: .strengthA, daysSinceLastStrength: 1, consecutiveInactiveDays: 0, recentBackPain: true, hasActivityToday: false)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .recovery)
    }
    func testRanTodayBeatsAlternationEvenIfStrengthShort() {
        let stats = baseStats(strengthCountToday: 0, hasActivityToday: true, hasRunToday: true)
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .recovery)
    }
    func testStrengthMetTodayDoesNotSuggestStrength() {
        let stats = baseStats(strengthCountToday: 1, hasActivityToday: false)
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
        XCTAssertEqual(stats.strengthCountToday, 1, "today's strength should be 1 (the strengthA today)")
        XCTAssertTrue(stats.hasActivityToday)
        XCTAssertEqual(stats.lastStrengthType, .strengthA)
    }

    func testRecentBackPainDetectedFromFeeling() {
        let svc = WorkoutStatsService(calendar: calendar, now: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let records = [SessionRecord(date: yesterday, type: .strengthA, bodyFeeling: "backTight")]
        XCTAssertTrue(svc.stats(sessions: records).recentBackPain)
    }

    // MARK: - 过度训练保护(规则 3)

    /// 连续练了 6 天且本周目标全达成 → 应该建议休息,而不是继续练。
    func testSixActiveDaysWithWeeklyGoalsMet_RecommendsRest() {
        let stats = baseStats(
            strengthCount: 7, runCount: 2, recoveryCount: 14,
            strengthCountToday: 1,
            consecutiveActiveDays: 6
        )
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .rest)
    }

    /// 连续练很多天但周目标还差得远 → 不能因为"连续天数"就让人停。
    func testSixActiveDaysButGoalsShort_KeepsTraining() {
        let stats = baseStats(
            strengthCount: 2, runCount: 0, recoveryCount: 0,
            strengthCountToday: 1,
            consecutiveActiveDays: 9
        )
        let action = engine.recommend(stats: stats, goal: goal, now: now).action
        XCTAssertNotEqual(action, .rest)
    }

    /// 没到阈值时不应触发休息。
    func testFiveActiveDays_NoRest() {
        let stats = baseStats(
            strengthCount: 7, runCount: 2, recoveryCount: 14,
            strengthCountToday: 1,
            consecutiveActiveDays: 5
        )
        XCTAssertNotEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .rest)
    }

    // MARK: - 中断后重新起步

    /// 距上次力量已超过 7 天 → 回到力量 A,而不是按上次的 B 继续交替。
    func testLongGapResetsToPlanA() {
        let stats = baseStats(
            strengthCountToday: 0,
            lastStrengthType: .strengthA,
            daysSinceLastStrength: 10
        )
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .startStrength(.strengthA))
    }

    /// 间隔在阈值内 → 仍按 A/B 交替。
    func testShortGapStillAlternates() {
        let stats = baseStats(
            strengthCountToday: 0,
            lastStrengthType: .strengthA,
            daysSinceLastStrength: 2
        )
        XCTAssertEqual(engine.recommend(stats: stats, goal: goal, now: now).action, .startStrength(.strengthB))
    }

    // MARK: - 腰痛识别的精确性

    /// 备注里出现 "back to normal" 这类说法不能被当成腰痛。
    func testBareBackWordInNoteIsNotBackPain() {
        let svc = WorkoutStatsService(calendar: calendar, now: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let records = [SessionRecord(date: yesterday, type: .strengthA, note: "back to normal, feeling good")]
        XCTAssertFalse(svc.stats(sessions: records).recentBackPain)
    }

    /// 明确的腰痛描述仍然要识别出来。
    func testExplicitBackPainNoteIsDetected() {
        let svc = WorkoutStatsService(calendar: calendar, now: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let records = [SessionRecord(date: yesterday, type: .strengthA, note: "下午腰有点酸")]
        XCTAssertTrue(svc.stats(sessions: records).recentBackPain)
    }

    /// bodyFeeling 走结构化比对,和备注关键词互不干扰。
    func testFeelingBackTightStillDetected() {
        XCTAssertTrue(BackPainMarkers.indicatesBackPain(feeling: "backTight"))
        XCTAssertFalse(BackPainMarkers.indicatesBackPain(feeling: "normal"))
        XCTAssertFalse(BackPainMarkers.indicatesBackPain(feeling: nil))
    }

    // MARK: - 连续训练天数

    func testConsecutiveActiveDaysCountsBackwards() {
        let svc = WorkoutStatsService(calendar: calendar, now: now)
        let records = (0..<3).map { offset in
            SessionRecord(date: calendar.date(byAdding: .day, value: -offset, to: now)!, type: .strengthA)
        }
        XCTAssertEqual(svc.stats(sessions: records).consecutiveActiveDays, 3)
    }

    /// 今天还没练时,从昨天往回数,不该把连续记录清零。
    func testConsecutiveActiveDaysIgnoresEmptyToday() {
        let svc = WorkoutStatsService(calendar: calendar, now: now)
        let records = (1...2).map { offset in
            SessionRecord(date: calendar.date(byAdding: .day, value: -offset, to: now)!, type: .strengthB)
        }
        XCTAssertEqual(svc.stats(sessions: records).consecutiveActiveDays, 2)
    }

    /// 中间断了一天就停。
    func testConsecutiveActiveDaysStopsAtGap() {
        let svc = WorkoutStatsService(calendar: calendar, now: now)
        let records = [
            SessionRecord(date: now, type: .strengthA),
            SessionRecord(date: calendar.date(byAdding: .day, value: -1, to: now)!, type: .strengthB),
            SessionRecord(date: calendar.date(byAdding: .day, value: -3, to: now)!, type: .strengthA)
        ]
        XCTAssertEqual(svc.stats(sessions: records).consecutiveActiveDays, 2)
    }

    // MARK: - Helpers
    private func baseStats(
        strengthCount: Int = 0, runCount: Int = 0, recoveryCount: Int = 0,
        strengthCountToday: Int = 0, recoveryCountToday: Int = 0,
        lastStrengthType: WorkoutType? = nil, daysSinceLastStrength: Int? = nil,
        consecutiveInactiveDays: Int = 0, consecutiveActiveDays: Int = 0,
        recentBackPain: Bool = false,
        hasActivityToday: Bool = false, hasRunToday: Bool = false
    ) -> WorkoutStats {
        WorkoutStats(
            strengthCount: strengthCount, runCount: runCount, recoveryCount: recoveryCount,
            strengthCountToday: strengthCountToday, recoveryCountToday: recoveryCountToday,
            lastStrengthType: lastStrengthType, daysSinceLastStrength: daysSinceLastStrength,
            consecutiveInactiveDays: consecutiveInactiveDays,
            consecutiveActiveDays: consecutiveActiveDays,
            hasActivityToday: hasActivityToday,
            hasRunToday: hasRunToday, recentBackPain: recentBackPain
        )
    }
}
