import Foundation

/// An editable, portable plan. Duration choices are volume budgets, not promises
/// about how quickly a particular person must finish.
public struct TrainingPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var baseType: WorkoutType
    public var exercises: [PlannedExercise]
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, baseType: WorkoutType,
                exercises: [PlannedExercise], updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.baseType = baseType
        self.exercises = exercises
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 120 else { throw TrainingPlanError.invalidName }
        guard [.strengthA, .strengthB, .recovery, .minimal].contains(baseType),
              updatedAt.timeIntervalSince1970.isFinite,
              !exercises.isEmpty, exercises.count <= 15 else { throw TrainingPlanError.invalidPlan }
        var seen: Set<String> = []
        for item in exercises {
            guard seen.insert(item.exerciseID).inserted else { throw TrainingPlanError.duplicateExercise(item.exerciseID) }
            try item.validate()
        }
    }

    /// Estimate includes work at a generic 3 seconds/rep, 10 seconds setup per
    /// step, and programmed rests. Real execution can take longer or shorter.
    public var estimatedMinutes: Int {
        guard (try? validate()) != nil else { return 0 }
        let steps = exercises.reduce(0) { $0 + $1.sets * ($1.perSide ? 2 : 1) }
        guard steps > 0 else { return 0 }
        let seconds = exercises.reduce(0) { result, item in
            let count = item.sets * (item.perSide ? 2 : 1)
            let work = item.isHold ? item.reps : item.reps * 3
            return result + count * (work + item.restSeconds + 10)
        } - (exercises.last?.restSeconds ?? 0)
        return max(1, Int(ceil(Double(seconds) / 60)))
    }

    public func executionSteps() throws -> [ExecutionStep] {
        try validate()
        return exercises.flatMap { item in
            (1...item.sets).flatMap { index -> [ExecutionStep] in
                let sides: [WorkoutPlanStep.Side?] = item.perSide ? [.left, .right] : [nil]
                return sides.map { ExecutionStep(exercise: item, setIndex: index, side: $0) }
            }
        }
    }

    /// Replacement retains volume but adopts the replacement's units and side
    /// semantics, so replacing an exercise never turns seconds into repetitions.
    public func replacing(exerciseID: String, with replacementID: String,
                          avoiding excludedIDs: Set<String> = [], now: Date = .now) throws -> TrainingPlan {
        guard let index = exercises.firstIndex(where: { $0.exerciseID == exerciseID }),
              ExerciseAlternatives.candidates(for: exerciseID, avoiding: excludedIDs).contains(where: { $0.id == replacementID }),
              !exercises.contains(where: { $0.exerciseID == replacementID }) else {
            throw TrainingPlanError.invalidReplacement
        }
        var result = self
        let old = exercises[index]
        let rx = PrescriptionLibrary.prescription(for: baseType, exerciseID: replacementID)
        result.exercises[index] = PlannedExercise(exerciseID: replacementID, sets: old.sets,
            reps: min(old.reps, rx.repsHigh), isHold: ExerciseAlternatives.isHold(replacementID),
            perSide: ExerciseAlternatives.isPerSide(replacementID), restSeconds: old.restSeconds)
        result.updatedAt = now
        try result.validate()
        return result
    }
}

public struct PlannedExercise: Codable, Equatable, Identifiable, Sendable {
    public var exerciseID: String
    public var sets: Int
    /// Target repetitions; seconds for a hold.
    public var reps: Int
    public var isHold: Bool
    public var perSide: Bool
    public var restSeconds: Int
    public var id: String { exerciseID }

    public init(exerciseID: String, sets: Int, reps: Int, isHold: Bool = false,
                perSide: Bool = false, restSeconds: Int) {
        self.exerciseID = exerciseID
        self.sets = sets
        self.reps = reps
        self.isHold = isHold
        self.perSide = perSide
        self.restSeconds = restSeconds
    }

    public func validate() throws {
        guard ExerciseLibrary.exercise(id: exerciseID) != nil else { throw TrainingPlanError.unknownExercise(exerciseID) }
        guard (1...10).contains(sets), (1...(isHold ? 600 : 100)).contains(reps),
              (0...600).contains(restSeconds) else { throw TrainingPlanError.invalidDose(exerciseID) }
        guard isHold == ExerciseAlternatives.isHold(exerciseID),
              perSide == ExerciseAlternatives.isPerSide(exerciseID) else { throw TrainingPlanError.invalidUnits(exerciseID) }
    }
}

