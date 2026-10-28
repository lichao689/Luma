import Foundation

/// 一次训练里单个动作的执行处方。
///
/// 与 `Exercise` 分开,是因为同一个动作在不同计划里剂量不同:臀桥在力量 A 里
/// 是 3 组 12-15 次,在腰背恢复里只做 1 组,不追求力竭。所以处方按
/// `(计划, 动作)` 组合查询,而不是挂在 `Exercise` 上。
///
/// 数值全部结构化(组数/次数/秒数/休息),这样跟练模式的计时器可以直接用,
/// 展示文案由 App 层按语言拼装。
public struct Prescription: Equatable, Sendable {
    /// 组数。
    public let sets: Int
    /// 每组次数下限;`isHold` 为 true 时表示保持秒数下限。
    public let repsLow: Int
    /// 每组次数上限;`isHold` 为 true 时表示保持秒数上限。
    public let repsHigh: Int
    /// true 表示按秒保持(平板支撑、侧平板、髋屈肌拉伸)。
    public let isHold: Bool
    /// true 表示左右各做一组(弓步、侧平板、鸟狗等)。
    public let perSide: Bool
    /// 组间休息秒数。0 表示不需要正式休息。
    public let restSeconds: Int
    /// 预计耗时(分钟),用于在列表里估算整套训练时长。
    public let estimatedMinutes: Int
    /// 节奏文案的本地化 key,如 "prescription.tempo.gobletSquat"。
    public let tempoKey: String

    public init(
        sets: Int,
        repsLow: Int,
        repsHigh: Int,
        isHold: Bool = false,
        perSide: Bool = false,
        restSeconds: Int,
        estimatedMinutes: Int,
        tempoKey: String
    ) {
        self.sets = sets
        self.repsLow = repsLow
        self.repsHigh = repsHigh
        self.isHold = isHold
        self.perSide = perSide
        self.restSeconds = restSeconds
        self.estimatedMinutes = estimatedMinutes
        self.tempoKey = tempoKey
    }

    /// 一整套的总组数(计左右各一组的动作时翻倍)。
    public var totalSets: Int {
        sets * (perSide ? 2 : 1)
    }

    /// 单组目标的展示值:次数区间或秒数区间。
    public var repRangeText: String {
        repsLow == repsHigh ? "\(repsLow)" : "\(repsLow)-\(repsHigh)"
    }
}

/// 处方库:按 `(计划, 动作 id)` 查剂量。
///
/// 数据集中在这里,而不是散落在视图层,好处是跟练模式、动作详情、单测
/// 读的是同一份来源,改剂量只需要动一处。
public enum PrescriptionLibrary {

    /// 最低版(8 分钟)的动作组合:推、蹲、臀各一个,覆盖全身主要模式。
    public static let minimalExercises: [Exercise] = [
        ExerciseLibrary.gobletSquat,
        ExerciseLibrary.pushUp,
        ExerciseLibrary.gluteBridge,
    ]

    /// 查一个动作在某计划下的处方。找不到时回退到通用剂量。
    public static func prescription(for plan: WorkoutType, exerciseID: String) -> Prescription {
        table["\(plan.rawValue):\(exerciseID)"] ?? fallback(for: plan)
    }

    /// 最低版处方:固定 2 组,组间 45 秒,总量控制在 8 分钟内。
    public static func minimalPrescription(exerciseID: String) -> Prescription {
        Prescription(
            sets: 2,
            repsLow: 8,
            repsHigh: 12,
            restSeconds: 45,
            estimatedMinutes: 3,
            tempoKey: "prescription.tempo.\(exerciseID)"
        )
    }

    /// 某个计划全部动作的处方,顺序与 `ExerciseLibrary.exercises(for:)` 一致。
    public static func prescriptions(for plan: WorkoutType) -> [Prescription] {
        ExerciseLibrary.exercises(for: plan).map { prescription(for: plan, exerciseID: $0.id) }
    }

    /// 估算整套训练时长(分钟)。
    public static func estimatedMinutes(for plan: WorkoutType) -> Int {
        prescriptions(for: plan).reduce(0) { $0 + $1.estimatedMinutes }
    }

    // MARK: - 数据

    private static func strength(
        sets: Int, repsLow: Int, repsHigh: Int,
        perSide: Bool = false, rest: Int, minutes: Int, tempoFor id: String
    ) -> Prescription {
        Prescription(
            sets: sets, repsLow: repsLow, repsHigh: repsHigh,
            perSide: perSide, restSeconds: rest, estimatedMinutes: minutes,
            tempoKey: "prescription.tempo.\(id)"
        )
    }

