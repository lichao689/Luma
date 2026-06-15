import Foundation

/// 目标肌群。rawValue 仅用于逻辑判断,不做展示(展示文案在 App 层)。
public enum MuscleGroup: String, Sendable, CaseIterable {
    case legs
    case back
    case chest
    case core
    case shoulders
    case glutes
}

/// 力量动作库中的一个动作。
///
/// 设计上与 `WorkoutType` / `Recommendation` 一致:逻辑层只持稳定的 key,
/// 所有展示文案(名字、要领、常见错误、目标肌群)由 App 层的
/// `UILocalization` 用 `Localizable.strings` 翻译。这样本类型可在无 UI、
/// 无 SwiftData 的库里被单测,文案改动不需要动逻辑层。
public struct Exercise: Identifiable, Equatable, Hashable, Sendable {
    /// 稳定标识,如 "gobletSquat"。
    public let id: String
    /// 名字文案 key,如 "ex.gobletSquat.name"。
    public let nameKey: String
    /// 目标肌群(可多个)。
    public let targets: [MuscleGroup]
    /// 主要目标肌群的文案 key,如 "muscle.legs"。
    public let primaryMuscleKey: String
    /// 要领文案 key。App 层会把分号分隔的多条拆成列表展示。
    public let cuesKey: String
    /// 组数×次数,如 "3×8-12"。已自带格式,无需本地化。
    public let setsReps: String
    /// 常见错误文案 key(分号分隔多条)。
    public let commonMistakesKey: String
    /// 图上重点文案 key(分号分隔多条),用于解释静态图中的箭头/对齐线。
    public let visualFocusKey: String
    /// 降低难度版本文案 key(分号分隔多条)。
    public let easierVariationKey: String
    /// 不适时停止条件文案 key(分号分隔多条)。
    public let stopConditionKey: String
    /// 媒体资源名(不含扩展名),指向 bundle 内的图片文件。nil 表示无图。
    public let imageAssetName: String?
    /// 媒体资源名(不含扩展名),指向 bundle 内的视频文件。优先于图片。
    public let videoAssetName: String?

    public init(
        id: String,
        nameKey: String,
        targets: [MuscleGroup],
        primaryMuscleKey: String,
        cuesKey: String,
        setsReps: String,
        commonMistakesKey: String,
        visualFocusKey: String? = nil,
        easierVariationKey: String? = nil,
        stopConditionKey: String? = nil,
        imageAssetName: String? = nil,
        videoAssetName: String? = nil
    ) {
        self.id = id
        self.nameKey = nameKey
        self.targets = targets
        self.primaryMuscleKey = primaryMuscleKey
        self.cuesKey = cuesKey
        self.setsReps = setsReps
        self.commonMistakesKey = commonMistakesKey
        self.visualFocusKey = visualFocusKey ?? "ex.\(id).focus"
        self.easierVariationKey = easierVariationKey ?? "ex.\(id).easier"
        self.stopConditionKey = stopConditionKey ?? "ex.\(id).stop"
        self.imageAssetName = imageAssetName ?? videoAssetName ?? id
        self.videoAssetName = videoAssetName
    }
}

/// 静态动作库 + 力量 A/B 分组查询。
///
/// 数据用硬编码常量,避免引入 JSON 资源文件、改 `Package.swift` 或改
/// Xcode 工程配置。新增动作只需在此处追加一条 `Exercise(...)`,再在
/// `planA` / `planB` 里引用即可。文案 key 对应 App 层 `Localizable.strings`
/// 的条目;缺失的 key 会回退到默认英文 fallback,不会崩溃。
public enum ExerciseLibrary {

    // MARK: - 动作定义

    /// 高脚杯深蹲(办公室哑铃环境)
    public static let gobletSquat = Exercise(
        id: "gobletSquat",
        nameKey: "ex.gobletSquat.name",
        targets: [.legs, .glutes, .core],
        primaryMuscleKey: "muscle.legs",
        cuesKey: "ex.gobletSquat.cues",
        setsReps: "3×8-12",
        commonMistakesKey: "ex.gobletSquat.mistakes",
        imageAssetName: "gobletSquat"
    )

