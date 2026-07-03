import CryptoKit
import CoreData
import Foundation

struct ClipboardRepresentationPayload: Sendable, Equatable {
    let itemIndex: Int
    let order: Int
    let utiIdentifier: String
    let data: Data?
    let stringValue: String?

    var byteCount: Int64 {
        Int64((data?.count ?? 0) + (stringValue?.utf8.count ?? 0))
    }
}

struct ClipboardPayload: Sendable {
    let type: String
    let plainText: String?
    let utiType: String?
    let rawData: Data?
    let imageData: Data?
    let representations: [ClipboardRepresentationPayload]

    init(
        type: String,
        plainText: String?,
        utiType: String?,
        rawData: Data?,
        imageData: Data?,
        representations: [ClipboardRepresentationPayload] = []
    ) {
        self.type = type
        self.plainText = plainText
        self.utiType = utiType
        self.rawData = rawData
        self.imageData = imageData
        self.representations = representations
    }

    var byteCount: Int64 {
        if !representations.isEmpty {
            return representations.reduce(0) { $0 + $1.byteCount }
        }

        return Int64(
            (plainText?.utf8.count ?? 0)
                + (rawData?.count ?? 0)
                + (imageData?.count ?? 0)
        )
    }
}

enum ClipboardContentHasher {
    static func hash(_ payload: ClipboardPayload) -> String {
        var data = Data()
        append(payload.type.data(using: .utf8), to: &data)
        append(payload.utiType?.data(using: .utf8), to: &data)
        append(payload.plainText?.data(using: .utf8), to: &data)
        if payload.representations.isEmpty {
            append(payload.rawData, to: &data)
            append(payload.imageData, to: &data)
        } else {
            for representation in payload.representations.sorted(by: {
                if $0.itemIndex != $1.itemIndex {
                    return $0.itemIndex < $1.itemIndex
                }
                if $0.order != $1.order {
                    return $0.order < $1.order
                }
                return $0.utiIdentifier < $1.utiIdentifier
            }) {
                append(String(representation.itemIndex).data(using: .utf8), to: &data)
                append(String(representation.order).data(using: .utf8), to: &data)
                append(representation.utiIdentifier.data(using: .utf8), to: &data)
                append(representation.data, to: &data)
                append(representation.stringValue?.data(using: .utf8), to: &data)
            }
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func append(_ value: Data?, to data: inout Data) {
        var count = UInt64(value?.count ?? 0).bigEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        if let value {
            data.append(value)
        }
    }
}

struct ClipboardSyncPackage: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var item: ClipboardSyncPackageItem
    var representations: [ClipboardSyncPackageRepresentation]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        item: ClipboardSyncPackageItem,
        representations: [ClipboardSyncPackageRepresentation]
    ) {
        self.schemaVersion = schemaVersion
        self.item = item
        self.representations = representations
    }

    @MainActor
    init(item: ClipboardItem) {
        self.schemaVersion = Self.currentSchemaVersion
        self.item = ClipboardSyncPackageItem(item: item)
        self.representations = item.sortedRepresentations.map(ClipboardSyncPackageRepresentation.init)
    }

    var itemIdentifier: UUID {
        item.id
    }

