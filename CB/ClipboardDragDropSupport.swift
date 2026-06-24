import AppKit
import Foundation
import UniformTypeIdentifiers

struct DroppedClipboardRepresentation: Sendable {
    let itemIndex: Int
    let order: Int
    let utiIdentifier: String
    let data: Data
}

@MainActor
enum ClipboardDragDropSupport {
    static let acceptedTypes: [UTType] = [
        .item,
        .data,
        .content,
        .text,
        .image,
        .fileURL,
        .url
    ]

    static func itemProvider(for item: ClipboardItem) -> NSItemProvider {
        let provider = nativeItemProvider(for: item)
        let representations = item.sortedRepresentations.filter { $0.itemIndex == 0 }

        if representations.isEmpty {
            registerLegacyRepresentation(of: item, with: provider)
            return provider
        }

        for representation in representations {
            guard let utiIdentifier = representation.utiIdentifier else {
                continue
            }

            let data = representation.data
                ?? representation.stringValue?.data(using: .utf8)
                ?? Data()
            provider.registerDataRepresentation(
                forTypeIdentifier: utiIdentifier,
                visibility: .all
            ) { completion in
                completion(data, nil)
                return nil
            }
        }

        provider.suggestedName = item.dragSuggestedName
        return provider
    }

    static func loadDroppedProviders(
        _ providers: [NSItemProvider],
        completion: @escaping @MainActor ([DroppedClipboardRepresentation]) -> Void
    ) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var loadedRepresentations: [DroppedClipboardRepresentation] = []
        var startedLoad = false

        for (itemIndex, provider) in providers.enumerated() {
            for (order, typeIdentifier) in provider.registeredTypeIdentifiers.enumerated() {
                startedLoad = true
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                    defer { group.leave() }
                    guard let data else {
                        return
                    }

                    lock.lock()
                    loadedRepresentations.append(
                        DroppedClipboardRepresentation(
                            itemIndex: itemIndex,
                            order: order,
                            utiIdentifier: typeIdentifier,
                            data: data
                        )
                    )
                    lock.unlock()
                }
            }
        }

        guard startedLoad else {
            return false
        }

        group.notify(queue: .main) {
            completion(loadedRepresentations)
        }
        return true
    }

    private static func registerLegacyRepresentation(
        of item: ClipboardItem,
        with provider: NSItemProvider
    ) {
        let identifier = item.utiType ?? NSPasteboard.PasteboardType.string.rawValue
        let data = item.rawData
            ?? item.imageData
            ?? item.plainText?.data(using: .utf8)
            ?? Data()
        provider.registerDataRepresentation(
            forTypeIdentifier: identifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }
        provider.suggestedName = item.dragSuggestedName
    }

    private static func nativeItemProvider(for item: ClipboardItem) -> NSItemProvider {
        switch item.type {
        case ClipboardItemType.file:
            if let plainText = item.plainText,
               let url = URL(string: plainText),
               url.isFileURL {
                return NSItemProvider(object: url as NSURL)
            }
        case ClipboardItemType.url:
            if let plainText = item.plainText,
               let url = URL(string: plainText) {
                return NSItemProvider(object: url as NSURL)
            }
        case ClipboardItemType.text,
            ClipboardItemType.json,
            ClipboardItemType.xml,
            ClipboardItemType.sourceCode,
            ClipboardItemType.tabularText,
            ClipboardItemType.contact,
            ClipboardItemType.color:
            if let plainText = item.plainText {
                return NSItemProvider(object: plainText as NSString)
            }
        default:
            break
        }

        return NSItemProvider()
    }
}

private extension ClipboardItem {
    var dragSuggestedName: String {
        switch type {
        case ClipboardItemType.file:
            if let plainText,
               let url = URL(string: plainText) {
                return url.lastPathComponent
            }
        case ClipboardItemType.image:
            return "Clipboard Image.png"
        case ClipboardItemType.pdf:
            return "Clipboard Document.pdf"
        default:
            break
        }

        return displayTitle.truncatedForMenu
    }
}
