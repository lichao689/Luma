import SwiftUI
import Charts
import OfficeWorkoutLogic

/// Recent history + a small weekly summary, shown inline inside the
/// menu-bar popover (not as a sheet — see MenuBarPopoverView).
struct SummaryView: View {
    /// Called when the user taps back → returns to home page.
    var onDone: () -> Void

    @EnvironmentObject private var store: WorkoutStore
    @State private var sessions: [WorkoutSession] = []

    private var stats: WorkoutStats {
        let records = sessions.map { $0.asRecord }
        return WorkoutStatsService().stats(sessions: records)
    }
    private var goal: UserGoalValues { UserGoalValues(store.fetchGoal()) }
    private var recent: [WorkoutSession] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return sessions.filter { $0.date >= cutoff }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            navBar
            weeklySummary
            Divider()
            recentList
        }
        .padding(12)
        .frame(width: 320, height: 460)
        .controlSize(.small)
        .onAppear { sessions = store.fetchAllSessions() }
    }

    /// Compact title bar: back chevron + title.
    private var navBar: some View {
        HStack(spacing: 6) {
            Button {
                onDone()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "common.back", defaultValue: "返回"))
            Text(String(localized: "summary.title", defaultValue: "记录与总结")).font(.headline)
            Spacer()
        }
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                statBadge(String(localized: "goal.strength", defaultValue: "力量"),
                          stats.strengthCount, goal.weeklyStrengthTarget)
                statBadge(String(localized: "goal.run", defaultValue: "跑步"),
                          stats.runCount, goal.weeklyRunTarget)
                statBadge(String(localized: "goal.recovery", defaultValue: "腰背恢复"),
                          stats.recoveryCount, goal.weeklyRecoveryTarget)
            }
            trendChart
                .frame(height: 90)
            Text(generatedSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 7-day activity trend: one bar per day, height = number of sessions.
    private var trendChart: some View {
        let daily = dailyCounts()
        let maxCount = max(1, daily.map(\.count).max() ?? 1)
        return Chart(daily) { day in
            BarMark(
                x: .value("day", day.label),
                y: .value("count", day.count)
            )
            .foregroundStyle(day.count > 0 ? Color.accentColor : Color.secondary.opacity(0.3))
            .cornerRadius(3)
        }
        .chartYScale(domain: 0...maxCount)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisValueLabel().font(.caption2)
            }
        }
    }

    /// Aggregate recent sessions into per-day counts (oldest→newest).
    private struct DayCount: Identifiable {
        let id: String
        let label: String
        var count: Int
    }
    private func dailyCounts() -> [DayCount] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var buckets = (0..<7).map { offset -> (Date, DayCount) in
            let day = cal.date(byAdding: .day, value: -(6 - offset), to: today)!
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "EEE"
            return (day, DayCount(id: f.string(from: day), label: f.string(from: day), count: 0))
        }
        let indexByKey = Dictionary(uniqueKeysWithValues: buckets.enumerated().map { ($0.element.0, $0.offset) })
        for s in recent where s.type.isActivity {
            let key = cal.startOfDay(for: s.date)
            if let idx = indexByKey[key] { buckets[idx].1.count += 1 }
        }
        return buckets.map(\.1)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "summary.recent", defaultValue: "最近 7 天"))
                .font(.headline)
            if recent.isEmpty {
                Text(String(localized: "summary.empty", defaultValue: "还没有记录。从菜单栏快速记录一次吧。"))
                    .foregroundStyle(.secondary)
                    .padding(.vertical)
            } else {
                List {
                    ForEach(recent) { session in
                        sessionRow(session)
                    }
                    .onDelete { indexSet in
                        indexSet.map { recent[$0] }.forEach { store.delete($0) }
                        sessions = store.fetchAllSessions()
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func sessionRow(_ s: WorkoutSession) -> some View {
        HStack {
            Image(systemName: s.type.systemImage).foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading) {
                Text(s.type.localizedName)
                if let feeling = s.bodyFeeling { Text(feeling).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(s.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                Text("\(s.durationMinutes) min").font(.caption).monospacedDigit()
            }
            // Visible delete affordance (left-swipe also works via .onDelete).
            Button(role: .destructive) {
                withAnimation { store.delete(s) }
                sessions = store.fetchAllSessions()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "summary.delete", defaultValue: "删除这条记录"))
        }
    }

    private func statBadge(_ label: String, _ done: Int, _ target: Int) -> some View {
        VStack {
            Text("\(done)/\(target)").font(.title3).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// A rule-based weekly summary. (LLM-based summaries are Phase 5+.)
    private var generatedSummary: String {
        var parts: [String] = []
        parts.append("本周力量 \(stats.strengthCount)、跑步 \(stats.runCount)、腰背恢复 \(stats.recoveryCount)。")
        if stats.strengthCount >= goal.weeklyStrengthTarget && stats.runCount >= goal.weeklyRunTarget {
            parts.append("整体完成度很好,下周保持当前频率。")
        } else if stats.strengthCount < goal.weeklyStrengthTarget {
            parts.append("力量还差 \(goal.weeklyStrengthTarget - stats.strengthCount) 次,建议补齐。")
        }
        return parts.joined()
    }
}
