//
//  CBTests.swift
//  CBTests
//
//  Created by Adrian Feeger on 23/6/2026.
//

import Foundation
import AppKit
import CoreGraphics
import CoreData
import ImageIO
import Testing
@testable import ClipSnap

struct CBTests {
    @Test func contentHashIsStableAndContentSensitive() {
        let first = ClipboardPayload(
            type: ClipboardItemType.text,
            plainText: "Example",
            utiType: "public.utf8-plain-text",
            rawData: nil,
            imageData: nil
        )
        let same = ClipboardPayload(
            type: ClipboardItemType.text,
            plainText: "Example",
            utiType: "public.utf8-plain-text",
            rawData: nil,
            imageData: nil
        )
        let different = ClipboardPayload(
            type: ClipboardItemType.text,
            plainText: "Different",
            utiType: "public.utf8-plain-text",
            rawData: nil,
            imageData: nil
        )

        #expect(ClipboardContentHasher.hash(first) == ClipboardContentHasher.hash(same))
        #expect(ClipboardContentHasher.hash(first) != ClipboardContentHasher.hash(different))
    }

    @Test func excludedBundleIdentifiersAreNormalized() {
        let identifiers = ClipboardSettings.parseBundleIdentifiers(
            "com.example.Passwords,\n COM.EXAMPLE.SECRETS "
        )

        #expect(identifiers.contains("com.example.passwords"))
        #expect(
            ClipboardPrivacyPolicy.excludes(
                bundleIdentifier: "com.example.Secrets",
                excludedBundleIdentifiers: identifiers
            )
        )
        #expect(
            ClipboardSettings.formattedBundleIdentifiers(identifiers)
                == "com.example.passwords\ncom.example.secrets"
        )
    }

    @Test func representationOrderAffectsContentIdentity() {
        let first = ClipboardRepresentationPayload(
            itemIndex: 0,
            order: 0,
            utiIdentifier: "public.utf8-plain-text",
            data: Data("First".utf8),
            stringValue: nil
        )
        let second = ClipboardRepresentationPayload(
            itemIndex: 1,
            order: 0,
            utiIdentifier: "public.utf8-plain-text",
            data: Data("Second".utf8),
            stringValue: nil
        )
        let forward = ClipboardPayload(
            type: ClipboardItemType.text,
            plainText: "First",
            utiType: "public.utf8-plain-text",
            rawData: nil,
            imageData: nil,
            representations: [first, second]
        )
        let reversed = ClipboardPayload(
            type: ClipboardItemType.text,
            plainText: "First",
            utiType: "public.utf8-plain-text",
            rawData: nil,
            imageData: nil,
            representations: [
                ClipboardRepresentationPayload(
                    itemIndex: 0,
                    order: 0,
                    utiIdentifier: second.utiIdentifier,
                    data: second.data,
                    stringValue: nil
                ),
                ClipboardRepresentationPayload(
                    itemIndex: 1,
                    order: 0,
                    utiIdentifier: first.utiIdentifier,
                    data: first.data,
                    stringValue: nil
                )
            ]
        )

        #expect(ClipboardContentHasher.hash(forward) != ClipboardContentHasher.hash(reversed))
        #expect(forward.byteCount == 11)
    }

    @MainActor
    @Test func syncPackageRoundTripsClipboardItemMetadataAndRepresentations() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let item = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "Package text",
            previewText: "Package text",
            rawData: Data("Package text".utf8),
            utiType: "public.utf8-plain-text",
            sourceApp: "Tests",
            sourceBundleIdentifier: "com.example.tests"
        )
        item.customTitle = "Packaged Item"
        item.notes = "Package notes"
        item.tagsText = "sync, package"
        item.collectionName = "Testing"
        item.isFavorite = true
        item.isPinned = true

        let representation = ClipboardRepresentation(context: context)
        representation.item = item
        representation.itemIndex = 0
        representation.order = 0
        representation.utiIdentifier = "public.utf8-plain-text"
        representation.data = Data("Representation data".utf8)
        representation.stringValue = "Representation string"
        representation.byteCount = Int64(
            (representation.data?.count ?? 0)
                + (representation.stringValue?.utf8.count ?? 0)
        )
        item.updateContentIdentity()

        let package = ClipboardSyncPackage(item: item)
        let decoded = try ClipboardSyncPackage.decode(from: package.encodedData())

        #expect(decoded.schemaVersion == ClipboardSyncPackage.currentSchemaVersion)
        #expect(decoded.item.id == item.id)
        #expect(decoded.item.customTitle == "Packaged Item")
        #expect(decoded.item.tagsText == "sync, package")
        #expect(decoded.representations.count == 1)
        #expect(decoded.representations.first?.stringValue == "Representation string")
        #expect(decoded.contentHash == item.contentHash)
    }

    @MainActor
    @Test func syncPackageCanRebuildClipboardItem() throws {
        let sourcePersistence = PersistenceController(inMemory: true)
        let sourceContext = sourcePersistence.container.viewContext
        let sourceItem = ClipboardItem.make(
            in: sourceContext,
            type: ClipboardItemType.url,
            plainText: "https://example.com/sync",
            previewText: "https://example.com/sync",
            rawData: Data("https://example.com/sync".utf8),
            utiType: "public.url",
            sourceApp: "Tests"
        )
        sourceItem.customTitle = "Sync URL"
        sourceItem.isArchived = true
        sourceItem.updateContentIdentity()

        let targetPersistence = PersistenceController(inMemory: true)
        let targetContext = targetPersistence.container.viewContext
        let rebuiltItem = ClipboardSyncPackage(item: sourceItem).makeClipboardItem(in: targetContext)

        #expect(rebuiltItem.id == sourceItem.id)
        #expect(rebuiltItem.displayTitle == "Sync URL")
        #expect(rebuiltItem.plainText == "https://example.com/sync")
        #expect(rebuiltItem.utiType == "public.url")
        #expect(rebuiltItem.isArchived)
        #expect(rebuiltItem.contentHash == sourceItem.contentHash)
    }

    @MainActor
    @Test func syncConflictResolverUpdatesMetadataWhenContentHashMatches() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let existingItem = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "Same payload",
            previewText: "Same payload",
            rawData: Data("Same payload".utf8),
            utiType: "public.utf8-plain-text",
            sourceApp: "Tests"
        )
        existingItem.customTitle = "Old Title"
        existingItem.updatedAt = Date(timeIntervalSince1970: 1)
        existingItem.updateContentIdentity()

        let remoteItem = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "Same payload",
            previewText: "Same payload",
            rawData: Data("Same payload".utf8),
            utiType: "public.utf8-plain-text",
            sourceApp: "Tests"
        )
        remoteItem.id = existingItem.id
        remoteItem.customTitle = "New Title"
        remoteItem.tagsText = "synced"
        remoteItem.updatedAt = Date(timeIntervalSince1970: 2)
        remoteItem.updateContentIdentity()

        let merge = ClipboardSyncConflictResolver.merge(
            package: ClipboardSyncPackage(item: remoteItem),
            existingItem: existingItem,
            in: context
        )

        #expect(merge.result == .updatedMetadata)
        #expect(merge.item?.id == existingItem.id)
        #expect(existingItem.customTitle == "New Title")
        #expect(existingItem.tagsText == "synced")
    }

    @MainActor
    @Test func syncConflictResolverPreservesBothCopiesWhenPayloadDiffers() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let existingItem = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "Local payload",
            previewText: "Local payload",
            rawData: Data("Local payload".utf8),
            utiType: "public.utf8-plain-text",
            sourceApp: "Tests"
        )
        existingItem.customTitle = "Shared Item"
        existingItem.updateContentIdentity()

        let remoteItem = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "Remote payload",
            previewText: "Remote payload",
            rawData: Data("Remote payload".utf8),
            utiType: "public.utf8-plain-text",
            sourceApp: "Tests"
        )
        remoteItem.id = existingItem.id
        remoteItem.customTitle = "Shared Item"
        remoteItem.updateContentIdentity()

        let merge = ClipboardSyncConflictResolver.merge(
            package: ClipboardSyncPackage(item: remoteItem),
            existingItem: existingItem,
            in: context
        )

        #expect(merge.result == .preservedConflict)
        #expect(merge.item?.id != existingItem.id)
        #expect(merge.item?.relatedItemIdentifier == existingItem.id?.uuidString)
        #expect(merge.item?.customTitle == "Shared Item (Conflict)")
        #expect(existingItem.plainText == "Local payload")
    }

    @MainActor
    @Test func localFolderSyncProviderUploadsDownloadsAndDeletesPackages() async throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipSnapLocalFolderProvider-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: folderURL)
        }

        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let item = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "Local folder sync",
            previewText: "Local folder sync",
            rawData: Data("Local folder sync".utf8),
            utiType: "public.utf8-plain-text",
            sourceApp: "Tests"
        )
        item.updateContentIdentity()

        let package = ClipboardSyncPackage(item: item)
        let provider = ClipboardLocalFolderSyncProvider(
            folderURL: folderURL,
            descriptor: ClipboardSyncProviderDescriptor(
                id: "local-test",
                kind: .localFolder,
                displayName: "Local Test",
                capabilities: .localFolder,
                isEnabled: true
            )
        )

        try await provider.upload(package)

        let downloaded = try await provider.downloadPackages(since: nil)
        #expect(downloaded.map(\.itemIdentifier) == [package.itemIdentifier])
        #expect(downloaded.first?.contentHash == package.contentHash)

        let futurePackages = try await provider.downloadPackages(since: Date().addingTimeInterval(60))
        #expect(futurePackages.isEmpty)

        try await provider.deletePackage(itemIdentifier: package.itemIdentifier, updatedAt: Date())
        let afterDelete = try await provider.downloadPackages(since: nil)
        #expect(afterDelete.isEmpty)
        let deleteMarkers = try await provider.downloadDeleteMarkers(since: nil)
        #expect(deleteMarkers.map(\.itemIdentifier) == [package.itemIdentifier])

        let markerURL = folderURL
            .appendingPathComponent("deleted", isDirectory: true)
            .appendingPathComponent(package.itemIdentifier.uuidString)
            .appendingPathExtension(ClipboardLocalFolderSyncProvider.deleteMarkerFileExtension)
        #expect(FileManager.default.fileExists(atPath: markerURL.path))
    }

    @MainActor
    @Test func syncDeleteMarkerDoesNotRemoveNewerLocalItem() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let item = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "Edited locally",
            previewText: "Edited locally",
            rawData: Data("Edited locally".utf8),
            utiType: "public.utf8-plain-text",
            sourceApp: "Tests"
        )
        let marker = ClipboardSyncDeleteMarker(
            itemIdentifier: try #require(item.id),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        item.updatedAt = Date(timeIntervalSince1970: 20)

        #expect(
            ClipboardSyncConflictResolver.resolveDeleteMarker(marker, existingItem: item)
                == .keepNewerLocal
        )
    }

    @MainActor
    @Test func syncDeleteMarkerRemovesOlderLocalItem() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let item = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "Old local",
            previewText: "Old local",
            rawData: Data("Old local".utf8),
            utiType: "public.utf8-plain-text",
            sourceApp: "Tests"
        )
        let marker = ClipboardSyncDeleteMarker(
            itemIdentifier: try #require(item.id),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        item.updatedAt = Date(timeIntervalSince1970: 10)

        #expect(
            ClipboardSyncConflictResolver.resolveDeleteMarker(marker, existingItem: item)
                == .deleteLocal
        )
    }

    @Test func syncProviderRegistryTracksEnabledProviders() {
        var registry = SyncProviderRegistry()
        #expect(registry.enabledProviders.map(\.kind) == [.iCloud])

        registry.upsert(
            ClipboardSyncProviderDescriptor(
                id: "local-folder",
                kind: .localFolder,
                displayName: "Local Folder",
                capabilities: .localFolder,
                isEnabled: true
            )
        )

        #expect(registry.enabledProviders.map(\.kind) == [.iCloud, .localFolder])
    }

    @Test func sensitiveContentDetectionCoversCommonSecrets() {
        #expect(ClipboardPrivacyPolicy.isSensitive("123456"))
        #expect(ClipboardPrivacyPolicy.isSensitive("4242 4242 4242 4242"))
        #expect(ClipboardPrivacyPolicy.isSensitive("-----BEGIN PRIVATE KEY-----"))
        #expect(ClipboardPrivacyPolicy.isSensitive("api_key=abcdefgh12345678"))
        #expect(!ClipboardPrivacyPolicy.isSensitive("A normal clipboard note"))
    }

    @MainActor
    @Test func storedSensitiveContentIsMarkedWhenSkippingIsDisabled() throws {
        let suiteName = "CBTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(false, forKey: ClipboardSettingKey.detectSensitiveContent)
        let original = UserDefaults.standard.object(forKey: ClipboardSettingKey.detectSensitiveContent)
        UserDefaults.standard.set(false, forKey: ClipboardSettingKey.detectSensitiveContent)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: ClipboardSettingKey.detectSensitiveContent)
            } else {
                UserDefaults.standard.removeObject(forKey: ClipboardSettingKey.detectSensitiveContent)
            }
            defaults.removePersistentDomain(forName: suiteName)
        }

        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let monitor = ClipboardMonitor(context: context)
        let identifier = monitor.importRecognizedText(
            "api_key=abcdefgh12345678",
            copyToPasteboard: false
        )
        let item = try #require(try context.fetch(ClipboardItem.fetchRequest()).first)

        #expect(identifier != nil)
        #expect(item.isSensitive)
    }

    @Test func retentionKeepsPinnedAndFavoriteItems() {
        let now = Date()
        let pinnedID = UUID()
        let favoriteID = UUID()
        let recentID = UUID()
        let oldestID = UUID()
        let items = [
            ClipboardRetentionItem(
                id: pinnedID,
                createdAt: now.addingTimeInterval(-100_000),
                byteCount: 10,
                isPinned: true,
                isFavorite: false
            ),
            ClipboardRetentionItem(
                id: favoriteID,
                createdAt: now.addingTimeInterval(-90_000),
                byteCount: 10,
                isPinned: false,
                isFavorite: true
            ),
            ClipboardRetentionItem(
                id: recentID,
                createdAt: now,
                byteCount: 10,
                isPinned: false,
                isFavorite: false
            ),
            ClipboardRetentionItem(
                id: oldestID,
                createdAt: now.addingTimeInterval(-1_000),
                byteCount: 10,
                isPinned: false,
                isFavorite: false
            )
        ]
        var settings = ClipboardSettings.defaults
        settings.maximumItemCount = 1
        settings.retentionDays = 0

        let identifiers = ClipboardRetentionPolicy.identifiersToDelete(
            from: items,
            settings: settings,
            now: now
        )

        #expect(!identifiers.contains(pinnedID))
        #expect(!identifiers.contains(favoriteID))
        #expect(!identifiers.contains(recentID))
        #expect(identifiers.contains(oldestID))
    }

    @Test func sensitiveExpiryOverridesPinProtection() {
        let now = Date()
        let expiredSensitiveID = UUID()
        let recentSensitiveID = UUID()
        var settings = ClipboardSettings.defaults
        settings.retentionDays = 0
        settings.maximumItemCount = 100
        settings.sensitiveRetentionMinutes = 60

        let identifiers = ClipboardRetentionPolicy.identifiersToDelete(
            from: [
                ClipboardRetentionItem(
                    id: expiredSensitiveID,
                    createdAt: now.addingTimeInterval(-3_601),
                    byteCount: 10,
                    isPinned: true,
                    isFavorite: true,
                    isSensitive: true
                ),
                ClipboardRetentionItem(
                    id: recentSensitiveID,
                    createdAt: now.addingTimeInterval(-300),
                    byteCount: 10,
                    isPinned: false,
                    isFavorite: false,
                    isSensitive: true
                )
            ],
            settings: settings,
            now: now
        )

        #expect(identifiers.contains(expiredSensitiveID))
        #expect(!identifiers.contains(recentSensitiveID))
    }

    @Test func perTypeRetentionOverridesGlobalRetention() {
        let now = Date()
        let oldTextID = UUID()
        let oldImageID = UUID()
        var settings = ClipboardSettings.defaults
        settings.retentionDays = 30
        settings.textRetentionDays = 1
        settings.imageRetentionDays = 0
        settings.sensitiveRetentionMinutes = 0

        let identifiers = ClipboardRetentionPolicy.identifiersToDelete(
            from: [
                ClipboardRetentionItem(
                    id: oldTextID,
                    type: ClipboardItemType.text,
                    createdAt: now.addingTimeInterval(-2 * 86_400),
                    byteCount: 10,
                    isPinned: false,
                    isFavorite: false
                ),
                ClipboardRetentionItem(
                    id: oldImageID,
                    type: ClipboardItemType.image,
                    createdAt: now.addingTimeInterval(-400 * 86_400),
                    byteCount: 10,
                    isPinned: false,
                    isFavorite: false
                )
            ],
            settings: settings,
            now: now
        )

        #expect(identifiers.contains(oldTextID))
        #expect(!identifiers.contains(oldImageID))
    }

    @Test func explicitAppRuleTakesPrecedenceOverLegacyExcludedApp() {
        var settings = ClipboardSettings.defaults
        settings.excludedBundleIdentifiers = ["com.example.app"]
        settings.appRules = [
            ClipboardAppRule(
                bundleIdentifier: "com.example.app",
                ignoresClipboard: false,
                keepsLocalOnly: true,
                automaticTags: "work"
            )
        ]

        let rule = settings.appRule(for: "com.example.app")

        #expect(rule?.ignoresClipboard == false)
        #expect(rule?.keepsLocalOnly == true)
        #expect(rule?.automaticTags == "work")
    }

    @Test func legacyExcludedAppBecomesIgnoreRule() {
        var settings = ClipboardSettings.defaults
        settings.excludedBundleIdentifiers = ["com.example.noisy"]
        settings.appRules = []

        let rule = settings.appRule(for: "COM.EXAMPLE.NOISY")

        #expect(rule?.ignoresClipboard == true)
        #expect(rule?.bundleIdentifier == "com.example.noisy")
    }

    @Test func appRuleRetentionOverridesPerTypeAndGlobalRetention() {
        let now = Date()
        let appExpiredID = UUID()
        let appRetainedID = UUID()
        var settings = ClipboardSettings.defaults
        settings.retentionDays = 30
        settings.textRetentionDays = 30
        settings.sensitiveRetentionMinutes = 0
        settings.appRules = [
            ClipboardAppRule(bundleIdentifier: "com.example.short", retentionDays: 1),
            ClipboardAppRule(bundleIdentifier: "com.example.never", retentionDays: 0)
        ]

        let identifiers = ClipboardRetentionPolicy.identifiersToDelete(
            from: [
                ClipboardRetentionItem(
                    id: appExpiredID,
                    type: ClipboardItemType.text,
                    createdAt: now.addingTimeInterval(-2 * 86_400),
                    byteCount: 10,
                    isPinned: false,
                    isFavorite: false,
                    sourceBundleIdentifier: "com.example.short"
                ),
                ClipboardRetentionItem(
                    id: appRetainedID,
                    type: ClipboardItemType.text,
                    createdAt: now.addingTimeInterval(-60 * 86_400),
                    byteCount: 10,
                    isPinned: false,
                    isFavorite: false,
                    sourceBundleIdentifier: "com.example.never"
                )
            ],
            settings: settings,
            now: now
        )

        #expect(identifiers.contains(appExpiredID))
        #expect(!identifiers.contains(appRetainedID))
    }

    @Test func storageSummaryGroupsLargestCategoriesFirst() {
        let summary = ClipboardStorageSummary.make(
            from: [
                ClipboardStorageItem(type: ClipboardItemType.text, byteCount: 10, isSensitive: true),
                ClipboardStorageItem(type: ClipboardItemType.image, byteCount: 100, isSensitive: false),
                ClipboardStorageItem(type: ClipboardItemType.text, byteCount: 20, isSensitive: false)
            ]
        )

        #expect(summary.itemCount == 3)
        #expect(summary.sensitiveItemCount == 1)
        #expect(summary.byteCount == 130)
        #expect(summary.categories.map(\.type) == [ClipboardItemType.image, ClipboardItemType.text])
    }

    @MainActor
    @Test func binaryPayloadsUseCoreDataExternalStorage() throws {
        let persistence = PersistenceController(inMemory: true)
        let model = persistence.container.managedObjectModel
        let item = try #require(model.entitiesByName["ClipboardItem"])
        let representation = try #require(model.entitiesByName["ClipboardRepresentation"])

        #expect(item.attributesByName["rawData"]?.allowsExternalBinaryDataStorage == true)
        #expect(item.attributesByName["imageData"]?.allowsExternalBinaryDataStorage == true)
        #expect(item.attributesByName["thumbnailData"]?.allowsExternalBinaryDataStorage == true)
        #expect(representation.attributesByName["data"]?.allowsExternalBinaryDataStorage == true)
    }

    @MainActor
    @Test func localOnlyCopyPreservesClipboardMetadata() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let source = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "Local content",
            previewText: "Local content",
            rawData: Data("Local content".utf8),
            utiType: "public.utf8-plain-text"
        )
        source.tagsText = "private"
        source.isSensitive = true

        // In-memory tests use one store, so copying to the cloud route validates
        // graph preservation independently of the on-disk two-store topology.
        let copy = try #require(
            PersistenceStoreRouting.copy(source, localOnly: false, in: context)
        )

        #expect(copy.id == source.id)
        #expect(copy.plainText == source.plainText)
        #expect(copy.tagsText == "private")
        #expect(copy.isSensitive)
        #expect(!copy.isLocalOnly)
    }

    @MainActor
    @Test func itemSyncStateSeparatesLocalAndPendingItems() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let monitor = CloudSyncMonitor(container: persistence.container)
        let local = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "Local"
        )
        local.isLocalOnly = true
        let cloud = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "Cloud"
        )

        #expect(monitor.syncState(for: local) == .localOnly)
        #expect(monitor.syncState(for: cloud) == .pending)
    }

    @MainActor
    @Test func screenCaptureImportStoresPNGAndDeduplicates() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let monitor = ClipboardMonitor(context: context)
        let image = try #require(makeTestImage())

        let firstIdentifier = monitor.importScreenCapture(
            image,
            sourceDescription: "Region Capture",
            copyToPasteboard: false
        )
        let secondIdentifier = monitor.importScreenCapture(
            image,
            sourceDescription: "Region Capture",
            copyToPasteboard: false
        )

        let request = ClipboardItem.fetchRequest()
        let items = try context.fetch(request)
        let item = try #require(items.first)

        #expect(firstIdentifier != nil)
        #expect(firstIdentifier == secondIdentifier)
        #expect(items.count == 1)
        #expect(item.type == ClipboardItemType.image)
        #expect(item.utiType == "public.png")
        #expect(item.imageData?.isEmpty == false)
        #expect(item.thumbnailData?.isEmpty == false)
        #expect(item.sourceApp == "Screen Capture")
    }

    @MainActor
    @Test func recognizedTextImportStoresTextAndDeduplicates() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let monitor = ClipboardMonitor(context: context)

        let firstIdentifier = monitor.importRecognizedText(
            "Recognized screen text",
            copyToPasteboard: false
        )
        let secondIdentifier = monitor.importRecognizedText(
            "Recognized screen text",
            copyToPasteboard: false
        )

        let request = ClipboardItem.fetchRequest()
        let items = try context.fetch(request)
        let item = try #require(items.first)

        #expect(firstIdentifier == secondIdentifier)
        #expect(items.count == 1)
        #expect(item.type == ClipboardItemType.text)
        #expect(item.plainText == "Recognized screen text")
        #expect(item.utiType == "public.utf8-plain-text")
        #expect(item.sourceApp == "Screen OCR")
    }

    @MainActor
    @Test func recognizedTextLinksBackToSourceImage() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let monitor = ClipboardMonitor(context: context)
        let image = try #require(makeTestImage())
        let sourceIdentifier = try #require(
            monitor.importScreenCapture(
                image,
                sourceDescription: "OCR Region Capture",
                copyToPasteboard: false
            )
        )

        let textIdentifier = monitor.importRecognizedText(
            "Linked OCR text",
            sourceItemIdentifier: sourceIdentifier,
            copyToPasteboard: false
        )
        let request = ClipboardItem.fetchRequest()
        let items = try context.fetch(request)
        let source = try #require(items.first { $0.id?.uuidString == sourceIdentifier })
        let text = try #require(items.first { $0.id?.uuidString == textIdentifier })

        #expect(source.recognizedText == "Linked OCR text")
        #expect(text.relatedItemIdentifier == sourceIdentifier)
    }

    @MainActor
    @Test func clipboardSearchSupportsMetadataQualifiers() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let item = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.image,
            previewText: "Quarterly dashboard",
            utiType: "public.png",
            sourceApp: "Screen Capture"
        )
        item.customTitle = "Revenue review"
        item.notes = "Discuss at planning"
        item.tagsText = "finance, work"
        item.collectionName = "Reports"
        item.isFavorite = true
        item.createdAt = Date(timeIntervalSince1970: 1_735_689_600)

        #expect(ClipboardSearchQuery("revenue tag:finance favorite:true").matches(item))
        #expect(ClipboardSearchQuery("app:screen type:image").matches(item))
        #expect(ClipboardSearchQuery("collection:reports after:2024-01-01 before:2026-01-01").matches(item))
        #expect(!ClipboardSearchQuery("tag:personal").matches(item))
        #expect(!ClipboardSearchQuery("archived:true").matches(item))
    }

    @Test func generatedMetadataNormalizesValues() {
        let metadata = ClipboardGeneratedMetadata(
            suggestedTitle: "  Document Screenshot  ",
            suggestedTags: [" image ", "Image", "", " screenshot "],
            suggestedCollection: "  Screenshots  ",
            summary: "  Captured document window.  ",
            contentCategory: "  Reference  ",
            detectedEntities: [" ClipSnap ", "clipsnap", "  "],
            confidence: 1.5,
            modelVersion: "  apple-intelligence-foundationmodels  ",
            status: .suggested,
            failureReason: "   "
        )

        #expect(metadata.suggestedTitle == "Document Screenshot")
        #expect(metadata.suggestedTags == ["image", "screenshot"])
        #expect(metadata.suggestedCollection == "Screenshots")
        #expect(metadata.summary == "Captured document window.")
        #expect(metadata.contentCategory == "Reference")
        #expect(metadata.detectedEntities == ["ClipSnap"])
        #expect(metadata.confidence == 1)
        #expect(metadata.modelVersionDisplayName == "Apple Intelligence")
        #expect(metadata.failureReason == nil)
    }

    @MainActor
    @Test func generatedMetadataAppliesWithoutOverwritingExistingFields() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let item = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "Existing note",
            previewText: "Existing note",
            utiType: "public.utf8-plain-text",
            sourceApp: "Tests"
        )
        item.customTitle = "Existing Title"
        item.collectionName = "Existing Collection"
        item.tagsText = "reference"

        let metadata = ClipboardGeneratedMetadata(
            suggestedTitle: "Generated Title",
            suggestedTags: ["reference", "ai"],
            suggestedCollection: "Generated Collection",
            status: .suggested
        )

        #expect(item.applyGeneratedMetadata(metadata))
        #expect(item.customTitle == "Existing Title")
        #expect(item.collectionName == "Existing Collection")
        #expect(item.tags == ["reference", "ai"])

        #expect(item.applyGeneratedMetadata(metadata, fillsEmptyFieldsOnly: false))
        #expect(item.customTitle == "Generated Title")
        #expect(item.collectionName == "Generated Collection")
        #expect(item.tags == ["reference", "ai"])
    }

    @MainActor
    @Test func generatedMetadataParticipatesInSearchAndSuggestionFilters() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let item = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.image,
            previewText: "Image",
            utiType: "public.png",
            sourceApp: "ClipSnap"
        )
        let itemIdentifier = try #require(item.id)
        let metadata = ClipboardGeneratedMetadata(
            suggestedTitle: "Document Screenshot",
            suggestedTags: ["document", "screenshot"],
            suggestedCollection: "Screenshots",
            summary: "A screenshot of a document.",
            contentCategory: "Reference",
            detectedEntities: ["ClipSnap"],
            confidence: 0.8,
            modelVersion: "apple-intelligence-foundationmodels",
            status: .suggested
        )

        ClipboardGeneratedMetadataStore.save(metadata, for: itemIdentifier)
        defer {
            ClipboardGeneratedMetadataStore.remove(for: itemIdentifier)
        }

        #expect(ClipboardSearchQuery("document").matches(item))
        #expect(ClipboardSearchQuery("collection:screenshots").matches(item))
        #expect(ClipboardSearchQuery("suggestions:suggested").matches(item))
        #expect(ClipboardSearchQuery("ai:any").matches(item))
        #expect(!ClipboardSearchQuery("suggestions:accepted").matches(item))
        #expect(!ClipboardSearchQuery("ai:none").matches(item))
    }

    @Test func structuredTextFormatterPrettyPrintsJSON() {
        let formatted = ClipboardTextFormatter.formatted(
            "{\"b\":2,\"a\":1}",
            itemType: ClipboardItemType.json
        )

        #expect(formatted.contains("\n"))
        #expect(formatted.firstIndex(of: "a")! < formatted.firstIndex(of: "b")!)
    }

    @Test func htmlPreviewNormalizesEscapedAttributeFragments() {
        let source = """
        <meta charset='utf-8'><span style=&quot;color: rgb(240, 246, 252); background-color: rgb(13, 17, 23);&quot;>ClipSnap is a native macOS clipboard manager.</span>
        """
        let normalized = HTMLClipboardPreview.normalizedSource(from: source)

        #expect(normalized.contains("<span"))
        #expect(normalized.contains("style=\"color: rgb(240, 246, 252); background-color: rgb(13, 17, 23);\""))
        #expect(!normalized.contains("&quot;"))
        #expect(normalized.contains("ClipSnap is a native macOS clipboard manager."))
    }

    @Test func textTransformationsAndMergingProduceReusableText() {
        let cleanedURL = ClipboardTextTransformation.removeTrackingParameters.apply(
            to: "https://example.com/article?utm_source=newsletter&id=42&fbclid=abc"
        )
        let merged = ClipboardTextMerger.merge([" First ", "", "Second\n"])

        #expect(cleanedURL == "https://example.com/article?id=42")
        #expect(merged == "First\n\nSecond")
        #expect(
            ClipboardTextTransformation.removeBlankLines.apply(to: "one\n \n two")
                == "one\n two"
        )
    }

    @MainActor
    @Test func automationFormatsJSONAndAddsCodeTag() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let item = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: " {\"b\":2,\"a\":1} ",
            previewText: "JSON",
            rawData: Data(" {\"b\":2,\"a\":1} ".utf8),
            utiType: "public.utf8-plain-text"
        )
        var settings = ClipboardAutomationSettings.defaults
        settings.trimsWhitespace = true
        settings.formatsJSON = true

        let result = ClipboardAutomation.apply(to: item, settings: settings)

        #expect(result.contentChanged)
        #expect(item.type == ClipboardItemType.json)
        #expect(item.plainText?.contains("\n") == true)
        #expect(item.tags.contains("code"))
    }

    @MainActor
    @Test func automationCleansURLsAndTagsOCR() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let item = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.url,
            plainText: "https://example.com/?utm_source=test&id=1",
            sourceApp: "Screen OCR"
        )
        var settings = ClipboardAutomationSettings.defaults
        settings.removesURLTracking = true

        let result = ClipboardAutomation.apply(to: item, settings: settings)

        #expect(result.contentChanged)
        #expect(item.plainText == "https://example.com/?id=1")
        #expect(item.tags.contains("ocr"))
    }

    @MainActor
    @Test func aggregateExportsEncodeSelectedMetadata() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let item = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "Exported content",
            previewText: "Exported content",
            sourceApp: "Tests"
        )
        item.customTitle = "Example"
        item.tagsText = "one, two"

        let jsonData = try ClipboardExportService.aggregateData(
            for: [item],
            format: .json
        )
        let csvData = try ClipboardExportService.aggregateData(
            for: [item],
            format: .csv
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: jsonData) as? [[String: String]]
        )
        let csv = try #require(String(data: csvData, encoding: .utf8))

        #expect(json.first?["title"] == "Example")
        #expect(json.first?["content"] == "Exported content")
        #expect(csv.contains("\"Example\""))
        #expect(csv.contains("\"one, two\""))
    }

    @MainActor
    @Test func postCaptureActionsApplyMetadataWithoutRemovingAutomationTags() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let item = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.image,
            previewText: "Capture",
            sourceApp: "Screen Capture"
        )
        item.tagsText = "screenshot"
        let actions = ScreenCapturePostActions(
            automaticallyRecognizesText: true,
            favoritesCapture: true,
            pinsCapture: true,
            tags: ["work", "reference"]
        )

        actions.apply(to: item)

        #expect(item.isFavorite)
        #expect(item.isPinned)
        #expect(item.tags == ["reference", "screenshot", "work"])
    }

    @Test func postCaptureTagsAreNormalized() {
        #expect(
            ScreenCapturePostActions.parseTags("work, reference\nwork")
                == ["reference", "work"]
        )
    }

    @Test func imageCropChangesDimensionsAndRedactionPreservesThem() throws {
        let image = try #require(makeQuadrantTestImage())
        let data = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        )
        let selection = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let croppedData = try #require(
            ClipboardImageEditing.edit(data, normalizedSelection: selection, operation: .crop)
        )
        let redactedData = try #require(
            ClipboardImageEditing.edit(data, normalizedSelection: selection, operation: .redact)
        )
        let outlinedData = try #require(
            ClipboardImageEditing.edit(data, normalizedSelection: selection, operation: .outline)
        )
        let croppedSource = try #require(CGImageSourceCreateWithData(croppedData as CFData, nil))
        let redactedSource = try #require(CGImageSourceCreateWithData(redactedData as CFData, nil))
        let cropped = try #require(CGImageSourceCreateImageAtIndex(croppedSource, 0, nil))
        let redacted = try #require(CGImageSourceCreateImageAtIndex(redactedSource, 0, nil))
        let outlinedSource = try #require(CGImageSourceCreateWithData(outlinedData as CFData, nil))
        let outlined = try #require(CGImageSourceCreateImageAtIndex(outlinedSource, 0, nil))

        #expect(cropped.width == 2)
        #expect(cropped.height == 2)
        #expect(redacted.width == 4)
        #expect(redacted.height == 4)
        #expect(outlined.width == 4)
        #expect(outlined.height == 4)
        #expect(isRedDominant(pixel(in: cropped, x: 0, y: 0)))
        #expect(isBlack(pixel(in: redacted, x: 0, y: 0)))
    }

    @Test func imageAnnotationsPreserveDimensionsAndChangeContent() throws {
        let image = try #require(makeTestImage())
        let data = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        )
        let selection = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let annotatedData = try #require(
            ClipboardImageEditing.edit(
                data,
                normalizedSelection: selection,
                operation: .rectangle(
                    color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                    fillColor: nil,
                    lineWidth: 2
                )
            )
        )
        let source = try #require(CGImageSourceCreateWithData(annotatedData as CFData, nil))
        let annotated = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(annotated.width == image.width)
        #expect(annotated.height == image.height)
        #expect(annotatedData != data)
    }

    @Test func zipArchiveParserReadsCentralDirectoryEntries() {
        var bytes = [UInt8](repeating: 0, count: 46)
        bytes[0...3] = [0x50, 0x4B, 0x01, 0x02]
        bytes[24...27] = [0x2A, 0, 0, 0]
        bytes[28...29] = [8, 0]
        bytes.append(contentsOf: Array("note.txt".utf8))

        let entries = ZIPArchiveParser.entries(in: Data(bytes))

        #expect(entries == [ZIPArchiveEntry(name: "note.txt", uncompressedSize: 42)])
    }

    @Test func savedFiltersNormalizeAndDiscardInvalidEntries() {
        let firstID = UUID()
        let filters = [
            ClipboardSavedFilter(id: firstID, name: "  Mail  ", query: " app:Mail ", isBuiltIn: true),
            ClipboardSavedFilter(name: "Mail", query: "app:Other"),
            ClipboardSavedFilter(name: " ", query: "type:image"),
            ClipboardSavedFilter(name: "Images", query: "type:image")
        ]

        let parsed = ClipboardSettings.parseSavedFilters(
            ClipboardSettings.formattedSavedFilters(filters)
        )

        #expect(parsed.map(\.name) == ["Mail", "Images"])
        #expect(parsed.first?.id == firstID)
        #expect(parsed.allSatisfy { !$0.isBuiltIn })
    }

    @MainActor
    @Test func savedFilterQueriesMatchUnknownDataLargeAndUnsyncedItems() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext

        let unknownItem = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.unknown,
            rawData: Data(repeating: 0, count: 12 * 1_024 * 1_024),
            utiType: "com.example.private",
            sourceApp: "Example"
        )
        unknownItem.isLocalOnly = true

        let imageItem = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.image,
            previewText: "Image",
            rawData: Data(repeating: 0, count: 12),
            utiType: "public.png",
            sourceApp: "Screen Capture"
        )

        #expect(ClipboardSearchQuery("type:unknown,data").matches(unknownItem))
        #expect(ClipboardSearchQuery("size:large").matches(unknownItem))
        #expect(ClipboardSearchQuery("sync:unsynced").matches(unknownItem))
        #expect(ClipboardSearchQuery("type:image app:Screen").matches(imageItem))
        #expect(!ClipboardSearchQuery("size:large").matches(imageItem))
    }

    @MainActor
    @Test func sourceAwareTitlesDescribeGenericImageAndVideoItems() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let image = try #require(makeTestImage())
        let imageData = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        )

        let imageItem = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.image,
            previewText: "Image",
            imageData: imageData,
            rawData: imageData,
            utiType: "public.png",
            sourceApp: "Safari"
        )
        let videoItem = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.video,
            previewText: "Video",
            rawData: Data([0x00, 0x01]),
            utiType: "public.mpeg-4",
            sourceApp: "QuickTime Player"
        )

        #expect(imageItem.displayTitle == "Image from Safari - 4x4")
        #expect(videoItem.displayTitle == "Video from QuickTime Player")
    }

    @Test func defaultIgnoredInternalTypesIncludeKnownPrivateMetadata() {
        let ignoredTypes = ClipboardSettings.defaults.ignoredPasteboardTypes

        #expect(ClipboardSettings.defaults.ignoresInternalPasteboardTypes)
        #expect(ignoredTypes.contains("org.chromium.internal.*"))
        #expect(ignoredTypes.contains("org.chromium.source-url"))
        #expect(ignoredTypes.contains("com.apple.IconComposer.layer"))
        #expect(ignoredTypes.contains("com.apple.IconComposer.assets"))
    }

    private func makeTestImage() -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return context.makeImage()
    }

    private func makeQuadrantTestImage() -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 2, width: 2, height: 2))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 2, y: 2, width: 2, height: 2))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 2, y: 0, width: 2, height: 2))
        return context.makeImage()
    }

    private func pixel(in image: CGImage, x: Int, y: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return pixel
        }

        context.draw(
            image,
            in: CGRect(
                x: -x,
                y: y - image.height + 1,
                width: image.width,
                height: image.height
            )
        )
        return pixel
    }

    private func isRedDominant(_ pixel: [UInt8]) -> Bool {
        pixel[0] > 180 && pixel[1] < 100 && pixel[2] < 100
    }

    private func isBlack(_ pixel: [UInt8]) -> Bool {
        pixel[0] < 40 && pixel[1] < 40 && pixel[2] < 40
    }
}