    /// 罗马尼亚硬拉(RDL,哑铃版,不依赖凳椅)
    public static let romanianDeadlift = Exercise(
        id: "romanianDeadlift",
        nameKey: "ex.romanianDeadlift.name",
        targets: [.legs, .glutes, .back],
        primaryMuscleKey: "muscle.legs",
        cuesKey: "ex.romanianDeadlift.cues",
        setsReps: "3×8-10",
        commonMistakesKey: "ex.romanianDeadlift.mistakes",
        imageAssetName: "romanianDeadlift"
    )

    /// 俯卧撑
    public static let pushUp = Exercise(
        id: "pushUp",
        nameKey: "ex.pushUp.name",
        targets: [.chest, .shoulders, .core],
        primaryMuscleKey: "muscle.chest",
        cuesKey: "ex.pushUp.cues",
        setsReps: "3×8-15",
        commonMistakesKey: "ex.pushUp.mistakes",
        imageAssetName: "pushUp"
    )

    /// 臀桥
    public static let gluteBridge = Exercise(
        id: "gluteBridge",
        nameKey: "ex.gluteBridge.name",
        targets: [.glutes, .legs, .core],
        primaryMuscleKey: "muscle.glutes",
        cuesKey: "ex.gluteBridge.cues",
        setsReps: "3×12-15",
        commonMistakesKey: "ex.gluteBridge.mistakes",
        imageAssetName: "gluteBridge"
    )

    /// 鸟狗式(核心/腰背恢复)
    public static let birdDog = Exercise(
        id: "birdDog",
        nameKey: "ex.birdDog.name",
        targets: [.core, .back],
        primaryMuscleKey: "muscle.core",
        cuesKey: "ex.birdDog.cues",
        setsReps: "3×8/侧",
        commonMistakesKey: "ex.birdDog.mistakes",
        imageAssetName: "birdDog"
    )

    /// 死虫式(核心)
    public static let deadBug = Exercise(
        id: "deadBug",
        nameKey: "ex.deadBug.name",
        targets: [.core],
        primaryMuscleKey: "muscle.core",
        cuesKey: "ex.deadBug.cues",
        setsReps: "3×8/侧",
        commonMistakesKey: "ex.deadBug.mistakes",
        imageAssetName: "deadBug"
    )

    /// 站姿哑铃肩推(不依赖椅凳)
    public static let shoulderPress = Exercise(
        id: "shoulderPress",
        nameKey: "ex.shoulderPress.name",
        targets: [.shoulders],
        primaryMuscleKey: "muscle.shoulders",
        cuesKey: "ex.shoulderPress.cues",
        setsReps: "3×8-12",
        commonMistakesKey: "ex.shoulderPress.mistakes",
        imageAssetName: "shoulderPress"
    )

    /// 站姿俯身哑铃划船(无凳椅版)
    public static let bentOverDumbbellRow = Exercise(
        id: "bentOverDumbbellRow",
        nameKey: "ex.bentOverDumbbellRow.name",
        targets: [.back],
        primaryMuscleKey: "muscle.back",
        cuesKey: "ex.bentOverDumbbellRow.cues",
        setsReps: "3×10-12",
        commonMistakesKey: "ex.bentOverDumbbellRow.mistakes",
        imageAssetName: "bentOverDumbbellRow"
    )

    /// 平板支撑
    public static let plank = Exercise(
        id: "plank",
        nameKey: "ex.plank.name",
        targets: [.core],
        primaryMuscleKey: "muscle.core",
        cuesKey: "ex.plank.cues",
        setsReps: "3×30-60s",
        commonMistakesKey: "ex.plank.mistakes",
        imageAssetName: "plank"
    )

    /// 反向弓步(不依赖凳椅)
    public static let reverseLunge = Exercise(
        id: "reverseLunge",
        nameKey: "ex.reverseLunge.name",
        targets: [.legs, .glutes, .core],
        primaryMuscleKey: "muscle.legs",
        cuesKey: "ex.reverseLunge.cues",
        setsReps: "3×8-10/侧",
        commonMistakesKey: "ex.reverseLunge.mistakes",
        imageAssetName: "reverseLunge"
    )

