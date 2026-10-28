import Foundation
import UserNotifications
import AppKit
import AVFoundation
import OfficeWorkoutLogic

/// Drives all local notifications + the sedentary-reminder escalation chain.
///
/// The sedentary behavior is a direct port of `tools/health-reminder/sedentary_reminder.sh`:
///   • idle reset after ~10 min real break
///   • work window Mon–Fri 09:30–18:30
///   • defer when a meeting/presentation app is frontmost
///   • escalation: notify → (2 min) voice → (10 min) modal dialog
/// Only the transport changed from launchd/AppleScript to native AppKit.
@MainActor
final class NotificationManager: NSObject, ObservableObject {

    /// Deep-link request set when the user taps a notification action.
    /// The popover observes this, navigates accordingly, then resets it.
    enum DeepLink: Equatable {
        case startMinimal     // "开始 8 分钟" → minimal quick-log page
        case startRecovery    // 久坐提醒 → 腰背恢复跟练
    }
    @Published var pendingDeepLink: DeepLink?

    // Notification identifiers
    enum Category: String {
        case flexible   = "FLEXIBLE"
        case weekly     = "WEEKLY"
        case sedentary  = "SEDENTARY"
    }

    // Apps that should suppress the sedentary reminder (from the shell script).
    static let deferredApps: Set<String> = [
        "zoom.us", "腾讯会议", "Microsoft Teams", "FaceTime",
        "Keynote", "Microsoft PowerPoint"
    ]

    // UserDefaults keys: 只保留"最后一次"的标记,不再按日期/周次无限新增。
    static let lastFlexibleDayKey = "flex.lastFiredDay"
    static let lastWeeklyWeekKey = "weekly.lastFiredWeek"

    // Escalation thresholds (seconds). Match the shell script's constants.
    private let restThreshold: TimeInterval = 600           // 10 min idle = real break
    private let voiceEscalationAfter: TimeInterval = 120    // 2 min → speak
    private let dialogEscalationAfter: TimeInterval = 600   // 10 min → modal

    // Mutable reminder state (persisted across ticks within a run).
    private var activeSince: Date?
    private var lastAlertAt: Date?
    private var snoozeUntil: Date?

    private var tickTimer: Timer?
    /// Latest goal snapshot, used for re-evaluating on settings change.
    private var currentGoal: UserGoalValues = .default

    /// 跟练进行中时置 true,久坐提醒会跳过 —— 否则练到一半被弹窗打断。
    /// 由 `WorkoutStartView` 在开始/结束时设置。
    var isWorkoutInProgress = false

    /// 唯一的共享实例。注入环境、通知回调、设置页刷新都走这一个 ——
    /// 之前这里同时存在 `shared` 和 `sharedInstance` 两个实例,导致通知
    /// 回调把深链写进了另一个对象,点「开始 8 分钟」没有反应。
    static let shared = NotificationManager()

