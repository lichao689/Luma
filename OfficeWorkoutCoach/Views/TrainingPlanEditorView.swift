import SwiftUI
import OfficeWorkoutLogic

/// Preparation is deliberately separate from execution: edits never change a
/// running workout or rewrite its completed sets.
struct TrainingPlanEditorView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var workout: WorkoutCoordinator
    @State private var minutes = 25
    @State private var planToDelete: TrainingPlan?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "plan.prepare", defaultValue: "准备训练")).font(.title2.bold())
                Spacer()
                Menu(String(localized: "plan.saved", defaultValue: "我的计划")) {
                    ForEach(store.customPlans) { plan in
                        Button(plan.name) { workout.draft = plan }
                    }
                    if store.customPlans.isEmpty {
                        Text(String(localized: "plan.empty", defaultValue: "还没有保存的计划"))
                    }
                }
            }
            HStack {
                Picker(String(localized: "plan.template", defaultValue: "模板"), selection: templateBinding) {
                    ForEach([WorkoutType.strengthA, .strengthB, .recovery, .minimal]) { type in
                        Text(type.localizedName).tag(type)
                    }
                }
                Picker(String(localized: "plan.budget", defaultValue: "模板预算"), selection: $minutes) {
                    ForEach(TrainingPlanFactory.timeOptions, id: \.self) { Text("\($0) min").tag($0) }
                }
                .frame(width: 200)
                Button(String(localized: "plan.reset", defaultValue: "重新生成")) { rebuild() }
            }
            TextField(String(localized: "plan.name", defaultValue: "计划名称"), text: $workout.draft.name)
                .textFieldStyle(.roundedBorder)
            Text(String(format: NSLocalizedString("plan.estimate", value: "预计约 %d 分钟。可调整组数、次数、顺序和休息；实际时长以完成情况为准。", comment: ""), workout.draft.estimatedMinutes))
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(Array(workout.draft.exercises.enumerated()), id: \.element.id) { index, item in
                    exerciseRow(index: index, item: item)
                }
            }
            .listStyle(.inset)
            Menu {
                ForEach(availableExercises) { exercise in
                    Button(exercise.localizedName) { add(exercise) }
                }
            } label: {
                Label(String(localized: "plan.add", defaultValue: "添加动作"), systemImage: "plus")
            }
            HStack {
                Button(String(localized: "plan.save", defaultValue: "保存计划")) { savePlan(asCopy: false) }
                Button(String(localized: "plan.saveCopy", defaultValue: "另存为新计划")) { savePlan(asCopy: true) }
                if store.customPlans.contains(where: { $0.id == workout.draft.id }) {
                    Button(role: .destructive) { planToDelete = workout.draft } label: {
                        Image(systemName: "trash")
                    }.help(String(localized: "plan.delete", defaultValue: "删除已保存计划"))
                }
                if isPlanSaved { Text(String(localized: "plan.savedNotice", defaultValue: "已保存")).font(.caption).foregroundStyle(.green) }
                Spacer()
                Button(String(localized: "plan.begin", defaultValue: "开始跟练")) { workout.begin() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(workout.draft.exercises.isEmpty)
            }
        }
        .padding(20)
        .onAppear { minutes = TrainingPlanFactory.timeOptions.first(where: { $0 >= workout.draft.estimatedMinutes }) ?? 25 }
        .confirmationDialog(String(localized: "plan.delete.confirm", defaultValue: "删除这个已保存的计划？训练历史会保留。"), isPresented: Binding(get: { planToDelete != nil }, set: { if !$0 { planToDelete = nil } })) {
            Button(String(localized: "plan.delete", defaultValue: "删除已保存计划"), role: .destructive) {
                guard let plan = planToDelete else { return }
                do { try store.deletePlan(id: plan.id); planToDelete = nil }
                catch { workout.errorMessage = error.localizedDescription }
            }
        }
    }

    private var isPlanSaved: Bool { store.customPlans.contains { $0 == workout.draft } }

    private var templateBinding: Binding<WorkoutType> {
        Binding(get: { workout.draft.baseType }, set: { type in
            workout.draft = WorkoutCoordinator.builtIn(type, minutes: minutes)
        })
    }

    private var availableExercises: [Exercise] {
        ExerciseLibrary.all.filter { exercise in !workout.draft.exercises.contains { $0.exerciseID == exercise.id } }
    }

    private func exerciseRow(index: Int, item: PlannedExercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ExerciseLibrary.exercise(id: item.exerciseID)?.localizedName ?? item.exerciseID).font(.headline)
                if item.perSide { Text(String(localized: "plan.eachSide", defaultValue: "左右各做")).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Menu(String(localized: "plan.replace", defaultValue: "替换")) {
                    let candidates = ExerciseAlternatives.candidates(for: item.exerciseID, avoiding: Set(workout.draft.exercises.map(\.exerciseID)))
                    ForEach(candidates) { candidate in
                        Button(candidate.localizedName) { replace(item.exerciseID, with: candidate.id) }
                    }
                    if candidates.isEmpty { Text(String(localized: "plan.noAlternative", defaultValue: "没有同类可用动作")) }
                }
                Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(index == 0).help(String(localized: "plan.moveUp", defaultValue: "上移"))
                Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(index == workout.draft.exercises.count - 1).help(String(localized: "plan.moveDown", defaultValue: "下移"))
                Button(role: .destructive) { workout.draft.exercises.remove(at: index) } label: { Image(systemName: "minus.circle") }
                    .help(String(localized: "plan.remove", defaultValue: "移除动作"))
            }
            HStack(spacing: 16) {
                Stepper(value: itemBinding(index, \.sets), in: 1...10) {
                    Text(String(format: NSLocalizedString("plan.sets", value: "%d 组", comment: ""), item.sets))
                }
                Stepper(value: itemBinding(index, \.reps), in: 1...(item.isHold ? 600 : 100)) {
                    Text("\(item.reps) " + String(localized: item.isHold ? "workout.unit.seconds" : "workout.unit.reps"))
                }
                Stepper(value: itemBinding(index, \.restSeconds), in: 0...600, step: 15) {
                    Text(String(format: NSLocalizedString("plan.rest", value: "休息 %d 秒", comment: ""), item.restSeconds))
                }
            }.font(.caption)
        }.padding(.vertical, 6)
    }

    private func itemBinding(_ index: Int, _ path: WritableKeyPath<PlannedExercise, Int>) -> Binding<Int> {
        Binding(get: { workout.draft.exercises.indices.contains(index) ? workout.draft.exercises[index][keyPath: path] : 1 }, set: { value in
            guard workout.draft.exercises.indices.contains(index) else { return }
            workout.draft.exercises[index][keyPath: path] = value
            workout.draft.updatedAt = .now
        })
    }

    private func rebuild() { workout.draft = WorkoutCoordinator.builtIn(workout.draft.baseType, minutes: minutes) }
    private func move(_ index: Int, by offset: Int) {
        guard workout.draft.exercises.indices.contains(index + offset) else { return }
        workout.draft.exercises.swapAt(index, index + offset)
        workout.draft.updatedAt = .now
    }
    private func replace(_ old: String, with new: String) {
        do { workout.draft = try workout.draft.replacing(exerciseID: old, with: new) }
        catch { workout.errorMessage = error.localizedDescription }
    }
    private func add(_ exercise: Exercise) {
        let rx = PrescriptionLibrary.prescription(for: workout.draft.baseType, exerciseID: exercise.id)
        workout.draft.exercises.append(PlannedExercise(exerciseID: exercise.id, sets: rx.sets, reps: rx.repsLow,
            isHold: ExerciseAlternatives.isHold(exercise.id), perSide: ExerciseAlternatives.isPerSide(exercise.id), restSeconds: rx.restSeconds))
        workout.draft.updatedAt = .now
    }
    private func savePlan(asCopy: Bool) {
        do {
            var candidate = workout.draft
            if asCopy { candidate.id = UUID() }
            candidate.updatedAt = .now
            try store.savePlan(candidate)
            workout.draft = candidate
        } catch { workout.errorMessage = error.localizedDescription }
    }
}
