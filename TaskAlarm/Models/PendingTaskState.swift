import Foundation
import SwiftData

@Model
final class PendingTaskState {
    var alarmID: UUID
    var firedAt: Date
    var guardCount: Int
    /// AlarmKit ID of the currently scheduled guard alarm, if any.
    var guardAlarmKitID: UUID?
    var snoozesUsed: Int

    init(alarmID: UUID, firedAt: Date, guardCount: Int = 0, snoozesUsed: Int = 0) {
        self.alarmID = alarmID
        self.firedAt = firedAt
        self.guardCount = guardCount
        self.snoozesUsed = snoozesUsed
    }
}
