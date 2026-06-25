import CryptoKit
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

    init(
        id: UUID,
        type: String = ClipboardItemType.unknown,
        createdAt: Date,
        byteCount: Int64,
        isPinned: Bool,
        isFavorite: Bool,
        isSensitive: Bool = false
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.byteCount = byteCount
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.isSensitive = isSensitive
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
            let retentionDays = settings.retentionDays(for: item.type)
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
