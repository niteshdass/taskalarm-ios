import Foundation
import SwiftData

@Model
final class QRCodeRecord {
    var payload: String
    var createdAt: Date

    init(payload: String, createdAt: Date = .now) {
        self.payload = payload
        self.createdAt = createdAt
    }
}
