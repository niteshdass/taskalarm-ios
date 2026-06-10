import Testing
@testable import TaskAlarm

struct QRTaskTests {
    @Test func payloadHasWakeupPrefix() {
        let payload = QRTask.generatePayload()
        #expect(payload.hasPrefix("wakeup-"))
    }

    @Test func payloadsAreUnique() {
        #expect(QRTask.generatePayload() != QRTask.generatePayload())
    }

    @Test func validateAcceptsMatchingPayload() {
        let payload = QRTask.generatePayload()
        #expect(QRTask.validate(scanned: payload, against: payload))
    }

    @Test func validateRejectsOtherPayload() {
        #expect(!QRTask.validate(scanned: "wakeup-aaaa", against: "wakeup-bbbb"))
    }

    @Test func validateRejectsArbitraryQRContent() {
        #expect(!QRTask.validate(scanned: "https://example.com", against: QRTask.generatePayload()))
    }
}
