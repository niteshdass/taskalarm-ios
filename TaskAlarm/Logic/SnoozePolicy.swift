import Foundation

enum SnoozePolicy {
    static let duration: TimeInterval = 9 * 60
    static let maxSnoozes = 3

    static func canSnooze(snoozesUsed: Int) -> Bool {
        snoozesUsed < maxSnoozes
    }
}
