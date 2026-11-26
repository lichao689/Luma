import SwiftUI
import UniformTypeIdentifiers
import OfficeWorkoutLogic

@main
struct LumaHealthBridgeApp: App {
    var body: some Scene {
        WindowGroup { HealthExportView() }
    }
}

private struct HealthExportView: View {
    @StateObject private var exporter = HealthKitExporter()
    @State private var days = 30
    @State private var exporting = false
    @State private var document = HealthJSONDocument(data: Data())

    var body: some View {
        NavigationStack {
            Form {
                Section("导入小盏") {
                    Text("读取 iPhone 上可见的运动、每日步数和睡眠记录，生成文件后由你导入 Mac 上的小盏。")
                    Text("文件只包含这些健康数据，不会上传服务器，也不会修改 Apple 健康。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker("时间范围", selection: $days) {
                        Text("最近 7 天").tag(7)
                        Text("最近 30 天").tag(30)
                        Text("最近 90 天").tag(90)
                    }
                    .disabled(exporter.isBusy)
                    Button {
                        Task { await exporter.prepare(days: days) }
                    } label: {
                        if exporter.isBusy { ProgressView("正在读取可见数据…") }
                        else { Label("授权并读取", systemImage: "heart.text.square") }
                    }
                    .disabled(exporter.isBusy)
                }

                if let packet = exporter.packet {
                    Section("本次文件") {
                        LabeledContent("运动记录", value: "\(packet.workouts.count)")
                        LabeledContent("有步数的日期", value: "\(packet.stepDays.filter { $0.count != nil }.count)")
                        LabeledContent("睡眠片段", value: "\(packet.sleepSamples.count)")
                        Text("授权请求已处理。Apple 不向 App 透露读取权限是否被拒绝；空结果也可能表示没有记录或只允许近期数据。")
                            .font(.footnote).foregroundStyle(.secondary)
                        if packet.workouts.isEmpty && packet.sleepSamples.isEmpty && packet.stepDays.allSatisfy({ $0.count == nil }) {
                            Text("本次没有读到可见记录。可在“健康”或系统设置中检查读取范围，然后重试。")
                        }
                        Button {
                            guard let data = exporter.preparedData else { return }
                            document = HealthJSONDocument(data: data)
                            exporting = true
                        } label: {
                            Label("保存健康数据文件", systemImage: "square.and.arrow.up")
                        }
                        .disabled(exporter.isBusy)
                    }
                }

                if let error = exporter.errorMessage {
                    Section("读取未完成") { Text(error).foregroundStyle(.red) }
                }

                Section("在 Mac 上使用") {
                    Text("1. 保存 JSON 文件到“文件”。\n2. 用 AirDrop 或你选择的方式传到 Mac。\n3. 在小盏“设置 → 数据”中选择健康数据导入。")
                    Text("重复导入按健康记录 ID 去重。只把跑步计入跑步目标；其他运动、步数和睡眠保留为参考数据。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("小盏健康桥")
            .fileExporter(isPresented: $exporting, document: document,
                          contentType: .json, defaultFilename: "luma-health") { result in
                if case .failure(let error) = result { exporter.errorMessage = error.localizedDescription }
            }
        }
    }
}

private struct HealthJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
