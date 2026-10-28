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
    /// Localized headline for the popover.
    var localizedTitle: String {
        switch action {
        case .startStrength(let t):
            let name = t.localizedName
            return String(localized: "做 \(name),约 25 分钟")
        case .logRun:   return String(localized: "rec.run.title",       defaultValue: "本周力量已达标,可以跑步")
        case .recovery: return localized(key: titleKey, fallback: recoveryFallback)
        case .minimal:  return String(localized: "rec.minimal.title",   defaultValue: "做 8 分钟最低版")
        case .rest:     return localized(key: titleKey, fallback: "")
        }
    }

    /// Localized subtitle.
    var localizedReason: String {
        switch action {
        case .logRun:
            let runShort = interpolations.first ?? "1"
            return "本周力量已完成,跑步还差 \(runShort) 次。"
        case .startStrength:
            let strengthShort = interpolations.dropFirst().first ?? "0/3"
            return "本周力量 \(strengthShort) 次,今天补上。"
        case .minimal:
            let days = interpolations.first ?? "2"
            return "已经连续 \(days) 天没运动,先完成最低版,保持习惯。"
        case .rest:
            let days = interpolations.first ?? "6"
            let format = NSLocalizedString(
                "rec.rest.reason",
                value: "已经连续训练 %1$@ 天,本周目标都达成了。恢复也是训练的一部分。",
                comment: ""
            )
            return String(format: format, days)
        default:
            return localized(key: reasonKey, fallback: "")
        }
    }

    private var recoveryFallback: String {
        switch titleKey {
        case "rec.back.title":     return String(localized: "rec.back.title",     defaultValue: "先做腰背恢复")
        case "rec.afterRun.title": return String(localized: "rec.afterRun.title", defaultValue: "跑步后做腰背恢复")
        case "rec.maintain.title": return String(localized: "rec.maintain.title", defaultValue: "今天做腰背恢复或休息")
        default:                   return String(localized: "rec.back.title",     defaultValue: "先做腰背恢复")
        }
    }

    private func localized(key: String, fallback: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
