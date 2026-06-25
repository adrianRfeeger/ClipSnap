import CoreData
@preconcurrency import CoreSpotlight
import OSLog
import UniformTypeIdentifiers

enum SpotlightSettingKey {
    static let indexesClipboardHistory = "indexesClipboardHistoryInSpotlight"
}

@MainActor
final class ClipboardSpotlightIndexer {
    static let shared = ClipboardSpotlightIndexer()

    private let index = CSSearchableIndex.default()
    private let domainIdentifier = "clipboard-bro.history"
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CB",
        category: "Spotlight"
    )

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SpotlightSettingKey.indexesClipboardHistory)
    }

    func indexItem(_ item: ClipboardItem) {
        guard isEnabled, let searchableItem = searchableItem(for: item) else {
            if let identifier = item.id?.uuidString {
                deleteIdentifiers([identifier])
            }
            return
        }

        index.indexSearchableItems([searchableItem]) { [logger] error in
            if let error {
                logger.error("Failed to index clipboard item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func rebuild(context: NSManagedObjectContext) {
        guard isEnabled else {
            deleteAll()
            return
        }

        let request = ClipboardItem.fetchRequest()
        do {
            let searchableItems = try context.fetch(request).compactMap(searchableItem(for:))
            let index = index
            index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { [weak self] error in
                guard error == nil, let self else {
                    return
                }
                index.indexSearchableItems(searchableItems) { [logger] error in
                    if let error {
                        logger.error("Failed to rebuild Spotlight index: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        } catch {
            logger.error("Failed to fetch items for Spotlight: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteIdentifiers(_ identifiers: [String]) {
        guard !identifiers.isEmpty else {
            return
        }
        index.deleteSearchableItems(withIdentifiers: identifiers, completionHandler: nil)
    }

    func deleteAll() {
        index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier], completionHandler: nil)
    }

    private func searchableItem(for item: ClipboardItem) -> CSSearchableItem? {
        guard !item.isArchived,
              !item.isSensitive,
              !item.isLocalOnly,
              let identifier = item.id?.uuidString,
              !ClipboardPrivacyPolicy.isSensitive(item.plainText) else {
            return nil
        }

        let contentType = item.utiType.flatMap(UTType.init) ?? .data
        let attributes = CSSearchableItemAttributeSet(contentType: contentType)
        attributes.title = item.displayTitle
        attributes.displayName = item.displayTitle
        attributes.contentDescription = [item.displayType, item.sourceApp]
            .compactMap { $0 }
            .joined(separator: " • ")
        attributes.textContent = [item.plainText, item.notes]
            .compactMap { $0 }
            .joined(separator: "\n")
        attributes.keywords = item.tags + [item.normalizedCollectionName].compactMap { $0 }
        attributes.contentCreationDate = item.createdAt
        attributes.contentModificationDate = item.updatedAt
        attributes.thumbnailData = item.thumbnailData

        let searchableItem = CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
        searchableItem.expirationDate = .distantFuture
        return searchableItem
    }
}
