import Foundation

enum TaskType: String, Codable, CaseIterable, Identifiable {
    case qrScan
    case phrase

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qrScan: "Scan QR code"
        case .phrase: "Type a phrase"
        }
    }
}