    private static func hold(
        sets: Int, secondsLow: Int, secondsHigh: Int,
        perSide: Bool = false, rest: Int, minutes: Int, tempoFor id: String
    ) -> Prescription {
        Prescription(
            sets: sets, repsLow: secondsLow, repsHigh: secondsHigh,
            isHold: true, perSide: perSide, restSeconds: rest, estimatedMinutes: minutes,
            tempoKey: "prescription.tempo.\(id)"
        )
    }

    private static func recovery(
        sets: Int, repsLow: Int, repsHigh: Int,
        isHold: Bool = false, perSide: Bool = false,
        rest: Int, minutes: Int, tempoFor id: String
    ) -> Prescription {
        Prescription(
            sets: sets, repsLow: repsLow, repsHigh: repsHigh,
            isHold: isHold, perSide: perSide, restSeconds: rest,
            estimatedMinutes: minutes, tempoKey: "prescription.tempo.\(id)"
        )
    }

    private static let table: [String: Prescription] = {
        var t: [String: Prescription] = [:]

        // 力量 A:下肢 + 推 + 核心
        t["strengthA:gobletSquat"] = strength(sets: 3, repsLow: 8, repsHigh: 12, rest: 60, minutes: 5, tempoFor: "gobletSquat")
        t["strengthA:pushUp"] = strength(sets: 3, repsLow: 8, repsHigh: 15, rest: 60, minutes: 4, tempoFor: "pushUp")
        t["strengthA:shoulderPress"] = strength(sets: 3, repsLow: 8, repsHigh: 12, rest: 60, minutes: 4, tempoFor: "shoulderPress")
        t["strengthA:gluteBridge"] = strength(sets: 3, repsLow: 12, repsHigh: 15, rest: 45, minutes: 4, tempoFor: "gluteBridge")
        t["strengthA:plank"] = hold(sets: 3, secondsLow: 30, secondsHigh: 60, rest: 45, minutes: 4, tempoFor: "plank")

        // 力量 B:后链 + 拉 + 单腿 + 抗侧屈
        t["strengthB:romanianDeadlift"] = strength(sets: 3, repsLow: 8, repsHigh: 10, rest: 75, minutes: 5, tempoFor: "romanianDeadlift")
        t["strengthB:bentOverDumbbellRow"] = strength(sets: 3, repsLow: 10, repsHigh: 12, rest: 60, minutes: 4, tempoFor: "bentOverDumbbellRow")
        t["strengthB:reverseLunge"] = strength(sets: 3, repsLow: 8, repsHigh: 10, perSide: true, rest: 75, minutes: 6, tempoFor: "reverseLunge")
        t["strengthB:proneWRaise"] = strength(sets: 3, repsLow: 10, repsHigh: 12, rest: 40, minutes: 3, tempoFor: "proneWRaise")
        t["strengthB:sidePlank"] = hold(sets: 2, secondsLow: 20, secondsHigh: 40, perSide: true, rest: 40, minutes: 4, tempoFor: "sidePlank")

        // 腰背恢复:轻、慢、不追力竭
        t["recovery:catCow"] = recovery(sets: 1, repsLow: 6, repsHigh: 8, rest: 0, minutes: 2, tempoFor: "catCow")
        t["recovery:pelvicTilt"] = recovery(sets: 2, repsLow: 8, repsHigh: 10, rest: 30, minutes: 2, tempoFor: "pelvicTilt")
        t["recovery:deadBug"] = recovery(sets: 1, repsLow: 5, repsHigh: 6, perSide: true, rest: 30, minutes: 2, tempoFor: "deadBug")
        t["recovery:birdDog"] = recovery(sets: 1, repsLow: 5, repsHigh: 6, perSide: true, rest: 30, minutes: 2, tempoFor: "birdDog")
        t["recovery:gluteBridge"] = recovery(sets: 1, repsLow: 10, repsHigh: 12, rest: 30, minutes: 1, tempoFor: "gluteBridge")
        t["recovery:hipFlexorStretch"] = recovery(sets: 1, repsLow: 30, repsHigh: 30, isHold: true, perSide: true, rest: 0, minutes: 2, tempoFor: "hipFlexorStretch")

        return t
    }()

    /// 表里没有的组合(新增动作但还没配处方)用这套保底剂量。
    private static func fallback(for plan: WorkoutType) -> Prescription {
        Prescription(
            sets: plan == .recovery ? 1 : 3,
            repsLow: 8,
            repsHigh: 12,
            restSeconds: 60,
            estimatedMinutes: 4,
            tempoKey: "prescription.tempo.default"
        )
    }
}