    var contentHash: String {
        item.contentHash
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> ClipboardSyncPackage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClipboardSyncPackage.self, from: data)
    }

    @discardableResult
    func makeClipboardItem(
        in context: NSManagedObjectContext,
        preservesIdentifier: Bool = true
    ) -> ClipboardItem {
        let item = ClipboardItem.make(
            in: context,
            type: self.item.type,
            plainText: self.item.plainText,
            previewText: self.item.previewText,
            imageData: self.item.imageData,
            thumbnailData: self.item.thumbnailData,
            rawData: self.item.rawData,
            utiType: self.item.utiType,
            sourceApp: self.item.sourceApp,
            sourceBundleIdentifier: self.item.sourceBundleIdentifier
        )
        item.id = preservesIdentifier ? self.item.id : UUID()
        item.createdAt = self.item.createdAt
        item.updatedAt = self.item.updatedAt
        item.customTitle = self.item.customTitle
        item.notes = self.item.notes
        item.tagsText = self.item.tagsText
        item.collectionName = self.item.collectionName
        item.isPinned = self.item.isPinned
        item.isFavorite = self.item.isFavorite
        item.isArchived = self.item.isArchived
        item.isSensitive = self.item.isSensitive
        item.isLocalOnly = self.item.isLocalOnly
        item.recognizedText = self.item.recognizedText
        item.relatedItemIdentifier = self.item.relatedItemIdentifier
        item.byteCount = self.item.byteCount
        item.contentHash = self.item.contentHash

        for representation in representations {
            representation.makeClipboardRepresentation(for: item, in: context)
        }
        return item
    }
}

enum ClipboardSyncMergeResult: Equatable {
    case inserted
    case updatedMetadata
    case preservedConflict
    case unchanged
}

enum ClipboardSyncDeleteResolution: Equatable {
    case deleteLocal
    case keepNewerLocal
    case missingLocal
}

enum ClipboardSyncConflictResolver {
    @MainActor
    @discardableResult
    static func merge(
        package: ClipboardSyncPackage,
        existingItem: ClipboardItem?,
        in context: NSManagedObjectContext
    ) -> (item: ClipboardItem?, result: ClipboardSyncMergeResult) {
        guard let existingItem else {
            return (package.makeClipboardItem(in: context), .inserted)
        }

        if existingItem.contentHash == package.contentHash {
            guard package.item.updatedAt > (existingItem.updatedAt ?? .distantPast) else {
                return (existingItem, .unchanged)
            }

            applyMetadata(from: package, to: existingItem)
            return (existingItem, .updatedMetadata)
        }

        let conflict = package.makeClipboardItem(in: context, preservesIdentifier: false)
        conflict.relatedItemIdentifier = existingItem.id?.uuidString
        if conflict.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            conflict.customTitle = "\(conflict.displayTitle) (Conflict)"
        } else if let customTitle = conflict.customTitle,
                  !customTitle.localizedCaseInsensitiveContains("conflict") {
            conflict.customTitle = "\(customTitle) (Conflict)"
        }
        return (conflict, .preservedConflict)
    }

    @MainActor
    static func resolveDeleteMarker(
        _ marker: ClipboardSyncDeleteMarker,
        existingItem: ClipboardItem?
    ) -> ClipboardSyncDeleteResolution {
        guard let existingItem else {
            return .missingLocal
        }

        let localUpdatedAt = existingItem.updatedAt ?? existingItem.createdAt ?? .distantPast
        if localUpdatedAt > marker.updatedAt {
            return .keepNewerLocal
        }

        return .deleteLocal
    }

    @MainActor
    private static func applyMetadata(
        from package: ClipboardSyncPackage,
        to item: ClipboardItem
    ) {
        item.customTitle = package.item.customTitle
        item.notes = package.item.notes
        item.tagsText = package.item.tagsText
        item.collectionName = package.item.collectionName
        item.isPinned = package.item.isPinned
        item.isFavorite = package.item.isFavorite
        item.isArchived = package.item.isArchived
        item.isSensitive = package.item.isSensitive
        item.recognizedText = package.item.recognizedText
        item.relatedItemIdentifier = package.item.relatedItemIdentifier
        item.updatedAt = package.item.updatedAt
    }
}

struct ClipboardSyncPackageItem: Codable, Equatable, Sendable {
    var id: UUID
    var type: String
    var plainText: String?
    var previewText: String?
    var customTitle: String?
    var notes: String?
    var tagsText: String?
    var collectionName: String?
    var utiType: String?
    var rawData: Data?
    var imageData: Data?
    var thumbnailData: Data?
    var sourceApp: String?
    var sourceBundleIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var byteCount: Int64
    var contentHash: String
    var isPinned: Bool
    var isFavorite: Bool
    var isArchived: Bool
    var isSensitive: Bool
    var isLocalOnly: Bool
    var recognizedText: String?
    var relatedItemIdentifier: String?

