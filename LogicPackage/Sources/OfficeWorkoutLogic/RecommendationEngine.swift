import Foundation

/// What the app suggests the user do right now.
public struct Recommendation: Equatable, Sendable {
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

/// Transparent product defaults, not an individualized physiological model.
/// The duration × reported-effort value is only a scheduling signal and has no
/// clinical units. Callers may inject a different policy without changing data.
public struct RecommendationPolicy: Equatable, Sendable {
    public var strengthRecoveryHours: Double
    public var sameMuscleRecoveryHours: Double
    public var runRecoveryHours: Double
    public var hardSessionRecoveryHours: Double
    public var maximumConsecutiveActiveDays: Int
    public var loadThreshold24Hours: Double

    public init(strengthRecoveryHours: Double = 48, sameMuscleRecoveryHours: Double = 36,
                runRecoveryHours: Double = 24, hardSessionRecoveryHours: Double = 24,
                maximumConsecutiveActiveDays: Int = 6, loadThreshold24Hours: Double = 240) {
        self.strengthRecoveryHours = strengthRecoveryHours
        self.sameMuscleRecoveryHours = sameMuscleRecoveryHours
        self.runRecoveryHours = runRecoveryHours
        self.hardSessionRecoveryHours = hardSessionRecoveryHours
        self.maximumConsecutiveActiveDays = maximumConsecutiveActiveDays
        self.loadThreshold24Hours = loadThreshold24Hours
    }

    public static let `default` = RecommendationPolicy()
}

/// A pure, injectable scheduling policy. Discomfort and intentional rest take
/// precedence over targets. Partial work still affects recovery; it does not
/// silently become a completed goal. Daily targets apply on training days.
public struct RecommendationEngine {
    public static let restAfterConsecutiveDays = 6
    public static let restartAfterIdleDays = 7
    public let policy: RecommendationPolicy

    public init(policy: RecommendationPolicy = .default) { self.policy = policy }

