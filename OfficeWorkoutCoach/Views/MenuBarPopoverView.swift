import SwiftUI
import SwiftData
import AppKit
import OfficeWorkoutLogic

/// The window that appears when the menu-bar icon is clicked.
struct MenuBarPopoverView: View {
    var onQuit: @MainActor () -> Void

    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var notifier: NotificationManager
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var sessions: [WorkoutSession] = []
    /// 保存成功后的轻量提示。菜单栏弹窗没有系统 toast,自己叠一个。
    @State private var toast: String?

    /// Inline page navigation. We avoid `.sheet` because dismissing a sheet
    /// inside a `MenuBarExtra(.window)` popover also closes the popover itself.
    /// Switching pages in place keeps the popover open and returns to home.
    private enum Page: Equatable {
        case home
        case quickLog(WorkoutType)
        case summary
    }
    @State private var page: Page = .home

    private var stats: WorkoutStats {
        let records = sessions.map { $0.asRecord }
        return WorkoutStatsService().stats(sessions: records)
    }
    private var goal: UserGoalValues { UserGoalValues(store.fetchGoal()) }
    private var recommendation: Recommendation {
        RecommendationEngine.default.recommend(stats: stats, goal: goal)
    }

    var body: some View {
        Group {
            switch page {
            case .home:
                homeView
            case .quickLog(let type):
                QuickLogView(type: type) { saved in
                    if saved { showToast(type) }
                    backToHome()
                }
            case .summary:
                SummaryView(onDone: backToHome)
            }
        }
        .frame(width: 340)
        .overlay(alignment: .top) { toastView }
        .onAppear { if page == .home { reload() } }
        // React to notification deep-links (e.g. tapping "开始 8 分钟").
        .onChange(of: notifier.pendingDeepLink) { _, link in
            guard let link else { return }
            switch link {
            case .startMinimal:
                withAnimation(.easeInOut(duration: 0.18)) { page = .quickLog(.minimal) }
            case .startRecovery:
                startWorkout(.recovery)
            }
            notifier.pendingDeepLink = nil
        }
    }

    // MARK: - 首页

