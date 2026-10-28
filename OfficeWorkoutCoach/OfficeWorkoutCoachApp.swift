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
            MenuBarPopoverView(onQuit: quitApp)
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
        }
        .defaultSize(width: 800, height: 560)
    }

    @MainActor
    private func quitApp() {
        AppQuitAction(
            stopMonitoring: { notifier.stopMonitoring() },
            terminate: { NSApplication.shared.terminate(nil) }
        )()
    }

    /// Menu-bar badge: one rendered image containing icon + labeled progress chips.
    ///
    /// Layout: `S 0/1 3/7 / R 0/2 5/14 / R 1/2`.
    /// Each number pair sits in a colored capsule: green when met, soft red when not.
    /// The badge is rendered into a single non-template image because menu-bar
    /// labels clip/drop styling when given several SwiftUI subviews directly.
    /// Reading `store.changeToken` creates the SwiftUI dependency that makes
    /// the badge refresh after each log/delete.
    @ViewBuilder private var badgeLabel: some View {
        let _ = store.changeToken   // observe mutations
        let _ = badgeClockTick      // refresh day/week rollover while app stays open
        let stats = store.currentStats()
        let goal = UserGoalValues(store.fetchGoal())
        let title = badgeTitle(stats: stats, goal: goal)

        Image(nsImage: menuBarBadgeImage(stats: stats, goal: goal))
            .renderingMode(.original)
            .interpolation(.high)
            .accessibilityLabel(Text(title))
            .help(title)
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

    private struct BadgeChip {
        let text: String
        let met: Bool
    }

    private struct BadgeGroup {
        let label: String
        let titleLabel: String
        let chips: [BadgeChip]
    }

    private func badgeGroups(stats: WorkoutStats, goal: UserGoalValues) -> [BadgeGroup] {
        [
            BadgeGroup(
                label: "S",
                titleLabel: "力量",
                chips: [
                    BadgeChip(text: "\(stats.strengthCountToday)/\(goal.dailyStrengthTarget)",
                              met: stats.strengthCountToday >= goal.dailyStrengthTarget),
                    BadgeChip(text: "\(stats.strengthCount)/\(goal.weeklyStrengthTarget)",
                              met: stats.strengthCount >= goal.weeklyStrengthTarget)
                ]
            ),
            BadgeGroup(
                label: "R",
                titleLabel: "恢复",
                chips: [
                    BadgeChip(text: "\(stats.recoveryCountToday)/\(goal.dailyRecoveryTarget)",
                              met: stats.recoveryCountToday >= goal.dailyRecoveryTarget),
                    BadgeChip(text: "\(stats.recoveryCount)/\(goal.weeklyRecoveryTarget)",
                              met: stats.recoveryCount >= goal.weeklyRecoveryTarget)
                ]
            ),
            BadgeGroup(
                label: "R",
                titleLabel: "跑步",
                chips: [
                    BadgeChip(text: "\(stats.runCount)/\(goal.weeklyRunTarget)",
                              met: stats.runCount >= goal.weeklyRunTarget)
                ]
            )
        ]
    }

    private func badgeTitle(stats: WorkoutStats, goal: UserGoalValues) -> String {
        let groups = badgeGroups(stats: stats, goal: goal)
        return groups
            .map { group in "\(group.titleLabel) " + group.chips.map(\.text).joined(separator: " ") }
            .joined(separator: " / ")
    }

    private func menuBarBadgeImage(stats: WorkoutStats, goal: UserGoalValues) -> NSImage {
        let allMet = allGoalsMet(stats: stats, goal: goal)
        let groups = badgeGroups(stats: stats, goal: goal)

        let height: CGFloat = 22
        let iconSize: CGFloat = 16
        let chipHPad: CGFloat = 4
        let chipVPad: CGFloat = 2
        let cornerRadius: CGFloat = 4
        let gap: CGFloat = 4
        let groupGap: CGFloat = 7

        let labelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let chipFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let textColor = NSColor.white.withAlphaComponent(0.9)
        let separatorColor = NSColor.white.withAlphaComponent(0.55)
        let chipTextColor = NSColor.white
        let unmetChipColor = NSColor(calibratedRed: 0.86, green: 0.42, blue: 0.38, alpha: 0.78)
        let chipAttrs: [NSAttributedString.Key: Any] = [
            .font: chipFont,
            .foregroundColor: chipTextColor
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: textColor
        ]
        let separatorAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: separatorColor
        ]

        func textSize(_ text: String, attrs: [NSAttributedString.Key: Any]) -> NSSize {
            NSAttributedString(string: text, attributes: attrs).size()
        }

        let slashWidth = textSize("/", attrs: separatorAttrs).width
        let chipHeight = ceil(textSize("0/0", attrs: chipAttrs).height + chipVPad * 2)
        var width = iconSize + gap

        for (index, group) in groups.enumerated() {
            width += ceil(textSize(group.label, attrs: labelAttrs).width) + gap
            for chip in group.chips {
                width += ceil(textSize(chip.text, attrs: chipAttrs).width + chipHPad * 2) + gap
            }
            if index < groups.count - 1 {
                width += groupGap + slashWidth + groupGap
            }
        }

        let image = NSImage(size: NSSize(width: ceil(width), height: height))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        var x: CGFloat = 0
        let iconRect = NSRect(x: x, y: (height - iconSize) / 2, width: iconSize, height: iconSize)
        drawMenuBarIcon(in: iconRect, allMet: allMet, color: textColor)
        x += iconSize + gap

        for (index, group) in groups.enumerated() {
            let label = NSAttributedString(string: group.label, attributes: labelAttrs)
            let labelSize = label.size()
            label.draw(at: NSPoint(x: x, y: (height - labelSize.height) / 2))
            x += ceil(labelSize.width) + gap

            for chip in group.chips {
                let attributedChip = NSAttributedString(string: chip.text, attributes: chipAttrs)
                let chipSize = attributedChip.size()
                let chipWidth = ceil(chipSize.width + chipHPad * 2)
                let chipRect = NSRect(x: x, y: (height - chipHeight) / 2, width: chipWidth, height: chipHeight)
                (chip.met ? NSColor.systemGreen : unmetChipColor).setFill()
                NSBezierPath(roundedRect: chipRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
                attributedChip.draw(at: NSPoint(
                    x: x + chipHPad,
                    y: chipRect.minY + (chipHeight - chipSize.height) / 2
                ))
                x += chipWidth + gap
            }

            if index < groups.count - 1 {
                x += groupGap
                let slash = NSAttributedString(string: "/", attributes: separatorAttrs)
                let slashSize = slash.size()
                slash.draw(at: NSPoint(x: x, y: (height - slashSize.height) / 2))
                x += ceil(slashSize.width) + groupGap
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func drawMenuBarIcon(in rect: NSRect, allMet: Bool, color: NSColor) {
        if let image = Self.menuBarTemplateImage {
            NSGraphicsContext.saveGraphicsState()
            color.withAlphaComponent(allMet ? 1.0 : 0.75).setFill()
            rect.fill()
            image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        let symbolName = allMet ? "figure.strengthtraining.traditional.fill" : "figure.strengthtraining.traditional"
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return }
        symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: allMet ? 1.0 : 0.75)
    }
}
