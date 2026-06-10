import Foundation

enum PhraseTask {
    static let wordPool: [String] = [
        "anchor", "basket", "candle", "dragon", "ember", "falcon", "garden",
        "hammer", "island", "jacket", "kettle", "lantern", "marble", "needle",
        "orange", "pebble", "quiver", "ribbon", "saddle", "timber", "umbrella",
        "violet", "walnut", "yellow", "zipper", "bridge", "copper", "desert",
        "engine", "forest", "guitar", "harbor", "iceberg", "jungle", "kitten",
        "ladder", "magnet", "nectar", "ocean", "pencil", "quartz", "rocket",
        "silver", "tunnel", "valley", "window", "garlic", "helmet", "insect", "jigsaw"
    ]

    static func generate() -> String {
        wordPool.shuffled().prefix(8).joined(separator: " ")
    }

    static func validate(input: String, against phrase: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines) == phrase
    }
}
