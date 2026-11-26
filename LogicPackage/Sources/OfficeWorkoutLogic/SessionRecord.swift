import Foundation

/// Value-type representation of one logged activity.
///
/// The app's SwiftData `@Model` (`WorkoutSession`) maps into this type before
/// being handed to the logic layer. Keeping the logic layer free of SwiftData
/// makes the recommendation engine + stats fully testable as pure Swift.
public struct SessionRecord: Equatable, Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let type: WorkoutType
    public let bodyFeeling: String?
    /// 自由文本备注。腰痛识别会扫描它,所以必须进逻辑层。
    public let note: String?
    public let durationMinutes: Int
    public let completion: CompletionLevel
    /// User-reported effort on the existing 1...5 scale; 0 is unknown (e.g. a
    /// HealthKit import), never evidence that a workout was easy.
    public let intensity: Int
    /// Actual performed exercises. Older manual records may have no detail.
    public let exerciseIDs: [String]

    public init(
        id: UUID = UUID(),
        date: Date,
        type: WorkoutType,
        bodyFeeling: String? = nil,
        note: String? = nil,
        durationMinutes: Int = 0,
        completion: CompletionLevel = .full,
        intensity: Int = 3,
        exerciseIDs: [String] = []
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.bodyFeeling = bodyFeeling
        self.note = note
        self.durationMinutes = durationMinutes
        self.completion = completion
        self.intensity = intensity
        self.exerciseIDs = exerciseIDs
    }
}
