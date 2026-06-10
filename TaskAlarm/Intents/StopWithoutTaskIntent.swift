import AppIntents

struct StopWithoutTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Alarm"
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID")
    var originalAlarmID: String

    init() {}
    init(originalAlarmID: String) {
        self.originalAlarmID = originalAlarmID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: originalAlarmID) {
            await GateService.shared.handleCheatStop(originalAlarmID: id)
        }
        return .result()
    }
}
