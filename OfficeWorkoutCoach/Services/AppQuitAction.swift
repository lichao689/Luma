import Foundation

@MainActor
struct AppQuitAction {
    var stopMonitoring: () -> Void
    var terminate: () -> Void

    func callAsFunction() {
        stopMonitoring()
        terminate()
    }
}
