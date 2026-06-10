import Testing
@testable import TaskAlarm

struct SnoozePolicyTests {
    @Test func allowsUpToThreeSnoozes() {
        #expect(SnoozePolicy.canSnooze(snoozesUsed: 0))
        #expect(SnoozePolicy.canSnooze(snoozesUsed: 2))
        #expect(!SnoozePolicy.canSnooze(snoozesUsed: 3))
    }

    @Test func snoozeDurationIsNineMinutes() {
        #expect(SnoozePolicy.duration == 9 * 60)
    }
}
