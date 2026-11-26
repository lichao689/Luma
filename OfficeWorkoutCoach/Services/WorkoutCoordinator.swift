import Foundation
import Combine
import OfficeWorkoutLogic

/// One workout for the whole app. Closing its window pauses the session and
/// preserves the plan, entered values, and completed sets until it is reopened.
@MainActor
final class WorkoutCoordinator: ObservableObject {
    @Published var draft: TrainingPlan = WorkoutCoordinator.builtIn(.strengthA, minutes: 15)
    @Published private(set) var execution: WorkoutExecution?
    @Published private(set) var saved = false
    @Published var repetitionsText = ""
    @Published var weightText = ""
    @Published var intensity = 3
    @Published var bodyFeeling: BodyFeeling = .normal
    @Published var notes = ""
    @Published var errorMessage: String?
    private var sessionID = UUID()

    var hasWorkout: Bool { execution != nil && !saved }
    var hasUnsavedWork: Bool { hasWorkout && execution?.startedAt != nil }

    static func builtIn(_ type: WorkoutType, minutes: Int) -> TrainingPlan {
        var plan = TrainingPlanFactory.make(for: type, minutes: minutes)
        plan.name = "\(type.localizedName) · \(minutes) min"
        return plan
    }

    /// An existing session always wins over another launch request.
    func prepare(_ type: WorkoutType, minutes: Int? = nil) {
        guard !hasWorkout else { return }
        reset()
        draft = Self.builtIn(type, minutes: minutes ?? (type == .minimal || type == .recovery ? 8 : 25))
    }

    func begin() {
        do {
            execution = try WorkoutExecution(plan: draft)
            sessionID = UUID()
            saved = false
            repetitionsText = ""
            weightText = ""
            updateReminderState()
        } catch { errorMessage = error.localizedDescription }
    }

    func startSet() { mutate { $0.start() } }
    func pause() { mutate { $0.pause() } }
    func resume() { mutate { $0.resume() } }
    func skipRest() { mutate { $0.skipRest() } }
    func addRest() { mutate { $0.addRest(seconds: 30) } }
    func finishEarly() { mutate { $0.finish() } }

    func tick(at now: Date) {
        let prior = execution?.currentStep?.id
        mutate { $0.update(at: now) }
        if execution?.currentStep?.id != prior { repetitionsText = ""; weightText = "" }
    }

    func completeSet() {
        guard var run = execution, let step = run.currentStep else { return }
        do {
            let actual: Int
            if step.exercise.isHold {
                actual = run.elapsedSeconds()
            } else {
                guard let value = Int(repetitionsText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw WorkoutExecutionError.invalidRepetitions
                }
                actual = value
            }
            let text = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
            let weight: Double?
            if text.isEmpty { weight = nil }
            else {
                guard let value = Double(text.replacingOccurrences(of: ",", with: ".")) else {
                    throw WorkoutExecutionError.invalidWeight
                }
                weight = value
            }
            try run.completeSet(reps: actual, weightKg: weight)
            execution = run
            repetitionsText = ""
            weightText = ""
            updateReminderState()
        } catch { errorMessage = error.localizedDescription }
    }

    func save(using store: WorkoutStore) {
        guard let run = execution, run.phase == .finished, !run.completedSets.isEmpty, !saved else { return }
        do {
            _ = try store.saveWorkout(
                id: sessionID, type: run.plan.baseType, planCode: run.plan.id.uuidString,
                durationMinutes: max(1, Int(ceil(Double(run.durationSeconds()) / 60))),
                completion: run.completion, intensity: intensity,
                bodyFeeling: bodyFeeling.rawValue, notes: notes.isEmpty ? nil : notes,
                date: run.startedAt ?? .now, plannedExerciseIDs: run.plan.exercises.map(\.exerciseID), sets: run.completedSets
            )
            saved = true
            updateReminderState()
        } catch { errorMessage = error.localizedDescription }
    }

    func reset() {
        execution = nil
        saved = false
        sessionID = UUID()
        repetitionsText = ""
        weightText = ""
        intensity = 3
        bodyFeeling = .normal
        notes = ""
        errorMessage = nil
        updateReminderState()
    }

    private func mutate(_ action: (inout WorkoutExecution) -> Void) {
        guard var run = execution, !saved else { return }
        action(&run)
        execution = run
        updateReminderState()
    }

    private func updateReminderState() {
        NotificationManager.shared.isWorkoutInProgress = hasWorkout
            && execution?.phase != .paused && execution?.phase != .finished
    }
}
