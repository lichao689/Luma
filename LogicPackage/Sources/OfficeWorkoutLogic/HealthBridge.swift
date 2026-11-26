import Foundation

/// Portable, explicitly exported HealthKit data. It contains only the three
/// requested categories; it never assumes that an empty query means permission
/// was denied, zero activity, or that an older sample was deleted.
public struct HealthBridgePacket: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var format: String
    public var schemaVersion: Int
    public var generatedAt: Date
    public var periodStart: Date
    public var periodEnd: Date
    public var timeZoneIdentifier: String
    public var workouts: [HealthWorkout]
    public var stepDays: [HealthStepDay]
    public var sleepSamples: [HealthSleepSample]
    /// Only explicit HKDeletedObject UUIDs or existing imported tombstones.
    public var deletedWorkoutIDs: [UUID]
    public var deletedSleepIDs: [UUID]

    public init(id: UUID = UUID(), generatedAt: Date = .now, periodStart: Date,
                periodEnd: Date, timeZoneIdentifier: String,
                workouts: [HealthWorkout] = [], stepDays: [HealthStepDay] = [],
                sleepSamples: [HealthSleepSample] = [], deletedWorkoutIDs: [UUID] = [],
                deletedSleepIDs: [UUID] = []) {
        self.id = id
        self.format = "luma-health"
        self.schemaVersion = 1
        self.generatedAt = generatedAt
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.timeZoneIdentifier = timeZoneIdentifier
        self.workouts = workouts
        self.stepDays = stepDays
        self.sleepSamples = sleepSamples
        self.deletedWorkoutIDs = deletedWorkoutIDs
        self.deletedSleepIDs = deletedSleepIDs
    }

    @discardableResult
    public func validated() throws -> HealthBridgePacket {
        guard format == "luma-health", schemaVersion == 1 else {
            throw HealthBridgeError.invalidDocument("Unsupported health export format or version.")
        }
        guard Self.validDate(generatedAt), Self.validInterval(periodStart, periodEnd),
              TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw HealthBridgeError.invalidDocument("Invalid export period or time zone.")
        }
        guard workouts.count + stepDays.count + sleepSamples.count + deletedWorkoutIDs.count + deletedSleepIDs.count <= 100_000 else {
            throw HealthBridgeError.invalidDocument("The health export contains too many records.")
        }
        guard Set(workouts.map(\.id)).count == workouts.count,
              Set(stepDays.map(\.id)).count == stepDays.count,
              Set(sleepSamples.map(\.id)).count == sleepSamples.count else {
            throw HealthBridgeError.invalidDocument("Duplicate identifiers within the health export.")
        }
        for workout in workouts {
            guard Self.validInterval(workout.start, workout.end),
                  workout.durationSeconds.isFinite, workout.durationSeconds >= 0,
                  workout.durationSeconds <= workout.end.timeIntervalSince(workout.start) + 1,
                  Self.validSource(workout.sourceBundleIdentifier) else {
                throw HealthBridgeError.invalidDocument("Invalid workout duration, interval, or source.")
            }
        }
        for day in stepDays {
            guard Self.validInterval(day.start, day.end), Self.validDate(day.observedAt),
                  TimeZone(identifier: day.timeZoneIdentifier) != nil,
                  day.end.timeIntervalSince(day.start) <= 26 * 3600,
                  day.sourceBundleIdentifiers.allSatisfy(Self.validSource),
                  day.count.map({ $0.isFinite && $0 >= 0 }) ?? true else {
                throw HealthBridgeError.invalidDocument("Invalid step total or daily interval.")
            }
        }
        for sleep in sleepSamples {
            guard Self.validInterval(sleep.start, sleep.end),
                  Self.validSource(sleep.sourceBundleIdentifier) else {
                throw HealthBridgeError.invalidDocument("Invalid sleep interval or source.")
            }
        }
        return self
    }

    private static func validSource(_ source: String) -> Bool {
        !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && source.utf8.count <= 512
    }

    private static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite
    }

    private static func validInterval(_ start: Date, _ end: Date) -> Bool {
        validDate(start) && validDate(end) && start < end
    }
}