    @MainActor
    init(item: ClipboardItem) {
        self.id = item.id ?? UUID()
        self.type = item.type ?? ClipboardItemType.unknown
        self.plainText = item.plainText
        self.previewText = item.previewText
        self.customTitle = item.customTitle
        self.notes = item.notes
        self.tagsText = item.tagsText
        self.collectionName = item.collectionName
        self.utiType = item.utiType
        self.rawData = item.rawData
        self.imageData = item.imageData
        self.thumbnailData = item.thumbnailData
        self.sourceApp = item.sourceApp
        self.sourceBundleIdentifier = item.sourceBundleIdentifier
        self.createdAt = item.createdAt ?? Date()
        self.updatedAt = item.updatedAt ?? item.createdAt ?? Date()
        self.byteCount = item.byteCount
        self.contentHash = item.contentHash ?? ""
        self.isPinned = item.isPinned
        self.isFavorite = item.isFavorite
        self.isArchived = item.isArchived
        self.isSensitive = item.isSensitive
        self.isLocalOnly = item.isLocalOnly
        self.recognizedText = item.recognizedText
        self.relatedItemIdentifier = item.relatedItemIdentifier
    }
}

struct ClipboardSyncPackageRepresentation: Codable, Equatable, Sendable {
    var itemIndex: Int
    var order: Int
    var utiIdentifier: String
    var data: Data?
    var stringValue: String?
    var byteCount: Int64

    @MainActor
    init(representation: ClipboardRepresentation) {
        self.itemIndex = Int(representation.itemIndex)
        self.order = Int(representation.order)
        self.utiIdentifier = representation.utiIdentifier ?? ClipboardItemType.unknown
        self.data = representation.data
        self.stringValue = representation.stringValue
        self.byteCount = representation.byteCount
    }

    @discardableResult
    func makeClipboardRepresentation(
        for item: ClipboardItem,
        in context: NSManagedObjectContext
    ) -> ClipboardRepresentation {
        let representation = ClipboardRepresentation(context: context)
        representation.item = item
        representation.itemIndex = Int16(itemIndex)
        representation.order = Int16(order)
        representation.utiIdentifier = utiIdentifier
        representation.data = data
        representation.stringValue = stringValue
        representation.byteCount = byteCount
        return representation
    }
}

enum ClipboardPrivacyPolicy {
    static func excludes(bundleIdentifier: String?, excludedBundleIdentifiers: Set<String>) -> Bool {
        guard let bundleIdentifier else {
            return false
        }

        return excludedBundleIdentifiers.contains(bundleIdentifier.lowercased())
    }

