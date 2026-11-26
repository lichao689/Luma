import SwiftUI
import SwiftData
import AppKit
import OfficeWorkoutLogic

@main
struct OfficeWorkoutCoachApp: App {
    @StateObject private var store: WorkoutStore
    @StateObject private var notifier = NotificationManager.shared
    @StateObject private var workout = WorkoutCoordinator()
    @State private var bootstrapped = false
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
            MenuBarPopoverView(onQuit: quitApp)
                .environmentObject(store)
                .environmentObject(notifier)
                .environmentObject(workout)
                .modelContainer(store.container)
        } label: {
            badgeLabel
                .modifier(WorkoutLaunchModifier(notifier: notifier, workout: workout))
                .task { await bootstrap() }
                .onChange(of: store.changeToken) { notifier.refresh(from: UserGoalValues(store.fetchGoal())) }
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(String(localized: "command.quit", defaultValue: "退出小盏")) {
                    quitApp()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        SettingsView()
            .environmentObject(store)
            .modelContainer(store.container)

        // 独立的动作示意窗口。popover 太窄放不下视频,这里给它正常尺寸。
        // 通过 openWindow(id: "exerciseGuide") 打开。
        Window(String(localized: "scene.guide.title", defaultValue: "动作示意"), id: "exerciseGuide") {
            ExerciseGuideView(preselected: nil)
                .environmentObject(workout)
        }
        .defaultSize(width: 800, height: 560)

        // A single scene prevents two sessions from racing reminder and save state.
        Window(String(localized: "scene.workout.title", defaultValue: "训练计划与跟练"), id: "workout") {
            WorkoutStartView()
                .environmentObject(store)
                .environmentObject(workout)
                .modelContainer(store.container)
        }
        .defaultSize(width: 900, height: 620)
    }

    @MainActor
    private func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        await notifier.requestAuthorization()
        notifier.startMonitoring(goal: UserGoalValues(store.fetchGoal()),
            statsProvider: { store.currentStats() },
            restToday: {
                do {
                    _ = try store.saveWorkout(type: .rest, durationMinutes: 0,
                        completion: .full, intensity: 1, sets: [])
                } catch { store.lastError = userFacingError(error) }
            })
    }

    @MainActor
    private func quitApp() {
        if workout.hasUnsavedWork {
            workout.pause()
            let alert = NSAlert()
            alert.messageText = String(localized: "quit.unsaved.title", defaultValue: "还有尚未保存的训练")
            alert.informativeText = String(localized: "quit.unsaved.body", defaultValue: "返回跟练窗口可以结束并保存已完成的组。退出会丢弃本次未保存进度。")
            alert.addButton(withTitle: String(localized: "quit.unsaved.stay", defaultValue: "继续使用"))
            alert.addButton(withTitle: String(localized: "quit.unsaved.discard", defaultValue: "丢弃并退出"))
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        AppQuitAction(
            stopMonitoring: { notifier.stopMonitoring() },
            terminate: { NSApplication.shared.terminate(nil) }
        )()
    }

    /// 菜单栏徽标:图标 + 今日达标分数。
    ///
    /// 之前这里是 200 行手绘 NSImage,把 6 组比值(日/周 × 力量/恢复/跑步)
    /// 全塞进菜单栏 —— 既占地方又难读,两个 "R" 还分别是"恢复"和"跑步"。
    /// 现在只回答一个问题:今天还差几项;分项明细留给弹窗。
    @ViewBuilder private var badgeLabel: some View {
        let _ = store.changeToken   // observe mutations
        let _ = badgeClockTick      // refresh day rollover while app stays open
        let stats = store.currentStats()
        let goal = UserGoalValues(store.fetchGoal())
        let progress = todayProgress(stats: stats, goal: goal)

        HStack(spacing: 3) {
            menuBarIcon(allMet: progress.allMet)
            if !progress.allMet {
                Text("\(progress.done)/\(progress.total)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(Text(progress.accessibilityText))
        .help(progress.accessibilityText)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            badgeClockTick &+= 1
        }
    }

    @ViewBuilder
    private func menuBarIcon(allMet: Bool) -> some View {
        if let image = Self.menuBarTemplateImage {
            Image(nsImage: image)
                .renderingMode(.template)
                .opacity(allMet ? 1.0 : 0.85)
        } else {
            Image(systemName: allMet ? "checkmark.circle.fill" : "figure.strengthtraining.traditional")
        }
    }

    private struct TodayProgress {
        let done: Int
        let total: Int
        let accessibilityText: String
        var allMet: Bool { total > 0 && done >= total }
    }

    /// 今日进度只统计有日目标的项(力量、恢复)。跑步是周目标,不计入今日。
    private func todayProgress(stats: WorkoutStats, goal: UserGoalValues) -> TodayProgress {
        let recommendation = RecommendationEngine.default.recommend(stats: stats, goal: goal)
        if case .rest = recommendation.action {
            return TodayProgress(done: 1, total: 1, accessibilityText: recommendation.localizedTitle)
        }
        var done = 0
        var total = 0
        let strengthDue: Bool
        if case .startStrength = recommendation.action { strengthDue = true }
        else { strengthDue = stats.strengthCountToday > 0 }
        if goal.dailyStrengthTarget > 0 && strengthDue {
            total += 1
            if stats.strengthCountToday >= goal.dailyStrengthTarget { done += 1 }
        }
        if goal.dailyRecoveryTarget > 0 {
            total += 1
            if stats.recoveryCountToday >= goal.dailyRecoveryTarget { done += 1 }
        }
        let format = NSLocalizedString(
            "badge.accessibility",
            value: "今日 %1$d/%2$d 项达标,本周力量 %3$d 次、跑步 %4$d 次",
            comment: ""
        )
        let text = String(format: format, done, total, stats.strengthCount, stats.runCount)
        return TodayProgress(done: done, total: total, accessibilityText: text)
    }
}
