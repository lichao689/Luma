import Foundation
import OfficeWorkoutLogic

/// App-layer localization for logic-layer types. The logic package returns
/// stable keys + interpolation values; this turns them into display strings
/// using the app's `Localizable.strings`.

extension WorkoutType {
    /// Localized display name, e.g. "力量 A" / "Strength A".
    var localizedName: String {
        switch self {
        case .strengthA: return String(localized: "workout.type.strengthA", defaultValue: "力量 A")
        case .strengthB: return String(localized: "workout.type.strengthB", defaultValue: "力量 B")
        case .run:       return String(localized: "workout.type.run",       defaultValue: "跑步")
        case .recovery:  return String(localized: "workout.type.recovery",  defaultValue: "腰背恢复")
        case .minimal:   return String(localized: "workout.type.minimal",   defaultValue: "8 分钟最低版")
        case .rest:      return String(localized: "workout.type.rest",      defaultValue: "休息")
        }
    }

    /// SF Symbol used in lists and menus.
    var systemImage: String {
        switch self {
        case .strengthA, .strengthB: return "figure.strengthtraining.traditional"
        case .run:                   return "figure.run"
        case .recovery:              return "figure.cooldown"
        case .minimal:               return "timer"
        case .rest:                  return "moon"
        }
    }
}

extension CompletionLevel {
    var localizedName: String {
        switch self {
        case .full:    return String(localized: "completion.full",    defaultValue: "完整")
        case .partial: return String(localized: "completion.partial", defaultValue: "部分")
        case .minimal: return String(localized: "completion.minimal", defaultValue: "最低版")
        }
    }
}

extension ReminderMode {
    var localizedName: String {
        switch self {
        case .light:    return String(localized: "reminder.mode.light",    defaultValue: "轻提醒")
        case .standard: return String(localized: "reminder.mode.standard", defaultValue: "标准提醒")
        case .strict:   return String(localized: "reminder.mode.strict",   defaultValue: "强监督")
        }
    }
}

extension MuscleGroup {
    /// Localized display name, e.g. "腿" / "背部".
    var localizedName: String {
        switch self {
        case .legs:      return String(localized: "muscle.legs",      defaultValue: "腿")
        case .back:      return String(localized: "muscle.back",      defaultValue: "背部")
        case .chest:     return String(localized: "muscle.chest",     defaultValue: "胸")
        case .core:      return String(localized: "muscle.core",      defaultValue: "核心")
        case .shoulders: return String(localized: "muscle.shoulders", defaultValue: "肩")
        case .glutes:    return String(localized: "muscle.glutes",    defaultValue: "臀部")
        }
    }
}

extension Exercise {
    /// Localized display name of the exercise.
    var localizedName: String {
        // Fallback to the key itself when no string is defined; this keeps the
        // UI readable while localization strings are being authored.
        NSLocalizedString(nameKey, value: id, comment: "")
    }

    /// Localized "primary muscle" label.
    var localizedPrimaryMuscle: String {
        NSLocalizedString(primaryMuscleKey, value: primaryMuscleKey, comment: "")
    }

    /// Cue lines as an array, split from the semicolon-delimited localized
    /// string. Each element is a single actionable cue.
    var localizedCues: [String] {
        splitList(cuesKey)
    }

    /// Common-mistake lines as an array.
    var localizedMistakes: [String] {
        splitList(commonMistakesKey)
    }

    /// What the static illustration is trying to emphasize.
    var localizedVisualFocus: [String] {
        splitList(visualFocusKey)
    }

    /// Easier versions for low-energy or painful days.
    var localizedEasierVariations: [String] {
        splitList(easierVariationKey)
    }

    /// Stop conditions for discomfort or unsafe compensation.
    var localizedStopConditions: [String] {
        splitList(stopConditionKey)
    }

    /// Localized labels for every targeted muscle group.
    var localizedTargetMuscles: [String] {
        targets.map { $0.localizedName }
    }

    /// Splits a semicolon-delimited localized string into trimmed lines.
    private func splitList(_ key: String) -> [String] {
        let raw = NSLocalizedString(key, value: "", comment: "")
        return raw
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

extension Recommendation {
    var localizedTitle: String { formatted(titleKey) }
    var localizedReason: String { formatted(reasonKey) }

    private func formatted(_ key: String) -> String {
        let format = NSLocalizedString(key, comment: "")
        guard !interpolations.isEmpty else { return format }
        return String(format: format, arguments: interpolations.map { $0 as CVarArg })
    }
}
