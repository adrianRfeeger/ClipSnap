import CoreData
import OSLog

@MainActor
struct HistoryCleanupService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CB", category: "HistoryCleanup")

    func clean(context: NSManagedObjectContext, settings: ClipboardSettings) {
        let request = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]

        do {
            let items = try context.fetch(request)
            let snapshots = items.compactMap { item -> ClipboardRetentionItem? in
                guard let id = item.id else {
                    return nil
                }

                return ClipboardRetentionItem(
                    id: id,
                    createdAt: item.createdAt ?? .distantPast,
                    byteCount: item.byteCount,
                    isPinned: item.isPinned,
                    isFavorite: item.isFavorite
                )
            }
            let identifiers = ClipboardRetentionPolicy.identifiersToDelete(from: snapshots, settings: settings)
            guard !identifiers.isEmpty else {
                return
            }

            for item in items where item.id.map(identifiers.contains) == true {
                context.delete(item)
            }
            try context.save()
            logger.info("Removed \(identifiers.count, privacy: .public) clipboard history items")
        } catch {
            context.rollback()
            logger.error("History cleanup failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
