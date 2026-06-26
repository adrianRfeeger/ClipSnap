import CoreData
import Foundation

enum AppLaunchConfiguration {
    static let uiTestingArgument = "--ui-testing"

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

        try? context.save()
    }
}
