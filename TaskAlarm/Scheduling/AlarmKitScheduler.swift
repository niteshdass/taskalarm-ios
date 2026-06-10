import AlarmKit
import AppIntents
import SwiftUI

struct TaskAlarmMetadata: AlarmMetadata {
    let originalAlarmID: UUID
}

final class AlarmKitScheduler: AlarmScheduling {
    static let shared = AlarmKitScheduler()
    private let manager = AlarmManager.shared

    func requestAuthorization() async -> Bool {
        do {
            return try await manager.requestAuthorization() == .authorized
        } catch {
            return false
        }
    }

    func scheduleAlarm(for item: AlarmItemSnapshot) async throws -> UUID {
        let time = Alarm.Schedule.Relative.Time(hour: item.hour, minute: item.minute)
        let recurrence: Alarm.Schedule.Relative.Recurrence =
            item.weekdays.isEmpty ? .never : .weekly(item.weekdays.compactMap(Self.localeWeekday))
        let schedule = Alarm.Schedule.relative(.init(time: time, repeats: recurrence))
        return try await submit(schedule: schedule, label: item.label, originalAlarmID: item.id)
    }

    func scheduleOneShot(label: String, after interval: TimeInterval,
                         originalAlarmID: UUID) async throws -> UUID {
        let schedule = Alarm.Schedule.fixed(Date.now.addingTimeInterval(interval))
        return try await submit(schedule: schedule, label: label, originalAlarmID: originalAlarmID)
    }

    private func submit(schedule: Alarm.Schedule, label: String,
                          originalAlarmID: UUID) async throws -> UUID {
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: label.isEmpty ? "Wake up!" : label),
            secondaryButton: AlarmButton(text: "Solve task", textColor: .white,
                                         systemImageName: "qrcode.viewfinder"),
            secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: TaskAlarmMetadata(originalAlarmID: originalAlarmID),
            tintColor: Color.orange)
        let id = UUID()
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopWithoutTaskIntent(originalAlarmID: originalAlarmID.uuidString),
            secondaryIntent: OpenTaskGateIntent(originalAlarmID: originalAlarmID.uuidString))
        _ = try await manager.schedule(id: id, configuration: configuration)
        return id
    }

    func stop(id: UUID) throws { try manager.stop(id: id) }
    func cancel(id: UUID) throws { try manager.cancel(id: id) }

    /// Maps Calendar weekday number (1 = Sunday) to Locale.Weekday.
    static func localeWeekday(_ number: Int) -> Locale.Weekday? {
        switch number {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: nil
        }
    }
}
