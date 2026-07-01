import Foundation

struct ClipboardSearchQuery {
    let terms: [String]
    let source: String?
    let types: [String]
    let tag: String?
    let collection: String?
    let isFavorite: Bool?
    let isPinned: Bool?
    let isArchived: Bool?
    let isLocalOnly: Bool?
    let isUnsynced: Bool?
    let minimumByteCount: Int64?
    let afterDate: Date?
    let beforeDate: Date?

    init(_ input: String) {
        var terms: [String] = []
        var source: String?
        var types: [String] = []
        var tag: String?
        var collection: String?
        var isFavorite: Bool?
        var isPinned: Bool?
        var isArchived: Bool?
        var isLocalOnly: Bool?
        var isUnsynced: Bool?
        var minimumByteCount: Int64?
        var afterDate: Date?
        var beforeDate: Date?

        for token in input.split(whereSeparator: \.isWhitespace).map(String.init) {
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                terms.append(token)
                continue
            }

            let key = parts[0].lowercased()
            let value = parts[1].lowercased()
            switch key {
            case "app", "source":
                source = value
            case "type":
                types = value
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            case "tag":
                tag = value
            case "collection", "in":
                collection = value
            case "favorite":
                isFavorite = Self.parseBoolean(value)
            case "pinned":
                isPinned = Self.parseBoolean(value)
            case "archived":
                isArchived = Self.parseBoolean(value)
            case "local":
                isLocalOnly = Self.parseBoolean(value)
            case "sync":
                switch value {
                case "unsynced":
                    isUnsynced = true
                case "synced":
                    isUnsynced = false
                default:
                    terms.append(token)
                }
            case "size":
                if value == "large" {
                    minimumByteCount = 10 * 1_024 * 1_024
                } else if let byteCount = Self.parseByteCount(value) {
                    minimumByteCount = byteCount
                }
            case "after":
                afterDate = Self.parseDate(value)
            case "before":
                beforeDate = Self.parseDate(value)
            default:
                terms.append(token)
            }
        }

        self.terms = terms
        self.source = source
        self.types = types
        self.tag = tag
        self.collection = collection
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.isLocalOnly = isLocalOnly
        self.isUnsynced = isUnsynced
        self.minimumByteCount = minimumByteCount
        self.afterDate = afterDate
        self.beforeDate = beforeDate
    }

    func matches(_ item: ClipboardItem) -> Bool {
        if let source,
           !(item.sourceApp ?? "").localizedCaseInsensitiveContains(source) {
            return false
        }
        if !types.isEmpty,
           !types.contains(where: { type in
               [item.type, item.displayType, item.utiType]
                   .compactMap { $0 }
                   .contains { $0.localizedCaseInsensitiveContains(type) }
           }) {
            return false
        }
        if let tag,
           !item.tags.contains(where: { $0.localizedCaseInsensitiveContains(tag) }) {
            return false
        }
        if let collection,
           !(item.collectionName ?? "").localizedCaseInsensitiveContains(collection) {
            return false
        }
        if let isFavorite, item.isFavorite != isFavorite {
            return false
        }
        if let isPinned, item.isPinned != isPinned {
            return false
        }
        if let isArchived, item.isArchived != isArchived {
            return false
        }
        if let isLocalOnly, item.isLocalOnly != isLocalOnly {
            return false
        }
        if let isUnsynced {
            let itemIsUnsynced = item.isLocalOnly || item.isSensitive
            if itemIsUnsynced != isUnsynced {
                return false
            }
        }
        if let minimumByteCount, item.byteCount < minimumByteCount {
            return false
        }
        if let afterDate, (item.createdAt ?? .distantPast) < afterDate {
            return false
        }
        if let beforeDate, (item.createdAt ?? .distantFuture) >= beforeDate {
            return false
        }

        let searchableValues = [
            item.customTitle,
            item.notes,
            item.tagsText,
            item.collectionName,
            item.plainText,
            item.previewText,
            item.utiType,
            item.sourceApp,
            item.displayType
        ]
        .compactMap { $0 }

        return terms.allSatisfy { term in
            searchableValues.contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }

    private static func parseBoolean(_ value: String) -> Bool? {
        switch value {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let calendar = Calendar.current
        switch value {
        case "today":
            return calendar.startOfDay(for: Date())
        case "week":
            return calendar.date(byAdding: .day, value: -7, to: Date())
        case "month":
            return calendar.date(byAdding: .month, value: -1, to: Date())
        default:
            return try? Date(value, strategy: .iso8601.year().month().day())
        }
    }

    private static func parseByteCount(_ value: String) -> Int64? {
        let pattern = /^([0-9]+)(kb|mb|gb|b)?$/
        guard let match = value.firstMatch(of: pattern),
              let quantity = Int64(match.output.1) else {
            return nil
        }

        switch match.output.2 {
        case "kb":
            return quantity * 1_024
        case "mb":
            return quantity * 1_024 * 1_024
        case "gb":
            return quantity * 1_024 * 1_024 * 1_024
        default:
            return quantity
        }
    }
}

struct ClipboardSavedFilter: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var query: String
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, query: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.query = query
        self.isBuiltIn = isBuiltIn
    }

    var normalized: ClipboardSavedFilter {
        ClipboardSavedFilter(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            isBuiltIn: isBuiltIn
        )
    }

    static let builtIns = [
        ClipboardSavedFilter(name: "Images Today", query: "type:image after:today", isBuiltIn: true),
        ClipboardSavedFilter(name: "From Mail", query: "app:Mail", isBuiltIn: true),
        ClipboardSavedFilter(name: "Screenshots", query: "type:image app:Screen Capture", isBuiltIn: true),
        ClipboardSavedFilter(name: "Favorites", query: "favorite:true", isBuiltIn: true),
        ClipboardSavedFilter(name: "Unsynced", query: "sync:unsynced", isBuiltIn: true),
        ClipboardSavedFilter(name: "Large Items", query: "size:large", isBuiltIn: true),
        ClipboardSavedFilter(name: "Unknown/Data", query: "type:unknown,data", isBuiltIn: true)
    ]
}
