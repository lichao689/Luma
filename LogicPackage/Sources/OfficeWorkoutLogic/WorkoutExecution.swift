import Foundation

/// Portable record of a performed set. `reps` is seconds only when `isHold`.
/// A unilateral step keeps its side through persistence and export.
public struct ExecutedSet: Codable, Equatable, Identifiable, Sendable {
    public let exerciseID: String
    public let setIndex: Int
    public let side: WorkoutPlanStep.Side?
    public let reps: Int
    public let isHold: Bool
    public let weightKg: Double?
    public let completedAt: Date
    public var id: String { "\(exerciseID)#\(setIndex)#\(side?.rawValue ?? "-")" }

    public init(exerciseID: String, setIndex: Int, side: WorkoutPlanStep.Side? = nil,
                reps: Int, isHold: Bool, weightKg: Double? = nil, completedAt: Date = .now) {
        self.exerciseID = exerciseID
        self.setIndex = setIndex
        self.side = side
        self.reps = reps
        self.isHold = isHold
        self.weightKg = weightKg
        self.completedAt = completedAt
    }
}

public enum WorkoutExecutionError: Error, Equatable, LocalizedError {
    case notWorking, invalidRepetitions, invalidWeight
    public var errorDescription: String? {
        switch self {
        case .notWorking: return "请先开始当前组。"
        case .invalidRepetitions: return "请输入有效的完成次数或秒数。"
        case .invalidWeight: return "重量须为 0–500 kg 的有限数值，也可以留空。"
        }
    }
}

/// Deterministic workout state machine. UI ticks only ask for a new snapshot;
/// elapsed time comes from supplied dates, so a delayed tick does not slow time.
/// A finished hold can advance through its rest, but never starts the next set.
public struct WorkoutExecution: Sendable {
    public enum Phase: String, Equatable, Sendable { case ready, working, resting, paused, finished }
    public let plan: TrainingPlan
    public let steps: [ExecutionStep]
    public private(set) var phase: Phase = .ready
    public private(set) var index = 0
    public private(set) var completedSets: [ExecutedSet] = []
    public private(set) var startedAt: Date?
    public private(set) var endedAt: Date?
    private var phaseStartedAt: Date?
    private var accumulatedWork: TimeInterval = 0
    private var restDuration: TimeInterval = 0
    private var suspendedPhase: Phase?
    private var pausedAt: Date?
    private var totalPaused: TimeInterval = 0

    public init(plan: TrainingPlan) throws {
        self.plan = plan
        self.steps = try plan.executionSteps()
    }

    public var currentStep: ExecutionStep? { steps.indices.contains(index) ? steps[index] : nil }
    public var completion: CompletionLevel { completedSets.count == steps.count ? .full : .partial }

    public mutating func start(at now: Date = .now) {
        guard phase == .ready, currentStep != nil else { return }
        if startedAt == nil { startedAt = now }
        phase = .working
        phaseStartedAt = now
        accumulatedWork = 0
    }

    public func elapsedSeconds(at now: Date = .now) -> Int {
        let running = phase == .working ? max(0, now.timeIntervalSince(phaseStartedAt ?? now)) : 0
        return max(0, Int(accumulatedWork + running))
    }

    public func restRemaining(at now: Date = .now) -> Int {
        let running = phase == .resting ? max(0, now.timeIntervalSince(phaseStartedAt ?? now)) : 0
        return max(0, Int(ceil(restDuration - running)))
    }

    /// Elapsed training session time, excluding explicit pauses and preview time.
    public func durationSeconds(at now: Date = .now) -> Int {
        guard let startedAt else { return 0 }
        let end = endedAt ?? now
        let openPause = pausedAt.map { max(0, end.timeIntervalSince($0)) } ?? 0
        return max(0, Int(end.timeIntervalSince(startedAt) - totalPaused - openPause))
    }

    public mutating func pause(at now: Date = .now) {
        update(at: now)
        guard phase == .working || phase == .resting || phase == .ready else { return }
        if phase == .working { accumulatedWork += max(0, now.timeIntervalSince(phaseStartedAt ?? now)) }
        if phase == .resting { restDuration = max(0, restDuration - max(0, now.timeIntervalSince(phaseStartedAt ?? now))) }
        suspendedPhase = phase
        phase = .paused
        phaseStartedAt = nil
        pausedAt = now
    }

    public mutating func resume(at now: Date = .now) {
        guard phase == .paused, let prior = suspendedPhase else { return }
        if let pausedAt, startedAt != nil { totalPaused += max(0, now.timeIntervalSince(pausedAt)) }
        phase = prior
        phaseStartedAt = now
        suspendedPhase = nil
        pausedAt = nil
    }

    public mutating func update(at now: Date = .now) {
        if phase == .working, let step = currentStep, step.exercise.isHold,
           elapsedSeconds(at: now) >= step.exercise.reps {
            let remaining = max(0, Double(step.exercise.reps) - accumulatedWork)
            let completedAt = (phaseStartedAt ?? now).addingTimeInterval(remaining)
            // A hold is recorded at its target deadline, not at a delayed UI tick.
            try? completeSet(reps: step.exercise.reps, weightKg: nil, at: completedAt)
        }
        if phase == .resting, restRemaining(at: now) == 0 { advance() }
    }

    public mutating func completeSet(reps: Int, weightKg: Double?, at now: Date = .now) throws {
        guard phase == .working, let step = currentStep else { throw WorkoutExecutionError.notWorking }
        guard (1...(step.exercise.isHold ? 3600 : 1000)).contains(reps) else { throw WorkoutExecutionError.invalidRepetitions }
        if let weightKg, (!weightKg.isFinite || !(0...500).contains(weightKg)) { throw WorkoutExecutionError.invalidWeight }
        completedSets.append(ExecutedSet(exerciseID: step.exerciseID, setIndex: step.setIndex,
            side: step.side, reps: reps, isHold: step.exercise.isHold, weightKg: weightKg, completedAt: now))
        accumulatedWork = 0
        if index == steps.count - 1 {
            finish(at: now)
        } else if step.exercise.restSeconds > 0 {
            phase = .resting
            phaseStartedAt = now
            restDuration = Double(step.exercise.restSeconds)
        } else {
            advance()
        }
    }

    public mutating func skipRest(at now: Date = .now) {
        guard phase == .resting else { return }
        advance()
    }

    public mutating func addRest(seconds: Int = 30, at now: Date = .now) {
        guard phase == .resting, seconds > 0 else { return }
        restDuration = Double(min(1800, restRemaining(at: now) + seconds))
        phaseStartedAt = now
    }

    /// Finishing preserves completed sets. An incomplete current set is not
    /// fabricated; users can complete it with their actual value first.
    public mutating func finish(at now: Date = .now) {
        guard phase != .finished else { return }
        if let pausedAt, startedAt != nil { totalPaused += max(0, now.timeIntervalSince(pausedAt)) }
        pausedAt = nil
        suspendedPhase = nil
        phase = .finished
        endedAt = now
        phaseStartedAt = nil
    }

    private mutating func advance() {
        index += 1
        phase = .ready
        phaseStartedAt = nil
        accumulatedWork = 0
        restDuration = 0
    }
}
