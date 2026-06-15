import SwiftUI
import SwiftData
import OfficeWorkoutLogic

/// Tabbed settings: weekly goals, reminders, and work window.
///
/// We mirror the singleton `UserGoal` row into a local `@State` value type on
/// appear and persist back on each change. This avoids juggling optional
/// SwiftData bindings across enum/weekday fields.
struct SettingsView: Scene {
    var body: some Scene {
        Settings {
            SettingsContent()
                .environmentObject(WorkoutStore.sharedContainer)
        }
    }
}

private struct SettingsContent: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var values: UserGoalValues = .default
    @State private var loaded = false

    var body: some View {
        TabView {
            goalsTab.tabItem { Label(String(localized: "settings.goals", defaultValue: "目标"), systemImage: "target") }
            remindersTab.tabItem { Label(String(localized: "settings.reminders", defaultValue: "提醒"), systemImage: "bell") }
            windowTab.tabItem { Label(String(localized: "settings.window", defaultValue: "时间窗"), systemImage: "clock") }
        }
        .frame(width: 420, height: 340)
        .onAppear { if !loaded { values = UserGoalValues(store.fetchGoal()); loaded = true } }
    }

    @ViewBuilder private var goalsTab: some View {
        Form {
            Section(String(localized: "settings.daily", defaultValue: "每日目标")) {
                Stepper(value: $values.dailyStrengthTarget, in: 0...3) {
                    labelRow(String(localized: "goal.strength", defaultValue: "力量"), values.dailyStrengthTarget)
                }
                Stepper(value: $values.dailyRecoveryTarget, in: 0...5) {
                    labelRow(String(localized: "goal.recovery", defaultValue: "恢复"), values.dailyRecoveryTarget)
                }
            }
            Section(String(localized: "settings.weekly", defaultValue: "每周目标")) {
                Stepper(value: $values.weeklyStrengthTarget, in: 0...14) {
                    labelRow(String(localized: "goal.strength", defaultValue: "力量"), values.weeklyStrengthTarget)
                }
                Stepper(value: $values.weeklyRecoveryTarget, in: 0...21) {
                    labelRow(String(localized: "goal.recovery", defaultValue: "恢复"), values.weeklyRecoveryTarget)
                }
                Stepper(value: $values.weeklyRunTarget, in: 0...7) {
                    labelRow(String(localized: "goal.run", defaultValue: "跑步"), values.weeklyRunTarget)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: values) { persist() }
    }

    @ViewBuilder private var remindersTab: some View {
        Form {
            Section(String(localized: "settings.mode", defaultValue: "提醒模式")) {
                Picker(String(localized: "settings.mode", defaultValue: "提醒模式"), selection: $values.reminderMode) {
                    ForEach(ReminderMode.allCases) { Text($0.localizedName).tag($0) }
                }
                Toggle(String(localized: "settings.flexible", defaultValue: "当日运动柔性提醒"),
                       isOn: $values.enableFlexibleReminder)
            }
            Section {
                Picker(String(localized: "settings.threshold", defaultValue: "连续操作多久后提醒"), selection: $values.sedentaryReminderMinutes) {
                    Text(String(localized: "settings.min60", defaultValue: "60 分钟")).tag(60)
                    Text(String(localized: "settings.min75", defaultValue: "75 分钟")).tag(75)
                    Text(String(localized: "settings.min90", defaultValue: "90 分钟")).tag(90)
                    Text(String(localized: "settings.off", defaultValue: "关闭")).tag(0)
                }
            } header: {
                Text(String(localized: "settings.sedentary", defaultValue: "久坐提醒"))
            } footer: {
                Text(String(localized: "settings.sedentary.footer",
                     defaultValue: "连续在电脑前操作超过该时长且没有真正离开(空闲≥10 分钟)时,提醒做一组腰背恢复。会议/演示应用(Zoom、腾讯会议等)在前台时会自动延迟。"))
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .onChange(of: values) { persist() }
    }

    @ViewBuilder private var windowTab: some View {
        Form {
            Section(String(localized: "settings.workWindow", defaultValue: "工作时间窗")) {
                Picker(String(localized: "settings.start", defaultValue: "开始"), selection: $values.workStartMinutes) {
                    ForEach([570, 600, 630, 660, 690, 720], id: \.self) { Text(timeString($0)).tag($0) }
                }
                Picker(String(localized: "settings.end", defaultValue: "结束"), selection: $values.workEndMinutes) {
                    ForEach([1080, 1110, 1140, 1170, 1200], id: \.self) { Text(timeString($0)).tag($0) }
                }
            }
            Section(String(localized: "settings.weekdays", defaultValue: "工作日")) {
                ForEach(weekdayOptions, id: \.value) { option in
                    Toggle(option.label, isOn: weekdayToggleBinding(option.value))
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: values) { persist() }
    }

    // MARK: - Persistence

    private func persist() {
        let goal = store.fetchGoal()
        goal.dailyStrengthTarget = values.dailyStrengthTarget
        goal.weeklyStrengthTarget = values.weeklyStrengthTarget
        goal.dailyRecoveryTarget = values.dailyRecoveryTarget
        goal.weeklyRecoveryTarget = values.weeklyRecoveryTarget
        goal.weeklyRunTarget = values.weeklyRunTarget
        goal.sedentaryReminderMinutes = values.sedentaryReminderMinutes
        goal.enableFlexibleReminder = values.enableFlexibleReminder
        goal.reminderMode = values.reminderMode
        goal.workStartMinutes = values.workStartMinutes
        goal.workEndMinutes = values.workEndMinutes
        goal.workWeekdays = values.workWeekdays
        try? goal.modelContext?.save()
        NotificationManager.sharedInstance.refresh(from: values)
    }

    // MARK: - Helpers

    private func labelRow(_ label: String, _ value: Int) -> some View {
        HStack { Text(label); Spacer(); Text("\(value)").monospacedDigit().foregroundStyle(.secondary) }
    }

    private func timeString(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private struct WeekdayOption { let value: Int; let label: String }
    private let weekdayOptions: [WeekdayOption] = [
        .init(value: 2, label: "周一"), .init(value: 3, label: "周二"),
        .init(value: 4, label: "周三"), .init(value: 5, label: "周四"),
        .init(value: 6, label: "周五"), .init(value: 7, label: "周六"),
        .init(value: 1, label: "周日")
    ]

    private func weekdayToggleBinding(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { values.workWeekdays.contains(day) },
            set: { isOn in
                if isOn, !values.workWeekdays.contains(day) { values.workWeekdays.append(day) }
                else if !isOn { values.workWeekdays.removeAll { $0 == day } }
                values.workWeekdays.sort()
            }
        )
    }
}
