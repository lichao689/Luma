import Foundation

public struct DailyActivity: Equatable, Identifiable, Sendable {
    public let date: Date
    public var sessions: Int
    public var minutes: Int
    public var id: Date { date }
}

public struct ExerciseHistoryPoint: Equatable, Identifiable, Sendable {
    public let sessionID: UUID
    public let date: Date
    public let setCount: Int
    public let repetitions: Int
    public let holdSeconds: Int
    public let maximumWeightKg: Double?
    public var id: UUID { sessionID }
}

public enum HistoryAnalytics {
    /// Calendar day buckets preserve local midnight across DST transitions.
    /// Rest entries and future records never count as activity.
    public static func daily(sessions: [SessionRecord], days: Int,
                             now: Date = .now, calendar: Calendar = .current) -> [DailyActivity] {
        let count = max(1, min(366, days))
        let today = calendar.startOfDay(for: now)
        var buckets = (0..<count).compactMap { offset -> DailyActivity? in
            guard let day = calendar.date(byAdding: .day, value: offset - count + 1, to: today) else { return nil }
            return DailyActivity(date: day, sessions: 0, minutes: 0)
        }
        let index = Dictionary(uniqueKeysWithValues: buckets.enumerated().map { ($0.element.date, $0.offset) })
        var seen = Set<UUID>()
        for session in sessions where session.type.isActivity && session.date <= now {
            guard seen.insert(session.id).inserted,
                  let i = index[calendar.startOfDay(for: session.date)] else { continue }
            buckets[i].sessions += 1
            buckets[i].minutes += max(0, session.durationMinutes)
        }
        return buckets
    }

    /// Trends compare one exercise at a time. Holds and repetitions are kept
    /// separate, and no volume/tonnage metric is inferred for bodyweight work.
    public static func exerciseTrend(exerciseID: String, sessions: [BackupSession],
                                     sets: [BackupSet], since: Date, now: Date = .now) -> [ExerciseHistoryPoint] {
        let eligible = Dictionary(sessions.filter { $0.date >= since && $0.date <= now && $0.type.isActivity }
            .map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        let selected = sets.filter { $0.exerciseID == exerciseID && eligible[$0.sessionID] != nil && seen.insert($0.id).inserted }
        return Dictionary(grouping: selected, by: \.sessionID).compactMap { id, items in
            guard let session = eligible[id] else { return nil }
            let weights = items.compactMap(\.weightKg).filter { $0.isFinite && $0 >= 0 }
            return ExerciseHistoryPoint(sessionID: id, date: session.date, setCount: items.count,
                                        repetitions: items.filter { !$0.isHold }.reduce(0) { $0 + max(0, $1.reps) },
                                        holdSeconds: items.filter(\.isHold).reduce(0) { $0 + max(0, $1.reps) },
                                        maximumWeightKg: weights.max())
        }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
    }
}
