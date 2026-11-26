import XCTest
@testable import OfficeWorkoutLogic

final class HealthBridgeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func packet(workouts: [HealthWorkout] = [], steps: [HealthStepDay] = [],
                        sleep: [HealthSleepSample] = [], deleted: [UUID] = [], offset: Double = 0) -> HealthBridgePacket {
        HealthBridgePacket(generatedAt: start.addingTimeInterval(86_400 + offset), periodStart: start,
                           periodEnd: start.addingTimeInterval(86_400), timeZoneIdentifier: "UTC",
                           workouts: workouts, stepDays: steps, sleepSamples: sleep, deletedWorkoutIDs: deleted)
    }

    private func workout(id: UUID = UUID(), seconds: Double = 600) -> HealthWorkout {
        HealthWorkout(id: id, activity: .running, sourceBundleIdentifier: "com.apple.health",
                      start: start, end: start.addingTimeInterval(3600), durationSeconds: seconds)
    }

    func testHealthPacketRoundTripPreservesUnitsIDsSourcesAndMissingValues() throws {
        let source = packet(workouts: [workout()], steps: [
            HealthStepDay(start: start, end: start.addingTimeInterval(86_400), timeZoneIdentifier: "UTC",
                          count: nil, observedAt: start)
        ])
        let decoded = try HealthBridgeCodec.decode(HealthBridgeCodec.encode(source))
        XCTAssertEqual(decoded, source)
        XCTAssertNil(decoded.stepDays.first?.count)
        XCTAssertEqual(decoded.workouts.first?.durationSeconds, 600)
    }

    func testRepeatedImportDoesNotDoubleCountAndNewestUpdateWins() throws {
        let id = UUID()
        let old = packet(workouts: [workout(id: id)])
        let new = packet(workouts: [workout(id: id, seconds: 900)], offset: 60)
        let once = try HealthBridgeMerger.merge(existing: old, incoming: new)
        let twice = try HealthBridgeMerger.merge(existing: once, incoming: new)
        XCTAssertEqual(once, twice)
        XCTAssertEqual(twice.workouts.count, 1)
        XCTAssertEqual(twice.workouts.first?.durationSeconds, 900)
        let reverse = try HealthBridgeMerger.merge(existing: twice, incoming: old)
        XCTAssertEqual(reverse.workouts.first?.durationSeconds, 900)
    }

    func testLocalAndSourceTombstonesPreventResurrection() throws {
        let localID = UUID(), sourceID = UUID()
        let old = packet(workouts: [workout(id: localID), workout(id: sourceID)])
        let deletion = packet(deleted: [sourceID], offset: 60)
        let merged = try HealthBridgeMerger.merge(existing: old, incoming: deletion,
                                                  locallyDeletedWorkoutIDs: [localID])
        XCTAssertTrue(merged.workouts.isEmpty)
        let replay = try HealthBridgeMerger.merge(existing: merged, incoming: old)
        XCTAssertTrue(replay.workouts.isEmpty)
        XCTAssertEqual(Set(replay.deletedWorkoutIDs), [localID, sourceID])
    }

    func testEmptyQueryDoesNotDeleteOldRecords() throws {
        let old = packet(workouts: [workout()])
        let merged = try HealthBridgeMerger.merge(existing: old, incoming: packet(offset: 60))
        XCTAssertEqual(merged.workouts, old.workouts)
    }

    func testStepBucketsAreReplacedNotAddedAndUnknownDoesNotEraseKnown() throws {
        func day(_ count: Double?, _ offset: Double) -> HealthStepDay {
            HealthStepDay(start: start, end: start.addingTimeInterval(86_400), timeZoneIdentifier: "UTC",
                          count: count, observedAt: start.addingTimeInterval(offset))
        }
        let merged = try HealthBridgeMerger.merge(existing: packet(steps: [day(1200, 1)]),
                                                  incoming: packet(steps: [day(1800, 2)]))
        XCTAssertEqual(merged.stepDays.count, 1)
        XCTAssertEqual(merged.stepDays.first?.count, 1800)
        let unknown = try HealthBridgeMerger.merge(existing: merged, incoming: packet(steps: [day(nil, 3)]))
        XCTAssertEqual(unknown.stepDays.first?.count, 1800)
        XCTAssertEqual(unknown.stepDays.first?.observedAt, start.addingTimeInterval(2))
        let reverse = try HealthBridgeMerger.merge(existing: packet(steps: [day(nil, 3)]),
                                                   incoming: packet(steps: [day(1800, 2)]))
        XCTAssertEqual(reverse.stepDays.first?.count, 1800)
        XCTAssertEqual(reverse.stepDays.first?.observedAt, start.addingTimeInterval(2))
    }

    func testSleepUsesUnionAndExcludesInBedAwakeAndOutsideWindow() {
        func sample(_ a: Double, _ b: Double, _ stage: HealthSleepStage) -> HealthSleepSample {
            HealthSleepSample(id: UUID(), start: start.addingTimeInterval(a), end: start.addingTimeInterval(b),
                              stage: stage, sourceBundleIdentifier: "test.source")
        }
        let samples = [sample(0, 1000, .inBed), sample(0, 100, .awake),
                       sample(100, 500, .asleepCore), sample(300, 700, .asleepUnspecified),
                       sample(700, 900, .asleepREM), sample(1100, 1200, .asleepDeep)]
        let window = DateInterval(start: start.addingTimeInterval(200), duration: 600)
        XCTAssertEqual(HealthBridgeSummary.sleepSeconds(in: window, samples: samples), 600)
        XCTAssertNil(HealthBridgeSummary.sleepSeconds(in: window, samples: [sample(0, 1000, .inBed)]))
    }

    func testValidationRejectsUnsupportedVersionDuplicateIDsAndImpossibleDurations() throws {
        var wrongVersion = packet()
        wrongVersion.schemaVersion = 2
        XCTAssertThrowsError(try wrongVersion.validated())
        let sample = workout()
        XCTAssertThrowsError(try packet(workouts: [sample, sample]).validated())
        XCTAssertThrowsError(try packet(workouts: [workout(seconds: -1)]).validated())
        XCTAssertThrowsError(try packet(workouts: [workout(seconds: 3602)]).validated())
        XCTAssertThrowsError(try packet(workouts: [workout(seconds: .infinity)]).validated())
    }

    func testValidationAcceptsDSTDayAndRejectsNegativeSteps() throws {
        let springDay = HealthStepDay(start: start, end: start.addingTimeInterval(23 * 3600),
                                     timeZoneIdentifier: "America/Los_Angeles", count: 500,
                                     observedAt: start)
        XCTAssertNoThrow(try packet(steps: [springDay]).validated())
        let bad = HealthStepDay(start: start, end: start.addingTimeInterval(86_400),
                                timeZoneIdentifier: "UTC", count: -1, observedAt: start)
        XCTAssertThrowsError(try packet(steps: [bad]).validated())
    }

    func testCodecRejectsOversizedPayloadBeforeParsing() {
        let data = Data(repeating: 32, count: HealthBridgeCodec.maximumBytes + 1)
        XCTAssertThrowsError(try HealthBridgeCodec.decode(data)) { error in
            XCTAssertEqual(error as? HealthBridgeError, .fileTooLarge)
        }
    }

    func testCodecAcceptsFractionalISOTimestamps() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(packet())
        let text = String(decoding: encoded, as: UTF8.self)
        let fractional = text.replacingOccurrences(of: "Z\"", with: ".000Z\"")
        XCTAssertNoThrow(try HealthBridgeCodec.decode(Data(fractional.utf8)))
    }

    func testCodecPreservesFractionalDatePrecisionAndStableStepKeys() throws {
        let fraction = Date(timeIntervalSinceReferenceDate: 800_123_456.1234567)
        let day = HealthStepDay(start: fraction, end: fraction.addingTimeInterval(3600),
                                timeZoneIdentifier: "UTC", count: 400, observedAt: fraction,
                                sourceBundleIdentifiers: ["com.apple.health", "com.example.watch"])
        let source = HealthBridgePacket(generatedAt: fraction, periodStart: fraction,
                                         periodEnd: fraction.addingTimeInterval(3600),
                                         timeZoneIdentifier: "UTC", stepDays: [day])
        let decoded = try HealthBridgeCodec.decode(HealthBridgeCodec.encode(source))
        XCTAssertEqual(source, decoded)
        XCTAssertEqual(source.stepDays.first?.id, decoded.stepDays.first?.id)
        XCTAssertEqual(try HealthBridgeMerger.merge(existing: decoded, incoming: source).stepDays.count, 1)
    }

    func testExplicitSleepDeletionSurvivesOldFileReplay() throws {
        let sample = HealthSleepSample(id: UUID(), start: start, end: start.addingTimeInterval(3600),
                                       stage: .asleepCore, sourceBundleIdentifier: "test.source")
        let original = packet(sleep: [sample])
        var deleted = packet(offset: 60)
        deleted.deletedSleepIDs = [sample.id]
        let merged = try HealthBridgeMerger.merge(existing: original, incoming: deleted)
        let replayed = try HealthBridgeMerger.merge(existing: merged, incoming: original)
        XCTAssertTrue(replayed.sleepSamples.isEmpty)
        XCTAssertEqual(replayed.deletedSleepIDs, [sample.id])
    }

    func testConflictingSampleObservationsAtTheSameTimeAreRejected() throws {
        let id = UUID()
        let first = workout(id: id, seconds: 600)
        let changed = workout(id: id, seconds: 500)
        XCTAssertThrowsError(try HealthBridgeMerger.merge(existing: packet(workouts: [first]),
                                                         incoming: packet(workouts: [changed])))
        let sleepID = UUID()
        let firstSleep = HealthSleepSample(id: sleepID, start: start, end: start.addingTimeInterval(600),
                                          stage: .asleepCore, sourceBundleIdentifier: "test.source")
        let changedSleep = HealthSleepSample(id: sleepID, start: start, end: start.addingTimeInterval(600),
                                            stage: .awake, sourceBundleIdentifier: "test.source")
        XCTAssertThrowsError(try HealthBridgeMerger.merge(existing: packet(sleep: [firstSleep]),
                                                         incoming: packet(sleep: [changedSleep])))
        // An explicit deletion still wins even over disputed stale samples.
        let deleted = try HealthBridgeMerger.merge(existing: packet(workouts: [first]),
                                                   incoming: packet(workouts: [changed], deleted: [id]))
        XCTAssertTrue(deleted.workouts.isEmpty)
    }

    func testConflictingStepTotalsAreRejectedAndEqualTotalsCombineSources() throws {
        func day(_ count: Double, _ source: String) -> HealthStepDay {
            HealthStepDay(start: start, end: start.addingTimeInterval(86_400), timeZoneIdentifier: "UTC",
                          count: count, observedAt: start, sourceBundleIdentifiers: [source])
        }
        let a = packet(steps: [day(1200, "source.a")])
        let b = packet(steps: [day(1800, "source.b")])
        XCTAssertThrowsError(try HealthBridgeMerger.merge(existing: a, incoming: b))
        let sameTotal = packet(steps: [day(1200, "source.b")])
        let forward = try HealthBridgeMerger.merge(existing: a, incoming: sameTotal)
        let reverse = try HealthBridgeMerger.merge(existing: sameTotal, incoming: a)
        XCTAssertEqual(forward.stepDays, reverse.stepDays)
        XCTAssertEqual(forward.stepDays.first?.count, 1200)
        XCTAssertEqual(forward.stepDays.first?.sourceBundleIdentifiers, ["source.a", "source.b"])
    }
}
