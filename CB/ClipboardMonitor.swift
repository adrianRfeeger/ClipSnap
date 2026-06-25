import AppKit
import Combine
import CoreData
import OSLog
import UniformTypeIdentifiers

@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var isMonitoring = false

    private let context: NSManagedObjectContext
    private let cleanupService = HistoryCleanupService()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CB", category: "ClipboardMonitor")
    private var monitoringTask: Task<Void, Never>?
    private var lastChangeCount: Int
    private var isRestoring = false

    init(context: NSManagedObjectContext) {
        self.context = context
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    deinit {
        monitoringTask?.cancel()
    }

    func start() {
        guard monitoringTask == nil else {
            return
        }

        lastChangeCount = NSPasteboard.general.changeCount
        isMonitoring = true
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled else {
                    return
                }
                self?.checkPasteboard()
            }
        }
        cleanupService.clean(context: context, settings: ClipboardSettings.load())
        logger.info("Clipboard monitoring started")
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        isMonitoring = false
        logger.info("Clipboard monitoring stopped")
    }

    func copyToClipboard(_ item: ClipboardItem) {
        isRestoring = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        defer {
            lastChangeCount = pasteboard.changeCount
            isRestoring = false
        }

        if restoreRepresentations(for: item, to: pasteboard) {
            return
        }

        switch item.type {
        case ClipboardItemType.text:
            if let plainText = item.plainText {
                pasteboard.setString(plainText, forType: .string)
            }
        case ClipboardItemType.image:
            if let image = item.image {
                pasteboard.writeObjects([image])
            } else if let imageData = item.imageData {
                pasteboard.setData(imageData, forType: .png)
            }
        case ClipboardItemType.file:
            writeURLString(item.plainText, to: pasteboard, type: .fileURL)
        case ClipboardItemType.url:
            writeURLString(item.plainText, to: pasteboard, type: .URL)
        case ClipboardItemType.rtf:
            writeData(item.rawData, utiType: item.utiType, fallbackType: .rtf, to: pasteboard)
        case ClipboardItemType.rtfd:
            writeData(item.rawData, utiType: item.utiType, fallbackType: .rtfd, to: pasteboard)
        case ClipboardItemType.html:
            writeData(item.rawData, utiType: item.utiType, fallbackType: .html, to: pasteboard)
        case ClipboardItemType.color:
            if let rawData = item.rawData,
               let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: rawData) {
                color.write(to: pasteboard)
            } else {
                writeData(item.rawData, utiType: item.utiType, fallbackType: .color, to: pasteboard)
            }
        case ClipboardItemType.pdf:
            writeData(item.rawData, utiType: item.utiType, fallbackType: .pdf, to: pasteboard)
        case ClipboardItemType.json,
            ClipboardItemType.xml,
            ClipboardItemType.sourceCode,
            ClipboardItemType.tabularText,
            ClipboardItemType.contact,
            ClipboardItemType.audio,
            ClipboardItemType.video,
            ClipboardItemType.archive,
            ClipboardItemType.data:
            writeData(item.rawData, utiType: item.utiType, fallbackType: .string, to: pasteboard)
        default:
            if let rawData = item.rawData, let utiType = item.utiType {
                pasteboard.setData(rawData, forType: NSPasteboard.PasteboardType(utiType))
            } else if let plainText = item.plainText {
                pasteboard.setString(plainText, forType: .string)
            }
        }

    }

    @discardableResult
    func importScreenCapture(
        _ image: CGImage,
        sourceDescription: String,
        copyToPasteboard: Bool
    ) -> String? {
        let nsImage = NSImage(cgImage: image, size: .zero)
        guard let pngData = nsImage.pngData() else {
            logger.error("Failed to encode screen capture as PNG")
            return nil
        }

        let item = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.image,
            previewText: sourceDescription,
            imageData: pngData,
            thumbnailData: nsImage.thumbnailData(maxDimension: 220),
            rawData: pngData,
            utiType: UTType.png.identifier,
            sourceApp: "Screen Capture",
            sourceBundleIdentifier: Bundle.main.bundleIdentifier
        )
        item.updateContentIdentity()

        let settings = ClipboardSettings.load()
        do {
            if let duplicate = findDuplicate(of: item) {
                context.delete(item)
                if settings.moveDuplicatesToTop {
                    let now = Date()
                    duplicate.createdAt = now
                    duplicate.updatedAt = now
                    duplicate.sourceApp = "Screen Capture"
                    duplicate.sourceBundleIdentifier = Bundle.main.bundleIdentifier
                }
                try context.save()
                if copyToPasteboard {
                    copyToClipboard(duplicate)
                }
                return duplicate.id?.uuidString
            }

            try context.save()
            cleanupService.clean(context: context, settings: settings)
            if copyToPasteboard {
                copyToClipboard(item)
            }
            logger.info("Stored screen capture, bytes \(pngData.count, privacy: .public)")
            return item.id?.uuidString
        } catch {
            context.rollback()
            logger.error("Failed to save screen capture: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    func importRecognizedText(_ text: String, copyToPasteboard: Bool) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        let item = ClipboardItem.make(
            in: context,
            type: ClipboardItemType.text,
            plainText: trimmedText,
            previewText: trimmedText.clipboardPreview,
            rawData: Data(trimmedText.utf8),
            utiType: UTType.utf8PlainText.identifier,
            sourceApp: "Screen OCR",
            sourceBundleIdentifier: Bundle.main.bundleIdentifier
        )
        item.updateContentIdentity()

        let settings = ClipboardSettings.load()
        do {
            if let duplicate = findDuplicate(of: item) {
                context.delete(item)
                if settings.moveDuplicatesToTop {
                    let now = Date()
                    duplicate.createdAt = now
                    duplicate.updatedAt = now
                    duplicate.sourceApp = "Screen OCR"
                    duplicate.sourceBundleIdentifier = Bundle.main.bundleIdentifier
                }
                try context.save()
                if copyToPasteboard {
                    copyToClipboard(duplicate)
                }
                return duplicate.id?.uuidString
            }

            try context.save()
            cleanupService.clean(context: context, settings: settings)
            if copyToPasteboard {
                copyToClipboard(item)
            }
            logger.info("Stored OCR text, characters \(trimmedText.count, privacy: .public)")
            return item.id?.uuidString
        } catch {
            context.rollback()
            logger.error("Failed to save OCR text: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func importDroppedRepresentations(_ representations: [DroppedClipboardRepresentation]) {
        guard !representations.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CB.Drop.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let grouped = Dictionary(grouping: representations, by: \.itemIndex)
        let pasteboardItems = grouped.keys.sorted().compactMap { itemIndex -> NSPasteboardItem? in
            guard let values = grouped[itemIndex] else {
                return nil
            }

            let pasteboardItem = NSPasteboardItem()
            var wroteValue = false
            for value in values.sorted(by: { $0.order < $1.order }) {
                pasteboardItem.setData(
                    value.data,
                    forType: NSPasteboard.PasteboardType(value.utiIdentifier)
                )
                wroteValue = true
            }
            return wroteValue ? pasteboardItem : nil
        }

        guard !pasteboardItems.isEmpty, pasteboard.writeObjects(pasteboardItems) else {
            return
        }

        processPasteboard(
            pasteboard,
            sourceApp: "Drag and Drop",
            sourceBundleIdentifier: nil
        )
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount

        let sourceApplication = NSWorkspace.shared.frontmostApplication
        guard !isRestoring else {
            return
        }

        processPasteboard(
            pasteboard,
            sourceApp: sourceApplication?.localizedName,
            sourceBundleIdentifier: sourceApplication?.bundleIdentifier
        )
    }

    private func processPasteboard(
        _ pasteboard: NSPasteboard,
        sourceApp: String?,
        sourceBundleIdentifier: String?
    ) {
        let settings = ClipboardSettings.load()
        guard !containsProtectedPasteboardType(pasteboard),
              !ClipboardPrivacyPolicy.excludes(
                bundleIdentifier: sourceBundleIdentifier,
                excludedBundleIdentifiers: settings.excludedBundleIdentifiers
              ),
              let capturedItem = captureItem(from: pasteboard) else {
            return
        }

        captureRepresentations(from: pasteboard, for: capturedItem)
        capturedItem.sourceApp = sourceApp
        capturedItem.sourceBundleIdentifier = sourceBundleIdentifier
        let capturedType = capturedItem.type ?? ClipboardItemType.unknown
        let capturedByteCount = capturedItem.byteCount

        if settings.detectSensitiveContent,
           ClipboardPrivacyPolicy.isSensitive(capturedItem.plainText) {
            context.delete(capturedItem)
            logger.info("Skipped clipboard content because a privacy rule matched")
            return
        }

        do {
            if let duplicate = findDuplicate(of: capturedItem) {
                context.delete(capturedItem)
                if settings.moveDuplicatesToTop {
                    let now = Date()
                    duplicate.createdAt = now
                    duplicate.updatedAt = now
                    duplicate.sourceApp = sourceApp
                    duplicate.sourceBundleIdentifier = sourceBundleIdentifier
                }
            }
            try context.save()
            cleanupService.clean(context: context, settings: settings)
            logger.info(
                "Processed clipboard item type \(capturedType, privacy: .public), bytes \(capturedByteCount, privacy: .public)"
            )
        } catch {
            context.rollback()
            logger.error("Failed to save clipboard item: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func captureItem(from pasteboard: NSPasteboard) -> ClipboardItem? {
        if let fileURL = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL {
            return ClipboardItem.make(
                in: context,
                type: ClipboardItemType.file,
                plainText: fileURL.absoluteString,
                previewText: fileURL.lastPathComponent,
                utiType: NSPasteboard.PasteboardType.fileURL.rawValue
            )
        }

        if let color = NSColor(from: pasteboard),
           let colorData = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            return ClipboardItem.make(
                in: context,
                type: ClipboardItemType.color,
                plainText: color.hexDescription,
                previewText: color.hexDescription,
                rawData: colorData,
                utiType: NSPasteboard.PasteboardType.color.rawValue
            )
        }

        if let pdfData = pasteboard.data(forType: .pdf) {
            return ClipboardItem.make(
                in: context,
                type: ClipboardItemType.pdf,
                previewText: "PDF",
                rawData: pdfData,
                utiType: NSPasteboard.PasteboardType.pdf.rawValue
            )
        }

        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
           let data = image.pngData() {
            return ClipboardItem.make(
                in: context,
                type: ClipboardItemType.image,
                previewText: "Image",
                imageData: data,
                thumbnailData: image.thumbnailData(maxDimension: 220),
                rawData: pasteboard.data(forType: .tiff),
                utiType: NSPasteboard.PasteboardType.tiff.rawValue
            )
        }

        if let rtfdData = pasteboard.data(forType: .rtfd) {
            return ClipboardItem.make(
                in: context,
                type: ClipboardItemType.rtfd,
                previewText: "RTFD",
                rawData: rtfdData,
                utiType: NSPasteboard.PasteboardType.rtfd.rawValue
            )
        }

        if let rtfData = pasteboard.data(forType: .rtf) {
            return ClipboardItem.make(
                in: context,
                type: ClipboardItemType.rtf,
                previewText: richTextPreview(from: rtfData) ?? "Rich text",
                rawData: rtfData,
                utiType: NSPasteboard.PasteboardType.rtf.rawValue
            )
        }

        if let htmlData = pasteboard.data(forType: .html) {
            return ClipboardItem.make(
                in: context,
                type: ClipboardItemType.html,
                previewText: stringPreview(from: htmlData) ?? "HTML",
                rawData: htmlData,
                utiType: NSPasteboard.PasteboardType.html.rawValue
            )
        }

        if let item = captureTypedData(from: pasteboard) {
            return item
        }

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            let isURL = URL(string: string)?.scheme != nil
            return ClipboardItem.make(
                in: context,
                type: isURL ? ClipboardItemType.url : ClipboardItemType.text,
                plainText: string,
                previewText: string.clipboardPreview,
                rawData: string.data(using: .utf8),
                utiType: isURL ? NSPasteboard.PasteboardType.URL.rawValue : NSPasteboard.PasteboardType.string.rawValue
            )
        }

        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type) {
                return ClipboardItem.make(
                    in: context,
                    type: ClipboardItemType.unknown,
                    previewText: type.rawValue,
                    rawData: data,
                    utiType: type.rawValue
                )
            }
        }

        return nil
    }

    private func captureTypedData(from pasteboard: NSPasteboard) -> ClipboardItem? {
        for pasteboardType in pasteboard.types ?? [] {
            guard let data = pasteboard.data(forType: pasteboardType),
                  let uniformType = UTType(pasteboardType.rawValue) else {
                continue
            }

            let itemType = uniformType.clipboardItemType
            guard itemType != ClipboardItemType.image,
                  itemType != ClipboardItemType.pdf,
                  itemType != ClipboardItemType.rtf,
                  itemType != ClipboardItemType.rtfd,
                  itemType != ClipboardItemType.html,
                  itemType != ClipboardItemType.text,
                  itemType != ClipboardItemType.unknown else {
                continue
            }

            return ClipboardItem.make(
                in: context,
                type: itemType,
                plainText: textualContent(from: data, itemType: itemType),
                previewText: previewText(for: itemType, data: data, utiType: uniformType),
                rawData: data,
                utiType: pasteboardType.rawValue
            )
        }

        return nil
    }

    private func findDuplicate(of newItem: ClipboardItem) -> ClipboardItem? {
        let request = ClipboardItem.fetchRequest()
        request.fetchLimit = 1
        request.includesPendingChanges = false
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)]
        if let contentHash = newItem.contentHash {
            request.predicate = NSPredicate(format: "contentHash == %@", contentHash)
        }

        do {
            return try context.fetch(request).first
        } catch {
            logger.error("Failed to check clipboard duplicate: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func containsProtectedPasteboardType(_ pasteboard: NSPasteboard) -> Bool {
        let protectedTypes = Set([
            "org.nspasteboard.TransientType",
            "org.nspasteboard.ConcealedType"
        ])
        return pasteboard.types?.contains { protectedTypes.contains($0.rawValue) } == true
    }

    private func captureRepresentations(from pasteboard: NSPasteboard, for clipboardItem: ClipboardItem) {
        let protectedTypes = Set([
            "org.nspasteboard.TransientType",
            "org.nspasteboard.ConcealedType"
        ])

        for (itemIndex, pasteboardItem) in (pasteboard.pasteboardItems ?? []).enumerated() {
            for (order, pasteboardType) in pasteboardItem.types.enumerated() {
                guard !protectedTypes.contains(pasteboardType.rawValue) else {
                    continue
                }

                let data = pasteboardItem.data(forType: pasteboardType)
                let stringValue = data == nil ? pasteboardItem.string(forType: pasteboardType) : nil
                guard data != nil || stringValue != nil else {
                    continue
                }

                let representation = ClipboardRepresentation(context: context)
                representation.id = UUID()
                representation.itemIndex = Int16(clamping: itemIndex)
                representation.order = Int16(clamping: order)
                representation.utiIdentifier = pasteboardType.rawValue
                representation.data = data
                representation.stringValue = stringValue
                representation.byteCount = Int64((data?.count ?? 0) + (stringValue?.utf8.count ?? 0))
                representation.item = clipboardItem
            }
        }

        clipboardItem.updateContentIdentity()
    }

    private func restoreRepresentations(for item: ClipboardItem, to pasteboard: NSPasteboard) -> Bool {
        let representations = item.sortedRepresentations
        guard !representations.isEmpty else {
            return false
        }

        let grouped = Dictionary(grouping: representations, by: \.itemIndex)
        let pasteboardItems = grouped.keys.sorted().compactMap { itemIndex -> NSPasteboardItem? in
            guard let storedRepresentations = grouped[itemIndex] else {
                return nil
            }

            let pasteboardItem = NSPasteboardItem()
            var wroteRepresentation = false
            for representation in storedRepresentations {
                guard let utiIdentifier = representation.utiIdentifier else {
                    continue
                }

                let pasteboardType = NSPasteboard.PasteboardType(utiIdentifier)
                if let data = representation.data {
                    pasteboardItem.setData(data, forType: pasteboardType)
                    wroteRepresentation = true
                } else if let stringValue = representation.stringValue {
                    pasteboardItem.setString(stringValue, forType: pasteboardType)
                    wroteRepresentation = true
                }
            }
            return wroteRepresentation ? pasteboardItem : nil
        }

        guard !pasteboardItems.isEmpty else {
            return false
        }

        return pasteboard.writeObjects(pasteboardItems)
    }

    private func writeURLString(_ value: String?, to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) {
        guard let value else {
            return
        }

        pasteboard.setString(value, forType: type)
        pasteboard.setString(value, forType: .string)
    }

    private func writeData(
        _ data: Data?,
        utiType: String?,
        fallbackType: NSPasteboard.PasteboardType,
        to pasteboard: NSPasteboard
    ) {
        guard let data else {
            return
        }

        let pasteboardType = utiType.map { NSPasteboard.PasteboardType($0) } ?? fallbackType
        pasteboard.setData(data, forType: pasteboardType)
    }

    private func previewText(for itemType: String, data: Data, utiType: UTType) -> String {
        if let textualContent = textualContent(from: data, itemType: itemType) {
            return textualContent.clipboardPreview
        }

        return "\(utiType.localizedDescription ?? utiType.identifier) - \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
    }

    private func textualContent(from data: Data, itemType: String) -> String? {
        guard itemType == ClipboardItemType.json
            || itemType == ClipboardItemType.xml
            || itemType == ClipboardItemType.sourceCode
            || itemType == ClipboardItemType.tabularText
            || itemType == ClipboardItemType.contact
            || itemType == ClipboardItemType.text else {
            return nil
        }

        return stringPreview(from: data)
    }

    private func stringPreview(from data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .ascii)
    }

    private func richTextPreview(from data: Data) -> String? {
        guard let attributedString = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else {
            return nil
        }

        return attributedString.string.clipboardPreview
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    func thumbnailData(maxDimension: CGFloat) -> Data? {
        let originalSize = size
        guard originalSize.width > 0, originalSize.height > 0 else {
            return pngData()
        }

        let scale = min(maxDimension / originalSize.width, maxDimension / originalSize.height, 1)
        let thumbnailSize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)
        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        draw(in: NSRect(origin: .zero, size: thumbnailSize))
        thumbnail.unlockFocus()
        return thumbnail.pngData()
    }
}

private extension NSColor {
    var hexDescription: String {
        guard let color = usingColorSpace(.deviceRGB) else {
            return "Color"
        }

        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        let alpha = Int(round(color.alphaComponent * 255))

        if alpha < 255 {
            return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
        }

        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
