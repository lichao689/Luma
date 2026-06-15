import SwiftUI
import AVKit
import AppKit
import OfficeWorkoutLogic

/// 动作示意窗口(独立窗口,空间足够放视频/图片+文字)。
///
/// 左侧动作列表,右侧详情。媒体区按优先级**自动降级**:视频 > 图片 > 占位,
/// 缺资源不报错、文字始终显示。新增 mp4/png 只需把文件丢进
/// `Resources/Exercises/` 并加入工程,无需改代码(见 README)。
struct ExerciseGuideView: View {
    /// 可选:从弹窗跳转时预选某个动作。
    var preselected: Exercise?

    @State private var selected: Exercise?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let selected {
                ExerciseDetail(exercise: selected)
            } else {
                ContentUnavailableView(
                    String(localized: "guide.empty.title", defaultValue: "选择一个动作"),
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text(String(localized: "guide.empty.subtitle",
                                              defaultValue: "左侧挑一个动作,看怎么练。"))
                )
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            if selected == nil { selected = preselected ?? ExerciseLibrary.all.first }
        }
    }

    /// 左侧:按计划分组的动作列表。
    private var sidebar: some View {
        List(selection: $selected) {
            Section(String(localized: "guide.section.planA", defaultValue: "力量 A")) {
                ForEach(ExerciseLibrary.planA) { exercise in
                    labelRow(exercise)
                }
            }
            Section(String(localized: "guide.section.planB", defaultValue: "力量 B")) {
                ForEach(ExerciseLibrary.planB) { exercise in
                    labelRow(exercise)
                }
            }
            Section(String(localized: "guide.section.recovery", defaultValue: "腰背恢复")) {
                ForEach(ExerciseLibrary.recoverySet) { exercise in
                    labelRow(exercise)
                }
            }
        }
        .navigationTitle(String(localized: "guide.title", defaultValue: "动作示意"))
    }

    /// 列表行:图标 + 名称 + 媒体状态点。
    @ViewBuilder
    private func labelRow(_ exercise: Exercise) -> some View {
        Label {
            HStack {
                Text(exercise.localizedName)
                if exercise.videoAssetName != nil {
                    Image(systemName: "play.circle")
                        .foregroundStyle(.tint)
                        .imageScale(.small)
                } else if exercise.imageAssetName != nil {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
            }
        } icon: {
            Image(systemName: "dumbbell")
        }
        .tag(exercise)
    }
}

/// 单个动作的详情:标题/标签 + 媒体 + 文字(要领/常见错误/练什么)。
private struct ExerciseDetail: View {
    let exercise: Exercise

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ExerciseMediaView(exercise: exercise)
                visualFocusSection
                cuesSection
                easierSection
                mistakesSection
                stopSection
                muscleSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(exercise.localizedName)
    }

    /// 顶部:名称 + 肌群标签 + 组数×次数。
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.localizedName)
                .font(.largeTitle.weight(.bold))
            HStack(spacing: 8) {
                ForEach(exercise.localizedTargetMuscles, id: \.self) { muscle in
                    Text(muscle)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text(exercise.setsReps)
                    .font(.callout.monospacedDigit())
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.tint.opacity(0.15), in: Capsule())
            }
        }
    }

    private var cuesSection: some View {
        detailList(
            title: String(localized: "guide.section.cues", defaultValue: "动作要领"),
            systemImage: "checkmark.circle",
            items: exercise.localizedCues
        )
    }

    private var visualFocusSection: some View {
        detailList(
            title: String(localized: "guide.section.focus", defaultValue: "图上重点"),
            systemImage: "scope",
            tint: .blue,
            items: exercise.localizedVisualFocus
        )
    }

    private var easierSection: some View {
        detailList(
            title: String(localized: "guide.section.easier", defaultValue: "降低难度"),
            systemImage: "arrow.down.forward.circle",
            tint: .green,
            items: exercise.localizedEasierVariations
        )
    }

    private var mistakesSection: some View {
        detailList(
            title: String(localized: "guide.section.mistakes", defaultValue: "常见错误"),
            systemImage: "exclamationmark.triangle",
            tint: .orange,
            items: exercise.localizedMistakes
        )
    }

    private var stopSection: some View {
        detailList(
            title: String(localized: "guide.section.stop", defaultValue: "不适时停止"),
            systemImage: "hand.raised",
            tint: .red,
            items: exercise.localizedStopConditions
        )
    }

    private var muscleSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .foregroundStyle(.tint)
            Text(String(localized: "guide.section.targets", defaultValue: "主要练:"))
                .font(.headline)
            Text(exercise.localizedPrimaryMuscle)
                .font(.body)
        }
    }

    /// 通用的小节:标题 + 项目列表。
    @ViewBuilder
    private func detailList(title: String, systemImage: String, tint: Color? = nil, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint ?? .primary)
            if items.isEmpty {
                Text(String(localized: "guide.empty.cues", defaultValue: "(暂无说明)"))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    Text("•  \(item)")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 媒体区:视频 > 图片 > 占位,自动降级。
/// 资源查找用 `Bundle.main.url(forResource:withExtension:)`,所以只要文件
/// 名与 assetName 对得上、且已加入 Resources build phase 即可被找到。
private struct ExerciseMediaView: View {
    let exercise: Exercise

    /// 当前选中的媒体来源(决定渲染哪种视图)。
    private enum Resolved {
        case video(URL)
        case image(Image)
        case placeholder
    }

    var body: some View {
        resolvedView
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var resolvedView: some View {
        switch resolve() {
        case .video(let url):
            VideoLoopPlayer(url: url)
        case .image(let image):
            image
                .resizable()
                .scaledToFit()
                .padding(8)
        case .placeholder:
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(String(localized: "guide.media.placeholder",
                        defaultValue: "暂无示意图,先看下方文字说明"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 按优先级解析媒体资源。视频缺失再找图片,都缺则占位。
    private func resolve() -> Resolved {
        if let videoName = exercise.videoAssetName,
           let url = Self.url(for: videoName, extensions: ["mp4", "mov", "m4v"]) {
            return .video(url)
        }
        if let imageName = exercise.imageAssetName,
           let image = Self.image(for: imageName, extensions: ["png", "jpg", "jpeg", "gif"]) {
            return .image(image)
        }
        return .placeholder
    }

    /// 在 bundle 中按名字 + 多种扩展名找文件 URL。
    private static func url(for name: String, extensions: [String]) -> URL? {
        for ext in extensions {
            if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Exercises") { return u }
            if let u = Bundle.main.url(forResource: name, withExtension: ext) { return u }
        }
        return nil
    }

    /// 在 bundle 中按名字 + 多种扩展名加载图片。
    private static func image(for name: String, extensions: [String]) -> Image? {
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Exercises"),
               let nsImage = NSImage(contentsOf: url) {
                return Image(nsImage: nsImage)
            }
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let nsImage = NSImage(contentsOf: url) {
                return Image(nsImage: nsImage)
            }
        }
        return nil
    }
}

/// 无声循环播放的视频视图(动作示意用,无需声音)。
private struct VideoLoopPlayer: View {
    let url: URL

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { setup() }
            .onDisappear { teardown() }
    }

    private func setup() {
        guard player == nil else { return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        let loop = AVPlayerLooper(player: queue, templateItem: item)
        queue.isMuted = true
        queue.play()
        player = queue
        looper = loop
    }

    private func teardown() {
        player?.pause()
        player = nil
        looper = nil
    }
}
