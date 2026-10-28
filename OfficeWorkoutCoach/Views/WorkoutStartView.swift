import SwiftUI
import Combine
import AppKit
import OfficeWorkoutLogic

/// 跟练模式:按处方逐个动作、逐组推进,自带计时和组间休息。
///
/// 这一步补的是原来断掉的环节 —— 之前点「开始」直接跳到记录表单,还没练
/// 就要填完成度和强度。现在开始训练是一个真实的执行流程,练完自动落库。
///
/// 独立窗口(通过 `openWindow(id: "workout", value:)` 打开),因为 popover
/// 只有 320pt 宽,放不下媒体和计时。
struct WorkoutStartView: View {
    /// `WorkoutType.rawValue`。
    let planRaw: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var notifier: NotificationManager

    private enum Phase: Equatable {
        case ready      // 等待开始
        case working    // 本组进行中
        case resting    // 组间休息
        case done       // 全部完成
    }

    @State private var steps: [WorkoutStep] = []
    @State private var index = 0
    @State private var phase: Phase = .ready
    @State private var elapsed = 0
    @State private var restRemaining = 0
    @State private var completed: [CompletedSet] = []
    @State private var startedAt = Date()
    @State private var weightText = ""
    @State private var showQuitConfirm = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var plan: WorkoutType? { WorkoutType(rawValue: planRaw) }
    private var currentStep: WorkoutStep? {
        steps.indices.contains(index) ? steps[index] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if phase == .done {
                doneView
            } else if let step = currentStep {
                HStack(alignment: .top, spacing: 0) {
                    mediaPane(step)
                    Divider()
                    controlPane(step)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(.background)
        .onAppear {
            steps = Self.buildSteps(for: plan)
            startedAt = .now
            notifier.isWorkoutInProgress = true
        }
        .onDisappear {
            notifier.isWorkoutInProgress = false
        }
        .onReceive(ticker) { _ in tick() }
        .confirmationDialog(
            String(localized: "workout.quit.title", defaultValue: "结束这次训练?"),
            isPresented: $showQuitConfirm
        ) {
            Button(String(localized: "workout.quit.confirm", defaultValue: "结束并放弃"), role: .destructive) {
                notifier.isWorkoutInProgress = false
                dismiss()
            }
            Button(String(localized: "workout.quit.cancel", defaultValue: "继续练"), role: .cancel) {}
        } message: {
            Text(String(localized: "workout.quit.message", defaultValue: "已完成的组不会被记录。"))
        }
    }

    // MARK: - 顶部

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: plan?.systemImage ?? "figure.strengthtraining.traditional")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan?.localizedName ?? "")
                    .font(.headline)
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button {
                if phase == .done { dismiss() } else { showQuitConfirm = true }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "workout.close", defaultValue: "结束训练"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var progressText: String {
        guard !steps.isEmpty else { return "" }
        let done = completed.count
        let total = steps.count
        let shown = done + (phase == .done ? 0 : 1)
        let format = NSLocalizedString("workout.progress", value: "第 %1$d / %2$d 组", comment: "")
        return String(format: format, shown, total)
    }

    // MARK: - 左:媒体

    @ViewBuilder
    private func mediaPane(_ step: WorkoutStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ExerciseMediaView(exercise: step.exercise)
                .frame(maxWidth: .infinity, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text(step.exercise.localizedName)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    tag(doseText(step))
                    if let side = step.side {
                        tag(side == .left
                            ? String(localized: "workout.side.left", defaultValue: "左侧")
                            : String(localized: "workout.side.right", defaultValue: "右侧"))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.secondary.opacity(0.12), in: Capsule())
    }

    // MARK: - 右:计时与控制

    @ViewBuilder
    private func controlPane(_ step: WorkoutStep) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            timerBlock(step)
            if let last = store.lastPerformance(exerciseID: step.exercise.id) {
                lastPerformanceRow(last, prescription: step.prescription)
            }
            focusRow(step)
            weightRow(step)
            Spacer(minLength: 0)
            actionButtons(step)
        }
        .padding(20)
        .frame(width: 340)
    }

