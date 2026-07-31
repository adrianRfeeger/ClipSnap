import CoreData
import Foundation

struct ClipboardDeletionSnapshot: Sendable, Equatable {
    struct Item: Sendable, Equatable {
        let identifier: UUID
        let needsLocalFolderTombstone: Bool
    }

    let items: [Item]

    var identifiers: [UUID] {
        items.map(\.identifier)
    }

    var isEmpty: Bool {
        items.isEmpty
    }
}

struct ClipboardDeletionPlan: Sendable {
    struct Entry: Sendable {
        let objectID: NSManagedObjectID
        let snapshot: ClipboardDeletionSnapshot.Item
    }

    let entries: [Entry]

    var isEmpty: Bool {
        entries.isEmpty
    }
}

struct ClipboardDeletionResult: Sendable {
    let deletedCount: Int
    let errorDescription: String?
}

@MainActor
enum ClipboardDeletionCoordinator {
    static func plan(_ items: [ClipboardItem]) -> ClipboardDeletionPlan {
        var seenObjectIDs = Set<NSManagedObjectID>()
        let entries = items.compactMap { item -> ClipboardDeletionPlan.Entry? in
            guard let identifier = item.id,
                  !item.objectID.isTemporaryID,
                  seenObjectIDs.insert(item.objectID).inserted else {
                return nil
            }

            return ClipboardDeletionPlan.Entry(
                objectID: item.objectID,
                snapshot: ClipboardDeletionSnapshot.Item(
                    identifier: identifier,
                    needsLocalFolderTombstone: !item.isLocalOnly && !item.isSensitive
                )
            )
        }
        return ClipboardDeletionPlan(entries: entries)
    }

    static func execute(
        _ plan: ClipboardDeletionPlan,
        in viewContext: NSManagedObjectContext,
        batchSize: Int = 100
    ) async -> ClipboardDeletionResult {
        guard !plan.isEmpty else {
            return ClipboardDeletionResult(deletedCount: 0, errorDescription: nil)
        }
        guard let coordinator = viewContext.persistentStoreCoordinator else {
            return ClipboardDeletionResult(
                deletedCount: 0,
                errorDescription: "The clipboard database is unavailable."
            )
        }

        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.persistentStoreCoordinator = coordinator
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        backgroundContext.undoManager = nil
        let chunkSize = max(1, batchSize)
        let entries = plan.entries

        let outcome = await backgroundContext.perform {
            var deletedEntries: [ClipboardDeletionPlan.Entry] = []
            var startIndex = 0

            while startIndex < entries.count {
                let endIndex = min(startIndex + chunkSize, entries.count)
                let batch = Array(entries[startIndex..<endIndex])
                do {
                    for entry in batch {
                        let object = try backgroundContext.existingObject(with: entry.objectID)
                        backgroundContext.delete(object)
                    }
                    try backgroundContext.save()
                    deletedEntries.append(contentsOf: batch)
                    backgroundContext.reset()
                    startIndex = endIndex
                } catch {
                    backgroundContext.rollback()
                    return ClipboardDeletionExecutionOutcome(
                        deletedEntries: deletedEntries,
                        errorDescription: error.localizedDescription
                    )
                }
            }

            return ClipboardDeletionExecutionOutcome(
                deletedEntries: deletedEntries,
                errorDescription: nil
            )
        }

        let deletedObjectIDs = outcome.deletedEntries.map(\.objectID)
        if !deletedObjectIDs.isEmpty {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: deletedObjectIDs],
                into: [viewContext]
            )
            let deletedSnapshot = ClipboardDeletionSnapshot(
                items: outcome.deletedEntries.map(\.snapshot)
            )
            finalize(deletedSnapshot)
        }

        return ClipboardDeletionResult(
            deletedCount: outcome.deletedEntries.count,
            errorDescription: outcome.errorDescription
        )
    }

    static func snapshot(_ items: [ClipboardItem]) -> ClipboardDeletionSnapshot {
        ClipboardDeletionSnapshot(
            items: items.compactMap { item in
                guard let identifier = item.id else {
                    return nil
                }

                return ClipboardDeletionSnapshot.Item(
                    identifier: identifier,
                    needsLocalFolderTombstone: !item.isLocalOnly && !item.isSensitive
                )
            }
        )
    }

    static func finalize(
        _ snapshot: ClipboardDeletionSnapshot,
        enqueueLocalFolderTombstones: Bool = true,
        defaults: UserDefaults = .standard
    ) {
        guard !snapshot.isEmpty else {
            return
        }

        ClipboardGeneratedMetadataStore.remove(
            for: snapshot.identifiers,
            defaults: defaults
        )
        ClipboardSpotlightIndexer.shared.deleteIdentifiers(
            snapshot.identifiers.map(\.uuidString)
        )

        guard enqueueLocalFolderTombstones else {
            return
        }

        ClipboardLocalFolderDeletionQueue.enqueue(
            snapshot.items
                .filter(\.needsLocalFolderTombstone)
                .map(\.identifier),
            defaults: defaults
        )
    }
}