public enum TrainingPlanError: Error, Equatable, LocalizedError {
    case invalidName, invalidPlan, duplicateExercise(String), unknownExercise(String)
    case invalidDose(String), invalidUnits(String), invalidReplacement
    public var errorDescription: String? {
        switch self {
        case .invalidName: return "计划名称不能为空，最多 120 个字符。"
        case .invalidPlan: return "训练计划需要 1–15 个有效动作。"
        case .duplicateExercise(let id): return "计划中有重复动作：\(id)。"
        case .unknownExercise(let id): return "未知动作：\(id)。"
        case .invalidDose(let id): return "动作剂量超出可接受范围：\(id)。"
        case .invalidUnits(let id): return "动作的次数/计时或左右侧设置不一致：\(id)。"
        case .invalidReplacement: return "请选择相同动作模式、未被排除且没有重复的替代动作。"
        }
    }
}

public enum ExerciseAlternatives {
    private static let groups: [[String]] = [
        ["gobletSquat", "reverseLunge"],
        ["romanianDeadlift", "gluteBridge"],
        ["pushUp", "shoulderPress"],
        ["bentOverDumbbellRow", "proneWRaise"],
        ["plank", "sidePlank"],
        ["deadBug", "birdDog", "pelvicTilt"],
        ["catCow"], ["hipFlexorStretch"]
    ]

    public static func candidates(for exerciseID: String, avoiding excludedIDs: Set<String> = []) -> [Exercise] {
        guard let group = groups.first(where: { $0.contains(exerciseID) }) else { return [] }
        return group.filter { $0 != exerciseID && !excludedIDs.contains($0) }.compactMap(ExerciseLibrary.exercise(id:))
    }

    public static func isHold(_ exerciseID: String) -> Bool {
        ["plank", "sidePlank", "hipFlexorStretch"].contains(exerciseID)
    }

    public static func isPerSide(_ exerciseID: String) -> Bool {
        ["reverseLunge", "sidePlank", "deadBug", "birdDog", "hipFlexorStretch"].contains(exerciseID)
    }
}

public enum TrainingPlanFactory {
    public static let timeOptions = [8, 15, 25]

    public static func make(for type: WorkoutType, minutes: Int = 25, now: Date = .now) -> TrainingPlan {
        let budget = timeOptions.contains(minutes) ? minutes : 25
        let source = type == .minimal ? PrescriptionLibrary.minimalExercises : ExerciseLibrary.exercises(for: type)
        var items = source.map { exercise -> PlannedExercise in
            let rx = type == .minimal
                ? PrescriptionLibrary.minimalPrescription(exerciseID: exercise.id)
                : PrescriptionLibrary.prescription(for: type, exerciseID: exercise.id)
            return PlannedExercise(exerciseID: exercise.id, sets: rx.sets,
                reps: budget < 25 ? rx.repsLow : rx.repsHigh,
                isHold: rx.isHold, perSide: rx.perSide, restSeconds: rx.restSeconds)
        }
        var plan = TrainingPlan(name: "\(type.rawValue) · \(budget) min", baseType: type, exercises: items, updatedAt: now)
        // Reduce rounds before dropping exercises. Preserve a mix of movement
        // patterns rather than filling the whole time budget with the first move.
        while plan.estimatedMinutes > budget {
            if let index = items.indices.reversed().max(by: { items[$0].sets < items[$1].sets }), items[index].sets > 1 {
                items[index].sets -= 1
            } else if items.count > 1 {
                items.removeLast()
            } else {
                break
            }
            plan.exercises = items
        }
        return plan
    }
}

public struct ExecutionStep: Equatable, Identifiable, Sendable {
    public let exercise: PlannedExercise
    public let setIndex: Int
    public let side: WorkoutPlanStep.Side?
    public var exerciseID: String { exercise.exerciseID }
    public var id: String { "\(exerciseID)#\(setIndex)#\(side?.rawValue ?? "-")" }
    public init(exercise: PlannedExercise, setIndex: Int, side: WorkoutPlanStep.Side? = nil) {
        self.exercise = exercise
        self.setIndex = setIndex
        self.side = side
    }
}
