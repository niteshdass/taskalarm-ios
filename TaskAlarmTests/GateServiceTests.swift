import Testing
import SwiftData
@testable import TaskAlarm

final class MockScheduler: AlarmScheduling, @unchecked Sendable {
    var scheduledOneShots: [(label: String, interval: TimeInterval, originalAlarmID: UUID)] = []
    var cancelledIDs: [UUID] = []
    var stoppedIDs: [UUID] = []

    func requestAuthorization() async -> Bool { true }
    func scheduleAlarm(for item: AlarmItemSnapshot) async throws -> UUID { UUID() }
    func scheduleOneShot(label: String, after interval: TimeInterval,
                         originalAlarmID: UUID) async throws -> UUID {
        scheduledOneShots.append((label, interval, originalAlarmID))
        return UUID()
    }
    func stop(id: UUID) throws { stoppedIDs.append(id) }
    func cancel(id: UUID) throws { cancelledIDs.append(id) }
}

@MainActor
struct GateServiceTests {
    func makeService() throws -> (GateService, MockScheduler, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AlarmItem.self, QRCodeRecord.self, PendingTaskState.self,
            configurations: config)
        let mock = MockScheduler()
        let service = GateService(scheduler: mock)
        service.modelContext = container.mainContext
        return (service, mock, container.mainContext)
    }

    @Test func cheatStopSchedulesGuardAndIncrementsCount() async throws {
        let (service, mock, context) = try makeService()
        let alarmID = UUID()

        await service.handleCheatStop(originalAlarmID: alarmID)

        #expect(mock.scheduledOneShots.count == 1)
        #expect(mock.scheduledOneShots[0].interval == 90)
        let pending = try context.fetch(FetchDescriptor<PendingTaskState>())
        #expect(pending.count == 1)
        #expect(pending[0].guardCount == 1)
    }

    @Test func cheatStopGivesUpAtCap() async throws {
        let (service, mock, context) = try makeService()
        let alarmID = UUID()
        let pending = PendingTaskState(alarmID: alarmID, firedAt: .now,
                                       guardCount: GuardPolicy.maxGuards)
        context.insert(pending)
        try context.save()

        await service.handleCheatStop(originalAlarmID: alarmID)

        #expect(mock.scheduledOneShots.isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingTaskState>()).isEmpty)
    }

    @Test func completeTaskCancelsGuardAndClearsState() async throws {
        let (service, mock, context) = try makeService()
        let alarmID = UUID()
        await service.handleCheatStop(originalAlarmID: alarmID)

        _ = service.completeTask(originalAlarmID: alarmID)

        #expect(mock.cancelledIDs.count == 1)
        #expect(try context.fetch(FetchDescriptor<PendingTaskState>()).isEmpty)
    }

    @Test func snoozeSchedulesNineMinuteOneShot() async throws {
        let (service, mock, context) = try makeService()
        let alarmID = UUID()

        await service.snooze(originalAlarmID: alarmID, snoozesUsed: 0)

        #expect(mock.scheduledOneShots.count == 1)
        #expect(mock.scheduledOneShots[0].interval == SnoozePolicy.duration)
        let pending = try context.fetch(FetchDescriptor<PendingTaskState>())
        #expect(pending[0].snoozesUsed == 1)
    }

    @Test func syncDisablesFiredOneShots() async throws {
        let (service, _, context) = try makeService()
        let oneShot = AlarmItem(hour: 7, minute: 0, weekdays: [], label: "Once")
        oneShot.alarmKitID = UUID()
        oneShot.isEnabled = true
        let weekly = AlarmItem(hour: 8, minute: 0, weekdays: [2], label: "Weekly")
        weekly.alarmKitID = UUID()
        weekly.isEnabled = true
        context.insert(oneShot)
        context.insert(weekly)
        try context.save()

        // Neither ID present in AlarmKit's set anymore.
        service.syncWithAlarmKit(activeAlarmKitIDs: [])

        #expect(oneShot.isEnabled == false)   // one-shot fired → disabled
        #expect(weekly.isEnabled == true)     // weekly stays enabled (AlarmKit reschedules)
    }
}
