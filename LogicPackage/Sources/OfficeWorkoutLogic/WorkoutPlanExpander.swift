import Foundation

/// 跟练序列里的一步:某个动作的第几组,以及单侧动作的左右。
///
/// 这是纯数据,不含 UI 类型。App 层拿它去配 `Exercise` 和 `Prescription`,
/// 单测则可以直接数步数、查顺序。
public struct WorkoutPlanStep: Equatable, Identifiable, Sendable {
    public enum Side: String, Equatable, Sendable {
        case left, right
    }

    public let exerciseID: String
    /// 第几组(1 开始)。
    public let setIndex: Int
    /// 单侧动作才有值;双侧动作是 nil。
    public let side: Side?

    public var id: String { "\(exerciseID)#\(setIndex)#\(side?.rawValue ?? "-")" }

    public init(exerciseID: String, setIndex: Int, side: Side? = nil) {
        self.exerciseID = exerciseID
        self.setIndex = setIndex
        self.side = side
    }
}

/// 把「计划」展开成「逐组执行序列」。
///
/// 单侧动作(弓步、侧平板、鸟狗等)每一组会拆成左右两步 —— 跟练时它们是
/// 两次独立的计时,不能合并成一步,否则用户不知道该练哪边。
public enum WorkoutPlanExpander {

    public static func steps(for plan: WorkoutType) -> [WorkoutPlanStep] {
        if plan == .minimal {
            return PrescriptionLibrary.minimalExercises.flatMap { exercise -> [WorkoutPlanStep] in
                let rx = PrescriptionLibrary.minimalPrescription(exerciseID: exercise.id)
                return (1...rx.sets).map {
                    WorkoutPlanStep(exerciseID: exercise.id, setIndex: $0)
                }
            }
        }

        return ExerciseLibrary.exercises(for: plan).flatMap { exercise -> [WorkoutPlanStep] in
            let rx = PrescriptionLibrary.prescription(for: plan, exerciseID: exercise.id)
            return (1...rx.sets).flatMap { setIndex -> [WorkoutPlanStep] in
                guard rx.perSide else {
                    return [WorkoutPlanStep(exerciseID: exercise.id, setIndex: setIndex)]
                }
                return [
                    WorkoutPlanStep(exerciseID: exercise.id, setIndex: setIndex, side: .left),
                    WorkoutPlanStep(exerciseID: exercise.id, setIndex: setIndex, side: .right),
                ]
            }
        }
    }

    /// 这套计划总共多少步(用于进度显示)。
    public static func stepCount(for plan: WorkoutType) -> Int {
        steps(for: plan).count
    }

    /// 该计划里出现了哪些动作,按首次出现顺序去重。
    public static func exerciseIDs(for plan: WorkoutType) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for step in steps(for: plan) where !seen.contains(step.exerciseID) {
            seen.insert(step.exerciseID)
            ordered.append(step.exerciseID)
        }
        return ordered
    }
}
