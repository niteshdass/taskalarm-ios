import AppIntents

struct OpenTaskGateIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Solve Task"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    @Parameter(title: "Alarm ID")
    var originalAlarmID: String

    init() {}
    init(originalAlarmID: String) {
        self.originalAlarmID = originalAlarmID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: originalAlarmID) {
            await GateService.shared.handleOpenGate(originalAlarmID: id)
        }
        return .result()
    }
}
