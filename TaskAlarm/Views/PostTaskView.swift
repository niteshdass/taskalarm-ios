import SwiftUI

struct PostTaskView: View {
    let alarmID: UUID
    let snoozesUsed: Int

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Task done. You're awake.")
                .font(.title2)

            Button("Dismiss alarm") {
                AppRouter.shared.activeGateAlarmID = nil
            }
            .buttonStyle(.borderedProminent)

            if SnoozePolicy.canSnooze(snoozesUsed: snoozesUsed) {
                Button("Snooze 9 minutes (\(SnoozePolicy.maxSnoozes - snoozesUsed) left)") {
                    Task {
                        await GateService.shared.snooze(originalAlarmID: alarmID,
                                                        snoozesUsed: snoozesUsed)
                        AppRouter.shared.activeGateAlarmID = nil
                    }
                }
            }
        }
        .padding()
    }
}
