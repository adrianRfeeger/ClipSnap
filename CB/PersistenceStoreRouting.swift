import CoreData

enum PersistenceStoreRouting {
    static let localStoreFilename = "CB-local.sqlite"

    static func localStore(in coordinator: NSPersistentStoreCoordinator?) -> NSPersistentStore? {
        coordinator?.persistentStores.first {
            $0.url?.lastPathComponent == localStoreFilename
        }
    }

    static func cloudStore(in coordinator: NSPersistentStoreCoordinator?) -> NSPersistentStore? {
        coordinator?.persistentStores.first {
            $0.url?.lastPathComponent != localStoreFilename
        }
    }

    @MainActor
    static func assign(_ item: ClipboardItem, localOnly: Bool, in context: NSManagedObjectContext) {
        let coordinator = context.persistentStoreCoordinator
        let store = localOnly ? localStore(in: coordinator) : cloudStore(in: coordinator)
        guard let store else {
            return
        }
        context.assign(item, to: store)
        item.sortedRepresentations.forEach { context.assign($0, to: store) }
        item.isLocalOnly = localOnly
    }

    @MainActor
    static func copy(
        _ source: ClipboardItem,
        localOnly: Bool,
        in context: NSManagedObjectContext
    ) -> ClipboardItem? {
        let coordinator = context.persistentStoreCoordinator
        let store = localOnly ? localStore(in: coordinator) : cloudStore(in: coordinator)
        guard let store else {
            return nil
        }

        let copy = ClipboardItem(context: context)
        context.assign(copy, to: store)
        copy.id = source.id
        copy.createdAt = source.createdAt
        copy.updatedAt = Date()
        copy.type = source.type
        copy.plainText = source.plainText
        copy.previewText = source.previewText
        copy.imageData = source.imageData
        copy.thumbnailData = source.thumbnailData
        copy.rawData = source.rawData
        copy.utiType = source.utiType
        copy.sourceApp = source.sourceApp
        copy.sourceBundleIdentifier = source.sourceBundleIdentifier
        copy.customTitle = source.customTitle
        copy.notes = source.notes
        copy.tagsText = source.tagsText
        copy.collectionName = source.collectionName
        copy.recognizedText = source.recognizedText
        copy.relatedItemIdentifier = source.relatedItemIdentifier
        copy.byteCount = source.byteCount
        copy.contentHash = source.contentHash
        copy.isArchived = source.isArchived
        copy.isFavorite = source.isFavorite
        copy.isPinned = source.isPinned
        copy.isSensitive = source.isSensitive
        copy.isLocalOnly = localOnly

        for sourceRepresentation in source.sortedRepresentations {
            let representation = ClipboardRepresentation(context: context)
            context.assign(representation, to: store)
            representation.id = sourceRepresentation.id
            representation.itemIndex = sourceRepresentation.itemIndex
            representation.order = sourceRepresentation.order
            representation.utiIdentifier = sourceRepresentation.utiIdentifier
            representation.data = sourceRepresentation.data
            representation.stringValue = sourceRepresentation.stringValue
            representation.byteCount = sourceRepresentation.byteCount
            representation.item = copy
        }
        return copy
    }
}
