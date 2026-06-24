import Foundation

enum ClipboardSettingKey {
    static let maximumItemCount = "maximumItemCount"
    static let retentionDays = "retentionDays"
    static let maximumStorageMegabytes = "maximumStorageMegabytes"
    static let keepFavorites = "keepFavorites"
    static let detectSensitiveContent = "detectSensitiveContent"
    static let moveDuplicatesToTop = "moveDuplicatesToTop"
    static let excludedBundleIdentifiers = "excludedBundleIdentifiers"
}

struct ClipboardSettings {
    var maximumItemCount: Int
    var retentionDays: Int
    var maximumStorageMegabytes: Int
    var keepFavorites: Bool
    var detectSensitiveContent: Bool
    var moveDuplicatesToTop: Bool
    var excludedBundleIdentifiers: Set<String>

    static let defaults = ClipboardSettings(
        maximumItemCount: 500,
        retentionDays: 30,
        maximumStorageMegabytes: 250,
        keepFavorites: true,
        detectSensitiveContent: true,
        moveDuplicatesToTop: true,
        excludedBundleIdentifiers: []
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

        return ClipboardSettings(
            maximumItemCount: maximumItemCount,
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

    private static func positiveValue(_ value: Int, fallback: Int) -> Int {
        value > 0 ? value : fallback
    }

}
