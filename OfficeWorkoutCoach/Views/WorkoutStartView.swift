import SwiftUI
import AppKit
import OfficeWorkoutLogic

struct WorkoutStartView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var workout: WorkoutCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var now = Date()
    @State private var confirmEnd = false
    @State private var confirmDiscard = false
    @State private var history: [ExercisePerformance] = []
    @State private var lastPerformance: LastPerformance?

    var body: some View {
        VStack(spacing: 0) {
            if let run = workout.execution {
                header(run)
                Divider()
                if workout.saved { savedView(run) }
                else if run.phase == .finished { reviewView(run) }
                else if let step = run.currentStep, let exercise = ExerciseLibrary.exercise(id: step.exerciseID) {
                    HStack(alignment: .top, spacing: 0) {
                        mediaPane(exercise: exercise, step: step)
                        Divider()
                        controlPane(run: run, step: step)
                    }
                }
            } else { TrainingPlanEditorView() }
        }
        .frame(minWidth: 860, minHeight: 600)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { date in
            now = date
            workout.tick(at: date)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in workout.pause() }
        .onDisappear { workout.pause() }
        .onAppear { reloadHistory() }
        .onChange(of: workout.execution?.currentStep?.id) { reloadHistory() }
        .onChange(of: store.changeToken) { reloadHistory() }
        .alert(String(localized: "common.error", defaultValue: "未能完成操作"), isPresented: Binding(get: { workout.errorMessage != nil }, set: { if !$0 { workout.errorMessage = nil } })) {
            Button(String(localized: "common.ok", defaultValue: "好")) { workout.errorMessage = nil }
        } message: { Text(workout.errorMessage ?? "") }
        .confirmationDialog(String(localized: "workout.end.confirm", defaultValue: "结束本次训练并查看已完成的组？"), isPresented: $confirmEnd) {
            Button(String(localized: "workout.end.review", defaultValue: "结束并查看记录")) { workout.finishEarly() }
            Button(String(localized: "common.cancel", defaultValue: "取消"), role: .cancel) { }
        } message: {
            Text(String(localized: "workout.end.hint", defaultValue: "已完成的组可以保存为部分完成；未完成的当前组不会自动记入。"))
        }
        .confirmationDialog(String(localized: "workout.discard.confirm", defaultValue: "丢弃这次尚未保存的训练？"), isPresented: $confirmDiscard) {
            Button(String(localized: "workout.discard", defaultValue: "丢弃训练"), role: .destructive) { workout.reset() }
        }
    }

    private func header(_ run: WorkoutExecution) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.plan.name).font(.headline)
                Text(String(format: NSLocalizedString("workout.progress.actual", value: "已完成 %1$d / %2$d 组", comment: ""), run.completedSets.count, run.steps.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(clock(run.durationSeconds(at: now))).monospacedDigit().foregroundStyle(.secondary)
            if run.phase != .finished {
                if run.phase == .paused {
                    Button(String(localized: "workout.resume", defaultValue: "继续")) { workout.resume() }
                } else {
                    Button(String(localized: "workout.pause", defaultValue: "暂停")) { workout.pause() }
                }
                Button(String(localized: "workout.end", defaultValue: "结束训练")) { confirmEnd = true }
            }
        }.padding(16)
    }

    private func mediaPane(exercise: Exercise, step: ExecutionStep) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ExerciseMediaView(exercise: exercise)
                    .frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 12))
                Text(exercise.localizedName).font(.title2.bold())
                HStack {
                    Text(String(format: NSLocalizedString("workout.step.target", value: "第 %1$d 组 · 目标 %2$d", comment: ""), step.setIndex, step.exercise.reps))
                    Text(step.exercise.isHold ? String(localized: "workout.unit.seconds", defaultValue: "秒") : String(localized: "workout.unit.reps", defaultValue: "次"))
                    if let side = step.side {
                        Text(side == .left ? String(localized: "workout.side.left", defaultValue: "左侧") : String(localized: "workout.side.right", defaultValue: "右侧"))
                    }
                }.font(.subheadline).foregroundStyle(.secondary)
                ForEach(exercise.localizedCues, id: \.self) { Text($0).font(.callout) }
                ForEach(exercise.localizedStopConditions, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            }.padding(20)
        }.frame(maxWidth: .infinity)
    }

    private func controlPane(run: WorkoutExecution, step: ExecutionStep) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 8) {
                    Text(phaseName(run.phase)).font(.caption).foregroundStyle(.secondary)
                    Text(timerText(run, step: step))
                        .font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                if let last = lastPerformance {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text(String(localized: "workout.lastTime", defaultValue: "上次"))
                        Text(lastValue(last, isHold: step.exercise.isHold))
                    }.font(.caption).foregroundStyle(.secondary)
                }
                progressionView(step)
                if !step.exercise.isHold {
                    TextField(String(localized: "workout.actualReps", defaultValue: "本组实际完成次数"), text: $workout.repetitionsText)
                        .textFieldStyle(.roundedBorder).disabled(run.phase != .working)
                    TextField(String(localized: "workout.weight.placeholder", defaultValue: "重量 kg（可留空）"), text: $workout.weightText)
                        .textFieldStyle(.roundedBorder).disabled(run.phase != .ready && run.phase != .working)
                    Text(String(localized: "workout.actual.hint", defaultValue: "填写实际完成值。目标次数仅作参考，不会自动写入记录。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                actionButtons(run: run, step: step)
                if run.phase == .paused {
                    Text(String(localized: "workout.pause.hint", defaultValue: "计时已暂停。关闭窗口后，本次进度会保留到应用退出。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
        }.frame(width: 340)
    }

    @ViewBuilder private func progressionView(_ step: ExecutionStep) -> some View {
        let suggestion = TrainingProgression.suggestion(for: step.exercise, history: history)
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString(suggestion.reasonKey, comment: "")).font(.caption).foregroundStyle(.secondary)
            if suggestion.requiresAcceptance, let weight = suggestion.weightKg {
                Button(String(format: NSLocalizedString("progress.acceptWeight", value: "本组使用建议重量 %.2f kg", comment: ""), weight)) {
                    workout.weightText = String(format: "%.2f", weight)
                }
                .disabled(workout.execution?.phase != .ready && workout.execution?.phase != .working)
            }
            if suggestion.requiresAcceptance, suggestion.weightKg == nil, let reps = suggestion.targetReps {
                Text(String(format: NSLocalizedString("progress.repsSuggestion", value: "本次可把目标调整为 %d 次；完成后仍填写实际次数。", comment: ""), reps))
                    .font(.caption)
            }
        }
    }

    @ViewBuilder private func actionButtons(run: WorkoutExecution, step: ExecutionStep) -> some View {
        switch run.phase {
        case .ready:
            Button(String(localized: "workout.startSet", defaultValue: "开始本组")) { workout.startSet() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        case .working:
            Button(step.exercise.isHold ? String(localized: "workout.hold.stop", defaultValue: "按实际秒数结束本组") : String(localized: "workout.finishSet", defaultValue: "完成本组")) { workout.completeSet() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(step.exercise.isHold ? run.elapsedSeconds(at: now) < 1 : workout.repetitionsText.isEmpty)
        case .resting:
            HStack {
                Button(String(localized: "workout.skipRest", defaultValue: "跳过休息")) { workout.skipRest() }
                Button(String(localized: "workout.addRest", defaultValue: "+30 秒")) { workout.addRest() }
            }
        case .paused:
            Button(String(localized: "workout.resume", defaultValue: "继续")) { workout.resume() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        case .finished: EmptyView()
        }
    }

    private func reviewView(_ run: WorkoutExecution) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(run.completion == .full ? String(localized: "workout.review.full", defaultValue: "已完成全部训练组") : String(localized: "workout.review.partial", defaultValue: "本次将保存为部分完成"))
                .font(.title2.bold())
            Text(String(format: NSLocalizedString("workout.review.sets", value: "%d 组实际记录；确认感受后保存。", comment: ""), run.completedSets.count))
                .foregroundStyle(.secondary)
            Form {
                Picker(String(localized: "field.intensity", defaultValue: "主观强度"), selection: $workout.intensity) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker(String(localized: "field.feeling", defaultValue: "身体感觉"), selection: $workout.bodyFeeling) {
                    ForEach(BodyFeeling.allCases) { Text($0.localizedName).tag($0) }
                }
                TextField(String(localized: "field.notes", defaultValue: "备注（可选）"), text: $workout.notes, axis: .vertical)
            }.formStyle(.grouped)
            HStack {
                Button(String(localized: "workout.discard", defaultValue: "丢弃训练"), role: .destructive) { confirmDiscard = true }
                Spacer()
                Button(String(localized: "workout.save", defaultValue: "保存本次训练")) { workout.save(using: store) }
                    .buttonStyle(.borderedProminent).disabled(run.completedSets.isEmpty)
            }
            if run.completedSets.isEmpty {
                Text(String(localized: "workout.empty", defaultValue: "还没有完成的组，未生成训练记录。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func savedView(_ run: WorkoutExecution) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 50)).foregroundStyle(.green)
            Text(String(localized: "workout.saved", defaultValue: "训练已保存")).font(.title2.bold())
            Text(String(format: NSLocalizedString("workout.progress.actual", value: "已完成 %1$d / %2$d 组", comment: ""), run.completedSets.count, run.steps.count))
            HStack {
                Button(String(localized: "workout.new", defaultValue: "准备下次计划")) { workout.reset() }
                Button(String(localized: "workout.done.close", defaultValue: "完成")) { dismiss() }.buttonStyle(.borderedProminent)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timerText(_ run: WorkoutExecution, step: ExecutionStep) -> String {
        switch run.phase {
        case .resting: return clock(run.restRemaining(at: now))
        case .working: return clock(step.exercise.isHold ? max(0, step.exercise.reps - run.elapsedSeconds(at: now)) : run.elapsedSeconds(at: now))
        case .ready: return "\(step.exercise.reps)"
        case .paused: return "—"
        case .finished: return clock(run.durationSeconds(at: now))
        }
    }
    private func phaseName(_ phase: WorkoutExecution.Phase) -> String {
        switch phase {
        case .ready: return String(localized: "workout.ready", defaultValue: "准备好了就开始")
        case .working: return String(localized: "workout.working", defaultValue: "进行中")
        case .resting: return String(localized: "workout.resting", defaultValue: "组间休息")
        case .paused: return String(localized: "workout.paused", defaultValue: "已暂停")
        case .finished: return String(localized: "workout.review", defaultValue: "待保存")
        }
    }
    private func lastValue(_ last: LastPerformance, isHold: Bool) -> String {
        let unit = isHold ? String(localized: "workout.unit.seconds", defaultValue: "秒") : String(localized: "workout.unit.reps", defaultValue: "次")
        let weight = last.weightKg.map { String(format: "%.1f kg × ", $0) } ?? ""
        return "\(weight)\(last.reps) \(unit)"
    }
    private func reloadHistory() {
        guard let id = workout.execution?.currentStep?.exerciseID else { history = []; lastPerformance = nil; return }
        history = store.exercisePerformances(exerciseID: id)
        lastPerformance = store.lastPerformance(exerciseID: id)
    }
    private func clock(_ seconds: Int) -> String { String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60) }
}
