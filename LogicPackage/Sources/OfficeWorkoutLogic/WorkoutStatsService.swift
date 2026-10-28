import Foundation

/// 腰痛信号的识别规则。
///
/// 分两路:结构化字段(`bodyFeeling` 存的是枚举 rawValue)直接比对,
/// 自由文本(`notes`)才做关键词扫描。
///
/// 刻意**不**把单独的 "back" 放进关键词表 —— 它会把
/// "back to normal"、"lower back feels fine" 这类备注误判成腰痛,
/// 进而错误地屏蔽硬拉和弓步。
public enum BackPainMarkers {
    /// `bodyFeeling` 字段里表示腰背不适的值(小写比对)。
    public static let feelingValues: Set<String> = [
        "backtight", "back_pain", "backpain", "lowerback"
    ]

    /// 只用于扫描备注文本。这些是完整短语,能直接命中。
    public static let noteTerms: [String] = [
        "腰紧", "腰酸", "腰痛", "腰疼", "腰不舒服",
        "back pain", "backache", "back tight", "back is tight", "lower back pain"
    ]

    /// 中文口语常把症状词隔开("腰有点酸""腰发紧"),所以再加一条共现规则:
    /// 同时出现"腰"和某个症状词,才算腰痛。
    private static let zhBodyPart = "腰"
    private static let zhSymptoms = ["酸", "痛", "紧", "疼", "僵", "麻", "不舒服", "不适"]

    /// 英文同理:"back" 单独出现不算(否则 "back to normal" 会误判),
    /// 必须和症状词共现。
    private static let enBodyPart = "back"
    private static let enSymptoms = ["pain", "ache", "tight", "sore", "stiff", "hurt"]

    public static func indicatesBackPain(feeling: String?) -> Bool {
        guard let feeling, !feeling.isEmpty else { return false }
        return feelingValues.contains(feeling.lowercased())
    }

    public static func indicatesBackPain(note: String?) -> Bool {
        guard let note, !note.isEmpty else { return false }
        let lower = note.lowercased()

        if noteTerms.contains(where: { lower.contains($0.lowercased()) }) { return true }

        if lower.contains(zhBodyPart), zhSymptoms.contains(where: { lower.contains($0) }) {
            return true
        }
        if lower.contains(enBodyPart), enSymptoms.contains(where: { lower.contains($0) }) {
            return true
        }
        return false
    }
}

/// Immutable snapshot of recent activity. The recommendation engine consumes
/// this so it stays a pure function with no I/O.
public struct WorkoutStats: Equatable {
    public let strengthCount: Int        // this week
    public let runCount: Int             // this week
    public let recoveryCount: Int        // this week
    public let strengthCountToday: Int   // today
    public let recoveryCountToday: Int   // today
    public let lastStrengthType: WorkoutType?
    public let daysSinceLastStrength: Int?
    public let consecutiveInactiveDays: Int
    /// 连续有训练的天数(今天还没练时从昨天往回数)。用于过度训练保护。
    public let consecutiveActiveDays: Int
    public let hasActivityToday: Bool
    public let hasRunToday: Bool
    public let recentBackPain: Bool

    public init(
        strengthCount: Int,
        runCount: Int,
        recoveryCount: Int,
        strengthCountToday: Int,
        recoveryCountToday: Int,
        lastStrengthType: WorkoutType?,
        daysSinceLastStrength: Int?,
        consecutiveInactiveDays: Int,
        consecutiveActiveDays: Int = 0,
        hasActivityToday: Bool,
        hasRunToday: Bool,
        recentBackPain: Bool
    ) {
        self.strengthCount = strengthCount
        self.runCount = runCount
        self.recoveryCount = recoveryCount
        self.strengthCountToday = strengthCountToday
        self.recoveryCountToday = recoveryCountToday
        self.lastStrengthType = lastStrengthType
        self.daysSinceLastStrength = daysSinceLastStrength
        self.consecutiveInactiveDays = consecutiveInactiveDays
        self.consecutiveActiveDays = consecutiveActiveDays
        self.hasActivityToday = hasActivityToday
        self.hasRunToday = hasRunToday
        self.recentBackPain = recentBackPain
    }
}

