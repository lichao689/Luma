import Foundation

/// The kinds of activity a user can log.
public enum WorkoutType: String, Codable, CaseIterable, Identifiable, Sendable {
    case strengthA
    case strengthB
    case run
    case recovery
    case minimal
    case rest

    public var id: String { rawValue }

    public var countsAsStrength: Bool { self == .strengthA || self == .strengthB }
    public var countsAsRun: Bool { self == .run }
    public var countsAsRecovery: Bool { self == .recovery }

    /// "Rest" is not real activity — it marks an intentional day off so the
    /// flexible reminder can be silenced.
    public var isActivity: Bool { self != .rest }
}

/// How much of a planned workout was actually completed.
public enum CompletionLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case full
    case partial
    case minimal

    public var id: String { rawValue }
}
