import SwiftUI
import SwiftData

struct TaskGateView: View {
    let alarmID: UUID
    @Environment(\.modelContext) private var modelContext
    @State private var solved = false
    @State private var snoozesUsed = 0
    @State private var forcePhraseFallback = false

    var body: some View {
        if solved {
            PostTaskView(alarmID: alarmID, snoozesUsed: snoozesUsed)
        } else {
            content
                .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private var content: some View {
        let alarm = (try? modelContext.fetch(FetchDescriptor<AlarmItem>()))?
            .first { $0.id == alarmID }
        let qrPayload = (try? modelContext.fetch(FetchDescriptor<QRCodeRecord>()).first)?.payload

        if let alarm, alarm.taskType == .qrScan, let qrPayload, !forcePhraseFallback {
            QRScanView(expectedPayload: qrPayload,
                       onSolved: complete,
                       onFallbackRequested: { forcePhraseFallback = true })
        } else {
            PhraseTaskView(onSolved: complete)
        }
    }

    private func complete() {
        snoozesUsed = GateService.shared.completeTask(originalAlarmID: alarmID)
        solved = true
    }
}
