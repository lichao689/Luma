import XCTest
@testable import OfficeWorkoutLogic

/// 钉死动作库的结构不变量:id 唯一、key 非空、A/B 分组合理、非力量类型返回空。
/// 这些是 App 层展示动作示意的前提;改库时这里会先红。
final class ExerciseLibraryTests: XCTestCase {

    // 库非空
    func testLibraryIsNotEmpty() {
        XCTAssertFalse(ExerciseLibrary.all.isEmpty, "动作库不应为空")
    }

    // 每个 id 唯一(App 层靠 id 做选中态/跳转)
    func testAllIdsAreUnique() {
        let ids = ExerciseLibrary.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "动作 id 必须唯一")
    }

    // 每个 id / nameKey / cuesKey / setsReps 非空(展示必需)
    func testEveryExerciseHasRequiredFields() {
        for ex in ExerciseLibrary.all {
            XCTAssertFalse(ex.id.isEmpty, "id 为空: \(ex)")
            XCTAssertFalse(ex.nameKey.isEmpty, "nameKey 为空: \(ex.id)")
            XCTAssertFalse(ex.primaryMuscleKey.isEmpty, "primaryMuscleKey 为空: \(ex.id)")
            XCTAssertFalse(ex.cuesKey.isEmpty, "cuesKey 为空: \(ex.id)")
            XCTAssertFalse(ex.commonMistakesKey.isEmpty, "commonMistakesKey 为空: \(ex.id)")
            XCTAssertFalse(ex.visualFocusKey.isEmpty, "visualFocusKey 为空: \(ex.id)")
            XCTAssertFalse(ex.easierVariationKey.isEmpty, "easierVariationKey 为空: \(ex.id)")
            XCTAssertFalse(ex.stopConditionKey.isEmpty, "stopConditionKey 为空: \(ex.id)")
            XCTAssertFalse(ex.setsReps.isEmpty, "setsReps 为空: \(ex.id)")
            XCTAssertFalse(ex.targets.isEmpty, "targets 为空: \(ex.id)")
            XCTAssertNotNil(ex.imageAssetName, "imageAssetName 为空: \(ex.id)")
        }
    }

    // 用户当前环境是办公室 + 瑜伽垫 + 哑铃;可见动作库不能依赖凳椅/长凳等家具。
    func testVisibleLibraryDoesNotRequireFurniture() {
        let disallowedIDs = Set([
            "dumbbellRow",
            "splitSquat",
            "dumbbellBenchPress",
            "proneRow",
        ])
        let visibleIDs = Set(ExerciseLibrary.all.map(\.id))
        XCTAssertTrue(visibleIDs.isDisjoint(with: disallowedIDs), "可见动作库包含需要椅凳/长凳支撑的动作")
    }

    // 力量 A 与 B 各非空
    func testStrengthPlansAreNonEmpty() {
        XCTAssertFalse(ExerciseLibrary.exercises(for: .strengthA).isEmpty)
        XCTAssertFalse(ExerciseLibrary.exercises(for: .strengthB).isEmpty)
    }

    // 计划里引用的动作必须是库里真实存在的(无悬挂引用)。
    // 注意:库可以包含额外动作(如纯核心/恢复动作),它们不必进 A/B 计划,
    // 因此这里只校验“A/B 引用的都在库里”,而非反向覆盖。
    func testPlansOnlyReferenceKnownExercises() {
        let known = Set(ExerciseLibrary.all.map(\.id))
        for ex in ExerciseLibrary.planA + ExerciseLibrary.planB + ExerciseLibrary.recoverySet {
            XCTAssertTrue(known.contains(ex.id), "计划引用了未知动作: \(ex.id)")
        }
    }

    // 恢复组的动作应都在库里
    func testRecoverySetReferencesKnownExercises() {
        let known = Set(ExerciseLibrary.all.map(\.id))
        for ex in ExerciseLibrary.recoverySet {
            XCTAssertTrue(known.contains(ex.id), "恢复组引用了未知动作: \(ex.id)")
        }
    }

    // 力量 A 与 B 不重叠(同一动作不应同时出现在两个计划里)
    func testPlansDoNotOverlap() {
        let aIDs = Set(ExerciseLibrary.planA.map(\.id))
        let bIDs = Set(ExerciseLibrary.planB.map(\.id))
        XCTAssertTrue(aIDs.isDisjoint(with: bIDs), "力量 A 与 B 存在重复动作")
    }

    // 非 strength / recovery 类型返回空(跑步/最低版/休息没有动作示意)
    func testNonStrengthTypesReturnEmpty() {
        XCTAssertTrue(ExerciseLibrary.exercises(for: .run).isEmpty)
        XCTAssertTrue(ExerciseLibrary.exercises(for: .minimal).isEmpty)
        XCTAssertTrue(ExerciseLibrary.exercises(for: .rest).isEmpty)
    }

    // 恢复组非空(久坐/腰背提醒会参考)
    func testRecoverySetIsNonEmpty() {
        XCTAssertFalse(ExerciseLibrary.exercises(for: .recovery).isEmpty)
    }

    // 按 id 能查回;未知 id 返回 nil
    func testLookupById() {
        XCTAssertEqual(ExerciseLibrary.exercise(id: "gobletSquat"), ExerciseLibrary.gobletSquat)
        XCTAssertEqual(ExerciseLibrary.exercise(id: "bentOverDumbbellRow"), ExerciseLibrary.bentOverDumbbellRow)
        XCTAssertNil(ExerciseLibrary.exercise(id: "doesNotExist"))
    }
}
