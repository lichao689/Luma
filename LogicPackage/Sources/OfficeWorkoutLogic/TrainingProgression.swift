import Foundation

/// All performed sets for an exercise in one session, not its last/best set.
/// Include incomplete sessions so they interrupt a sequence of successful work.
public struct ExercisePerformance: Equatable, Sendable {
    public let sessionID: UUID
    public let date: Date
    public let completion: CompletionLevel
    public let intensity: Int
    public let hasDiscomfort: Bool
    public let sets: [ExecutedSet]

    public init(sessionID: UUID, date: Date, completion: CompletionLevel,
                intensity: Int, hasDiscomfort: Bool, sets: [ExecutedSet]) {
        self.sessionID = sessionID
        self.date = date
        self.completion = completion
        self.intensity = intensity
        self.hasDiscomfort = hasDiscomfort
        self.sets = sets
    }
}

/// These are configurable suggestion limits, not a personalized prescription.
public struct ProgressionPolicy: Equatable, Sendable {
    public var minimumSessionGapHours: Double
    public var maximumHistoryAgeDays: Double
    public var maximumIncreaseFraction: Double
    public var weightIncrementKg: Double
    public var reductionFraction: Double

    public init(minimumSessionGapHours: Double = 24, maximumHistoryAgeDays: Double = 30,
                maximumIncreaseFraction: Double = 0.05, weightIncrementKg: Double = 0.5,
                reductionFraction: Double = 0.10) {
        self.minimumSessionGapHours = minimumSessionGapHours
        self.maximumHistoryAgeDays = maximumHistoryAgeDays
        self.maximumIncreaseFraction = maximumIncreaseFraction
        self.weightIncrementKg = weightIncrementKg
        self.reductionFraction = reductionFraction
    }

    public static let `default` = ProgressionPolicy()
}

public struct ProgressionSuggestion: Equatable, Sendable {
    public enum Change: String, Equatable, Sendable { case maintain, increaseWeight, reduceLoad }
    public let change: Change
    public let weightKg: Double?
    public let targetReps: Int?
    public let reasonKey: String
    /// The caller presents an accept action. Computing this value never changes
    /// a plan, a weight input, or a stored record.
    public var requiresAcceptance: Bool { change != .maintain }

    public init(change: Change, weightKg: Double? = nil, targetReps: Int? = nil, reasonKey: String) {
        self.change = change
        self.weightKg = weightKg
        self.targetReps = targetReps
        self.reasonKey = reasonKey
    }
}

public enum TrainingProgression {
    public static func suggestion(for exercise: PlannedExercise, history: [ExercisePerformance],
                                  now: Date = .now, policy: ProgressionPolicy = .default) -> ProgressionSuggestion {
        guard (try? exercise.validate()) != nil else { return maintain("progression.insufficient") }
        let sorted = history.filter { $0.date <= now }.sorted { $0.date > $1.date }
        guard let latest = sorted.first,
              now.timeIntervalSince(latest.date) <= max(0, policy.maximumHistoryAgeDays) * 86_400 else {
            return maintain("progression.insufficient")
        }
        // Pain does not merely lower a load and imply that continuing is safe.
        if latest.hasDiscomfort { return maintain("progression.pausePain") }
        if latest.completion != .full || (4...5).contains(latest.intensity) {
            let matching = latest.sets.filter { $0.exerciseID == exercise.exerciseID }
            let currentWeight = uniformWeight(matching)
            if let currentWeight, currentWeight > 0 {
                let fraction = min(0.20, max(0, policy.reductionFraction))
                let reduced = (currentWeight * (1 - fraction) * 100).rounded(.down) / 100
                if reduced < currentWeight {
                    return ProgressionSuggestion(change: .reduceLoad, weightKg: reduced,
                        reasonKey: latest.completion == .full ? "progression.highEffort" : "progression.incomplete")
                }
            }
            return maintain(latest.completion == .full ? "progression.highEffort" : "progression.incomplete")
        }
        guard sorted.count >= 2 else { return maintain("progression.insufficient") }
        let previous = sorted[1]
        // Duplicate copies or two saves during one workout cannot count as two
        // independent successful sessions. Old data does not trigger a jump.
        guard latest.sessionID != previous.sessionID,
              latest.date.timeIntervalSince(previous.date) >= max(0, policy.minimumSessionGapHours) * 3600,
              now.timeIntervalSince(previous.date) <= max(0, policy.maximumHistoryAgeDays) * 86_400,
              previous.completion == .full, !previous.hasDiscomfort,
              (1...3).contains(latest.intensity), (1...3).contains(previous.intensity) else {
            return maintain("progression.insufficient")
        }
        guard allSetsReachedTarget(exercise, in: latest), allSetsReachedTarget(exercise, in: previous) else {
            return maintain("progression.keepBuilding")
        }
        // Holds/body-weight work do not acquire an invented external load.
        guard !exercise.isHold,
              let latestWeight = uniformWeight(latest.sets.filter { $0.exerciseID == exercise.exerciseID }),
              let previousWeight = uniformWeight(previous.sets.filter { $0.exerciseID == exercise.exerciseID }),
              latestWeight > 0, abs(latestWeight - previousWeight) < 0.0001 else {
            return maintain("progression.keepBuilding")
        }
        let increment = policy.weightIncrementKg
        let fraction = min(0.10, max(0, policy.maximumIncreaseFraction))
        guard increment.isFinite, increment > 0, fraction.isFinite,
              increment <= latestWeight * fraction + 0.0001, latestWeight + increment <= 500 else {
            return maintain("progression.smallerIncrement")
        }
        return ProgressionSuggestion(change: .increaseWeight, weightKg: latestWeight + increment,
                                     reasonKey: "progression.ready")
    }

    private static func maintain(_ key: String) -> ProgressionSuggestion {
        ProgressionSuggestion(change: .maintain, reasonKey: key)
    }

    private static func allSetsReachedTarget(_ exercise: PlannedExercise, in performance: ExercisePerformance) -> Bool {
        let sets = performance.sets.filter { $0.exerciseID == exercise.exerciseID }
        let expectedSides: [WorkoutPlanStep.Side?] = exercise.perSide ? [.left, .right] : [nil]
        let expectedIDs = Set((1...exercise.sets).flatMap { setIndex in
            expectedSides.map { "\(exercise.exerciseID)#\(setIndex)#\($0?.rawValue ?? "-")" }
        })
        guard sets.count == expectedIDs.count, Set(sets.map(\.id)) == expectedIDs else { return false }
        // A short plan's low-end target is not the catalogue's upper bound.
        // Custom targets above that bound must also be met in every set.
        let cataloguePlan: WorkoutType = ExerciseLibrary.planA.contains(where: { $0.id == exercise.exerciseID })
            ? .strengthA : (ExerciseLibrary.planB.contains(where: { $0.id == exercise.exerciseID }) ? .strengthB : .recovery)
        let upperBound = max(exercise.reps, PrescriptionLibrary.prescription(for: cataloguePlan, exerciseID: exercise.exerciseID).repsHigh)
        return sets.allSatisfy {
            $0.reps >= upperBound && $0.reps <= (exercise.isHold ? 3600 : 1000) && $0.isHold == exercise.isHold
        }
    }

    private static func uniformWeight(_ sets: [ExecutedSet]) -> Double? {
        guard let first = sets.first?.weightKg, first.isFinite, (0...500).contains(first),
              sets.allSatisfy({ set in
                  guard let weight = set.weightKg, weight.isFinite else { return false }
                  return abs(first - weight) < 0.0001
              }) else { return nil }
        return first
    }
}
