import XCTest
@testable import OfficeWorkoutLogic

/// 钉住跟练序列的展开规则。
///
/// 这层逻辑原来写在视图里,没法测;挪到逻辑层之后,「单侧动作要拆左右」
/// 「组数和处方一致」这类容易回归的点就能被守住。
final class WorkoutPlanExpanderTests: XCTestCase {

    func testStrengthAStepsMatchPrescriptionSets() {
        let steps = WorkoutPlanExpander.steps(for: .strengthA)
        let expected = ExerciseLibrary.planA.reduce(0) { sum, exercise in
            sum + PrescriptionLibrary.prescription(for: .strengthA, exerciseID: exercise.id).totalSets
        }
        XCTAssertEqual(steps.count, expected)
    }

    /// 力量 A 里全是双侧动作,不应该出现 left/right。
    func testStrengthAHasNoSideSplit() {
        let steps = WorkoutPlanExpander.steps(for: .strengthA)
        XCTAssertTrue(steps.allSatisfy { $0.side == nil })
    }

    /// 反向弓步是单侧动作,每组必须拆成左右两步。
    func testReverseLungeSplitsIntoSides() {
        let steps = WorkoutPlanExpander.steps(for: .strengthB).filter { $0.exerciseID == "reverseLunge" }
        let rx = PrescriptionLibrary.prescription(for: .strengthB, exerciseID: "reverseLunge")
        XCTAssertEqual(steps.count, rx.sets * 2)
        for setIndex in 1...rx.sets {
            let inSet = steps.filter { $0.setIndex == setIndex }
            XCTAssertEqual(inSet.count, 2)
            XCTAssertEqual(Set(inSet.compactMap(\.side)), [.left, .right])
        }
    }

    /// 侧平板同样是单侧动作。
    func testSidePlankSplitsIntoSides() {
        let steps = WorkoutPlanExpander.steps(for: .strengthB).filter { $0.exerciseID == "sidePlank" }
        XCTAssertTrue(steps.contains { $0.side == .left })
        XCTAssertTrue(steps.contains { $0.side == .right })
    }

    /// 步骤顺序必须跟计划里的动作顺序一致,否则跟练会乱跳。
    func testStepOrderFollowsPlanOrder() {
        let steps = WorkoutPlanExpander.steps(for: .strengthA)
        let firstSeen = WorkoutPlanExpander.exerciseIDs(for: .strengthA)
        XCTAssertEqual(firstSeen, ExerciseLibrary.planA.map(\.id))

        // 第一步属于计划里的第一个动作
        XCTAssertEqual(steps.first?.exerciseID, ExerciseLibrary.planA.first?.id)
        // 最后一步属于最后一个动作
        XCTAssertEqual(steps.last?.exerciseID, ExerciseLibrary.planA.last?.id)
    }

    /// 最低版:3 个动作 × 2 组 = 6 步,不能拖成 20 分钟。
    func testMinimalPlanExpandsToSixSteps() {
        let steps = WorkoutPlanExpander.steps(for: .minimal)
        XCTAssertEqual(steps.count, 6)
        XCTAssertEqual(WorkoutPlanExpander.exerciseIDs(for: .minimal).count, 3)
    }

    /// 腰背恢复里既有双侧动作(猫牛式)也有单侧动作(死虫、鸟狗、髋屈肌拉伸),
    /// 只拆该拆的,不能一刀切。
    func testRecoverySplitsOnlySingleSidedMoves() {
        let steps = WorkoutPlanExpander.steps(for: .recovery)
        XCTAssertFalse(steps.isEmpty)

        let deadBug = steps.filter { $0.exerciseID == "deadBug" }
        XCTAssertTrue(deadBug.contains { $0.side == .left })
        XCTAssertTrue(deadBug.contains { $0.side == .right })

        let catCow = steps.filter { $0.exerciseID == "catCow" }
        XCTAssertFalse(catCow.isEmpty)
        XCTAssertTrue(catCow.allSatisfy { $0.side == nil })
    }

    /// 空计划(跑步/休息)不应该产生任何步骤。
    func testNonExercisePlansAreEmpty() {
        XCTAssertTrue(WorkoutPlanExpander.steps(for: .run).isEmpty)
        XCTAssertTrue(WorkoutPlanExpander.steps(for: .rest).isEmpty)
    }

    /// 每一步的 exerciseID 都必须在动作库里查得到。
    func testEveryStepReferencesAKnownExercise() {
        for plan in [WorkoutType.strengthA, .strengthB, .recovery, .minimal] {
            for step in WorkoutPlanExpander.steps(for: plan) {
                XCTAssertNotNil(
                    ExerciseLibrary.exercise(id: step.exerciseID),
                    "\(plan.rawValue) 引用了不存在的动作 \(step.exerciseID)"
                )
            }
        }
    }
}
