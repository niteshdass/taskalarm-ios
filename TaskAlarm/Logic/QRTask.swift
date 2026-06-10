import Foundation

enum QRTask {
    static func generatePayload() -> String {
        "wakeup-\(UUID().uuidString)"
    }

    static func validate(scanned: String, against payload: String) -> Bool {
        scanned == payload
    }
}
