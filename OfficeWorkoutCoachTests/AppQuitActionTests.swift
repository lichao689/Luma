import Testing

@MainActor
struct AppQuitActionTests {
    @Test
    func quitStopsMonitoringBeforeTerminating() {
        var events: [String] = []

        let action = AppQuitAction(
            stopMonitoring: { events.append("stop") },
            terminate: { events.append("terminate") }
        )

        action()

        #expect(events == ["stop", "terminate"])
    }
}