    override init() {
        super.init()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // User denied; reminders simply stay silent. Settings can re-request.
        }
        registerCategories()
    }

    private func registerCategories() {
        let start = UNNotificationAction(identifier: "START", title: String(localized: "notif.action.start", defaultValue: "开始 8 分钟"), options: .foreground)
        let later  = UNNotificationAction(identifier: "LATER", title: String(localized: "notif.action.later", defaultValue: "稍后提醒"))
        let done  = UNNotificationAction(identifier: "REST_TODAY", title: String(localized: "notif.action.rest", defaultValue: "今天休息"))

        let flex = UNNotificationCategory(identifier: Category.flexible.rawValue, actions: [start, later, done], intentIdentifiers: [], options: [])
        let weekly = UNNotificationCategory(identifier: Category.weekly.rawValue, actions: [start, later], intentIdentifiers: [], options: [])
        let sedentary = UNNotificationCategory(identifier: Category.sedentary.rawValue, actions: [start, later], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([flex, weekly, sedentary])
    }

    // MARK: - Tick loop

    /// Start the periodic evaluation loop. Call once at launch.
    func startMonitoring(goal: UserGoalValues, statsProvider: @escaping () -> WorkoutStats) {
        stopMonitoring()
        self.currentGoal = goal
        // Capture the provider so each tick reads fresh data.
        self.statsProvider = statsProvider
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func stopMonitoring() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    /// Re-apply goal changes (called from Settings) without restarting the timer.
    func refresh(from goal: UserGoalValues) {
        self.currentGoal = goal
    }

    private var statsProvider: (() -> WorkoutStats)?

    private func tick() {
        guard let stats = statsProvider?() else { return }
        let goal = currentGoal
        let now = Date()

        // Flexible + weekly reminders piggyback on the same tick.
        if goal.enableFlexibleReminder {
            evaluateFlexible(stats: stats, goal: goal, now: now)
            evaluateWeekly(stats: stats, goal: goal, now: now)
        }

        // Sedentary reminder (only when enabled and in work window).
        if goal.sedentaryReminderMinutes > 0 {
            evaluateSedentary(goal: goal, now: now)
        }
    }

    // MARK: - Flexible (no activity today)

    private func evaluateFlexible(stats: WorkoutStats, goal: UserGoalValues, now: Date) {
        guard goal.reminderMode != .light else { return }
        guard !stats.hasActivityToday, withinWorkWindow(goal: goal, now: now) else { return }
        // 只存"最后一次触发的日期",不再每天新建一个 key(旧写法一年会攒 365 个)。
        let today = dayKey(now)
        guard UserDefaults.standard.string(forKey: Self.lastFlexibleDayKey) != today else { return }
        fireFlexible(now: now)
        UserDefaults.standard.set(today, forKey: Self.lastFlexibleDayKey)
    }

    // MARK: - Weekly goal (Fri/Sat nudge if strength still short)

    private func evaluateWeekly(stats: WorkoutStats, goal: UserGoalValues, now: Date) {
        guard goal.reminderMode == .strict else { return }
        let weekday = Calendar.current.component(.weekday, from: now)
        guard weekday == 6 || weekday == 7 else { return } // Fri(6)/Sat(7)
        guard stats.strengthCount < goal.weeklyStrengthTarget else { return }
        let thisWeek = weekKey(now)
        guard UserDefaults.standard.string(forKey: Self.lastWeeklyWeekKey) != thisWeek else { return }
        fireWeekly(short: goal.weeklyStrengthTarget - stats.strengthCount, now: now)
        UserDefaults.standard.set(thisWeek, forKey: Self.lastWeeklyWeekKey)
    }

    // MARK: - Sedentary escalation (ported from shell)

    private func evaluateSedentary(goal: UserGoalValues, now: Date) {
        // 跟练进行中不打断;顺手把久坐计时归零,练完重新累计。
        guard !isWorkoutInProgress else {
            activeSince = nil
            return
        }
        guard withinWorkWindow(goal: goal, now: now) else {
            activeSince = nil
            return
        }
        if let snooze = snoozeUntil, now < snooze { return }

        if isMeetingAppFrontmost() {
            snoozeUntil = now.addingTimeInterval(600)
            return
        }

        let idle = systemIdleSeconds()
        if idle >= restThreshold {
            // Real break: reset the active clock.
            activeSince = nil
            return
        }

        if activeSince == nil { activeSince = now.addingTimeInterval(-idle) }
        guard let activeSince else { return }
        let activeDuration = now.timeIntervalSince(activeSince)
        let threshold = TimeInterval(goal.sedentaryReminderMinutes * 60)
        guard activeDuration >= threshold else { return }
        let cooldown = TimeInterval(goal.sedentaryCooldownMinutes * 60)
        if let last = lastAlertAt, now.timeIntervalSince(last) < cooldown { return }

        // Stage 1: notification.
        fireSedentary(now: now)
        lastAlertAt = now

        // Schedule escalation checks asynchronously on the main actor.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.voiceEscalationAfter ?? 120) * 1_000_000_000)
            guard let self else { return }
            if self.systemIdleSeconds() < self.voiceEscalationAfter {
                self.speakSedentary()
            }
            let remaining = (self.dialogEscalationAfter - self.voiceEscalationAfter)
            try? await Task.sleep(nanoseconds: UInt64(remaining) * 1_000_000_000)
            if self.systemIdleSeconds() < self.restThreshold {
                self.presentSedentaryDialog()
            }
        }
    }

    // MARK: - Firing notifications

    private func fireFlexible(now: Date) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notif.flex.title", defaultValue: "今天还没运动")
        content.body = String(localized: "notif.flex.body", defaultValue: "现在适合做一个 8 分钟最低版吗?")
        content.categoryIdentifier = Category.flexible.rawValue
        content.sound = .default
        let req = UNNotificationRequest(identifier: "flex-\(now.timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func fireWeekly(short: Int, now: Date) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notif.weekly.title", defaultValue: "本周力量还差 \(short) 次")
        content.body = String(localized: "notif.weekly.body", defaultValue: "建议今天做力量 B 或最低版,把目标补齐。")
        content.categoryIdentifier = Category.weekly.rawValue
        content.sound = .default
        let req = UNNotificationRequest(identifier: "weekly-\(now.timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func fireSedentary(now: Date) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notif.sedentary.title", defaultValue: "坐久了")
        content.body = String(localized: "notif.sedentary.body", defaultValue: "做一组腰背恢复:猫牛式、臀桥、鸟狗、髋屈肌拉伸。")
        content.categoryIdentifier = Category.sedentary.rawValue
        content.sound = .default
        let req = UNNotificationRequest(identifier: "sed-\(now.timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Voice + dialog escalation

    private func speakSedentary() {
        let utterance = AVSpeechUtterance(
            string: String(localized: "voice.sedentary", defaultValue: "该站起来活动十分钟了。先离开屏幕,做护腰、力量和远眺。")
        )
        // Default voice; use Chinese locale if available for natural reading.
        if let voice = AVSpeechSynthesisVoice(language: "zh-CN") { utterance.voice = voice }
        AVSpeechSynthesizer().speak(utterance)
    }

    private func presentSedentaryDialog() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "dialog.sedentary.title", defaultValue: "健康微休息")
        alert.informativeText = String(localized: "dialog.sedentary.body", defaultValue: "你已连续工作超过 1 小时,提醒后仍未休息。现在站起来活动 10 分钟。")
        alert.addButton(withTitle: String(localized: "dialog.sedentary.standup", defaultValue: "我现在起身"))
        alert.addButton(withTitle: String(localized: "dialog.sedentary.snooze", defaultValue: "延后 10 分钟"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // User stood up → reset the continuous-activity clock.
            activeSince = nil
        }
        snoozeUntil = Date().addingTimeInterval(600)
    }

    // MARK: - Helpers

    private func isMeetingAppFrontmost() -> Bool {
        guard let name = NSWorkspace.shared.frontmostApplication?.localizedName else { return false }
        return Self.deferredApps.contains(name)
    }

    /// Seconds since the last keyboard/mouse input system-wide.
    /// Equivalent to the shell script's `ioreg HIDIdleTime` reading.
    private func systemIdleSeconds() -> TimeInterval {
        // `.null` is the sentinel for "any event type" → seconds since the last
        // keyboard/mouse input, matching the shell script's `ioreg HIDIdleTime`.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }

    private func withinWorkWindow(goal: UserGoalValues, now: Date) -> Bool {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        guard goal.workWeekdays.contains(weekday) else { return false }
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return minutes >= goal.workStartMinutes && minutes <= goal.workEndMinutes
    }

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func weekKey(_ date: Date) -> String {
        // A stable week identifier so the weekly nudge fires at most once/week.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(comps.yearForWeekOfYear ?? 0)-W\(comps.weekOfYear ?? 0)"
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Reveal the app when the user taps a notification action, and
        // request a deep-link navigation for the START action.
        let isStart = response.actionIdentifier == "START"
        let category = response.notification.request.content.categoryIdentifier
        Task { @MainActor in
            NSApplication.shared.activate(ignoringOtherApps: true)
            if isStart {
                // 久坐提醒说的是"做一组腰背恢复",就该跳到腰背恢复;
                // 柔性提醒才是"8 分钟最低版"。之前一律跳最低版,语义对不上。
                let link: NotificationManager.DeepLink =
                    category == NotificationManager.Category.sedentary.rawValue
                    ? .startRecovery : .startMinimal
                NotificationManager.shared.pendingDeepLink = link
            }
        }
        completionHandler()
    }
}
