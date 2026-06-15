import SwiftUI
import SwiftData
import OfficeWorkoutLogic

/// The window that appears when the menu-bar icon is clicked.
struct MenuBarPopoverView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var notifier: NotificationManager
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var sessions: [WorkoutSession] = []

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
                QuickLogView(type: type, onDone: backToHome)
            case .summary:
                SummaryView(onDone: backToHome)
            }
        }
        .frame(width: 320)
        .onAppear { if page == .home { reload() } }
        // React to notification deep-links (e.g. tapping "开始 8 分钟").
        .onChange(of: notifier.pendingDeepLink) { _, link in
            guard let link else { return }
            switch link {
            case .startMinimal:
                withAnimation(.easeInOut(duration: 0.18)) { page = .quickLog(.minimal) }
            }
            notifier.pendingDeepLink = nil
        }
    }

    private func backToHome() {
        reload()
        withAnimation(.easeInOut(duration: 0.18)) { page = .home }
    }

    private var homeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            todayCard
            Divider()
            quickActions
            Divider()
            progressRow
            Divider()
            footer
        }
        .padding(12)
        .controlSize(.small)
    }

    // MARK: - Subviews

    private var todayCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: recommendationIcon)
                .font(.system(size: 22))
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "popover.today.title", defaultValue: "今日建议"))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(recommendation.localizedTitle)
                    .font(.subheadline.weight(.semibold))
                Text(recommendation.localizedReason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                primaryButton
            }
        }
    }

    private var primaryButton: some View {
        Button {
            handleRecommendationTap()
        } label: {
            Text(recommendationCTA)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(localized: "popover.quick.title", defaultValue: "快速记录"))
                .font(.caption2).foregroundStyle(.secondary)
            LazyVGrid(columns: [.init(.adaptive(minimum: 84), alignment: .leading)], spacing: 5) {
                ForEach(WorkoutType.allCases) { type in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { page = .quickLog(type) }
                    } label: {
                        Label(type.localizedName, systemImage: type.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "popover.progress.title", defaultValue: "本周进度"))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                progressPill(String(localized: "goal.strength", defaultValue: "力量"),
                             stats.strengthCount, goal.weeklyStrengthTarget)
                progressPill(String(localized: "goal.run", defaultValue: "跑步"),
                             stats.runCount, goal.weeklyRunTarget)
                progressPill(String(localized: "goal.recovery", defaultValue: "腰背恢复"),
                             stats.recoveryCount, goal.weeklyRecoveryTarget)
            }
        }
    }

    private func progressPill(_ label: String, _ done: Int, _ target: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(done)/\(target)").monospacedDigit().font(.callout)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { page = .summary }
            } label: {
                Label(String(localized: "popover.records", defaultValue: "查看记录"), systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.borderless)
            Button {
                // Menu-bar apps (LSUIElement) need activation before a Window
                // scene will come to the front; same reason openSettings needs it.
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "exerciseGuide")
            } label: {
                Label(String(localized: "popover.guide", defaultValue: "动作示意"), systemImage: "figure.strengthtraining.traditional")
            }
            .buttonStyle(.borderless)
            Spacer()
            Button {
                // Menu-bar apps (LSUIElement) have no main window to activate,
                // and SettingsLink silently no-ops in that context. Activate the
                // app first, then open the Settings scene via openSettings.
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "popover.settings", defaultValue: "设置"))
        }
    }

    // MARK: - Derived

    private var recommendationIcon: String {
        switch recommendation.action {
        case .startStrength: return "figure.strengthtraining.traditional"
        case .logRun:        return "figure.run"
        case .recovery:      return "figure.cooldown"
        case .minimal:       return "timer"
        case .rest:          return "moon"
        }
    }

    private var recommendationCTA: String {
        switch recommendation.action {
        case .startStrength(let t):
            return String(localized: "popover.cta.start", defaultValue: "开始") + " " + t.localizedName
        case .logRun:        return String(localized: "popover.cta.run",     defaultValue: "跑步已完成")
        case .recovery:      return String(localized: "popover.cta.recovery", defaultValue: "做腰背恢复")
        case .minimal:       return String(localized: "popover.cta.minimal",  defaultValue: "做 8 分钟最低版")
        case .rest:          return String(localized: "popover.cta.rest",     defaultValue: "今天休息")
        }
    }

    private func handleRecommendationTap() {
        // The "primary CTA" leads into the quick-log page for the chosen
        // type; logging happens there so duration/feeling can be captured.
        let type: WorkoutType
        switch recommendation.action {
        case .startStrength(let t): type = t
        case .logRun:               type = .run
        case .recovery:             type = .recovery
        case .minimal:              type = .minimal
        case .rest:                 type = .rest
        }
        withAnimation(.easeInOut(duration: 0.18)) { page = .quickLog(type) }
    }

    private func reload() {
        sessions = store.fetchAllSessions()
    }
}
