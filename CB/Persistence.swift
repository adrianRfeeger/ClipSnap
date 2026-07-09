//
//  Persistence.swift
//  CB
//
//  Created by Adrian Feeger on 23/6/2026.
//

import CoreData
import OSLog

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        ClipboardItem.make(
            in: viewContext,
            type: ClipboardItemType.text,
            plainText: "A copied note appears here.",
            previewText: "A copied note appears here.",
            utiType: "public.utf8-plain-text"
        )
        ClipboardItem.make(
            in: viewContext,
            type: ClipboardItemType.url,
            plainText: "https://developer.apple.com",
            previewText: "https://developer.apple.com",
            utiType: "public.url"
        )
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "CB")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else if let cloudDescription = container.persistentStoreDescriptions.first,
                  let cloudURL = cloudDescription.url {
            let localURL = cloudURL
                .deletingLastPathComponent()
                .appendingPathComponent(PersistenceStoreRouting.localStoreFilename)
            let localDescription = NSPersistentStoreDescription(url: localURL)
            localDescription.setOption(
                true as NSNumber,
                forKey: NSPersistentHistoryTrackingKey
            )
            localDescription.setOption(
                true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
            )
            localDescription.setOption(
                true as NSNumber,
                forKey: NSMigratePersistentStoresAutomaticallyOption
            )
            localDescription.setOption(
                true as NSNumber,
                forKey: NSInferMappingModelAutomaticallyOption
            )
            container.persistentStoreDescriptions.append(localDescription)
        }

        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        let loadState = PersistentStoreLoadState(
            expectedCompletionCount: container.persistentStoreDescriptions.count
        )
        let persistentContainer = container
        persistentContainer.loadPersistentStores { _, error in
            if let error {
                Self.logger.fault(
                    "Persistent store failed to load: \(error.localizedDescription, privacy: .public)"
                )
            }

            guard loadState.recordCompletion(),
                  persistentContainer.persistentStoreCoordinator.persistentStores.isEmpty else {
                return
            }

            do {
                _ = try persistentContainer.persistentStoreCoordinator.addPersistentStore(
                    type: .inMemory,
                    configuration: nil,
                    at: URL(fileURLWithPath: "/dev/null")
                )
                Self.logger.fault(
                    "ClipSnap is using temporary in-memory storage because no persistent store could be loaded"
                )
            } catch {
                Self.logger.fault(
                    "Temporary persistence recovery failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CB",
        category: "Persistence"
    )
}

private final class PersistentStoreLoadState: @unchecked Sendable {
    private let lock = NSLock()
    private let expectedCompletionCount: Int
    private var completionCount = 0

    init(expectedCompletionCount: Int) {
        self.expectedCompletionCount = expectedCompletionCount
    }

    func recordCompletion() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        completionCount += 1
        return completionCount == expectedCompletionCount
    }
}
