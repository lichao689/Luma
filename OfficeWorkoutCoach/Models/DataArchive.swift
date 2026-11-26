import Foundation
import SwiftData
import OfficeWorkoutLogic

@Model
final class SavedTrainingPlan {
    @Attribute(.unique) var id: UUID
    var json: Data
    var updatedAt: Date

    init(id: UUID, json: Data, updatedAt: Date) {
        self.id = id; self.json = json; self.updatedAt = updatedAt
    }
}

@Model
final class DataTombstone {
    @Attribute(.unique) var key: String
    var kindRaw: String
    var recordID: UUID
    var deletedAt: Date

    init(_ value: BackupTombstone) {
        self.key = value.key; self.kindRaw = value.kind.rawValue
        self.recordID = value.id; self.deletedAt = value.deletedAt
    }

    var value: BackupTombstone? {
        guard let kind = BackupTombstone.Kind(rawValue: kindRaw) else { return nil }
        return BackupTombstone(kind: kind, id: recordID, deletedAt: deletedAt)
    }
}

@Model
final class HealthImportArchive {
    @Attribute(.unique) var id: UUID
    var importedAt: Date
    var json: Data

    init(id: UUID, importedAt: Date = .now, json: Data) {
        self.id = id; self.importedAt = importedAt; self.json = json
    }
}