    public func recommend(stats: WorkoutStats, goal: UserGoalValues, now: Date = .now) -> Recommendation {
        // A "recovery" label is not evidence an exercise is appropriate for pain.
        if stats.recentBackPain {
            return Recommendation(action: .rest, titleKey: "rec.pause.title", reasonKey: "rec.pause.pain")
        }
        if stats.hasIntentionalRestToday {
            return Recommendation(action: .rest, titleKey: "rec.rest.title", reasonKey: "rec.rest.planned")
        }
        if stats.consecutiveActiveDays >= max(1, policy.maximumConsecutiveActiveDays) {
            return Recommendation(
                action: .rest, titleKey: "rec.rest.title", reasonKey: "rec.rest.reason",
                interpolations: [String(stats.consecutiveActiveDays)]
            )
        }

        let recent = stats.recentActivities.filter { $0.date <= now }
        if recent.contains(where: {
            $0.bodyFeeling?.lowercased() == "fatigue"
                && now.timeIntervalSince($0.date) < max(0, policy.hardSessionRecoveryHours) * 3600
        }) {
            return Recommendation(action: .rest, titleKey: "rec.rest.title", reasonKey: "rec.rest.fatigue")
        }
        if recent.contains(where: { session in
            session.type.isActivity && (4...5).contains(session.intensity)
                && now.timeIntervalSince(session.date) < max(0, policy.hardSessionRecoveryHours) * 3600
        }) {
            return Recommendation(action: .rest, titleKey: "rec.rest.title", reasonKey: "rec.rest.highEffort")
        }
        let load = recent.filter { $0.type.isActivity && now.timeIntervalSince($0.date) < 24 * 3600 }
            .reduce(0.0) { total, session in
                guard (1...5).contains(session.intensity) else { return total }
                return total + Double(max(0, min(1440, session.durationMinutes))) * Double(session.intensity)
            }
        if load >= max(1, policy.loadThreshold24Hours) {
            return Recommendation(action: .rest, titleKey: "rec.rest.title", reasonKey: "rec.rest.recentLoad")
        }
        if recent.contains(where: {
            $0.bodyFeeling?.lowercased() == "legsore"
                && now.timeIntervalSince($0.date) < max(0, policy.sameMuscleRecoveryHours) * 3600
        }) {
            return recoveryOrRest(stats: stats, goal: goal, reason: "rec.recovery.soreness")
        }
        if stats.hasRunToday || recent.contains(where: {
            $0.type == .run && now.timeIntervalSince($0.date) < max(0, policy.runRecoveryHours) * 3600
        }) {
            return recoveryOrRest(stats: stats, goal: goal, reason: "rec.afterRun.reason", title: "rec.afterRun.title")
        }

        let strengthHours = stats.lastStrengthAt.map { max(0, now.timeIntervalSince($0) / 3600) }
            ?? stats.daysSinceLastStrength.map { Double(max(0, $0)) * 24 }
        if let strengthHours, strengthHours < max(0, policy.strengthRecoveryHours) {
            return recoveryOrRest(stats: stats, goal: goal, reason: "rec.recovery.spacing")
        }

        let plan = nextPlan(stats: stats)
        let nextMuscles = Set(ExerciseLibrary.exercises(for: plan).flatMap(\.targets))
        let repeatedMuscles = recent.contains { session in
            guard session.type == .minimal || session.type.countsAsStrength,
                  now.timeIntervalSince(session.date) < max(0, policy.sameMuscleRecoveryHours) * 3600 else { return false }
            let exercises: [Exercise]
            if !session.exerciseIDs.isEmpty {
                exercises = session.exerciseIDs.compactMap(ExerciseLibrary.exercise(id:))
            } else {
                exercises = session.type == .minimal ? PrescriptionLibrary.minimalExercises : ExerciseLibrary.exercises(for: session.type)
            }
            return !nextMuscles.isDisjoint(with: exercises.flatMap(\.targets))
        }
        if repeatedMuscles {
            return recoveryOrRest(stats: stats, goal: goal, reason: "rec.recovery.muscles")
        }

        if goal.dailyStrengthTarget <= 0 || goal.weeklyStrengthTarget <= 0
            || stats.strengthCount >= goal.weeklyStrengthTarget {
            if !stats.hasActivityToday && stats.runCount < goal.weeklyRunTarget {
                return Recommendation(action: .logRun, titleKey: "rec.run.title", reasonKey: "rec.run.reason",
                                      interpolations: [String(goal.weeklyRunTarget - stats.runCount)])
            }
            return recoveryOrRest(stats: stats, goal: goal, reason: "rec.recovery.weeklyMet")
        }
        if stats.strengthCountToday >= goal.dailyStrengthTarget {
            return recoveryOrRest(stats: stats, goal: goal, reason: "rec.recovery.dailyMet")
        }
        if stats.consecutiveInactiveDays >= 2 && !stats.hasActivityToday {
            return Recommendation(action: .minimal, titleKey: "rec.minimal.title", reasonKey: "rec.minimal.reason",
                                  interpolations: [String(stats.consecutiveInactiveDays)])
        }
        return Recommendation(
            action: .startStrength(plan), titleKey: "rec.strength.title", reasonKey: "rec.strength.weeklyReason",
            interpolations: [plan == .strengthA ? "A" : "B", "\(stats.strengthCount)/\(goal.weeklyStrengthTarget)"]
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

    private func recoveryOrRest(stats: WorkoutStats, goal: UserGoalValues, reason: String,
                                title: String = "rec.maintain.title") -> Recommendation {
        if stats.recoveryCountToday < goal.dailyRecoveryTarget && stats.recoveryCount < goal.weeklyRecoveryTarget {
            return Recommendation(action: .recovery, titleKey: title, reasonKey: reason)
        }
        return Recommendation(action: .rest, titleKey: "rec.rest.title", reasonKey: "rec.rest.targetsMet")
    }
}

public extension RecommendationEngine {
    static let `default` = RecommendationEngine()
}
