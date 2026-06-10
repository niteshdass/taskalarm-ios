import Foundation

protocol AlarmScheduling: Sendable {
    /// Returns true if alarm authorization is granted.
    func requestAuthorization() async -> Bool
    /// Schedules the main alarm for an AlarmItem. Returns the AlarmKit alarm ID.
    func scheduleAlarm(for item: AlarmItemSnapshot) async throws -> UUID
    /// Schedules a one-shot alarm (guard or snooze) after `interval` seconds. Returns its ID.
    func scheduleOneShot(label: String, after interval: TimeInterval,
                         originalAlarmID: UUID) async throws -> UUID
    /// Stops a currently ringing alarm.
    func stop(id: UUID) throws
    /// Cancels a scheduled (not yet fired) alarm.
    func cancel(id: UUID) throws
}

/// Plain value passed across actor boundaries (SwiftData models are not Sendable).
struct AlarmItemSnapshot: Sendable {
    let id: UUID
    let hour: Int
    let minute: Int
    let weekdays: [Int]   // 1 = Sunday … 7 = Saturday
    let label: String
}
