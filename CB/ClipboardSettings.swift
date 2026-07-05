import Foundation

struct ClipboardAppRule: Codable, Hashable, Identifiable {
    var bundleIdentifier: String
    var ignoresClipboard: Bool
    var keepsLocalOnly: Bool
    var concealsPreviews: Bool
    var skipsAppleIntelligence: Bool
    var automaticTags: String
    var retentionDays: Int

    init(
        bundleIdentifier: String,
        ignoresClipboard: Bool = false,
        keepsLocalOnly: Bool = false,
        concealsPreviews: Bool = false,
        skipsAppleIntelligence: Bool = false,
        automaticTags: String = "",
        retentionDays: Int = -1
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.ignoresClipboard = ignoresClipboard
        self.keepsLocalOnly = keepsLocalOnly
        self.concealsPreviews = concealsPreviews
        self.skipsAppleIntelligence = skipsAppleIntelligence
        self.automaticTags = automaticTags
        self.retentionDays = retentionDays
    }

    enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case ignoresClipboard
        case keepsLocalOnly
        case concealsPreviews
        case skipsAppleIntelligence
        case automaticTags
        case retentionDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        ignoresClipboard = try container.decodeIfPresent(Bool.self, forKey: .ignoresClipboard) ?? false
        keepsLocalOnly = try container.decodeIfPresent(Bool.self, forKey: .keepsLocalOnly) ?? false
        concealsPreviews = try container.decodeIfPresent(Bool.self, forKey: .concealsPreviews) ?? false
        skipsAppleIntelligence = try container.decodeIfPresent(Bool.self, forKey: .skipsAppleIntelligence) ?? false
        automaticTags = try container.decodeIfPresent(String.self, forKey: .automaticTags) ?? ""
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? -1
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
            skipsAppleIntelligence: skipsAppleIntelligence,
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
            || skipsAppleIntelligence
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
    static let localFolderSyncEnabled = "localFolderSyncEnabled"
    static let localFolderSyncPath = "localFolderSyncPath"
    static let localFolderAutomaticSyncEnabled = "localFolderAutomaticSyncEnabled"
    static let localFolderAutomaticSyncIntervalMinutes = "localFolderAutomaticSyncIntervalMinutes"
    static let appleIntelligenceSuggestionsEnabled = "appleIntelligenceSuggestionsEnabled"
    static let appleIntelligenceSuggestsTitles = "appleIntelligenceSuggestsTitles"
    static let appleIntelligenceSuggestsTags = "appleIntelligenceSuggestsTags"
    static let appleIntelligenceSuggestsCollections = "appleIntelligenceSuggestsCollections"
    static let appleIntelligenceSummarizesContent = "appleIntelligenceSummarizesContent"
    static let appleIntelligenceDescribesImages = "appleIntelligenceDescribesImages"
    static let appleIntelligenceAppliesSuggestionsAutomatically = "appleIntelligenceAppliesSuggestionsAutomatically"
    static let appleIntelligenceReviewsSensitiveItems = "appleIntelligenceReviewsSensitiveItems"
    static let appleIntelligenceSyncsAcceptedMetadata = "appleIntelligenceSyncsAcceptedMetadata"
    static let generatedClipboardMetadata = "generatedClipboardMetadata"
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
    var appleIntelligenceSuggestionsEnabled: Bool
    var appleIntelligenceSuggestsTitles: Bool
    var appleIntelligenceSuggestsTags: Bool
    var appleIntelligenceSuggestsCollections: Bool
    var appleIntelligenceSummarizesContent: Bool
    var appleIntelligenceDescribesImages: Bool
    var appleIntelligenceAppliesSuggestionsAutomatically: Bool
    var appleIntelligenceReviewsSensitiveItems: Bool
    var appleIntelligenceSyncsAcceptedMetadata: Bool

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
        otherRetentionDays: -1,
        appleIntelligenceSuggestionsEnabled: false,
        appleIntelligenceSuggestsTitles: true,
        appleIntelligenceSuggestsTags: true,
        appleIntelligenceSuggestsCollections: false,
        appleIntelligenceSummarizesContent: true,
        appleIntelligenceDescribesImages: true,
        appleIntelligenceAppliesSuggestionsAutomatically: false,
        appleIntelligenceReviewsSensitiveItems: true,
        appleIntelligenceSyncsAcceptedMetadata: true
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
            ),
            appleIntelligenceSuggestionsEnabled: defaults.object(
                forKey: ClipboardSettingKey.appleIntelligenceSuggestionsEnabled
            ) as? Bool ?? fallback.appleIntelligenceSuggestionsEnabled,
            appleIntelligenceSuggestsTitles: defaults.object(
                forKey: ClipboardSettingKey.appleIntelligenceSuggestsTitles
            ) as? Bool ?? fallback.appleIntelligenceSuggestsTitles,
            appleIntelligenceSuggestsTags: defaults.object(
                forKey: ClipboardSettingKey.appleIntelligenceSuggestsTags
            ) as? Bool ?? fallback.appleIntelligenceSuggestsTags,
            appleIntelligenceSuggestsCollections: defaults.object(
                forKey: ClipboardSettingKey.appleIntelligenceSuggestsCollections
            ) as? Bool ?? fallback.appleIntelligenceSuggestsCollections,
            appleIntelligenceSummarizesContent: defaults.object(
                forKey: ClipboardSettingKey.appleIntelligenceSummarizesContent
            ) as? Bool ?? fallback.appleIntelligenceSummarizesContent,
            appleIntelligenceDescribesImages: defaults.object(
                forKey: ClipboardSettingKey.appleIntelligenceDescribesImages
            ) as? Bool ?? fallback.appleIntelligenceDescribesImages,
            appleIntelligenceAppliesSuggestionsAutomatically: defaults.object(
                forKey: ClipboardSettingKey.appleIntelligenceAppliesSuggestionsAutomatically
            ) as? Bool ?? fallback.appleIntelligenceAppliesSuggestionsAutomatically,
            appleIntelligenceReviewsSensitiveItems: defaults.object(
                forKey: ClipboardSettingKey.appleIntelligenceReviewsSensitiveItems
            ) as? Bool ?? fallback.appleIntelligenceReviewsSensitiveItems,
            appleIntelligenceSyncsAcceptedMetadata: defaults.object(
                forKey: ClipboardSettingKey.appleIntelligenceSyncsAcceptedMetadata
            ) as? Bool ?? fallback.appleIntelligenceSyncsAcceptedMetadata
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