public enum HealthActivity: String, Codable, CaseIterable, Sendable {
    case running, walking, cycling, strength, other
}

public struct HealthWorkout: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let activity: HealthActivity
    public let sourceBundleIdentifier: String
    public let start: Date
    public let end: Date
    /// HKWorkout.duration is active time and can be shorter than end - start.
    public let durationSeconds: Double

    public init(id: UUID, activity: HealthActivity, sourceBundleIdentifier: String,
                start: Date, end: Date, durationSeconds: Double) {
        self.id = id
        self.activity = activity
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.start = start
        self.end = end
        self.durationSeconds = durationSeconds
    }
}

/// Daily HealthKit statistics, already merged across data sources by HealthKit.
/// `nil` means no visible quantity; it is deliberately not converted to zero.
public struct HealthStepDay: Codable, Equatable, Sendable, Identifiable {
    public let start: Date
    public let end: Date
    public let timeZoneIdentifier: String
    public let count: Double?
    public let observedAt: Date
    public let sourceBundleIdentifiers: [String]

    public var id: String {
        "\(timeZoneIdentifier)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)"
    }

    public init(start: Date, end: Date, timeZoneIdentifier: String, count: Double?, observedAt: Date,
                sourceBundleIdentifiers: [String] = []) {
        self.start = start
        self.end = end
        self.timeZoneIdentifier = timeZoneIdentifier
        self.count = count
        self.observedAt = observedAt
        self.sourceBundleIdentifiers = sourceBundleIdentifiers
    }
}

public enum HealthSleepStage: String, Codable, CaseIterable, Sendable {
    case inBed, awake, asleepUnspecified, asleepCore, asleepDeep, asleepREM

    public var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: return true
        case .inBed, .awake: return false
        }
    }
}

public struct HealthSleepSample: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let stage: HealthSleepStage
    public let sourceBundleIdentifier: String

    public init(id: UUID, start: Date, end: Date, stage: HealthSleepStage,
                sourceBundleIdentifier: String) {
        self.id = id
        self.start = start
        self.end = end
        self.stage = stage
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }
}

public enum HealthBridgeError: LocalizedError, Equatable {
    case invalidDocument(String)
    case fileTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidDocument(let message): return message
        case .fileTooLarge: return "Health export must be smaller than 16 MB."
        }
    }
}

public enum HealthBridgeCodec {
    public static let maximumBytes = 16 * 1024 * 1024

