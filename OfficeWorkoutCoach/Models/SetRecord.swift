import Foundation
import SwiftData

/// 一次训练里某一组的实际完成情况。
///
/// 单独建表而不是塞进 `WorkoutSession`,是因为一次力量训练有 15 组左右,
/// 而且以后要按动作维度查历史(「深蹲上次做到多少」),独立表才好查。
///
/// 用 `sessionID` 做弱关联而不是 SwiftData 关系:删除记录时按 id 批量清理
/// 更简单,也避免关系删除规则的隐式行为。
@Model
final class SetRecord {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    /// 对应 `ExerciseLibrary` 里的动作 id。
    var exerciseID: String
    /// 第几组(1 开始)。
    var setIndex: Int
    /// 实际完成的次数;保持类动作这里是秒数。
    var reps: Int
    /// 重量(公斤)。办公室哑铃可以留空,表示只记次数。
    var weightKg: Double?
    var recordedAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        exerciseID: String,
        setIndex: Int,
        reps: Int,
        weightKg: Double? = nil,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.setIndex = setIndex
        self.reps = reps
        self.weightKg = weightKg
        self.recordedAt = recordedAt
    }
}

/// 某个动作最近一次的完成情况,用于在跟练时提示「上次做到多少」。
struct LastPerformance: Equatable {
    let reps: Int
    let weightKg: Double?
    let date: Date
}
