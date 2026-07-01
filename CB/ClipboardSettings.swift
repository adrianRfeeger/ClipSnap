import Foundation

struct ClipboardAppRule: Codable, Hashable, Identifiable {
    var bundleIdentifier: String
    var ignoresClipboard: Bool
    var keepsLocalOnly: Bool
    var concealsPreviews: Bool
    var automaticTags: String
    var retentionDays: Int

    init(
        bundleIdentifier: String,
        ignoresClipboard: Bool = false,
        keepsLocalOnly: Bool = false,
        concealsPreviews: Bool = false,
        automaticTags: String = "",
        retentionDays: Int = -1
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.ignoresClipboard = ignoresClipboard
        self.keepsLocalOnly = keepsLocalOnly
        self.concealsPreviews = concealsPreviews
        self.automaticTags = automaticTags
        self.retentionDays = retentionDays
    }

    var id: String {
        bundleIdentifier
    }

    var normalized: ClipboardAppRule {
        ClipboardAppRule(
            bundleIdentifier: bundleIdentifier
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            ignoresClipboard: ignoresClipboard,
            keepsLocalOnly: keepsLocalOnly,
            concealsPreviews: concealsPreviews,
            automaticTags: automaticTags
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", "),
            retentionDays: max(-1, retentionDays)
        )
    }

    var hasActions: Bool {
        ignoresClipboard
            || keepsLocalOnly
            || concealsPreviews
            || !automaticTags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || retentionDays >= 0
    }
}

enum ClipboardSettingKey {
    static let maximumItemCount = "maximumItemCount"
    static let menuBarItemCount = "menuBarItemCount"
    static let retentionDays = "retentionDays"
    static let maximumStorageMegabytes = "maximumStorageMegabytes"
    static let keepFavorites = "keepFavorites"
    static let detectSensitiveContent = "detectSensitiveContent"
    static let moveDuplicatesToTop = "moveDuplicatesToTop"
    static let excludedBundleIdentifiers = "excludedBundleIdentifiers"
    static let appRules = "appRules"
    static let savedFilters = "savedFilters"
    static let ignoresInternalPasteboardTypes = "ignoresInternalPasteboardTypes"
    static let ignoredPasteboardTypes = "ignoredPasteboardTypes"
    static let protectsSensitivePreviews = "protectsSensitivePreviews"
    static let sensitiveRetentionMinutes = "sensitiveRetentionMinutes"
    static let textRetentionDays = "textRetentionDays"
    static let imageRetentionDays = "imageRetentionDays"
    static let fileRetentionDays = "fileRetentionDays"
    static let mediaRetentionDays = "mediaRetentionDays"
    static let otherRetentionDays = "otherRetentionDays"
    static let lastCleanupDate = "lastCleanupDate"
    static let lastCleanupDeletedCount = "lastCleanupDeletedCount"
    static let hasCompletedSetup = "hasCompletedSetup"
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
    var appRules: [ClipboardAppRule]
    var ignoresInternalPasteboardTypes: Bool
    var ignoredPasteboardTypes: Set<String>
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
        appRules: [],
        ignoresInternalPasteboardTypes: true,
        ignoredPasteboardTypes: [
            "org.chromium.internal.*",
            "org.chromium.source-url",
            "com.apple.IconComposer.layer",
            "com.apple.IconComposer.assets"
        ],
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
            appRules: parseAppRules(
                defaults.string(forKey: ClipboardSettingKey.appRules) ?? ""
            ),
            ignoresInternalPasteboardTypes: defaults.object(
                forKey: ClipboardSettingKey.ignoresInternalPasteboardTypes
            ) as? Bool ?? fallback.ignoresInternalPasteboardTypes,
            ignoredPasteboardTypes: parsePasteboardTypes(
                defaults.string(forKey: ClipboardSettingKey.ignoredPasteboardTypes)
                    ?? formattedPasteboardTypes(fallback.ignoredPasteboardTypes)
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

    static func parsePasteboardTypes(_ value: String) -> Set<String> {
        Set(
            value
                .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func formattedPasteboardTypes(_ identifiers: Set<String>) -> String {
        identifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .joined(separator: "\n")
    }

    static func parseAppRules(_ value: String) -> [ClipboardAppRule] {
        guard let data = value.data(using: .utf8),
              let rules = try? JSONDecoder().decode([ClipboardAppRule].self, from: data) else {
            return []
        }

        return rules
            .map { $0.normalized }
            .filter { !$0.bundleIdentifier.isEmpty }
    }

    static func formattedAppRules(_ rules: [ClipboardAppRule]) -> String {
        let normalizedRules = rules
            .map { $0.normalized }
            .filter { !$0.bundleIdentifier.isEmpty }
            .sorted {
                $0.bundleIdentifier.localizedCaseInsensitiveCompare($1.bundleIdentifier) == .orderedAscending
            }

        guard let data = try? JSONEncoder().encode(normalizedRules),
              let value = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return value
    }

    static func parseSavedFilters(_ value: String) -> [ClipboardSavedFilter] {
        guard let data = value.data(using: .utf8),
              let filters = try? JSONDecoder().decode([ClipboardSavedFilter].self, from: data) else {
            return []
        }

        var seenNames: Set<String> = []
        return filters.compactMap { filter in
            let normalized = filter.normalized
            guard !normalized.name.isEmpty,
                  !normalized.query.isEmpty else {
                return nil
            }

            let key = normalized.name.lowercased()
            guard !seenNames.contains(key) else {
                return nil
            }

            seenNames.insert(key)
            return ClipboardSavedFilter(
                id: normalized.id,
                name: normalized.name,
                query: normalized.query,
                isBuiltIn: false
            )
        }
    }

    static func formattedSavedFilters(_ filters: [ClipboardSavedFilter]) -> String {
        let normalizedFilters = filters
            .map { $0.normalized }
            .filter { !$0.name.isEmpty && !$0.query.isEmpty }
            .map {
                ClipboardSavedFilter(
                    id: $0.id,
                    name: $0.name,
                    query: $0.query,
                    isBuiltIn: false
                )
            }

        guard let data = try? JSONEncoder().encode(normalizedFilters),
              let value = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return value
    }

    func appRule(for bundleIdentifier: String?) -> ClipboardAppRule? {
        guard let bundleIdentifier = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !bundleIdentifier.isEmpty else {
            return nil
        }

        if let rule = appRules.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return rule
        }

        if excludedBundleIdentifiers.contains(bundleIdentifier) {
            return ClipboardAppRule(bundleIdentifier: bundleIdentifier, ignoresClipboard: true)
        }

        return nil
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

    func retentionDays(for type: String, sourceBundleIdentifier: String?) -> Int {
        if let appRule = appRule(for: sourceBundleIdentifier),
           appRule.retentionDays >= 0 {
            return appRule.retentionDays
        }

        return retentionDays(for: type)
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
