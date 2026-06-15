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

        // 3. Weekly strength already met → run / recovery / rest.
        if stats.strengthCount >= goal.weeklyStrengthTarget {
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

        // 4. Two+ days fully inactive → lower the bar to the 8-minute minimum.
        if stats.consecutiveInactiveDays >= 2 && !stats.hasActivityToday {
            return Recommendation(
                action: .minimal,
                titleKey: "rec.minimal.title",
                reasonKey: "rec.minimal.reason",
                interpolations: ["\(stats.consecutiveInactiveDays)"]
            )
        }

        // 5. Need strength today → A/B alternation.
        let plan: WorkoutType
        switch stats.lastStrengthType {
        case .strengthA: plan = .strengthB
        case .strengthB: plan = .strengthA
        default:         plan = .strengthA
        }

        let strengthShort = "\(stats.strengthCount)/\(goal.weeklyStrengthTarget)"
        let planKey = plan == .strengthA ? "A" : "B"
        return Recommendation(
            action: .startStrength(plan),
            titleKey: "rec.strength.title",
            reasonKey: "rec.strength.reason",
            interpolations: [planKey, strengthShort]
        )
    }
}

public extension RecommendationEngine {
    static let `default` = RecommendationEngine()
}
