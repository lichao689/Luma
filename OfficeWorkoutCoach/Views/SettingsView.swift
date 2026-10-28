import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
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
            dataTab.tabItem { Label(String(localized: "settings.data", defaultValue: "数据"), systemImage: "externaldrive") }
        }
        .frame(width: 440, height: 380)
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
                Picker(String(localized: "settings.cooldown", defaultValue: "两次提醒至少间隔"), selection: $values.sedentaryCooldownMinutes) {
                    Text(String(localized: "settings.cooldown.30", defaultValue: "30 分钟")).tag(30)
                    Text(String(localized: "settings.cooldown.45", defaultValue: "45 分钟")).tag(45)
                    Text(String(localized: "settings.cooldown.60", defaultValue: "60 分钟")).tag(60)
                    Text(String(localized: "settings.cooldown.90", defaultValue: "90 分钟")).tag(90)
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

    @ViewBuilder private var dataTab: some View {
        Form {
            Section {
                Button {
                    exportCSV()
                } label: {
                    Label(String(localized: "settings.export", defaultValue: "导出为 CSV…"),
                          systemImage: "square.and.arrow.up")
                }
                Text(String(localized: "settings.export.hint",
                            defaultValue: "导出全部训练记录,包含每组的次数与重量,可直接用 Excel 或 Numbers 打开。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "settings.data", defaultValue: "数据"))
            } footer: {
                Text(String(localized: "settings.export.footer",
                            defaultValue: "数据只存在本机,重装系统或换机前记得先导出一份。"))
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    /// 导出 CSV。菜单栏 App 要先 activate,保存面板才会到前台。
    private func exportCSV() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmm"
        panel.nameFieldStringValue = "luma-\(stamp.string(from: .now)).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.exportCSV().write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Persistence

    private func persist() {        guard loaded else { return }
        store.updateGoal(values)
        NotificationManager.shared.refresh(from: values)
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
