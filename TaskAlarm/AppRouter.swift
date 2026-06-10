import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    /// When set, the UI must present the task gate for this AlarmItem id.
    var activeGateAlarmID: UUID?
}
