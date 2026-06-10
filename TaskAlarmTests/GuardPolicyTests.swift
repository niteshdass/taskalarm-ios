import Testing
@testable import TaskAlarm

struct GuardPolicyTests {
    @Test func reArmsBelowCap() {
        #expect(GuardPolicy.action(forGuardCount: 0) == .reArm(after: 90))
        #expect(GuardPolicy.action(forGuardCount: 19) == .reArm(after: 90))
    }

    @Test func givesUpAtCap() {
        #expect(GuardPolicy.action(forGuardCount: 20) == .giveUp)
        #expect(GuardPolicy.action(forGuardCount: 25) == .giveUp)
    }
}
