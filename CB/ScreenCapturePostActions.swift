import Foundation

enum ScreenCapturePostActionKey {
    static let automaticallyRecognizesText = "screenCaptureAutomaticallyRecognizesText"
    static let favoritesCapture = "screenCaptureFavoritesCapture"
    static let pinsCapture = "screenCapturePinsCapture"
    static let captureTags = "screenCaptureTags"
}

struct ScreenCapturePostActions: Equatable {
    var automaticallyRecognizesText: Bool
    var favoritesCapture: Bool
    var pinsCapture: Bool
    var tags: [String]

    static let defaults = ScreenCapturePostActions(
        automaticallyRecognizesText: false,
        favoritesCapture: false,
        pinsCapture: false,
        tags: []
    )

    static func load(from defaults: UserDefaults = .standard) -> ScreenCapturePostActions {
        let fallback = Self.defaults
        return ScreenCapturePostActions(
            automaticallyRecognizesText: defaults.object(
                forKey: ScreenCapturePostActionKey.automaticallyRecognizesText
            ) as? Bool ?? fallback.automaticallyRecognizesText,
            favoritesCapture: defaults.object(
                forKey: ScreenCapturePostActionKey.favoritesCapture
            ) as? Bool ?? fallback.favoritesCapture,
            pinsCapture: defaults.object(
                forKey: ScreenCapturePostActionKey.pinsCapture
            ) as? Bool ?? fallback.pinsCapture,
            tags: parseTags(
                defaults.string(forKey: ScreenCapturePostActionKey.captureTags) ?? ""
            )
        )
    }

    static func parseTags(_ value: String) -> [String] {
        Array(
            Set(
                value
                    .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    @MainActor
    func apply(to item: ClipboardItem) {
        item.isFavorite = favoritesCapture
        item.isPinned = pinsCapture
        let combinedTags = Set(item.tags).union(tags)
        item.tagsText = combinedTags.isEmpty
            ? nil
            : combinedTags.sorted().joined(separator: ", ")
        item.updatedAt = Date()
    }
}
