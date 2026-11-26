import Foundation
import Combine
@preconcurrency import HealthKit
import OfficeWorkoutLogic

/// A foreground-only read/export helper. macOS cannot read the HealthKit store;
/// the desktop app only decodes this helper's explicitly shared JSON document.
@MainActor
final class HealthKitExporter: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var packet: HealthBridgePacket?
    @Published private(set) var preparedData: Data?
    @Published var errorMessage: String?

    private let store = HKHealthStore()
    private var calendar = Calendar.current

    func prepare(days: Int) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        packet = nil
        preparedData = nil
        defer { isBusy = false }
        do {
            guard HKHealthStore.isHealthDataAvailable() else {
                throw ExportError.unavailable
            }
            guard [7, 30, 90].contains(days) else { throw ExportError.invalidRange }
            let readTypes: Set<HKObjectType> = [
                HKObjectType.workoutType(), HKQuantityType(.stepCount), HKCategoryType(.sleepAnalysis)
            ]
            // Successful completion is NOT evidence that any read access was granted.
            try await store.requestAuthorization(toShare: [], read: readTypes)

            // Capture one calendar and boundary after the permission sheet, so
            // an app left open across midnight or a time-zone change exports
            // the current local days consistently.
            calendar = .current
            let now = Date()
            guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else {
                throw ExportError.invalidRange
            }

            // Anchors supply explicit source deletions. No missing sample or empty
            // query is ever interpreted as a deletion or a denied permission.
            let state = try await updatedDeletionState(start: start)
            let workouts = try await readWorkouts(start: start, end: now)
            let steps = try await readSteps(start: start, end: now)
            let sleep = try await readSleep(start: start, end: now)
            let export = HealthBridgePacket(
                generatedAt: now, periodStart: start, periodEnd: now,
                timeZoneIdentifier: calendar.timeZone.identifier,
                workouts: workouts.filter { !state.deletedWorkoutIDs.contains($0.id) },
                stepDays: steps, sleepSamples: sleep.filter { !state.deletedSleepIDs.contains($0.id) },
                deletedWorkoutIDs: state.deletedWorkoutIDs.sorted { $0.uuidString < $1.uuidString },
                deletedSleepIDs: state.deletedSleepIDs.sorted { $0.uuidString < $1.uuidString }
            )
            let data = try HealthBridgeCodec.encode(export)
            try saveState(state)
            packet = export
            preparedData = data
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func readWorkouts(start: Date, end: Date) async throws -> [HealthWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    HealthWorkout(id: workout.uuid, activity: Self.activity(workout.workoutActivityType),
                                  sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
                                  start: workout.startDate, end: workout.endDate,
                                  durationSeconds: workout.duration)
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    private func readSteps(start: Date, end: Date) async throws -> [HealthStepDay] {
        let totals = try await readStepStatistics(start: start, end: end, separateSources: false)
        // HealthKit exposes statistics.sources only with separateBySource. A
        // second query preserves provenance without replacing system-merged
        // totals with a sum of overlapping iPhone and Watch counts.
        let sources = try await readStepStatistics(start: start, end: end, separateSources: true)
        let sourcesByDay = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.sourceBundleIdentifiers) })
        return totals.map { day in
            HealthStepDay(start: day.start, end: day.end, timeZoneIdentifier: day.timeZoneIdentifier,
                          count: day.count, observedAt: day.observedAt,
                          sourceBundleIdentifiers: sourcesByDay[day.id] ?? [])
        }
    }

    private func readStepStatistics(start: Date, end: Date, separateSources: Bool) async throws -> [HealthStepDay] {
        let zone = calendar.timeZone.identifier
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKStatisticsCollectionQuery(quantityType: HKQuantityType(.stepCount),
                                                     quantitySamplePredicate: predicate,
                                                     options: separateSources ? [.cumulativeSum, .separateBySource] : .cumulativeSum,
                                                     anchorDate: start,
                                                     intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                guard let result else { continuation.resume(throwing: ExportError.noResult); return }
                var days: [HealthStepDay] = []
                result.enumerateStatistics(from: start, to: end) { statistics, _ in
                    // Statistics merges sources; do not also sum raw iPhone/Watch samples.
                    // nil remains unknown rather than an invented zero-step day.
                    days.append(HealthStepDay(start: statistics.startDate, end: statistics.endDate,
                                             timeZoneIdentifier: zone,
                                             count: separateSources ? nil : statistics.sumQuantity()?.doubleValue(for: .count()),
                                             observedAt: end,
                                             sourceBundleIdentifiers: (statistics.sources ?? []).map(\.bundleIdentifier).sorted()))
                }
                continuation.resume(returning: days)
            }
            store.execute(query)
        }
    }

    private func readSleep(start: Date, end: Date) async throws -> [HealthSleepSample] {
        try await withCheckedThrowingContinuation { continuation in
            // Include intervals crossing the start boundary; the desktop summary
            // clips them to its display window and unions overlapping sleep.
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let sleep = (samples as? [HKCategorySample] ?? []).compactMap { sample -> HealthSleepSample? in
                    guard let stage = Self.sleepStage(sample.value) else { return nil }
                    return HealthSleepSample(id: sample.uuid, start: sample.startDate, end: sample.endDate,
                                             stage: stage, sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier)
                }
                continuation.resume(returning: sleep)
            }
            store.execute(query)
        }
    }

    // MARK: Explicit HealthKit source deletions

    private struct DeletionState: Codable {
        var start: Date
        var workoutAnchor: Data?
        var sleepAnchor: Data?
        var deletedWorkoutIDs: Set<UUID>
        var deletedSleepIDs: Set<UUID>
    }

    private func updatedDeletionState(start: Date) async throws -> DeletionState {
        var state = try loadState() ?? DeletionState(start: start, deletedWorkoutIDs: [], deletedSleepIDs: [])
        if start < state.start {
            // Drain the old predicate before resetting its anchors so widening
            // the range cannot lose deletions since the previous export.
            let oldWorkouts = try await readAnchor(type: .workoutType(), start: state.start, anchorData: state.workoutAnchor)
            let oldSleep = try await readAnchor(type: HKCategoryType(.sleepAnalysis), start: state.start, anchorData: state.sleepAnchor)
            state.deletedWorkoutIDs.formUnion(oldWorkouts.deletedIDs)
            state.deletedSleepIDs.formUnion(oldSleep.deletedIDs)
            // A broader user-selected range changes the predicate, requiring a
            // fresh anchor. Keep every deletion already learned.
            state.start = start
            state.workoutAnchor = nil
            state.sleepAnchor = nil
        }
        let workouts = try await readAnchor(type: .workoutType(), start: state.start, anchorData: state.workoutAnchor)
        let sleep = try await readAnchor(type: HKCategoryType(.sleepAnalysis), start: state.start, anchorData: state.sleepAnchor)
        state.workoutAnchor = workouts.data
        state.sleepAnchor = sleep.data
        state.deletedWorkoutIDs.formUnion(workouts.deletedIDs)
        state.deletedSleepIDs.formUnion(sleep.deletedIDs)
        return state
    }

    private func readAnchor(type: HKSampleType, start: Date, anchorData: Data?) async throws -> AnchorUpdate {
        let anchor = try anchorData.flatMap {
            try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: predicate,
                                              anchor: anchor, limit: HKObjectQueryNoLimit) { _, _, deleted, nextAnchor, error in
                if let error { continuation.resume(throwing: error); return }
                do {
                    let data = try nextAnchor.map { try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
                    continuation.resume(returning: AnchorUpdate(data: data, deletedIDs: Set((deleted ?? []).map(\.uuid))))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            store.execute(query)
        }
    }

    private struct AnchorUpdate: Sendable {
        let data: Data?
        let deletedIDs: Set<UUID>
    }

    private func stateURL() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        return directory.appendingPathComponent("health-workout-anchor.json")
    }

    private func loadState() throws -> DeletionState? {
        let url = try stateURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(DeletionState.self, from: Data(contentsOf: url))
    }

    private func saveState(_ state: DeletionState) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: stateURL(), options: [.atomic, .completeFileProtection])
    }

    // MARK: Value conversions run inside HealthKit's background callbacks

    nonisolated private static func activity(_ type: HKWorkoutActivityType) -> HealthActivity {
        switch type {
        case .running: return .running
        case .walking: return .walking
        case .cycling: return .cycling
        case .traditionalStrengthTraining, .functionalStrengthTraining: return .strength
        default: return .other
        }
    }

    nonisolated private static func sleepStage(_ value: Int) -> HealthSleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: return .inBed
        case .awake: return .awake
        case .asleepUnspecified: return .asleepUnspecified
        case .asleepCore: return .asleepCore
        case .asleepDeep: return .asleepDeep
        case .asleepREM: return .asleepREM
        default: return nil
        }
    }

    private enum ExportError: LocalizedError {
        case unavailable, invalidRange, noResult
        var errorDescription: String? {
            switch self {
            case .unavailable: return "此设备无法读取健康数据。请在支持健康数据的 iPhone 或 iPad 上使用。"
            case .invalidRange: return "无法确定导出时间范围，请重试。"
            case .noResult: return "健康查询未返回结果。请解锁设备后重试。"
            }
        }
    }
}
