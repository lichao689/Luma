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

    /// Menu-bar badge: icon + weekly strength progress, e.g. "🏃 2/3".
    /// We use an explicit HStack rather than Label because MenuBarExtra hides
    /// Label text by default — only the icon would show.
    /// Reading `store.changeToken` creates the SwiftUI dependency that makes
    /// the badge refresh after each log/delete.
    @ViewBuilder private var badgeLabel: some View {
        let _ = store.changeToken   // observe mutations
        let stats = store.currentStats()
        let goal = UserGoalValues(store.fetchGoal())
        let done = min(stats.strengthCount, goal.weeklyStrengthTarget)
        let target = goal.weeklyStrengthTarget
        let met = done >= target
        HStack(spacing: 3) {
            menuBarIcon(met: met)
            Text("\(done)/\(target)")
                .monospacedDigit()
        }
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
