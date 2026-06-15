import SwiftUI
import SwiftData
import AppKit
import OfficeWorkoutLogic

@main
struct OfficeWorkoutCoachApp: App {
    @StateObject private var store: WorkoutStore
    @StateObject private var notifier = NotificationManager.sharedInstance
    @State private var badgeClockTick = 0
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

    /// Menu-bar badge: icon + three colored progress chips.
    ///
    /// Layout: `💪 0/1 3/7 · 0/2 5/14 · 1/2`
    /// Each number pair sits in a colored capsule: green when met, red when not.
    /// Strength/recovery show today/week; run shows week only.
    /// Reading `store.changeToken` creates the SwiftUI dependency that makes
    /// the badge refresh after each log/delete.
    @ViewBuilder private var badgeLabel: some View {
        let _ = store.changeToken   // observe mutations
        let _ = badgeClockTick      // refresh day/week rollover while app stays open
        let stats = store.currentStats()
        let goal = UserGoalValues(store.fetchGoal())

        HStack(spacing: 3) {
            menuBarIcon(allMet: allGoalsMet(stats: stats, goal: goal))
            // 力量: today/week
            chipPair(today: stats.strengthCountToday, todayTarget: goal.dailyStrengthTarget,
                     week: stats.strengthCount, weekTarget: goal.weeklyStrengthTarget)
            Text("·").foregroundStyle(.secondary)
            // 恢复: today/week
            chipPair(today: stats.recoveryCountToday, todayTarget: goal.dailyRecoveryTarget,
                     week: stats.recoveryCount, weekTarget: goal.weeklyRecoveryTarget)
            Text("·").foregroundStyle(.secondary)
            // 跑步: week only
            chip(week: stats.runCount, weekTarget: goal.weeklyRunTarget)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            badgeClockTick &+= 1
        }
    }

    /// Whether ALL goals (today + week) are met — drives the icon fill state.
    private func allGoalsMet(stats: WorkoutStats, goal: UserGoalValues) -> Bool {
        stats.strengthCountToday >= goal.dailyStrengthTarget &&
        stats.recoveryCountToday >= goal.dailyRecoveryTarget &&
        stats.runCount >= goal.weeklyRunTarget
    }

    /// One activity with today + week chips, e.g. `0/1 3/7`.
    @ViewBuilder private func chipPair(today: Int, todayTarget: Int, week: Int, weekTarget: Int) -> some View {
        chip(value: today, target: todayTarget, met: today >= todayTarget)
        chip(value: week, target: weekTarget, met: week >= weekTarget)
    }

    /// Week-only chip (for run), computing met from week count vs target.
    @ViewBuilder private func chip(week: Int, weekTarget: Int) -> some View {
        chip(value: week, target: weekTarget, met: week >= weekTarget)
    }

    /// A single colored count chip: green bg when met, red bg when not.
    @ViewBuilder private func chip(value: Int, target: Int, met: Bool) -> some View {
        Text("\(value)/\(target)")
            .monospacedDigit()
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(met ? Color.green : Color.red)
            )
    }

    @ViewBuilder private func menuBarIcon(allMet: Bool) -> some View {
        if let image = Self.menuBarTemplateImage {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .opacity(allMet ? 1.0 : 0.82)
        } else {
            Image(systemName: allMet ? "figure.strengthtraining.traditional.fill"
                                  : "figure.strengthtraining.traditional")
        }
    }
}
