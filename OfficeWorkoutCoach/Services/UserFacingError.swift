import Foundation
import OfficeWorkoutLogic

/// Localize domain failures at the app boundary. The shared logic retains typed
/// errors and diagnostic values; system errors keep their own localized text.
func userFacingError(_ error: Error) -> String {
    switch error {
    case let error as TrainingPlanError:
        switch error {
        case .invalidName:
            return errorText("error.plan.invalidName", "Enter a plan name of up to 120 characters.")
        case .invalidPlan:
            return errorText("error.plan.invalidPlan", "A workout plan needs 1–15 valid exercises.")
        case .duplicateExercise(let id):
            return errorText("error.plan.duplicateExercise", "The plan includes this exercise more than once: %@.", exerciseName(id))
        case .unknownExercise(let id):
            return errorText("error.plan.unknownExercise", "Unknown exercise: %@.", id)
        case .invalidDose(let id):
            return errorText("error.plan.invalidDose", "Sets, reps, or rest are out of range for %@.", exerciseName(id))
        case .invalidUnits(let id):
            return errorText("error.plan.invalidUnits", "%@ has mismatched repetition, timing, or side settings.", exerciseName(id))
        case .invalidReplacement:
            return errorText("error.plan.invalidReplacement", "Choose an available exercise with a matching movement pattern that is not already in the plan.")
        }

    case let error as WorkoutExecutionError:
        switch error {
        case .notWorking:
            return errorText("error.workout.notWorking", "Start the current set first.")
        case .invalidRepetitions:
            return errorText("error.workout.invalidRepetitions", "Enter a valid number of completed reps or seconds.")
        case .invalidWeight:
            return errorText("error.workout.invalidWeight", "Enter a weight from 0 to 500 kg, or leave it empty.")
        }

    case let error as BackupError:
        switch error {
        case .unsupportedFormat:
            return errorText("error.backup.unsupportedFormat", "This backup format or version is not supported.")
        case .tooLarge:
            return errorText("error.backup.tooLarge", "The backup exceeds the supported file size or record count.")
        case .invalid(let detail):
            return errorText("error.backup.invalid", "The records could not be validated.\nDetails: %@", detail)
        case .conflict(let detail):
            return errorText("error.backup.conflict", "Conflicting records prevented this operation.\nDetails: %@", detail)
        }

    case let error as HealthBridgeError:
        switch error {
        case .invalidDocument(let detail):
            return errorText("error.health.invalidDocument", "The health data file could not be validated.\nDetails: %@", detail)
        case .fileTooLarge:
            return errorText("error.health.fileTooLarge", "The health data file cannot exceed %d MiB.", HealthBridgeCodec.maximumBytes / 1_024 / 1_024)
        }

    default:
        return error.localizedDescription
    }
}

private func errorText(_ key: String, _ fallback: String, _ arguments: CVarArg...) -> String {
    let text = NSLocalizedString(key, value: fallback, comment: "User-facing domain error")
    return arguments.isEmpty ? text : String(format: text, locale: Locale.current, arguments: arguments)
}

private func exerciseName(_ id: String) -> String {
    guard let exercise = ExerciseLibrary.exercise(id: id) else { return id }
    return NSLocalizedString(exercise.nameKey, value: id, comment: "Exercise name in an error")
}