    private var homeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            todayCard
            progressSection
            Divider()
            quickLogDisclosure
            Divider()
            footer
        }
        .padding(14)
        .controlSize(.small)
    }

    /// 今日建议卡片 —— 首页的视觉主体,回答"现在该做什么"。
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: recommendationIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "popover.today.title", defaultValue: "今日建议"))
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(recommendation.localizedTitle)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recommendation.localizedReason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            primaryButton
        }
        .padding(12)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var primaryButton: some View {
        Button {
            handleRecommendationTap()
        } label: {
            HStack(spacing: 6) {
                Text(recommendationCTA)
                if let minutes = workoutMinutes {
                    Text(String(localized: "popover.minutes", defaultValue: "约 \(minutes) 分钟"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
    }

    // MARK: - 进度

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(String(localized: "popover.progress.title", defaultValue: "今日进度"))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(weekSummaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            goalBar(label: String(localized: "goal.strength.short", defaultValue: "力量"),
                    done: stats.strengthCountToday, target: goal.dailyStrengthTarget)
            goalBar(label: String(localized: "goal.recovery.short", defaultValue: "恢复"),
                    done: stats.recoveryCountToday, target: goal.dailyRecoveryTarget)
            goalBar(label: String(localized: "goal.run.short", defaultValue: "跑步"),
                    done: stats.runCount, target: goal.weeklyRunTarget)
        }
    }

    /// 一条细进度条:达标转绿,否则用强调色。
    private func goalBar(label: String, done: Int, target: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 30, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.15))
                    Capsule()
                        .fill(done >= target ? Color.green : Color.accentColor)
                        .frame(width: geo.size.width * ratio(done: done, target: target))
                }
            }
            .frame(height: 5)
            Text("\(done)/\(target)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(done >= target ? .green : .secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func ratio(done: Int, target: Int) -> Double {
        guard target > 0 else { return done > 0 ? 1 : 0 }
        return min(1, Double(done) / Double(target))
    }

    private var weekSummaryText: String {
        let format = NSLocalizedString("popover.weekSummary", value: "本周 力量 %1$d · 恢复 %2$d · 跑步 %3$d", comment: "")
        return String(format: format, stats.strengthCount, stats.recoveryCount, stats.runCount)
    }

    // MARK: - 手动记录(默认折叠)

    private var quickLogDisclosure: some View {
        DisclosureGroup {
            LazyVGrid(columns: [.init(.adaptive(minimum: 92), alignment: .leading)], spacing: 6) {
                ForEach(WorkoutType.allCases) { type in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { page = .quickLog(type) }
                    } label: {
                        Label(type.localizedName, systemImage: type.systemImage)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, 6)
        } label: {
            Text(String(localized: "popover.manual", defaultValue: "手动记录(练完了补一条)"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 页脚

    /// 页脚统一为纯图标按钮:原来两个 `Label`(图标+文字)和两个裸 `Image`
    /// 混排,字号、视觉重量、点击热区都不一致,一行看着很毛躁。
    /// 名称放 tooltip,`accessibilityLabel` 保证 VoiceOver 仍能读到。
    private var footer: some View {
        HStack(spacing: 1) {
            footerButton(
                symbol: "list.bullet.rectangle",
                title: String(localized: "popover.records", defaultValue: "查看记录")
            ) {
                withAnimation(.easeInOut(duration: 0.18)) { page = .summary }
            }
            footerButton(
                symbol: "figure.strengthtraining.traditional",
                title: String(localized: "popover.guide", defaultValue: "动作示意")
            ) {
                // Menu-bar apps (LSUIElement) need activation before a Window
                // scene will come to the front; same reason openSettings needs it.
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "exerciseGuide")
            }
            Spacer(minLength: 0)
            footerButton(
                symbol: "gearshape",
                title: String(localized: "popover.settings", defaultValue: "设置")
            ) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            }
            footerButton(
                symbol: "power",
                title: String(localized: "popover.quit", defaultValue: "退出小盏")
            ) {
                onQuit()
            }
        }
    }

    private func footerButton(
        symbol: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.green.opacity(0.15), in: Capsule())
                .overlay(Capsule().stroke(.green.opacity(0.35), lineWidth: 0.5))
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func showToast(_ type: WorkoutType) {
        withAnimation(.easeOut(duration: 0.2)) { toast = "已记录 \(type.localizedName)" }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeIn(duration: 0.2)) { toast = nil }
        }
    }

    // MARK: - Derived

    private func backToHome() {
        reload()
        withAnimation(.easeInOut(duration: 0.18)) { page = .home }
    }

    private func reload() {
        sessions = store.fetchAllSessions()
    }

    private var recommendationIcon: String {
        switch recommendation.action {
        case .startStrength: return "figure.strengthtraining.traditional"
        case .logRun:        return "figure.run"
        case .recovery:      return "figure.cooldown"
        case .minimal:       return "timer"
        case .rest:          return "moon.zzz"
        }
    }

    private var recommendationCTA: String {
        switch recommendation.action {
        case .startStrength(let t): return String(localized: "popover.cta.begin", defaultValue: "开始") + " " + t.localizedName
        case .logRun:               return String(localized: "popover.cta.run", defaultValue: "跑步已完成")
        case .recovery:             return String(localized: "popover.cta.recovery", defaultValue: "开始腰背恢复")
        case .minimal:              return String(localized: "popover.cta.minimal", defaultValue: "开始 8 分钟")
        case .rest:                 return String(localized: "popover.cta.rest", defaultValue: "今天休息")
        }
    }

    /// 建议对应的预计时长,展示在按钮右侧。
    private var workoutMinutes: Int? {
        switch recommendation.action {
        case .startStrength(let t): return PrescriptionLibrary.estimatedMinutes(for: t)
        case .recovery:             return PrescriptionLibrary.estimatedMinutes(for: .recovery)
        case .minimal:
            return PrescriptionLibrary.minimalExercises.reduce(0) {
                $0 + PrescriptionLibrary.minimalPrescription(exerciseID: $1.id).estimatedMinutes
            }
        case .logRun, .rest:        return nil
        }
    }

    private func handleRecommendationTap() {
        switch recommendation.action {
        case .startStrength(let t):
            startWorkout(t)
        case .recovery:
            startWorkout(.recovery)
        case .minimal:
            startWorkout(.minimal)
        case .logRun:
            // 跑步没有动作序列,直接记录。
            withAnimation(.easeInOut(duration: 0.18)) { page = .quickLog(.run) }
        case .rest:
            withAnimation(.easeInOut(duration: 0.18)) { page = .quickLog(.rest) }
        }
    }

    /// 打开跟练窗口。菜单栏 App 必须先 activate,窗口才会到前台。
    private func startWorkout(_ plan: WorkoutType) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "workout", value: plan.rawValue)
    }
}
