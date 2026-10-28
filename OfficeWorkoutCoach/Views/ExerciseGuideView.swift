import SwiftUI
import AVKit
import AppKit
import OfficeWorkoutLogic

/// A sidebar row plus the plan context it belongs to.
///
/// Some exercises intentionally appear in multiple plans (for example glute
/// bridge in strength A and back recovery). Keeping the plan on the selection
/// lets the detail page show the right dosage for that context.
private struct ExerciseGuideItem: Identifiable, Hashable {
    let plan: WorkoutType
    let exercise: Exercise

    var id: String { "\(plan.rawValue):\(exercise.id)" }
}

/// 动作示意窗口(独立窗口,空间足够放视频/图片+文字)。
///
/// 左侧动作列表,右侧详情。媒体区按优先级**自动降级**:视频 > 图片 > 占位,
/// 缺资源不报错、文字始终显示。新增 mp4/png 只需把文件丢进
/// `Resources/Exercises/` 并加入工程,无需改代码(见 README)。
struct ExerciseGuideView: View {
    /// 可选:从弹窗跳转时预选某个动作。
    var preselected: Exercise?

    @State private var selected: ExerciseGuideItem?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let selected {
                ExerciseDetail(item: selected)
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
            if selected == nil { selected = initialSelection }
        }
    }

    /// 左侧:按计划分组的动作列表。
    private var sidebar: some View {
        List(selection: $selected) {
            Section(String(localized: "guide.section.planA", defaultValue: "力量 A")) {
                ForEach(items(for: .strengthA)) { item in
                    labelRow(item)
                }
            }
            Section(String(localized: "guide.section.planB", defaultValue: "力量 B")) {
                ForEach(items(for: .strengthB)) { item in
                    labelRow(item)
                }
            }
            Section(String(localized: "guide.section.recovery", defaultValue: "腰背恢复")) {
                ForEach(items(for: .recovery)) { item in
                    labelRow(item)
                }
            }
        }
        .navigationTitle(String(localized: "guide.title", defaultValue: "动作示意"))
    }

    private var initialSelection: ExerciseGuideItem? {
        let allItems = items(for: .strengthA) + items(for: .strengthB) + items(for: .recovery)
        if let preselected {
            return allItems.first { $0.exercise.id == preselected.id }
        }
        return allItems.first
    }

    private func items(for plan: WorkoutType) -> [ExerciseGuideItem] {
        ExerciseLibrary.exercises(for: plan).map { ExerciseGuideItem(plan: plan, exercise: $0) }
    }

    /// 列表行:图标 + 名称 + 媒体状态点。
    @ViewBuilder
    private func labelRow(_ item: ExerciseGuideItem) -> some View {
        Label {
            HStack {
                let exercise = item.exercise
                Text(exercise.localizedName)
                if hasDemoVideo(for: exercise) {
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
        .tag(item)
    }

    private func hasDemoVideo(for exercise: Exercise) -> Bool {
        let candidates = [exercise.videoAssetName, exercise.imageAssetName, exercise.id]
            .compactMap { $0 }
            .reduce(into: [String]()) { result, name in
                if !result.contains(name) { result.append(name) }
            }
        for name in candidates {
            for ext in ["mp4", "mov", "m4v"] {
                if Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Exercises") != nil {
                    return true
                }
                if Bundle.main.url(forResource: name, withExtension: ext) != nil {
                    return true
                }
            }
        }
        return false
    }
}

/// 单个动作的详情:标题/标签 + 媒体 + 文字(要领/常见错误/练什么)。
private struct ExerciseDetail: View {
    let item: ExerciseGuideItem

    private var exercise: Exercise { item.exercise }
    private var prescription: ExercisePrescription { ExercisePrescription.for(item) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ExerciseMediaView(exercise: exercise)
                prescriptionSection
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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(exercise.localizedName)
                    .font(.largeTitle.weight(.bold))
                Text(item.plan.localizedName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
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

    private var prescriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "guide.section.prescription", defaultValue: "本次处方"),
                  systemImage: "timer")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                prescriptionRow(String(localized: "guide.prescription.dose", defaultValue: "处方"),
                                prescription.dose)
                prescriptionRow(String(localized: "guide.prescription.tempo", defaultValue: "节奏"),
                                prescription.tempo)
                prescriptionRow(String(localized: "guide.prescription.rest", defaultValue: "休息"),
                                prescription.rest)
                prescriptionRow(String(localized: "guide.prescription.estimate", defaultValue: "预计"),
                                prescription.estimate)
                prescriptionRow(String(localized: "guide.prescription.focus", defaultValue: "重点"),
                                prescription.focus)
            }
            Text(prescription.intent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func prescriptionRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Text(value)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
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

private struct ExercisePrescription {
    let dose: String
    let tempo: String
    let rest: String
    let estimate: String
    let focus: String
    let intent: String

    static func `for`(_ item: ExerciseGuideItem) -> ExercisePrescription {
        switch (item.plan, item.exercise.id) {
        case (.strengthA, "gobletSquat"):
            return strength(
                dose: "3 组 × 8-12 次",
                tempo: "下蹲约 2 秒,起身约 1 秒",
                rest: "45-75 秒",
                estimate: "约 4-5 分钟",
                focus: "膝盖跟脚尖、脚跟踩实、腰背中立"
            )
        case (.strengthA, "pushUp"):
            return strength(
                dose: "3 组 × 8-15 次",
                tempo: "下落约 2 秒,推起约 1 秒",
                rest: "45-75 秒",
                estimate: "约 3-4 分钟",
                focus: "身体一条线、手肘约 45 度、不塌腰"
            )
        case (.strengthA, "shoulderPress"):
            return strength(
                dose: "3 组 × 8-12 次",
                tempo: "上推约 1 秒,下放约 2 秒",
                rest: "60 秒",
                estimate: "约 4 分钟",
                focus: "肋骨不外翻、手腕中立、不后仰顶腰"
            )
        case (.strengthA, "gluteBridge"):
            return strength(
                dose: "3 组 × 12-15 次",
                tempo: "上顶 1 秒,顶峰停 1 秒,下放 2 秒",
                rest: "45-60 秒",
                estimate: "约 3-4 分钟",
                focus: "臀部发力、顶峰不顶腰、下放保持控制"
            )
        case (.strengthA, "plank"):
            return strength(
                dose: "3 组 × 30-60 秒",
                tempo: "稳定保持,自然呼吸",
                rest: "30-60 秒",
                estimate: "约 3-5 分钟",
                focus: "肩髋踝一线、核心收紧、不憋气"
            )
        case (.strengthB, "romanianDeadlift"):
            return strength(
                dose: "3 组 × 8-10 次",
                tempo: "下放 2-3 秒,起身约 1 秒",
                rest: "60-90 秒",
                estimate: "约 4-5 分钟",
                focus: "髋向后推、哑铃贴腿、背部中立"
            )
        case (.strengthB, "bentOverDumbbellRow"):
            return strength(
                dose: "3 组 × 10-12 次",
                tempo: "拉起 1 秒,顶峰停 1 秒,下放 2 秒",
                rest: "60 秒",
                estimate: "约 4 分钟",
                focus: "手肘拉向后腰、肩颈放松、躯干不甩"
            )
        case (.strengthB, "reverseLunge"):
            return strength(
                dose: "2-3 组 × 8-10 次/侧",
                tempo: "下蹲约 2 秒,站起约 1 秒",
                rest: "60-90 秒",
                estimate: "约 5-7 分钟",
                focus: "前膝跟脚尖、躯干稳定、时间紧做 2 组"
            )
        case (.strengthB, "proneWRaise"):
            return strength(
                dose: "2-3 组 × 10-12 次",
                tempo: "抬起 1 秒,停 1 秒,下放 2 秒",
                rest: "30-45 秒",
                estimate: "约 3 分钟",
                focus: "肩胛后下收、脖子放松、小幅控制"
            )
        case (.strengthB, "sidePlank"):
            return strength(
                dose: "2 组 × 20-40 秒/侧",
                tempo: "稳定保持,自然呼吸",
                rest: "30-45 秒",
                estimate: "约 3-4 分钟",
                focus: "髋不下沉、身体不翻转、肩肘不痛"
            )
        case (.recovery, "catCow"):
            return recovery(
                dose: "6-8 次慢循环",
                tempo: "吸气下沉,呼气圆背,每次 8-10 秒",
                rest: "无需正式休息",
                estimate: "约 60-90 秒",
                focus: "慢、舒服、不甩腰、不追求最大幅度"
            )
        case (.recovery, "pelvicTilt"):
            return recovery(
                dose: "1-2 组 × 8-10 次",
                tempo: "呼气后倾,停 1-2 秒,放松回中立",
                rest: "约 30 秒",
                estimate: "约 60-90 秒",
                focus: "小幅控制、腰背轻贴地、不要做成臀桥"
            )
        case (.recovery, "deadBug"):
            return recovery(
                dose: "1 组 × 5-6 次/侧",
                tempo: "慢伸约 3 秒,慢收约 2 秒",
                rest: "30-45 秒",
                estimate: "约 90 秒",
                focus: "腰背贴地、动作慢、能呼吸"
            )
        case (.recovery, "birdDog"):
            return recovery(
                dose: "1 组 × 5-6 次/侧",
                tempo: "伸出 2 秒,停 1 秒,慢慢收回",
                rest: "30-45 秒",
                estimate: "约 90 秒",
                focus: "骨盆不晃、手脚伸长、不塌腰"
            )
        case (.recovery, "gluteBridge"):
            return recovery(
                dose: "1 组 × 10-12 次",
                tempo: "上顶 1 秒,顶峰停 1 秒,慢放下",
                rest: "约 30 秒",
                estimate: "约 60 秒",
                focus: "恢复版只做臀部激活,不追求力竭"
            )
        case (.recovery, "hipFlexorStretch"):
            return recovery(
                dose: "1 组 × 30 秒/侧",
                tempo: "稳定保持,自然呼吸",
                rest: "换侧即可",
                estimate: "约 60-75 秒",
                focus: "骨盆微后倾、拉髋前侧、不要压腰"
            )
        default:
            return strength(
                dose: item.exercise.setsReps,
                tempo: "慢做,全程可控",
                rest: "45-60 秒",
                estimate: "约 3-5 分钟",
                focus: item.exercise.localizedVisualFocus.first ?? "动作稳定、没有疼痛"
            )
        }
    }

    private static func strength(
        dose: String,
        tempo: String,
        rest: String,
        estimate: String,
        focus: String
    ) -> ExercisePrescription {
        ExercisePrescription(
            dose: dose,
            tempo: tempo,
            rest: rest,
            estimate: estimate,
            focus: focus,
            intent: "力量训练以动作不变形为准:最后 2 次可以吃力,但不要做到疼痛或失控。"
        )
    }

    private static func recovery(
        dose: String,
        tempo: String,
        rest: String,
        estimate: String,
        focus: String
    ) -> ExercisePrescription {
        ExercisePrescription(
            dose: dose,
            tempo: tempo,
            rest: rest,
            estimate: estimate,
            focus: focus,
            intent: "腰背恢复以舒服和可控为准:疼痛升高、麻木或放射感出现时停止。"
        )
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
        let videoCandidates = [exercise.videoAssetName, exercise.imageAssetName, exercise.id]
            .compactMap { $0 }
            .reduce(into: [String]()) { result, name in
                if !result.contains(name) { result.append(name) }
            }
        for videoName in videoCandidates {
            if let url = Self.url(for: videoName, extensions: ["mp4", "mov", "m4v"]) {
                return .video(url)
            }
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
        LoopingPlayerView(player: player)
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

private struct LoopingPlayerView: NSViewRepresentable {
    let player: AVQueuePlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}
