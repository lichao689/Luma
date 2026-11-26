import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OfficeWorkoutLogic

/// All exports and shared-folder writes originate in an explicit button action.
/// A JSON file is decoded, validated, and previewed before changing the store.
struct DataManagementView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var pending: PendingImport?
    @State private var showingReview = false
    @State private var importGoals = false
    @State private var folder: URL?

    private enum PendingImport {
        case backup(BackupSnapshot, BackupMergePreview)
        case health(HealthBridgePacket, HealthImportPreview)
        case folder(URL, BackupFolderReview)
    }

    var body: some View {
        Form {
            Section(String(localized: "data.backup.title", defaultValue: "备份与恢复")) {
                Text(String(localized: "data.backup.detail", defaultValue: "完整 JSON 备份包含训练、实际组数、目标、自定义计划、健康导入和删除标记。恢复会预览后合并；相同 ID 的冲突会停止导入。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(String(localized: "data.backup.export", defaultValue: "导出完整备份…"), action: exportBackup)
                    Button(String(localized: "data.backup.import", defaultValue: "恢复备份…"), action: chooseBackup)
                    Button(String(localized: "data.csv.export", defaultValue: "导出 CSV…"), action: exportCSV)
                }
                Text(String(localized: "data.csv.detail", defaultValue: "CSV 用独立列保存次数、保持秒数、左右侧和公斤；完整恢复请使用 JSON。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(String(localized: "data.health.title", defaultValue: "Apple 健康导入")) {
                Text(String(localized: "data.health.detail", defaultValue: "使用 Luma Health iPhone 配套导出器生成 JSON，再选择导入。仅跑步映射为跑步记录；步数和睡眠保留原始单位和来源，未知数据保持为空。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(String(localized: "data.health.import", defaultValue: "导入健康文件…"), action: chooseHealth)
            }
            Section(String(localized: "data.sync.title", defaultValue: "跨 Mac 文件夹同步")) {
                Text(String(localized: "data.sync.detail", defaultValue: "在各台 Mac 选择同一个 iCloud Drive 或共享文件夹，手动预览并同步。每台设备写入独立快照；删除标记随快照同步。目标偏好保留本机值，差异会显示。"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(localized: "data.sync.privacy", defaultValue: "同步快照包含训练和已导入的健康数据。请选择仅你信任的人能访问的目录；只有确认同步时才会写入。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(String(localized: "data.sync.choose", defaultValue: "选择同步文件夹…"), action: chooseFolder)
                    if let folder { Text(folder.lastPathComponent).lineLimit(1).truncationMode(.middle) }
                    Spacer()
                    Button(String(localized: "data.sync.preview", defaultValue: "预览同步…"), action: previewSync)
                        .disabled(folder == nil)
                }
            }
            if let message {
                Text(message).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingReview) { reviewSheet }
    }

    private var reviewSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "data.preview.title", defaultValue: "检查导入内容")).font(.title2.bold())
            if let pending {
                switch pending {
                case .backup(_, let preview):
                    previewRows(preview)
                    if preview.goalsDiffer {
                        Toggle(String(localized: "data.preview.goals", defaultValue: "同时使用此备份的目标和提醒偏好"), isOn: $importGoals)
                        Text(String(localized: "data.preview.goals.detail", defaultValue: "未勾选时保留本机设置。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .health(let packet, let preview):
                    Text(packet.periodStart.formatted(date: .abbreviated, time: .omitted) + " – " + packet.periodEnd.formatted(date: .abbreviated, time: .omitted))
                    countRow(String(localized: "data.preview.runs.new", defaultValue: "新增跑步"), preview.newRuns)
                    countRow(String(localized: "data.preview.runs.update", defaultValue: "更新跑步"), preview.updatedRuns)
                    countRow(String(localized: "data.preview.runs.delete", defaultValue: "源已明确删除的跑步"), preview.deletedRuns)
                    countRow(String(localized: "data.preview.workouts", defaultValue: "文件中的运动样本"), preview.workoutCount)
                    countRow(String(localized: "data.preview.steps", defaultValue: "每日步数记录"), preview.stepDayCount)
                    countRow(String(localized: "data.preview.sleep", defaultValue: "睡眠样本"), preview.sleepSampleCount)
                    Text(String(localized: "data.preview.health.detail", defaultValue: "相同来源 UUID 不会重复累计。来源中不可见的记录不会被推断为删除，导入的主观强度标为未知。"))
                        .font(.caption).foregroundStyle(.secondary)
                case .folder(let url, let review):
                    Text(url.path).font(.caption).textSelection(.enabled)
                    countRow(String(localized: "data.preview.devices", defaultValue: "已发现设备快照"), review.deviceCount)
                    previewRows(review.preview)
                    if review.differingGoalCount > 0 {
                        Text(String(localized: "data.preview.sync.goals", defaultValue: "其他设备的目标或提醒偏好不同，本次保留本机设置。需要替换时，请单独恢复该设备快照并明确选择导入目标。"))
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text(String(localized: "data.preview.sync.share", defaultValue: "确认后会合并以上内容，并将本机完整训练及健康数据写入该文件夹，供其他设备同步。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(String(localized: "data.preview.deletions", defaultValue: "备份中的删除标记会应用到对应记录，防止旧设备将其恢复。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(String(localized: "common.cancel", defaultValue: "取消")) { showingReview = false; pending = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "data.preview.confirm", defaultValue: "确认合并"), action: confirmImport)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func previewRows(_ preview: BackupMergePreview) -> some View {
        VStack(spacing: 6) {
            countRow(String(localized: "data.preview.sessions", defaultValue: "新增训练记录"), preview.addedSessions)
            countRow(String(localized: "data.preview.updated.sessions", defaultValue: "按较新健康来源更新的跑步"), preview.updatedSessions)
            countRow(String(localized: "data.preview.sets", defaultValue: "新增实际组记录"), preview.addedSets)
            countRow(String(localized: "data.preview.plans", defaultValue: "新增或更新计划"), preview.changedPlans)
            countRow(String(localized: "data.preview.health", defaultValue: "新增健康导入文件"), preview.addedHealthPackets)
            countRow(String(localized: "data.preview.deleted.sessions", defaultValue: "删除训练记录"), preview.deletedSessions)
            countRow(String(localized: "data.preview.deleted.plans", defaultValue: "删除自定义计划"), preview.deletedPlans)
        }
    }

    private func countRow(_ title: String, _ count: Int) -> some View {
        HStack { Text(title); Spacer(); Text(count.formatted()).monospacedDigit() }
    }

    private func run(_ operation: () throws -> Void) {
        errorMessage = nil; message = nil
        do { try operation() }
        catch { errorMessage = userFacingError(error) }
    }

    private func exportBackup() {
        run {
            let data = try BackupCodec.encode(store.snapshot())
            guard let url = saveURL(name: "Luma-backup.json", type: .json) else { return }
            try access(url) { try data.write(to: url, options: .atomic) }
            message = String(localized: "data.export.done", defaultValue: "导出已完成。")
        }
    }

    private func exportCSV() {
        run {
            let csv = try store.exportCSV()
            guard let url = saveURL(name: "Luma-history.csv", type: .commaSeparatedText) else { return }
            try access(url) { try csv.write(to: url, atomically: true, encoding: .utf8) }
            message = String(localized: "data.export.done", defaultValue: "导出已完成。")
        }
    }

    private func chooseBackup() {
        run {
            guard let url = openJSON() else { return }
            let snapshot = try BackupCodec.decode(read(url, maximum: BackupCodec.maximumBytes))
            let preview = try store.previewRestore(snapshot)
            pending = .backup(snapshot, preview); importGoals = false; showingReview = true
        }
    }

    private func chooseHealth() {
        run {
            guard let url = openJSON() else { return }
            let packet = try HealthBridgeCodec.decode(read(url, maximum: HealthBridgeCodec.maximumBytes))
            pending = .health(packet, try store.previewHealthImport(packet)); showingReview = true
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK { folder = panel.url; message = nil; errorMessage = nil }
    }

    private func previewSync() {
        run {
            guard let folder else { return }
            let review = try access(folder) { try BackupFolderSync.review(folder: folder, local: store.snapshot()) }
            pending = .folder(folder, review); showingReview = true
        }
    }

    private func confirmImport() {
        guard let pending else { return }
        showingReview = false
        run {
            switch pending {
            case .backup(let value, _): try store.restore(value, importGoals: importGoals)
            case .health(let packet, _): try store.importHealth(packet)
            case .folder(let folder, let review):
                try store.restore(review.merged)
                do {
                    try access(folder) { try BackupFolderSync.publish(store.snapshot(), to: folder) }
                } catch {
                    throw NSError(domain: "LumaFolderSync", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        String(localized: "data.sync.publish.failed", defaultValue: "数据已合并，但本设备快照写入失败。可安全重试同步：") + " " + userFacingError(error)])
                }
            }
            message = String(localized: "data.import.done", defaultValue: "合并已完成。重复导入不会新增相同记录。")
        }
        self.pending = nil
    }

    private func openJSON() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func saveURL(name: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name; panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func read(_ url: URL, maximum: Int) throws -> Data {
        try access(url) {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let size, size <= maximum else { throw BackupError.tooLarge }
            let data = try Data(contentsOf: url)
            guard data.count <= maximum else { throw BackupError.tooLarge }
            return data
        }
    }

    private func access<T>(_ url: URL, _ operation: () throws -> T) rethrows -> T {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        return try operation()
    }
}