    static func isSensitive(_ text: String?) -> Bool {
        guard let text else {
            return false
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        if trimmed.range(
            of: #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if trimmed.range(
            of: #"\b(?:sk|pk)_(?:live|test)_[A-Za-z0-9]{16,}\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }

        if trimmed.range(
            of: #"\b(?:api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*\S{8,}"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }

        let digits = trimmed.filter(\.isNumber)
        if (13...19).contains(digits.count), passesLuhnCheck(digits) {
            return true
        }

        return trimmed.count <= 8
            && trimmed.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil
    }

    private static func passesLuhnCheck(_ digits: String) -> Bool {
        let values = digits.reversed().compactMap(\.wholeNumberValue)
        guard values.count == digits.count else {
            return false
        }

        let sum = values.enumerated().reduce(0) { partialResult, entry in
            let (index, value) = entry
            if index.isMultiple(of: 2) {
                return partialResult + value
            }

            let doubled = value * 2
            return partialResult + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum.isMultiple(of: 10)
    }
}

struct ClipboardRetentionItem: Sendable {
    let id: UUID
    let type: String
    let createdAt: Date
    let byteCount: Int64
    let isPinned: Bool
    let isFavorite: Bool
    let isSensitive: Bool
    let sourceBundleIdentifier: String?

    init(
        id: UUID,
        type: String = ClipboardItemType.unknown,
        createdAt: Date,
        byteCount: Int64,
        isPinned: Bool,
        isFavorite: Bool,
        isSensitive: Bool = false,
        sourceBundleIdentifier: String? = nil
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.byteCount = byteCount
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.isSensitive = isSensitive
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }
}

enum ClipboardRetentionPolicy {
    static func identifiersToDelete(
        from items: [ClipboardRetentionItem],
        settings: ClipboardSettings,
        now: Date = Date()
    ) -> Set<UUID> {
        let sortedItems = items.sorted { $0.createdAt > $1.createdAt }
        var identifiers = Set<UUID>()

        func isProtected(_ item: ClipboardRetentionItem) -> Bool {
            item.isPinned || (settings.keepFavorites && item.isFavorite)
        }

        if settings.sensitiveRetentionMinutes > 0 {
            let cutoff = now.addingTimeInterval(
                -TimeInterval(settings.sensitiveRetentionMinutes * 60)
            )
            for item in sortedItems where item.isSensitive && item.createdAt < cutoff {
                identifiers.insert(item.id)
            }
        }

        for item in sortedItems where !identifiers.contains(item.id) && !isProtected(item) {
            let retentionDays = settings.retentionDays(
                for: item.type,
                sourceBundleIdentifier: item.sourceBundleIdentifier
            )
            guard retentionDays > 0,
                  let cutoff = Calendar.current.date(
                    byAdding: .day,
                    value: -retentionDays,
                    to: now
                  ),
                  item.createdAt < cutoff else {
                continue
            }
            identifiers.insert(item.id)
        }

        var retainedCount = 0
        for item in sortedItems where !identifiers.contains(item.id) {
            if isProtected(item) {
                continue
            }

            retainedCount += 1
            if retainedCount > settings.maximumItemCount {
                identifiers.insert(item.id)
            }
        }

        let byteLimit = Int64(settings.maximumStorageMegabytes) * 1_024 * 1_024
        var retainedBytes: Int64 = 0
        for item in sortedItems where !identifiers.contains(item.id) {
            if isProtected(item) {
                retainedBytes += item.byteCount
                continue
            }

            if retainedBytes + item.byteCount > byteLimit {
                identifiers.insert(item.id)
            } else {
                retainedBytes += item.byteCount
            }
        }

        return identifiers
    }
}

struct ClipboardStorageSummary: Equatable {
    struct Category: Identifiable, Equatable {
        let type: String
        let itemCount: Int
        let byteCount: Int64

        var id: String {
            type
        }
    }

    let itemCount: Int
    let sensitiveItemCount: Int
    let byteCount: Int64
    let categories: [Category]

    static func make(from items: [ClipboardStorageItem]) -> ClipboardStorageSummary {
        let grouped = Dictionary(grouping: items, by: \.type)
        let categories = grouped.map { type, values in
            Category(
                type: type,
                itemCount: values.count,
                byteCount: values.reduce(0) { $0 + $1.byteCount }
            )
        }
        .sorted {
            if $0.byteCount != $1.byteCount {
                return $0.byteCount > $1.byteCount
            }
            return $0.type < $1.type
        }

        return ClipboardStorageSummary(
            itemCount: items.count,
            sensitiveItemCount: items.filter(\.isSensitive).count,
            byteCount: items.reduce(0) { $0 + $1.byteCount },
            categories: categories
        )
    }
}

struct ClipboardStorageItem: Sendable {
    let type: String
    let byteCount: Int64
    let isSensitive: Bool
}
