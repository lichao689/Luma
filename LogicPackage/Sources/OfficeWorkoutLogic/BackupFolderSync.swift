import Foundation

public struct BackupFolderReview: Sendable {
    public let merged: BackupSnapshot
    public let preview: BackupMergePreview
    public let deviceCount: Int
    public let differingGoalCount: Int
}

/// Manual, per-device snapshot exchange. It does not observe a folder or start
/// networking: callers must obtain explicit user selection and confirmation.
public enum BackupFolderSync {
    public static func fileName(deviceID: UUID) -> String { "luma-device-\(deviceID.uuidString).json" }

    public static func review(folder: URL, local: BackupSnapshot) throws -> BackupFolderReview {
        try BackupCodec.validate(local)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))
            .filter { $0.lastPathComponent.hasPrefix("luma-device-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard files.count <= 256 else { throw BackupError.tooLarge }
        var result = local
        var differingGoals = 0
        var totalBytes = 0
        var devices = Set<UUID>()
        for file in files {
            let attributes = try file.resourceValues(forKeys: keys)
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else {
                throw BackupError.invalid("Sync snapshot is not a regular file: \(file.lastPathComponent)")
            }
            guard let size = attributes.fileSize, size <= BackupCodec.maximumBytes else { throw BackupError.tooLarge }
            totalBytes += size
            guard totalBytes <= 4 * BackupCodec.maximumBytes else { throw BackupError.tooLarge }
            let incoming = try BackupCodec.decode(Data(contentsOf: file))
            guard file.lastPathComponent == fileName(deviceID: incoming.deviceID), devices.insert(incoming.deviceID).inserted else {
                throw BackupError.invalid("Sync filename does not match its device ID")
            }
            if incoming.goal != local.goal { differingGoals += 1 }
            result = try BackupMerger.merge(local: result, incoming: incoming)
        }
        var preview = try BackupMerger.preview(local: local, incoming: result)
        preview.goalsDiffer = differingGoals > 0
        return BackupFolderReview(merged: result, preview: preview, deviceCount: devices.count,
                                  differingGoalCount: differingGoals)
    }

    /// One atomic replacement and a distinct filename per device avoid partial
    /// JSON and devices overwriting each other's snapshot. The caller must merge
    /// the reviewed data into its store successfully before publishing.
    public static func publish(_ snapshot: BackupSnapshot, to folder: URL) throws {
        let data = try BackupCodec.encode(snapshot)
        let destination = folder.appendingPathComponent(fileName(deviceID: snapshot.deviceID), isDirectory: false)
        #if os(macOS)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) }
            catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        #else
        try data.write(to: destination, options: .atomic)
        #endif
    }
}
