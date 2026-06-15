import SwiftUI
import OfficeWorkoutLogic

/// Lightweight completion card for logging one session, shown inline inside
/// the menu-bar popover (not as a sheet — see MenuBarPopoverView).
///
/// "Rest" and "minimal" default to zero-effort fields; strength/run/recovery
/// surface the full completion/intensity/feeling form.
struct QuickLogView: View {
    let type: WorkoutType
    /// Called when the user is done (save OR cancel) → returns to home page.
    var onDone: () -> Void

    @EnvironmentObject private var store: WorkoutStore

    @State private var durationMinutes: Int = 25
    @State private var completion: CompletionLevel = .full
    @State private var intensity: Int = 3
    @State private var bodyFeeling: BodyFeeling = .normal
    @State private var notes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            navBar
            if needsDetails {
                detailForm
            } else {
                Text(String(localized: "quicklog.minimalNote", defaultValue: "这一项默认按最低强度记录,点保存即可。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            actionBar
                .padding(.top, 4)
        }
        .padding(12)
        .frame(width: 300)
        .controlSize(.small)
        .onAppear { configureDefaults() }
    }

    /// Single compact title bar: back chevron + icon + type name.
    private var navBar: some View {
        HStack(spacing: 6) {
            Button {
                onDone()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "common.back", defaultValue: "返回"))
            Image(systemName: type.systemImage).foregroundStyle(.tint)
            Text(type.localizedName).font(.headline)
            Spacer()
        }
    }

    private var detailForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(String(localized: "field.duration", defaultValue: "时长(分钟)")) {
                Stepper("\(durationMinutes)", value: $durationMinutes, in: 0...240, step: 5)
                    .monospacedDigit()
            }
            Picker(String(localized: "field.completion", defaultValue: "完成度"), selection: $completion) {
                ForEach(CompletionLevel.allCases) { Text($0.localizedName).tag($0) }
            }
            Picker(String(localized: "field.intensity", defaultValue: "主观强度"), selection: $intensity) {
                ForEach(1...5, id: \.self) { Text(String($0)).tag($0) }
            }
            Picker(String(localized: "field.feeling", defaultValue: "身体感觉"), selection: $bodyFeeling) {
                ForEach(BodyFeeling.allCases) { Text($0.localizedName).tag($0) }
            }
            TextField(String(localized: "field.notes", defaultValue: "备注(可选)"), text: $notes, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                onDone()
            } label: {
                Text(String(localized: "quicklog.cancel", defaultValue: "取消"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)

            Button {
                save()
            } label: {
                Text(String(localized: "quicklog.save", defaultValue: "保存"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Logic

    private var needsDetails: Bool {
        switch type {
        case .strengthA, .strengthB, .run, .recovery: return true
        case .minimal, .rest: return false
        }
    }

    private func configureDefaults() {
        switch type {
        case .run:       durationMinutes = 30
        case .recovery:  durationMinutes = 8
        case .minimal:   durationMinutes = 8
        case .rest:      durationMinutes = 0
        default:         durationMinutes = 25
        }
    }

    private func save() {
        store.log(
            type: type,
            durationMinutes: needsDetails ? durationMinutes : (type == .minimal ? 8 : 0),
            completion: needsDetails ? completion : (type == .minimal ? .minimal : .full),
            intensity: needsDetails ? intensity : 2,
            bodyFeeling: needsDetails ? bodyFeeling.rawValue : nil,
            notes: notes.isEmpty ? nil : notes
        )
        onDone()
    }
}

/// Body-feeling picker values. The raw values are written into
/// `WorkoutSession.bodyFeeling` and scanned by `BackPainMarkers`.
enum BodyFeeling: String, CaseIterable, Identifiable {
    case normal, backTight, legSore, fatigue
    var id: String { rawValue }
    var localizedName: String {
        switch self {
        case .normal:    return String(localized: "feeling.normal",    defaultValue: "正常")
        case .backTight: return String(localized: "feeling.backTight", defaultValue: "腰紧")
        case .legSore:   return String(localized: "feeling.legSore",   defaultValue: "腿酸")
        case .fatigue:   return String(localized: "feeling.fatigue",   defaultValue: "疲劳")
        }
    }
}
