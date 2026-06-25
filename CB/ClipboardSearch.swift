import Foundation

struct ClipboardSearchQuery {
    let terms: [String]
    let source: String?
    let type: String?
    let tag: String?
    let collection: String?
    let isFavorite: Bool?
    let isPinned: Bool?
    let isArchived: Bool?
    let afterDate: Date?
    let beforeDate: Date?

    init(_ input: String) {
        var terms: [String] = []
        var source: String?
        var type: String?
        var tag: String?
        var collection: String?
        var isFavorite: Bool?
        var isPinned: Bool?
        var isArchived: Bool?
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
                type = value
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
        self.type = type
        self.tag = tag
        self.collection = collection
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.afterDate = afterDate
        self.beforeDate = beforeDate
    }

    func matches(_ item: ClipboardItem) -> Bool {
        if let source,
           !(item.sourceApp ?? "").localizedCaseInsensitiveContains(source) {
            return false
        }
        if let type,
           ![item.type, item.displayType, item.utiType]
            .compactMap({ $0 })
            .contains(where: { $0.localizedCaseInsensitiveContains(type) }) {
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
}
