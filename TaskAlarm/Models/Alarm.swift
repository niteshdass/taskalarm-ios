import Foundation
import SwiftData

@Model
final class AlarmItem {
    var id: UUID
    var hour: Int
    var minute: Int
    /// Calendar weekday numbers, 1 = Sunday … 7 = Saturday. Empty = one-shot.
    var weekdays: [Int]
    var label: String
    var isEnabled: Bool
    var taskType: TaskType
    /// ID of the currently scheduled AlarmKit alarm, if any.
    var alarmKitID: UUID?

    init(id: UUID = UUID(), hour: Int, minute: Int, weekdays: [Int] = [],
         label: String = "", isEnabled: Bool = true, taskType: TaskType = .phrase) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.label = label
        self.isEnabled = isEnabled
        self.taskType = taskType
    }
}