/// Reads `SessionRecord`s and produces a `WorkoutStats` snapshot.
public struct WorkoutStatsService {
    public let calendar: Calendar
    public let now: Date

    public init(calendar: Calendar = .current, now: Date = .now) {
        self.calendar = calendar
        self.now = now
    }

    public func stats(sessions: [SessionRecord]) -> WorkoutStats {
        let active = sessions.filter { $0.type.isActivity }
        let strength = active.filter { $0.type.countsAsStrength }

        let weekStart = startOfWeek()
        let thisWeek = active.filter { $0.date >= weekStart }
        let strengthThisWeek = thisWeek.filter { $0.type.countsAsStrength }
        let runThisWeek = thisWeek.filter { $0.type.countsAsRun }
        let recoveryThisWeek = thisWeek.filter { $0.type.countsAsRecovery }

        let lastStrength = strength.sorted { $0.date > $1.date }.first
        let daysSinceLastStrength = lastStrength.map { session in
            calendar.dateComponents([.day], from: calendar.startOfDay(for: session.date), to: calendar.startOfDay(for: now)).day ?? 0
        }

        let todayStart = calendar.startOfDay(for: now)
        let todays = active.filter { $0.date >= todayStart }
        let strengthToday = todays.filter { $0.type.countsAsStrength }
        let recoveryToday = todays.filter { $0.type.countsAsRecovery }

        let recentWindow = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let recentBackPain = sessions.contains { session in
            guard session.date >= recentWindow else { return false }
            return BackPainMarkers.indicatesBackPain(feeling: session.bodyFeeling)
                || BackPainMarkers.indicatesBackPain(note: session.note)
        }

        return WorkoutStats(
            strengthCount: strengthThisWeek.count,
            runCount: runThisWeek.count,
            recoveryCount: recoveryThisWeek.count,
            strengthCountToday: strengthToday.count,
            recoveryCountToday: recoveryToday.count,
            lastStrengthType: lastStrength?.type,
            daysSinceLastStrength: daysSinceLastStrength,
            consecutiveInactiveDays: consecutiveInactiveDays(active: active),
            consecutiveActiveDays: consecutiveActiveDays(active: active),
            hasActivityToday: !todays.isEmpty,
            hasRunToday: todays.contains { $0.type.countsAsRun },
            recentBackPain: recentBackPain
        )
    }

    /// Sessions from the last `days` days, newest first.
    public func recentSessions(_ sessions: [SessionRecord], days: Int = 7) -> [SessionRecord] {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        return sessions.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }
    }

    // MARK: - Private helpers

    private func startOfWeek() -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return cal.date(from: components) ?? now
    }

    private func consecutiveInactiveDays(active: [SessionRecord]) -> Int {
        let dayBuckets = Dictionary(grouping: active) { calendar.startOfDay(for: $0.date) }
        var cursor = calendar.startOfDay(for: now)
        if dayBuckets[cursor] != nil { return 0 }
        var streak = 1
        for _ in 0..<60 {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
            if dayBuckets[cursor] != nil { break }
            streak += 1
        }
        return streak
    }

    /// 从今天往回数连续有训练的天数。今天还没练时从昨天起算,这样早上打开
    /// App 不会因为"今天还没动"就把连续记录清零。
    private func consecutiveActiveDays(active: [SessionRecord]) -> Int {
        let dayBuckets = Dictionary(grouping: active) { calendar.startOfDay(for: $0.date) }
        var cursor = calendar.startOfDay(for: now)
        if dayBuckets[cursor] == nil {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var streak = 0
        for _ in 0..<120 {
            guard dayBuckets[cursor] != nil else { break }
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return streak
    }
}
