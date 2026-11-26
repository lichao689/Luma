import SwiftUI
import AppKit

/// Lives with the menu-bar label, so notifications can open the workout even
/// when the popover has never been opened or is currently closed.
struct WorkoutLaunchModifier: ViewModifier {
    @ObservedObject var notifier: NotificationManager
    @ObservedObject var workout: WorkoutCoordinator
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onChange(of: notifier.pendingDeepLink) { _, _ in consume() }
            .onAppear { consume() }
    }

    private func consume() {
        guard let link = notifier.pendingDeepLink else { return }
        switch link {
        case .startMinimal: workout.prepare(.minimal, minutes: 8)
        case .startRecovery: workout.prepare(.recovery, minutes: 8)
        }
        notifier.pendingDeepLink = nil
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "workout")
    }
}
