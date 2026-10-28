import Foundation
import SwiftData
import OfficeWorkoutLogic

/// One logged activity (a workout, a run, a recovery session, or a rest day).
///
/// This is the SwiftData persistence layer; it maps into the logic layer's
/// `SessionRecord` value type before being analyzed.
@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var typeRaw: String
    var planCode: String?
    var durationMinutes: Int
    var completionRaw: String
    /// Subjective intensity, 1 (easy) ... 5 (hard).
    var intensity: Int
    var bodyFeeling: String?
    var notes: String?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        type: WorkoutType,
        planCode: String? = nil,
        durationMinutes: Int = 0,
        completion: CompletionLevel = .full,
        intensity: Int = 3,
        bodyFeeling: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.typeRaw = type.rawValue
        self.planCode = planCode
        self.durationMinutes = durationMinutes
        self.completionRaw = completion.rawValue
        self.intensity = max(1, min(5, intensity))
        self.bodyFeeling = bodyFeeling
        self.notes = notes
    }

    var type: WorkoutType {
        get { WorkoutType(rawValue: typeRaw) ?? .rest }
        set { typeRaw = newValue.rawValue }
    }

    var completion: CompletionLevel {
        get { CompletionLevel(rawValue: completionRaw) ?? .full }
        set { completionRaw = newValue.rawValue }
    }

    /// Bridge into the logic layer's value type.
    /// `note` 必须一起带过去 —— 腰痛识别会扫描备注文本。
    var asRecord: SessionRecord {
        SessionRecord(id: id, date: date, type: type, bodyFeeling: bodyFeeling, note: notes)
    }
}
