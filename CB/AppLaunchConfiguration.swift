import CoreData
import Foundation

enum AppLaunchConfiguration {
    static let uiTestingArgument = "--ui-testing"
    static let largeHistoryUITestingArgument = "--ui-testing-large-history"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    @MainActor
    static func seedUITestData(in context: NSManagedObjectContext) {
        guard isUITesting else {
            return
        }

        let request = ClipboardItem.fetchRequest()
        request.fetchLimit = 1
        guard (try? context.count(for: request)) == 0 else {
            return
        }

        let note = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: "A deterministic clipboard note for interface testing.",
            previewText: "A deterministic clipboard note for interface testing.",
            rawData: Data("A deterministic clipboard note for interface testing.".utf8),
            utiType: "public.utf8-plain-text",
            sourceApp: "UI Tests"
        )
        note.customTitle = "UI Test Note"
        note.tagsText = "testing, note"

        let url = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.url,
            plainText: "https://example.com/ui-test",
            previewText: "https://example.com/ui-test",
            rawData: Data("https://example.com/ui-test".utf8),
            utiType: "public.url",
            sourceApp: "UI Tests"
        )
        url.customTitle = "UI Test URL"
        url.isFavorite = true

        if ProcessInfo.processInfo.arguments.contains(largeHistoryUITestingArgument) {
            seedLargeHistory(in: context)
        }

        try? context.save()
    }

    @MainActor
    private static func seedLargeHistory(in context: NSManagedObjectContext) {
        let pngData = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/luzGZQAAAABJRU5ErkJggg=="
        )

        for index in 0..<180 {
            let text = "Large history note \(index)"
            let item = ClipboardItem.make(
                in: context,
                type: ClipboardItemType.text,
                plainText: text,
                previewText: text,
                rawData: Data(text.utf8),
                utiType: "public.utf8-plain-text",
                sourceApp: "UI Tests"
            )
            item.tagsText = index.isMultiple(of: 3) ? "large-history, note" : "large-history"
        }

        if let pngData {
            for index in 0..<40 {
                let item = ClipboardItem.make(
                    in: context,
                    type: ClipboardItemType.image,
                    previewText: "Image",
                    imageData: pngData,
                    thumbnailData: pngData,
                    rawData: pngData,
                    utiType: "public.png",
                    sourceApp: "UI Tests"
                )
                item.customTitle = "Large History Image \(index)"
                item.tagsText = "large-history, image"
            }
        }
    }
}
