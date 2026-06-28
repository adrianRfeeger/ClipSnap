import Foundation

enum ClipboardSettingKey {
    static let maximumItemCount = "maximumItemCount"
    static let menuBarItemCount = "menuBarItemCount"
    static let retentionDays = "retentionDays"
    static let maximumStorageMegabytes = "maximumStorageMegabytes"
    static let keepFavorites = "keepFavorites"
    static let detectSensitiveContent = "detectSensitiveContent"
    static let moveDuplicatesToTop = "moveDuplicatesToTop"
    static let excludedBundleIdentifiers = "excludedBundleIdentifiers"
    static let protectsSensitivePreviews = "protectsSensitivePreviews"
    static let sensitiveRetentionMinutes = "sensitiveRetentionMinutes"
    static let textRetentionDays = "textRetentionDays"
    static let imageRetentionDays = "imageRetentionDays"
    static let fileRetentionDays = "fileRetentionDays"
    static let mediaRetentionDays = "mediaRetentionDays"
    static let otherRetentionDays = "otherRetentionDays"
}

struct ClipboardSettings {
    var maximumItemCount: Int
    var menuBarItemCount: Int
    var retentionDays: Int
    var maximumStorageMegabytes: Int
    var keepFavorites: Bool
    var detectSensitiveContent: Bool
    var moveDuplicatesToTop: Bool
    var excludedBundleIdentifiers: Set<String>
    var protectsSensitivePreviews: Bool
    var sensitiveRetentionMinutes: Int
    var textRetentionDays: Int
    var imageRetentionDays: Int
    var fileRetentionDays: Int
    var mediaRetentionDays: Int
    var otherRetentionDays: Int

    static let defaults = ClipboardSettings(
        maximumItemCount: 500,
        menuBarItemCount: 12,
        retentionDays: 30,
        maximumStorageMegabytes: 250,
        keepFavorites: true,
        detectSensitiveContent: true,
        moveDuplicatesToTop: true,
        excludedBundleIdentifiers: [],
        protectsSensitivePreviews: true,
        sensitiveRetentionMinutes: 60,
        textRetentionDays: -1,
        imageRetentionDays: -1,
        fileRetentionDays: -1,
        mediaRetentionDays: -1,
        otherRetentionDays: -1
    )

    static func load(from defaults: UserDefaults = .standard) -> ClipboardSettings {
        let fallback = Self.defaults
        let maximumItemCount = defaults.object(forKey: ClipboardSettingKey.maximumItemCount) == nil
            ? fallback.maximumItemCount
            : positiveValue(defaults.integer(forKey: ClipboardSettingKey.maximumItemCount), fallback: fallback.maximumItemCount)
        let retentionDays = defaults.object(forKey: ClipboardSettingKey.retentionDays) == nil
            ? fallback.retentionDays
            : max(0, defaults.integer(forKey: ClipboardSettingKey.retentionDays))
        let maximumStorageMegabytes = defaults.object(forKey: ClipboardSettingKey.maximumStorageMegabytes) == nil
            ? fallback.maximumStorageMegabytes
            : positiveValue(defaults.integer(forKey: ClipboardSettingKey.maximumStorageMegabytes), fallback: fallback.maximumStorageMegabytes)
        let menuBarItemCount = defaults.object(forKey: ClipboardSettingKey.menuBarItemCount) == nil
            ? fallback.menuBarItemCount
            : min(50, positiveValue(defaults.integer(forKey: ClipboardSettingKey.menuBarItemCount), fallback: fallback.menuBarItemCount))

        return ClipboardSettings(
            maximumItemCount: maximumItemCount,
            menuBarItemCount: menuBarItemCount,
            retentionDays: retentionDays,
            maximumStorageMegabytes: maximumStorageMegabytes,
            keepFavorites: defaults.object(forKey: ClipboardSettingKey.keepFavorites) as? Bool
                ?? fallback.keepFavorites,
            detectSensitiveContent: defaults.object(forKey: ClipboardSettingKey.detectSensitiveContent) as? Bool
                ?? fallback.detectSensitiveContent,
            moveDuplicatesToTop: defaults.object(forKey: ClipboardSettingKey.moveDuplicatesToTop) as? Bool
                ?? fallback.moveDuplicatesToTop,
            excludedBundleIdentifiers: parseBundleIdentifiers(
                defaults.string(forKey: ClipboardSettingKey.excludedBundleIdentifiers) ?? ""
            ),
            protectsSensitivePreviews: defaults.object(
                forKey: ClipboardSettingKey.protectsSensitivePreviews
            ) as? Bool ?? fallback.protectsSensitivePreviews,
            sensitiveRetentionMinutes: defaults.object(
                forKey: ClipboardSettingKey.sensitiveRetentionMinutes
            ) == nil
                ? fallback.sensitiveRetentionMinutes
                : max(0, defaults.integer(forKey: ClipboardSettingKey.sensitiveRetentionMinutes)),
            textRetentionDays: retentionOverride(
                forKey: ClipboardSettingKey.textRetentionDays,
                defaults: defaults
            ),
            imageRetentionDays: retentionOverride(
                forKey: ClipboardSettingKey.imageRetentionDays,
                defaults: defaults
            ),
            fileRetentionDays: retentionOverride(
                forKey: ClipboardSettingKey.fileRetentionDays,
                defaults: defaults
            ),
            mediaRetentionDays: retentionOverride(
                forKey: ClipboardSettingKey.mediaRetentionDays,
                defaults: defaults
            ),
            otherRetentionDays: retentionOverride(
                forKey: ClipboardSettingKey.otherRetentionDays,
                defaults: defaults
            )
        )
    }

    static func parseBundleIdentifiers(_ value: String) -> Set<String> {
        Set(
            value
                .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    static func formattedBundleIdentifiers(_ identifiers: Set<String>) -> String {
        identifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "\n")
    }

    private static func positiveValue(_ value: Int, fallback: Int) -> Int {
        value > 0 ? value : fallback
    }

    private static func retentionOverride(
        forKey key: String,
        defaults: UserDefaults
    ) -> Int {
        guard defaults.object(forKey: key) != nil else {
            return -1
        }
        return max(-1, defaults.integer(forKey: key))
    }

    func retentionDays(for type: String) -> Int {
        let override: Int
        switch ClipboardRetentionCategory(type: type) {
        case .text:
            override = textRetentionDays
        case .images:
            override = imageRetentionDays
        case .files:
            override = fileRetentionDays
        case .media:
            override = mediaRetentionDays
        case .other:
            override = otherRetentionDays
        }
        return override >= 0 ? override : retentionDays
    }

}

enum ClipboardRetentionCategory: String, CaseIterable, Identifiable {
    case text
    case images
    case files
    case media
    case other

    init(type: String) {
        switch type {
        case ClipboardItemType.text,
            ClipboardItemType.url,
            ClipboardItemType.rtf,
            ClipboardItemType.rtfd,
            ClipboardItemType.html,
            ClipboardItemType.json,
            ClipboardItemType.xml,
            ClipboardItemType.sourceCode,
            ClipboardItemType.tabularText,
            ClipboardItemType.contact:
            self = .text
        case ClipboardItemType.image, ClipboardItemType.color:
            self = .images
        case ClipboardItemType.file, ClipboardItemType.archive, ClipboardItemType.pdf:
            self = .files
        case ClipboardItemType.audio, ClipboardItemType.video:
            self = .media
        default:
            self = .other
        }
    }

    var id: String {
        rawValue
    }
}
