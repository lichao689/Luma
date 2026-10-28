import XCTest
@testable import OfficeWorkoutLogic

/// 钉住处方库的结构不变量。
///
/// 这些断言的目的不是校验具体数字(那会一改剂量就红),而是保证
/// **跟练模式能安全依赖这份数据**:每个动作都有处方、数值在合理区间、
/// 整套时长符合宣传口径。
final class PrescriptionLibraryTests: XCTestCase {

    // MARK: - 覆盖度

    func testEveryPlannedExerciseHasExplicitPrescription() {
        for plan in [WorkoutType.strengthA, .strengthB, .recovery] {
            for exercise in ExerciseLibrary.exercises(for: plan) {
                let rx = PrescriptionLibrary.prescription(for: plan, exerciseID: exercise.id)
                // 回退处方的 tempoKey 是 "prescription.tempo.default";
                // 命中这条说明表里漏了配置。
                XCTAssertNotEqual(
                    rx.tempoKey, "prescription.tempo.default",
                    "\(plan.rawValue)/\(exercise.id) 没有配置处方,落到了回退值"
                )
            }
        }
    }

    // MARK: - 数值合理性

    func testPrescriptionsAreStructurallyValid() {
        for plan in [WorkoutType.strengthA, .strengthB, .recovery] {
            for exercise in ExerciseLibrary.exercises(for: plan) {
                let rx = PrescriptionLibrary.prescription(for: plan, exerciseID: exercise.id)
                XCTAssertGreaterThan(rx.sets, 0, "\(exercise.id) 组数必须为正")
                XCTAssertGreaterThan(rx.repsLow, 0, "\(exercise.id) 次数下限必须为正")
                XCTAssertLessThanOrEqual(rx.repsLow, rx.repsHigh, "\(exercise.id) 次数区间反了")
                XCTAssertGreaterThanOrEqual(rx.restSeconds, 0)
                XCTAssertLessThanOrEqual(rx.restSeconds, 180, "\(exercise.id) 组间休息过长")
                XCTAssertGreaterThan(rx.estimatedMinutes, 0)
            }
        }
    }

    /// 保持类动作必须标 isHold,否则跟练计时会按"次数"处理。
    func testHoldExercisesAreMarked() {
        let plank = PrescriptionLibrary.prescription(for: .strengthA, exerciseID: "plank")
        XCTAssertTrue(plank.isHold)

        let sidePlank = PrescriptionLibrary.prescription(for: .strengthB, exerciseID: "sidePlank")
        XCTAssertTrue(sidePlank.isHold)
        XCTAssertTrue(sidePlank.perSide)

        let squat = PrescriptionLibrary.prescription(for: .strengthA, exerciseID: "gobletSquat")
        XCTAssertFalse(squat.isHold)
    }

    /// 同一个动作在不同计划里的剂量必须不同(臀桥是最典型的例子)。
    func testSameExerciseDiffersAcrossPlans() {
        let inStrength = PrescriptionLibrary.prescription(for: .strengthA, exerciseID: "gluteBridge")
        let inRecovery = PrescriptionLibrary.prescription(for: .recovery, exerciseID: "gluteBridge")
        XCTAssertGreaterThan(inStrength.sets, inRecovery.sets)
        XCTAssertGreaterThanOrEqual(inStrength.repsHigh, inRecovery.repsHigh)
    }

    // MARK: - 单侧动作

    func testPerSideDoublesTotalSets() {
        let lunge = PrescriptionLibrary.prescription(for: .strengthB, exerciseID: "reverseLunge")
        XCTAssertTrue(lunge.perSide)
        XCTAssertEqual(lunge.totalSets, lunge.sets * 2)
    }

    // MARK: - 时长口径

    /// 力量 A/B 的处方总和应落在 15-30 分钟,和文案里"约 25 分钟"对得上。
    func testStrengthPlanDurationIsRealistic() {
        for plan in [WorkoutType.strengthA, .strengthB] {
            let minutes = PrescriptionLibrary.estimatedMinutes(for: plan)
            XCTAssertGreaterThanOrEqual(minutes, 15, "\(plan.rawValue) 处方时长过短")
            XCTAssertLessThanOrEqual(minutes, 30, "\(plan.rawValue) 处方时长过长")
        }
    }

    /// 腰背恢复应该明显短于力量训练。
    func testRecoveryIsShorterThanStrength() {
        let recovery = PrescriptionLibrary.estimatedMinutes(for: .recovery)
        let strength = PrescriptionLibrary.estimatedMinutes(for: .strengthA)
        XCTAssertLessThan(recovery, strength)
    }

    /// 最低版要真的能在 8 分钟量级完成。
    func testMinimalPlanFitsEightMinutes() {
        let total = PrescriptionLibrary.minimalExercises.reduce(0) { sum, exercise in
            sum + PrescriptionLibrary.minimalPrescription(exerciseID: exercise.id).estimatedMinutes
        }
        XCTAssertGreaterThanOrEqual(total, 6)
        XCTAssertLessThanOrEqual(total, 10)
    }

    func testMinimalPlanCoversFullBodyPatterns() {
        let muscles = Set(PrescriptionLibrary.minimalExercises.flatMap(\.targets))
        XCTAssertTrue(muscles.contains(.legs))
        XCTAssertTrue(muscles.contains(.chest) || muscles.contains(.shoulders))
        XCTAssertTrue(muscles.contains(.glutes))
    }
}
