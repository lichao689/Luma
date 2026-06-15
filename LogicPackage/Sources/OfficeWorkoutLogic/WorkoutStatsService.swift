import Foundation

/// Substrings in a session's `bodyFeeling` that indicate back trouble.
/// Matched case-insensitively against both enum raw values and surface text.
public enum BackPainMarkers {
    public static let terms = ["腰紧", "腰酸", "腰痛", "腰不舒服", "backtight", "back tight", "back"]
}

/// Immutable snapshot of recent activity. The recommendation engine consumes
/// this so it stays a pure function with no I/O.
public struct WorkoutStats: Equatable {
    public let strengthCount: Int
    public let runCount: Int
    public let recoveryCount: Int
    public let lastStrengthType: WorkoutType?
    public let daysSinceLastStrength: Int?
    public let consecutiveInactiveDays: Int
    public let hasActivityToday: Bool
    public let hasRunToday: Bool
    public let recentBackPain: Bool

    public init(
        strengthCount: Int,
        runCount: Int,
        recoveryCount: Int,
        lastStrengthType: WorkoutType?,
        daysSinceLastStrength: Int?,
        consecutiveInactiveDays: Int,
        hasActivityToday: Bool,
        hasRunToday: Bool,
        recentBackPain: Bool
    ) {
        self.strengthCount = strengthCount
        self.runCount = runCount
        self.recoveryCount = recoveryCount
        self.lastStrengthType = lastStrengthType
        self.daysSinceLastStrength = daysSinceLastStrength
        self.consecutiveInactiveDays = consecutiveInactiveDays
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
        let consecutiveInactive = consecutiveInactiveDays(active: active)

        let recentWindow = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let recentBackPain = sessions.contains { session in
            guard session.date >= recentWindow, let feeling = session.bodyFeeling?.lowercased() else { return false }
            return BackPainMarkers.terms.contains { feeling.contains($0.lowercased()) }
        }

        return WorkoutStats(
            strengthCount: strengthThisWeek.count,
            runCount: runThisWeek.count,
            recoveryCount: recoveryThisWeek.count,
            lastStrengthType: lastStrength?.type,
            daysSinceLastStrength: daysSinceLastStrength,
            consecutiveInactiveDays: consecutiveInactive,
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
}
