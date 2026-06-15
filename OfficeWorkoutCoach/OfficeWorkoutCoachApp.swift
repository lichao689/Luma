import SwiftUI
import SwiftData
import AppKit
import OfficeWorkoutLogic

@main
struct OfficeWorkoutCoachApp: App {
    @StateObject private var store: WorkoutStore
    @StateObject private var notifier = NotificationManager.sharedInstance
    private static let menuBarTemplateImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppMenuBarIconTemplate", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    init() {
        // Build the store eagerly so the menu-bar badge has data immediately.
        let store: WorkoutStore
        do { store = try WorkoutStore() }
        catch { fatalError("Unable to initialize WorkoutStore: \(error)") }
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        // The menu-bar entry is the app's primary surface.
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(store)
                .environmentObject(notifier)
                .modelContainer(store.container)
                .task {
                    // One-time bootstrap: request notification auth + start loop.
                    await notifier.requestAuthorization()
                    notifier.startMonitoring(
                        goal: UserGoalValues(store.fetchGoal())
                    ) {
                        store.currentStats()
                    }
                }
        } label: {
            badgeLabel
        }
        .menuBarExtraStyle(.window)

        SettingsView()
            .environmentObject(store)
            .modelContainer(store.container)

        // 独立的动作示意窗口。popover 太窄放不下视频,这里给它正常尺寸。
        // 通过 openWindow(id: "exerciseGuide") 打开。
        Window(String(localized: "scene.guide.title", defaultValue: "动作示意"), id: "exerciseGuide") {
            ExerciseGuideView(preselected: nil)
        }
        .defaultSize(width: 800, height: 560)
    }

    /// Menu-bar badge: icon + today's unmet-goal count.
    ///
    /// Shows "还差 N" where N = today's goals not yet met (strength + recovery
    /// daily + run this week). When all met, the icon goes solid and the count
    /// is hidden. This answers "今天还差几样" at a glance — broader than the old
    /// strength-only `x/y` which ignored runs/recovery.
    /// Reading `store.changeToken` creates the SwiftUI dependency that makes
    /// the badge refresh after each log/delete.
    @ViewBuilder private var badgeLabel: some View {
        let _ = store.changeToken   // observe mutations
        let stats = store.currentStats()
        let goal = UserGoalValues(store.fetchGoal())
        let unmet = todayUnmetCount(stats: stats, goal: goal)
        let allMet = unmet == 0
        HStack(spacing: 3) {
            menuBarIcon(met: allMet)
            if !allMet {
                Text("\(unmet)")
                    .monospacedDigit()
            }
        }
        .help(badgeHelp(stats: stats, goal: goal))
    }

    /// Count of today's goals not yet met (for the badge number).
    private func todayUnmetCount(stats: WorkoutStats, goal: UserGoalValues) -> Int {
        var n = 0
        if stats.strengthCountToday < goal.dailyStrengthTarget { n += 1 }
        if stats.recoveryCountToday < goal.dailyRecoveryTarget { n += 1 }
        if stats.runCount < goal.weeklyRunTarget { n += 1 }
        return n
    }

    /// Hover tooltip summarizing today/week progress.
    private func badgeHelp(stats: WorkoutStats, goal: UserGoalValues) -> String {
        [
            "力量 \(stats.strengthCountToday)/\(goal.dailyStrengthTarget) 今日 · \(stats.strengthCount)/\(goal.weeklyStrengthTarget) 本周",
            "恢复 \(stats.recoveryCountToday)/\(goal.dailyRecoveryTarget) 今日 · \(stats.recoveryCount)/\(goal.weeklyRecoveryTarget) 本周",
            "跑步 \(stats.runCount)/\(goal.weeklyRunTarget) 本周"
        ].joined(separator: "\n")
    }

    @ViewBuilder private func menuBarIcon(met: Bool) -> some View {
        if let image = Self.menuBarTemplateImage {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .opacity(met ? 1.0 : 0.82)
        } else {
            Image(systemName: met ? "figure.strengthtraining.traditional.fill"
                                  : "figure.strengthtraining.traditional")
        }
    }
}
