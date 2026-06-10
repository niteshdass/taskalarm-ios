import Foundation
import Testing
import SwiftData
@testable import TaskAlarm

@MainActor
struct ModelTests {
    func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: AlarmItem.self, QRCodeRecord.self, PendingTaskState.self,
            configurations: config)
    }

    @Test func alarmItemRoundTrips() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let alarm = AlarmItem(hour: 7, minute: 30, weekdays: [2, 3, 4, 5, 6],
                              label: "Work", taskType: .qrScan)
        context.insert(alarm)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AlarmItem>())
        #expect(fetched.count == 1)
        #expect(fetched[0].hour == 7)
        #expect(fetched[0].minute == 30)
        #expect(fetched[0].weekdays == [2, 3, 4, 5, 6])
        #expect(fetched[0].taskType == .qrScan)
        #expect(fetched[0].isEnabled == true)
    }

    @Test func pendingTaskStateTracksGuardCount() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pending = PendingTaskState(alarmID: UUID(), firedAt: .now)
        context.insert(pending)
        #expect(pending.guardCount == 0)
        pending.guardCount += 1
        #expect(pending.guardCount == 1)
    }
}