private struct ClipboardDeletionExecutionOutcome: Sendable {
    let deletedEntries: [ClipboardDeletionPlan.Entry]
    let errorDescription: String?
}

struct ClipboardLocalFolderDeletionRecord: Codable, Sendable, Equatable {
    let itemIdentifier: UUID
    let updatedAt: Date
}

@MainActor
enum ClipboardLocalFolderDeletionQueue {
    static func enqueue(
        _ identifiers: [UUID],
        updatedAt: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        guard !identifiers.isEmpty,
              localFolderWasConfigured(defaults: defaults) else {
            return
        }

        var recordsByIdentifier = Dictionary(
            uniqueKeysWithValues: records(defaults: defaults).map {
                ($0.itemIdentifier, $0)
            }
        )
        for identifier in identifiers {
            let existingDate = recordsByIdentifier[identifier]?.updatedAt ?? .distantPast
            recordsByIdentifier[identifier] = ClipboardLocalFolderDeletionRecord(
                itemIdentifier: identifier,
                updatedAt: max(existingDate, updatedAt)
            )
        }
        save(
            Array(recordsByIdentifier.values),
            defaults: defaults
        )
    }

    static func records(defaults: UserDefaults = .standard) -> [ClipboardLocalFolderDeletionRecord] {
        guard let data = defaults.data(
            forKey: ClipboardSettingKey.pendingLocalFolderSyncDeletes
        ) else {
            return []
        }

        return (try? JSONDecoder().decode(
            [ClipboardLocalFolderDeletionRecord].self,
            from: data
        )) ?? []
    }

    static func flush(
        using provider: ClipboardLocalFolderSyncProvider,
        defaults: UserDefaults = .standard
    ) async throws {
        let pendingRecords = records(defaults: defaults)
            .sorted { $0.updatedAt < $1.updatedAt }
        guard !pendingRecords.isEmpty else {
            return
        }

        var completedIdentifiers = Set<UUID>()
        do {
            for record in pendingRecords {
                try await provider.deletePackage(
                    itemIdentifier: record.itemIdentifier,
                    updatedAt: record.updatedAt
                )
                completedIdentifiers.insert(record.itemIdentifier)
            }
        } catch {
            removeCompleted(
                completedIdentifiers,
                defaults: defaults
            )
            throw error
        }

        removeCompleted(
            completedIdentifiers,
            defaults: defaults
        )
    }

    private static func localFolderWasConfigured(defaults: UserDefaults) -> Bool {
        let path = defaults.string(
            forKey: ClipboardSettingKey.localFolderSyncPath
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !path.isEmpty
    }

    private static func removeCompleted(
        _ identifiers: Set<UUID>,
        defaults: UserDefaults
    ) {
        guard !identifiers.isEmpty else {
            return
        }

        save(
            records(defaults: defaults).filter {
                !identifiers.contains($0.itemIdentifier)
            },
            defaults: defaults
        )
    }

    private static func save(
        _ records: [ClipboardLocalFolderDeletionRecord],
        defaults: UserDefaults
    ) {
        guard !records.isEmpty else {
            defaults.removeObject(
                forKey: ClipboardSettingKey.pendingLocalFolderSyncDeletes
            )
            return
        }

        let sortedRecords = records.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt < $1.updatedAt
            }
            return $0.itemIdentifier.uuidString < $1.itemIdentifier.uuidString
        }
        guard let data = try? JSONEncoder().encode(sortedRecords) else {
            return
        }
        defaults.set(
            data,
            forKey: ClipboardSettingKey.pendingLocalFolderSyncDeletes
        )
    }
}
