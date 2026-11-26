import SwiftUI
import Charts
import OfficeWorkoutLogic

/// Date-range and exercise-specific history. Quantities retain their units;
/// missing weights and imported unknown effort are never displayed as zero.
struct SummaryView: View {
    var onDone: () -> Void
    @EnvironmentObject private var store: WorkoutStore
    @State private var snapshot: BackupSnapshot?
    @State private var health: HealthBridgePacket?
    @State private var days = 30
    @State private var activityMetric = 0
    @State private var exerciseID = "gobletSquat"
    @State private var exerciseMetric = 0
    @State private var errorMessage: String?
    @State private var deleting: BackupSession?

    private var daily: [DailyActivity] {
        HistoryAnalytics.daily(sessions: snapshot?.sessions.map(\.asRecord) ?? [], days: days)
    }
    private var cutoff: Date { daily.first?.date ?? Calendar.current.startOfDay(for: .now) }
    private var recent: [BackupSession] {
        (snapshot?.sessions ?? []).filter { $0.date >= cutoff && $0.date <= .now }.sorted { $0.date > $1.date }
    }
    private var points: [ExerciseHistoryPoint] {
        HistoryAnalytics.exerciseTrend(exerciseID: exerciseID, sessions: snapshot?.sessions ?? [],
            sets: snapshot?.sets ?? [], since: cutoff)
    }
    private var isHold: Bool { ExerciseAlternatives.isHold(exerciseID) }
    private var visiblePoints: [ExerciseHistoryPoint] {
        exerciseMetric == 0 ? points : points.filter { $0.maximumWeightKg != nil }
    }
    private var quantityLabel: String {
        isHold ? String(localized: "history.holdSeconds", defaultValue: "保持秒数")
               : String(localized: "history.repetitions", defaultValue: "完成次数")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: onDone) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).help(String(localized: "common.back", defaultValue: "返回"))
                Text(String(localized: "summary.title", defaultValue: "记录与总结")).font(.headline)
                Spacer()
            }
            Picker(String(localized: "history.range", defaultValue: "时间范围"), selection: $days) {
                Text(String(localized: "history.7", defaultValue: "7 天")).tag(7)
                Text(String(localized: "history.30", defaultValue: "30 天")).tag(30)
                Text(String(localized: "history.90", defaultValue: "90 天")).tag(90)
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    weeklySummary
                    Divider()
                    activityChart
                    Divider()
                    exerciseChart
                    if health != nil { Divider(); healthSummary }
                    Divider()
                    recentList
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.caption) }
                }
            }
        }
        .padding(12)
        .frame(height: 570, alignment: .topLeading)
        .controlSize(.small)
        .onAppear(perform: reload)
        .onChange(of: store.changeToken) { _, _ in reload() }
        .confirmationDialog(String(localized: "history.delete.confirm", defaultValue: "删除这条记录及其组明细？删除标记会随同步传到其他设备。"),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(String(localized: "summary.delete", defaultValue: "删除这条记录"), role: .destructive) {
                guard let id = deleting?.id else { return }
                do { try store.deleteSession(id: id); deleting = nil; reload() }
                catch { errorMessage = userFacingError(error); deleting = nil }
            }
        }
    }

    private var weeklySummary: some View {
        let stats = WorkoutStatsService().stats(sessions: snapshot?.sessions.map(\.asRecord) ?? [])
        let goal = snapshot?.goal ?? .default
        return VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "history.thisWeek", defaultValue: "本周记录")).font(.subheadline.bold())
            HStack {
                statBadge(String(localized: "goal.strength", defaultValue: "力量"), count: stats.strengthCount, target: goal.weeklyStrengthTarget)
                Spacer()
                statBadge(String(localized: "goal.recovery", defaultValue: "恢复"), count: stats.recoveryCount, target: goal.weeklyRecoveryTarget)
                Spacer()
                statBadge(String(localized: "goal.run", defaultValue: "跑步"), count: stats.runCount, target: goal.weeklyRunTarget)
            }
        }
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "history.activity", defaultValue: "每日活动")).font(.subheadline.bold())
            Picker(String(localized: "history.metric", defaultValue: "统计项"), selection: $activityMetric) {
                Text(String(localized: "history.sessions", defaultValue: "活动次数")).tag(0)
                Text(String(localized: "history.minutes", defaultValue: "活动分钟")).tag(1)
            }.pickerStyle(.segmented)
            if daily.allSatisfy({ $0.sessions == 0 }) {
                empty(String(localized: "history.activity.empty", defaultValue: "这个时间段还没有活动记录。"))
            } else {
                Chart(daily) { day in
                    BarMark(x: .value("Date", day.date, unit: .day),
                            y: .value("Activity", activityMetric == 0 ? day.sessions : day.minutes))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(activityMetric == 0 ? "\(day.sessions)" : "\(day.minutes) min")
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.month().day()) } }
                .frame(height: 125)
                HStack {
                    Label("\(daily.reduce(0) { $0 + $1.sessions })", systemImage: "figure.strengthtraining.traditional")
                    Spacer()
                    Label("\(daily.reduce(0) { $0 + $1.minutes }) min", systemImage: "clock")
                }.font(.caption).foregroundStyle(.secondary)
            }
            Text(String(localized: "history.activity.detail", defaultValue: "按本机时区的自然日统计；休息记录不计入活动。未记录时长的活动保留次数。"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var exerciseChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "history.exercise", defaultValue: "动作趋势")).font(.subheadline.bold())
            Picker(String(localized: "history.exercise.select", defaultValue: "动作"), selection: $exerciseID) {
                ForEach(ExerciseLibrary.all) { exercise in Text(exercise.localizedName).tag(exercise.id) }
            }
            Picker(String(localized: "history.metric", defaultValue: "统计项"), selection: $exerciseMetric) {
                Text(quantityLabel).tag(0)
                Text(String(localized: "history.weight", defaultValue: "重量 kg")).tag(1)
            }.pickerStyle(.segmented)
            if visiblePoints.isEmpty {
                empty(exerciseMetric == 1
                    ? String(localized: "history.weight.empty", defaultValue: "此动作没有已记录的重量。")
                    : String(localized: "history.exercise.empty", defaultValue: "此动作在所选时间段没有实际组记录。"))
            } else {
                Chart(visiblePoints) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Value", pointValue(point)))
                    PointMark(x: .value("Date", point.date), y: .value("Value", pointValue(point)))
                        .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .shortened))
                        .accessibilityValue("\(pointValue(point).formatted()) \(exerciseMetric == 1 ? "kg" : (isHold ? "s" : quantityLabel))")
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.month().day()) } }
                .frame(height: 125)
                if let latest = visiblePoints.last {
                    HStack {
                        Text(String(localized: "history.latest", defaultValue: "最近一次"))
                        Spacer()
                        Text("\(pointValue(latest).formatted()) \(exerciseMetric == 1 ? "kg" : (isHold ? "s" : quantityLabel))")
                    }.font(.caption).monospacedDigit()
                }
            }
            Text(String(localized: "history.exercise.detail", defaultValue: "次数或秒数为每次训练所有组与左右侧的合计；重量为最重一组。未填写重量时不推算负荷。"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var healthSummary: some View {
        let visible = health?.stepDays.filter { $0.start >= cutoff && $0.start <= .now } ?? []
        let latestDay = visible.filter { $0.end <= .now && $0.count != nil }.sorted { $0.end > $1.end }.first
        let sleep = HealthBridgeSummary.sleepSeconds(in: DateInterval(start: cutoff, end: .now), samples: health?.sleepSamples ?? [])
        return VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "data.health.title", defaultValue: "Apple 健康导入")).font(.subheadline.bold())
            HStack {
                Text(String(localized: "history.health.steps", defaultValue: "最近有记录的一天步数"))
                Spacer(); Text(latestDay?.count?.formatted(.number.precision(.fractionLength(0))) ?? "—")
            }
            if let day = latestDay {
                Text(stepDayLabel(day)).font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Text(String(localized: "history.health.sleep", defaultValue: "已导入睡眠合计"))
                Spacer(); Text(sleep.map { "\(($0 / 3600).formatted(.number.precision(.fractionLength(1)))) h" } ?? "—")
            }
            Text(String(localized: "history.health.detail", defaultValue: "仅汇总所选时间段内已导入、可见的数据；缺少数据不等于零。重复或重叠的睡眠片段只计一次。"))
                .font(.caption2).foregroundStyle(.secondary)
        }.font(.caption)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "history.records", defaultValue: "所选时间段的记录")).font(.subheadline.bold())
                Spacer(); Text(recent.count.formatted()).font(.caption).foregroundStyle(.secondary)
            }
            if recent.isEmpty {
                empty(String(localized: "summary.empty", defaultValue: "还没有记录。从菜单栏快速记录一次吧。"))
            } else {
                ForEach(recent) { session in sessionRow(session) }
            }
        }
    }

    private func sessionRow(_ session: BackupSession) -> some View {
        HStack(spacing: 8) {
            Image(systemName: session.type.systemImage).foregroundStyle(.tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.type.localizedName)
                Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                if session.completion == .partial {
                    Text(String(localized: "history.partial", defaultValue: "部分完成")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(session.durationMinutes) min").font(.caption).monospacedDigit()
            Button(role: .destructive) { deleting = session } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help(String(localized: "summary.delete", defaultValue: "删除这条记录"))
        }
    }

    private func statBadge(_ label: String, count: Int, target: Int) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("\(count)/\(target)").font(.callout).monospacedDigit()
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
    }

    private func pointValue(_ point: ExerciseHistoryPoint) -> Double {
        exerciseMetric == 1 ? (point.maximumWeightKg ?? 0) : Double(isHold ? point.holdSeconds : point.repetitions)
    }

    private func stepDayLabel(_ day: HealthStepDay) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = TimeZone(identifier: day.timeZoneIdentifier)
        return formatter.string(from: day.start) + " · " + day.timeZoneIdentifier
            + " · " + day.observedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func reload() {
        do { snapshot = try store.snapshot(); health = try store.healthSnapshot(); errorMessage = nil }
        catch { errorMessage = userFacingError(error) }
    }
}