    @ViewBuilder
    private func timerBlock(_ step: WorkoutStep) -> some View {
        VStack(spacing: 6) {
            switch phase {
            case .resting:
                Text(String(localized: "workout.resting", defaultValue: "组间休息"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(timeString(restRemaining))
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
            case .working:
                Text(step.prescription.isHold
                     ? String(localized: "workout.holding", defaultValue: "保持")
                     : String(localized: "workout.working", defaultValue: "进行中"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(timeString(step.prescription.isHold
                                ? max(0, step.prescription.repsHigh - elapsed)
                                : elapsed))
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            default:
                Text(String(localized: "workout.ready", defaultValue: "准备好了就开始"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(doseText(step))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func lastPerformanceRow(_ last: LastPerformance, prescription: Prescription) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            Text(String(localized: "workout.lastTime", defaultValue: "上次"))
                .font(.caption).foregroundStyle(.secondary)
            Text(lastText(last, prescription: prescription))
                .font(.caption.monospacedDigit())
            Spacer()
        }
    }

    private func lastText(_ last: LastPerformance, prescription: Prescription) -> String {
        let unit = prescription.isHold
            ? String(localized: "workout.unit.seconds", defaultValue: "秒")
            : String(localized: "workout.unit.reps", defaultValue: "次")
        if let weight = last.weightKg {
            return String(format: "%.1f kg × %d %@", weight, last.reps, unit)
        }
        return "\(last.reps) \(unit)"
    }

    @ViewBuilder
    private func focusRow(_ step: WorkoutStep) -> some View {
        if let focus = step.exercise.localizedVisualFocus.first {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "scope").foregroundStyle(.blue).font(.caption)
                Text(focus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func weightRow(_ step: WorkoutStep) -> some View {
        if !step.prescription.isHold {
            HStack(spacing: 8) {
                Text(String(localized: "workout.weight", defaultValue: "重量"))
                    .font(.caption).foregroundStyle(.secondary)
                TextField(String(localized: "workout.weight.placeholder", defaultValue: "kg(可留空)"),
                          text: $weightText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Text(String(localized: "workout.weight.hint", defaultValue: "留空表示只记次数"))
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func actionButtons(_ step: WorkoutStep) -> some View {
        switch phase {
        case .ready:
            Button {
                beginWork(step)
            } label: {
                Text(String(localized: "workout.startSet", defaultValue: "开始本组"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

        case .working:
            Button {
                completeCurrentSet(step, reps: step.prescription.isHold ? elapsed : step.prescription.repsHigh)
            } label: {
                Text(String(localized: "workout.finishSet", defaultValue: "完成本组"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

        case .resting:
            HStack(spacing: 8) {
                Button {
                    advance()
                } label: {
                    Text(String(localized: "workout.skipRest", defaultValue: "跳过休息"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    restRemaining += 30
                } label: {
                    Text(String(localized: "workout.addRest", defaultValue: "+30 秒"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

        case .done:
            EmptyView()
        }
    }

    // MARK: - 完成页

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text(String(localized: "workout.done.title", defaultValue: "训练完成"))
                .font(.title2.weight(.semibold))
            Text(doneDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                dismiss()
            } label: {
                Text(String(localized: "workout.done.close", defaultValue: "完成"))
                    .frame(width: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 状态机

    private func beginWork(_ step: WorkoutStep) {
        elapsed = 0
        phase = .working
        if weightText.isEmpty, let last = store.lastPerformance(exerciseID: step.exercise.id),
           let weight = last.weightKg {
            // 沿用上次重量作为默认值,减少重复输入。
            weightText = String(format: "%.1f", weight)
        }
    }

    private func completeCurrentSet(_ step: WorkoutStep, reps: Int) {
        completed.append(
            CompletedSet(
                exerciseID: step.exercise.id,
                setIndex: step.setIndex,
                reps: max(1, reps),
                weightKg: parsedWeight
            )
        )
        let isLastStep = index >= steps.count - 1
        if isLastStep {
            finish()
            return
        }
        if step.prescription.restSeconds > 0 {
            restRemaining = step.prescription.restSeconds
            phase = .resting
        } else {
            advance()
        }
    }

    private func advance() {
        index = min(index + 1, max(0, steps.count - 1))
        elapsed = 0
        phase = .ready
    }

    private func tick() {
        switch phase {
        case .working:
            elapsed += 1
            if let step = currentStep, step.prescription.isHold,
               elapsed >= step.prescription.repsHigh {
                completeCurrentSet(step, reps: step.prescription.repsHigh)
            }
        case .resting:
            restRemaining -= 1
            if restRemaining <= 0 { advance() }
        default:
            break
        }
    }

    private func finish() {
        guard let plan else { dismiss(); return }
        let id = store.log(
            type: plan,
            planCode: planRaw,
            durationMinutes: durationMinutes,
            completion: .full,
            intensity: 3,
            bodyFeeling: nil,
            notes: nil
        )
        for set in completed {
            store.recordSet(
                sessionID: id,
                exerciseID: set.exerciseID,
                setIndex: set.setIndex,
                reps: set.reps,
                weightKg: set.weightKg
            )
        }
        notifier.isWorkoutInProgress = false
        phase = .done
    }

    // MARK: - 派生

    private var parsedWeight: Double? {
        let trimmed = weightText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private var durationMinutes: Int {
        max(1, Int(Date().timeIntervalSince(startedAt) / 60))
    }

    private var doneDetail: String {
        let format = NSLocalizedString(
            "workout.done.detail",
            value: "共 %1$d 组 · %2$d 分钟,已记入今天。",
            comment: ""
        )
        return String(format: format, completed.count, durationMinutes)
    }

    private func doseText(_ step: WorkoutStep) -> String {
        let rx = step.prescription
        let key = rx.isHold ? "workout.dose.hold" : "workout.dose.reps"
        let fallback = rx.isHold ? "%1$d 组 × %2$@ 秒" : "%1$d 组 × %2$@ 次"
        let format = NSLocalizedString(key, value: fallback, comment: "")
        return String(format: format, rx.sets, rx.repRangeText)
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }

    // MARK: - 步骤构建

    /// 把计划展开成"逐组"的执行序列。
    ///
    /// 展开规则(单侧拆左右、组数与处方一致)在逻辑层的 `WorkoutPlanExpander`
    /// 里,有单测覆盖;这里只负责把 id 换成具体的 `Exercise` 和 `Prescription`。
    static func buildSteps(for plan: WorkoutType?) -> [WorkoutStep] {
        guard let plan else { return [] }
        return WorkoutPlanExpander.steps(for: plan).compactMap { step in
            guard let exercise = ExerciseLibrary.exercise(id: step.exerciseID) else { return nil }
            let rx = plan == .minimal
                ? PrescriptionLibrary.minimalPrescription(exerciseID: step.exerciseID)
                : PrescriptionLibrary.prescription(for: plan, exerciseID: step.exerciseID)

            let side: WorkoutStep.Side?
            switch step.side {
            case .left:  side = .left
            case .right: side = .right
            case nil:    side = nil
            }

            return WorkoutStep(exercise: exercise, prescription: rx, setIndex: step.setIndex, side: side)
        }
    }
}

// MARK: - 模型

struct WorkoutStep: Identifiable {
    enum Side { case left, right }

    let id = UUID()
    let exercise: Exercise
    let prescription: Prescription
    let setIndex: Int
    let side: Side?
}

struct CompletedSet {
    let exerciseID: String
    let setIndex: Int
    let reps: Int
    let weightKg: Double?
}
