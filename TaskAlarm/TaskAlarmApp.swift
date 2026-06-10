import SwiftUI
import SwiftData
import AlarmKit

@main
struct TaskAlarmApp: App {
    let container: ModelContainer
    @State private var router = AppRouter.shared
    @State private var authorized: Bool? = nil

    init() {
        do {
            container = try ModelContainer(
                for: AlarmItem.self, QRCodeRecord.self, PendingTaskState.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        GateService.shared.modelContext = container.mainContext
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch authorized {
                case nil: ProgressView()
                case false?: AuthorizationBlockedView()
                case true?: ContentView()
                }
            }
            .task {
                authorized = await GateService.shared.scheduler.requestAuthorization()
                resumePendingGate()
                for await alarms in AlarmManager.shared.alarmUpdates {
                    GateService.shared.syncWithAlarmKit(
                        activeAlarmKitIDs: Set(alarms.map(\.id)))
                }
            }
            .fullScreenCover(item: Binding(
                get: { router.activeGateAlarmID.map(GateTarget.init) },
                set: { router.activeGateAlarmID = $0?.id })) { target in
                TaskGateView(alarmID: target.id)
            }
        }
        .modelContainer(container)
    }

    /// App relaunched with unfinished gate (force-kill survival).
    private func resumePendingGate() {
        let pending = try? container.mainContext.fetch(FetchDescriptor<PendingTaskState>())
        if let first = pending?.first {
            AppRouter.shared.activeGateAlarmID = first.alarmID
        }
    }
}

struct GateTarget: Identifiable {
    let id: UUID
}