    public static func encode(_ packet: HealthBridgePacket) throws -> Data {
        try packet.validated()
        let encoder = JSONEncoder()
        // JSON numbers are seconds since 2001-01-01T00:00:00Z, the Foundation
        // reference date. This preserves Date's exact Double value, including
        // subsecond sample boundaries, instead of truncating them to seconds.
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(packet)
        guard data.count <= maximumBytes else { throw HealthBridgeError.fileTooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> HealthBridgePacket {
        guard data.count <= maximumBytes else { throw HealthBridgeError.fileTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                guard seconds.isFinite else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid timestamp.")
                }
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let text = try container.decode(String.self)
            let format = ISO8601DateFormatter()
            format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = format.date(from: text) { return date }
            format.formatOptions = [.withInternetDateTime]
            if let date = format.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO 8601 timestamp.")
        }
        return try decoder.decode(HealthBridgePacket.self, from: data).validated()
    }
}

/// Merge packets without double-counting reimports. Absence is never a delete.
/// Local deletion IDs and explicit source deletion IDs win over every packet,
/// including an older export imported after a newer one.
public enum HealthBridgeMerger {
    public static func merge(existing: HealthBridgePacket?, incoming: HealthBridgePacket,
                             locallyDeletedWorkoutIDs: Set<UUID> = []) throws -> HealthBridgePacket {
        try incoming.validated()
        if let existing { try existing.validated() }
        let tombstones = Set(existing?.deletedWorkoutIDs ?? [])
            .union(incoming.deletedWorkoutIDs).union(locallyDeletedWorkoutIDs)
        let deletedSleep = Set(existing?.deletedSleepIDs ?? []).union(incoming.deletedSleepIDs)
        var result = incoming
        if let existing {
            let incomingIsNewer = incoming.generatedAt >= existing.generatedAt
            let older = incomingIsNewer ? existing : incoming
            let newer = incomingIsNewer ? incoming : existing
            result = newer
            var workouts = Dictionary(uniqueKeysWithValues: older.workouts.map { ($0.id, $0) })
            for workout in newer.workouts {
                if existing.generatedAt == incoming.generatedAt,
                   let previous = workouts[workout.id], previous != workout,
                   !tombstones.contains(workout.id) {
                    throw HealthBridgeError.invalidDocument("Conflicting workout observations with the same timestamp: \(workout.id).")
                }
                workouts[workout.id] = workout
            }
            result.workouts = Array(workouts.values)
            var sleep = Dictionary(uniqueKeysWithValues: older.sleepSamples.map { ($0.id, $0) })
            for sample in newer.sleepSamples {
                if existing.generatedAt == incoming.generatedAt,
                   let previous = sleep[sample.id], previous != sample,
                   !deletedSleep.contains(sample.id) {
                    throw HealthBridgeError.invalidDocument("Conflicting sleep observations with the same timestamp: \(sample.id).")
                }
                sleep[sample.id] = sample
            }
            result.sleepSamples = Array(sleep.values)
            var steps = Dictionary(uniqueKeysWithValues: existing.stepDays.map { ($0.id, $0) })
            for day in incoming.stepDays {
                if let previous = steps[day.id] {
                    let sameObservation = day.observedAt == previous.observedAt
                    if sameObservation, let oldCount = previous.count, let newCount = day.count,
                       oldCount != newCount {
                        throw HealthBridgeError.invalidDocument("Conflicting step totals with the same observation timestamp.")
                    }
                    if sameObservation && day.count == previous.count {
                        // Source lists add provenance, not extra steps. Union
                        // them so a tie cannot depend on file import order.
                        steps[day.id] = HealthStepDay(start: day.start, end: day.end,
                            timeZoneIdentifier: day.timeZoneIdentifier, count: day.count,
                            observedAt: day.observedAt,
                            sourceBundleIdentifiers: Array(Set(day.sourceBundleIdentifiers)
                                .union(previous.sourceBundleIdentifiers)).sorted())
                        continue
                    }
                    // Unknown does not erase a known historical observation.
                    if day.count != nil && (previous.count == nil || day.observedAt > previous.observedAt) {
                        steps[day.id] = day
                    } else if previous.count == nil && day.observedAt > previous.observedAt {
                        steps[day.id] = day
                    }
                } else {
                    steps[day.id] = day
                }
            }
            result.stepDays = Array(steps.values)
            result.periodStart = min(existing.periodStart, incoming.periodStart)
            result.periodEnd = max(existing.periodEnd, incoming.periodEnd)
        }
        result.deletedWorkoutIDs = tombstones.sorted { $0.uuidString < $1.uuidString }
        result.deletedSleepIDs = deletedSleep.sorted { $0.uuidString < $1.uuidString }
        result.workouts = result.workouts.filter { !tombstones.contains($0.id) }.sorted {
            $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start
        }
        result.stepDays.sort { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        result.sleepSamples = result.sleepSamples.filter { !deletedSleep.contains($0.id) }.sorted {
            $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start
        }
        return try result.validated()
    }
}

public enum HealthBridgeSummary {
    /// Union of visible asleep intervals, clipped to the requested window.
    /// In-bed and awake samples never add sleep time. No visible asleep data
    /// returns nil, preserving the distinction between unknown and measured zero.
    public static func sleepSeconds(in window: DateInterval, samples: [HealthSleepSample]) -> Double? {
        let intervals = samples.filter(\.stage.isAsleep).compactMap { sample -> DateInterval? in
            let start = max(sample.start, window.start)
            let end = min(sample.end, window.end)
            guard start < end else { return nil }
            return DateInterval(start: start, end: end)
        }.sorted { $0.start < $1.start }
        guard var active = intervals.first else { return nil }
        var total = 0.0
        for interval in intervals.dropFirst() {
            if interval.start <= active.end {
                active = DateInterval(start: active.start, end: max(active.end, interval.end))
            } else {
                total += active.duration
                active = interval
            }
        }
        return total + active.duration
    }
}
