import Foundation

enum GuardPolicy {
    enum Action: Equatable {
        case reArm(after: TimeInterval)
        case giveUp
    }

    static let interval: TimeInterval = 90
    static let maxGuards = 20

    static func action(forGuardCount count: Int) -> Action {
        count >= maxGuards ? .giveUp : .reArm(after: interval)
    }
}
