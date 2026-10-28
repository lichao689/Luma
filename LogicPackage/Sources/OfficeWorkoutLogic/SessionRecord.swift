import Foundation

/// Value-type representation of one logged activity.
///
/// The app's SwiftData `@Model` (`WorkoutSession`) maps into this type before
/// being handed to the logic layer. Keeping the logic layer free of SwiftData
/// makes the recommendation engine + stats fully testable as pure Swift.
public struct SessionRecord: Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let type: WorkoutType
    public let bodyFeeling: String?
    /// 自由文本备注。腰痛识别会扫描它,所以必须进逻辑层。
    public let note: String?

    public init(
        id: UUID = UUID(),
        date: Date,
        type: WorkoutType,
        bodyFeeling: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.bodyFeeling = bodyFeeling
        self.note = note
    }
}