    /// 俯卧 W 提拉(无器械背部激活)
    public static let proneWRaise = Exercise(
        id: "proneWRaise",
        nameKey: "ex.proneWRaise.name",
        targets: [.back, .shoulders],
        primaryMuscleKey: "muscle.back",
        cuesKey: "ex.proneWRaise.cues",
        setsReps: "3×10-12",
        commonMistakesKey: "ex.proneWRaise.mistakes",
        imageAssetName: "proneWRaise"
    )

    /// 侧平板支撑
    public static let sidePlank = Exercise(
        id: "sidePlank",
        nameKey: "ex.sidePlank.name",
        targets: [.core, .shoulders],
        primaryMuscleKey: "muscle.core",
        cuesKey: "ex.sidePlank.cues",
        setsReps: "2×20-40s/侧",
        commonMistakesKey: "ex.sidePlank.mistakes",
        imageAssetName: "sidePlank"
    )

    /// 猫牛式(温和脊柱活动)
    public static let catCow = Exercise(
        id: "catCow",
        nameKey: "ex.catCow.name",
        targets: [.back, .core],
        primaryMuscleKey: "muscle.back",
        cuesKey: "ex.catCow.cues",
        setsReps: "6-8 次慢循环",
        commonMistakesKey: "ex.catCow.mistakes",
        imageAssetName: "catCow"
    )

    /// 骨盆后倾(腰背中立控制)
    public static let pelvicTilt = Exercise(
        id: "pelvicTilt",
        nameKey: "ex.pelvicTilt.name",
        targets: [.core, .back],
        primaryMuscleKey: "muscle.core",
        cuesKey: "ex.pelvicTilt.cues",
        setsReps: "2×8-10",
        commonMistakesKey: "ex.pelvicTilt.mistakes",
        imageAssetName: "pelvicTilt"
    )

    /// 髋屈肌拉伸(久坐髋前侧放松)
    public static let hipFlexorStretch = Exercise(
        id: "hipFlexorStretch",
        nameKey: "ex.hipFlexorStretch.name",
        targets: [.legs, .glutes, .core],
        primaryMuscleKey: "muscle.legs",
        cuesKey: "ex.hipFlexorStretch.cues",
        setsReps: "2×30s/侧",
        commonMistakesKey: "ex.hipFlexorStretch.mistakes",
        imageAssetName: "hipFlexorStretch"
    )

    // MARK: - 计划分组(对应 WorkoutType)

    /// 力量 A: 办公室哑铃 + 瑜伽垫环境下的下肢 + 推 + 核心。
    public static let planA: [Exercise] = [
        gobletSquat,
        pushUp,
        shoulderPress,
        gluteBridge,
        plank,
    ]

    /// 力量 B: 办公室哑铃 + 瑜伽垫环境下的后链 + 拉 + 单腿 + 抗侧屈核心。
    public static let planB: [Exercise] = [
        romanianDeadlift,
        bentOverDumbbellRow,
        reverseLunge,
        proneWRaise,
        sidePlank,
    ]

    /// 腰背恢复用到的轻量动作(恢复/久坐提醒时参考)。
    public static let recoverySet: [Exercise] = [
        catCow,
        pelvicTilt,
        deadBug,
        birdDog,
        gluteBridge,
        hipFlexorStretch,
    ]

    /// 全部动作(库的“目录”视图用)。
    public static let all: [Exercise] = [
        gobletSquat,
        pushUp,
        shoulderPress,
        gluteBridge,
        plank,
        romanianDeadlift,
        bentOverDumbbellRow,
        reverseLunge,
        proneWRaise,
        sidePlank,
        catCow,
        pelvicTilt,
        deadBug,
        birdDog,
        hipFlexorStretch,
    ]

    // MARK: - 查询

    /// 按 `WorkoutType` 取对应的动作分组。
    /// 力量 A/B 各返回一组;恢复返回腰背恢复组;其余类型返回空数组。
    public static func exercises(for type: WorkoutType) -> [Exercise] {
        switch type {
        case .strengthA: return planA
        case .strengthB: return planB
        case .recovery:  return recoverySet
        case .run, .minimal, .rest: return []
        }
    }

    /// 按 id 查单个动作;找不到返回 nil。
    public static func exercise(id: String) -> Exercise? {
        all.first { $0.id == id }
    }
}
