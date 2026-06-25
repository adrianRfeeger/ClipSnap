//
//  CBTests.swift
//  CBTests
//
//  Created by Adrian Feeger on 23/6/2026.
//

import Foundation
import CoreGraphics
import CoreData
import Testing
@testable import Clipboard_Bro

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

    @Test func sensitiveContentDetectionCoversCommonSecrets() {
        #expect(ClipboardPrivacyPolicy.isSensitive("123456"))
        #expect(ClipboardPrivacyPolicy.isSensitive("4242 4242 4242 4242"))
        #expect(ClipboardPrivacyPolicy.isSensitive("-----BEGIN PRIVATE KEY-----"))
        #expect(ClipboardPrivacyPolicy.isSensitive("api_key=abcdefgh12345678"))
        #expect(!ClipboardPrivacyPolicy.isSensitive("A normal clipboard note"))
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
}
