import Foundation

/// What the app suggests the user do right now.
public struct Recommendation: Equatable {
    public enum Action: Equatable, Sendable {
        case startStrength(WorkoutType)
        case logRun
        case recovery
        case minimal
        case rest
    }

    public let action: Action
    /// Stable key the app layer localizes into a headline.
    public let titleKey: String
    /// Stable key the app layer localizes into a subtitle.
    public let reasonKey: String
    /// Optional interpolation values for the app layer to format.
    public let interpolations: [String]

    public init(action: Action, titleKey: String, reasonKey: String, interpolations: [String] = []) {
        self.action = action
        self.titleKey = titleKey
        self.reasonKey = reasonKey
        self.interpolations = interpolations
    }
}

/// A pure, injectable decision function. No I/O, no SwiftData — takes the
/// stats snapshot + goal and returns a recommendation.
///
/// Rules are evaluated **in priority order**; the first match wins. The tests
/// pin each rule explicitly.
public struct RecommendationEngine {
    /// 连续训练多少天后建议休息(且本周目标已达成时)。
    public static let restAfterConsecutiveDays = 6
    /// 距上次力量训练超过这么多天,视为中断,从力量 A 重新开始而不是继续交替。
    public static let restartAfterIdleDays = 7

    public init() {}

    public func recommend(stats: WorkoutStats, goal: UserGoalValues, now: Date = .now) -> Recommendation {
        // 1. Recent back pain and not yet recovered today → recovery.
        if stats.recentBackPain && !stats.hasActivityToday {
            return Recommendation(action: .recovery, titleKey: "rec.back.title", reasonKey: "rec.back.reason")
        }

        // 2. Already ran today → recovery (no leg-loading strength).
        if stats.hasRunToday {
            return Recommendation(action: .recovery, titleKey: "rec.afterRun.title", reasonKey: "rec.afterRun.reason")
        }

        // 3. 过度训练保护:连续训练多天且本周目标已达成 → 休息。
        //    恢复本身是训练的一部分,没有这条规则系统永远不会让人停。
        if stats.consecutiveActiveDays >= Self.restAfterConsecutiveDays, weeklyGoalsMet(stats: stats, goal: goal) {
            return Recommendation(
                action: .rest,
                titleKey: "rec.rest.title",
                reasonKey: "rec.rest.reason",
                interpolations: ["\(stats.consecutiveActiveDays)"]
            )
        }

        // 4. Today's strength already met → run / recovery.
        if stats.strengthCountToday >= goal.dailyStrengthTarget {
            if stats.runCount < goal.weeklyRunTarget {
                let runShort = goal.weeklyRunTarget - stats.runCount
                return Recommendation(
                    action: .logRun,
                    titleKey: "rec.run.title",
                    reasonKey: "rec.run.reason",
                    interpolations: ["\(runShort)"]
                )
            }
            return Recommendation(action: .recovery, titleKey: "rec.maintain.title", reasonKey: "rec.maintain.reason")
        }

        // 5. Two+ days fully inactive → lower the bar to the 8-minute minimum.
        if stats.consecutiveInactiveDays >= 2 && !stats.hasActivityToday {
            return Recommendation(
                action: .minimal,
                titleKey: "rec.minimal.title",
                reasonKey: "rec.minimal.reason",
                interpolations: ["\(stats.consecutiveInactiveDays)"]
            )
        }

        // 6. Need strength today → A/B alternation, unless the gap is long
        //    enough that restarting from A is the safer ramp.
        let plan = nextPlan(stats: stats)

        let strengthShort = "\(stats.strengthCountToday)/\(goal.dailyStrengthTarget)"
        let planKey = plan == .strengthA ? "A" : "B"
        return Recommendation(
            action: .startStrength(plan),
            titleKey: "rec.strength.title",
            reasonKey: "rec.strength.reason",
            interpolations: [planKey, strengthShort]
        )
    }

    /// A/B 交替。中断超过 `restartAfterIdleDays` 天时回到 A 重新起步。
    private func nextPlan(stats: WorkoutStats) -> WorkoutType {
        if let idle = stats.daysSinceLastStrength, idle >= Self.restartAfterIdleDays {
            return .strengthA
        }
        switch stats.lastStrengthType {
        case .strengthA: return .strengthB
        case .strengthB: return .strengthA
        default:         return .strengthA
        }
    }

    private func weeklyGoalsMet(stats: WorkoutStats, goal: UserGoalValues) -> Bool {
        stats.strengthCount >= goal.weeklyStrengthTarget
            && stats.runCount >= goal.weeklyRunTarget
            && stats.recoveryCount >= goal.weeklyRecoveryTarget
    }
}

public extension RecommendationEngine {
    static let `default` = RecommendationEngine()
}
