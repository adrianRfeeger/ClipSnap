import AppKit
import CoreData
import UniformTypeIdentifiers

enum ClipboardItemType {
    static let text = "text"
    static let image = "image"
    static let file = "file"
    static let url = "url"
    static let rtf = "rtf"
    static let rtfd = "rtfd"
    static let html = "html"
    static let pdf = "pdf"
    static let color = "color"
    static let audio = "audio"
    static let video = "video"
    static let json = "json"
    static let xml = "xml"
    static let sourceCode = "sourceCode"
    static let tabularText = "tabularText"
    static let contact = "contact"
    static let archive = "archive"
    static let data = "data"
    static let unknown = "unknown"
}

extension ClipboardItem {
    var displayType: String {
        switch type {
        case ClipboardItemType.text:
            return "Text"
        case ClipboardItemType.image:
            return "Image"
        case ClipboardItemType.file:
            return "File"
        case ClipboardItemType.url:
            return "URL"
        case ClipboardItemType.rtf:
            return "Rich Text"
        case ClipboardItemType.rtfd:
            return "RTFD"
        case ClipboardItemType.html:
            return "HTML"
        case ClipboardItemType.pdf:
            return "PDF"
        case ClipboardItemType.color:
            return "Color"
        case ClipboardItemType.audio:
            return "Audio"
        case ClipboardItemType.video:
            return "Video"
        case ClipboardItemType.json:
            return "JSON"
        case ClipboardItemType.xml:
            return "XML"
        case ClipboardItemType.sourceCode:
            return "Source Code"
        case ClipboardItemType.tabularText:
            return "Table"
        case ClipboardItemType.contact:
            return "Contact"
        case ClipboardItemType.archive:
            return "Archive"
        case ClipboardItemType.data:
            return "Data"
        default:
            return "Unknown"
        }
    }

    var displayTitle: String {
        if let customTitle = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customTitle.isEmpty {
            return customTitle
        }

        if let previewText, !previewText.isEmpty {
            if type == ClipboardItemType.image,
               previewText == "Image" {
                return imageTitle
            }

            if type == ClipboardItemType.file,
               let sourceTitle = sourceAwareTitle(prefix: "File") {
                return "\(previewText) from \(sourceTitle)"
            }

            if (type == ClipboardItemType.audio || type == ClipboardItemType.video),
               isGenericPreview(previewText),
               let sourceTitle = sourceAwareTitle(prefix: displayType) {
                return sourceTitle
            }

            return previewText
        }

        if type == ClipboardItemType.image {
            return imageTitle
        }

        if type == ClipboardItemType.file,
           let sourceTitle = sourceAwareTitle(prefix: "File") {
            return sourceTitle
        }

        if (type == ClipboardItemType.audio || type == ClipboardItemType.video),
           let sourceTitle = sourceAwareTitle(prefix: displayType) {
            return sourceTitle
        }

        return utiType ?? "Clipboard Item"
    }

    var createdAtValue: Date {
        createdAt ?? .distantPast
    }

    var image: NSImage? {
        guard let imageData else {
            return nil
        }

        return NSImage(data: imageData)
    }

    var systemImageName: String {
        switch type {
        case ClipboardItemType.image:
            return "photo"
        case ClipboardItemType.file:
            return "doc"
        case ClipboardItemType.url:
            return "link"
        case ClipboardItemType.rtf, ClipboardItemType.rtfd:
            return "doc.richtext"
        case ClipboardItemType.html:
            return "chevron.left.forwardslash.chevron.right"
        case ClipboardItemType.pdf:
            return "doc.fill"
        case ClipboardItemType.color:
            return "paintpalette"
        case ClipboardItemType.audio:
            return "waveform"
        case ClipboardItemType.video:
            return "film"
        case ClipboardItemType.json, ClipboardItemType.xml, ClipboardItemType.sourceCode:
            return "curlybraces"
        case ClipboardItemType.tabularText:
            return "tablecells"
        case ClipboardItemType.contact:
            return "person.crop.square"
        case ClipboardItemType.archive:
            return "archivebox"
        case ClipboardItemType.data:
            return "externaldrive"
        case ClipboardItemType.text:
            return "text.alignleft"
        default:
            return "questionmark.square"
        }
    }

    var menuTitle: String {
        displayTitle.truncatedForMenu
    }

    private var imageTitle: String {
        let baseTitle = imageSourceTitle ?? "Image"
        guard let imageDimensionsDescription else {
            return baseTitle
        }
        return "\(baseTitle) - \(imageDimensionsDescription)"
    }

    private var imageSourceTitle: String? {
        guard type == ClipboardItemType.image,
              let sourceApp = sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceApp.isEmpty,
              sourceApp != "Screen Capture",
              sourceApp != "Screen OCR" else {
            return nil
        }

        return "Image from \(sourceApp)"
    }

    private var imageDimensionsDescription: String? {
        guard type == ClipboardItemType.image,
              let image else {
            return nil
        }

        let width = Int(round(image.size.width))
        let height = Int(round(image.size.height))
        guard width > 0, height > 0 else {
            return nil
        }

        return "\(width)x\(height)"
    }

    private func sourceAwareTitle(prefix: String) -> String? {
        guard let sourceApp = sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceApp.isEmpty,
              sourceApp != "Screen Capture",
              sourceApp != "Screen Recording",
              sourceApp != "Screen OCR" else {
            return nil
        }

        return "\(prefix) from \(sourceApp)"
    }

    private func isGenericPreview(_ value: String) -> Bool {
        value == displayType
            || value == "Audio"
            || value == "Video"
            || value == "Screen Recording"
    }

    var shouldProtectPreview: Bool {
        isSensitive
            && ClipboardSettings.load().protectsSensitivePreviews
    }

    var protectedMenuTitle: String {
        shouldProtectPreview ? "Sensitive Content" : menuTitle
    }

    var storageLocationDescription: String {
        isLocalOnly ? "On This Mac" : "iCloud"
    }

    var tags: [String] {
        (tagsText ?? "")
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var normalizedCollectionName: String? {
        guard let value = collectionName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    var isScreenCapture: Bool {
        sourceApp == "Screen Capture"
    }

    var isOCRCapture: Bool {
        sourceApp == "Screen OCR"
    }

    var sortedRepresentations: [ClipboardRepresentation] {
        let values = representations as? Set<ClipboardRepresentation> ?? []
        return values.sorted {
            if $0.itemIndex != $1.itemIndex {
                return $0.itemIndex < $1.itemIndex
            }
            if $0.order != $1.order {
                return $0.order < $1.order
            }
            return ($0.utiIdentifier ?? "") < ($1.utiIdentifier ?? "")
        }
    }

    var representationPayloads: [ClipboardRepresentationPayload] {
        sortedRepresentations.compactMap { representation in
            guard let utiIdentifier = representation.utiIdentifier else {
                return nil
            }

            return ClipboardRepresentationPayload(
                itemIndex: Int(representation.itemIndex),
                order: Int(representation.order),
                utiIdentifier: utiIdentifier,
                data: representation.data,
                stringValue: representation.stringValue
            )
        }
    }

    func updateContentIdentity() {
        let payload = ClipboardPayload(
            type: type ?? ClipboardItemType.unknown,
            plainText: plainText,
            utiType: utiType,
            rawData: rawData,
            imageData: imageData,
            representations: representationPayloads
        )
        byteCount = payload.byteCount
        contentHash = ClipboardContentHasher.hash(payload)
    }
}

extension ClipboardItem {
    @discardableResult
    static func make(
        in context: NSManagedObjectContext,
        type: String,
        plainText: String? = nil,
        previewText: String? = nil,
        imageData: Data? = nil,
        thumbnailData: Data? = nil,
        rawData: Data? = nil,
        utiType: String? = nil,
        sourceApp: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) -> ClipboardItem {
        let item = ClipboardItem(context: context)
        let now = Date()
        item.id = UUID()
        item.createdAt = now
        item.updatedAt = now
        item.type = type
        item.plainText = plainText
        item.previewText = previewText
        item.imageData = imageData
        item.thumbnailData = thumbnailData
        item.rawData = rawData
        item.utiType = utiType
        item.sourceApp = sourceApp
        item.sourceBundleIdentifier = sourceBundleIdentifier
        let payload = ClipboardPayload(
            type: type,
            plainText: plainText,
            utiType: utiType,
            rawData: rawData,
            imageData: imageData
        )
        item.byteCount = payload.byteCount
        item.contentHash = ClipboardContentHasher.hash(payload)
        item.isPinned = false
        item.isFavorite = false
        return item
    }
}

extension String {
    var clipboardPreview: String {
        let collapsed = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard collapsed.count > 160 else {
            return collapsed
        }

        return String(collapsed.prefix(157)) + "..."
    }

    var truncatedForMenu: String {
        let collapsed = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard collapsed.count > 30 else {
            return collapsed
        }

        return String(collapsed.prefix(27)) + "..."
    }
}

extension UTType {
    var clipboardItemType: String {
        if conforms(to: .image) {
            return ClipboardItemType.image
        }

        if conforms(to: .pdf) {
            return ClipboardItemType.pdf
        }

        if conforms(to: .rtfd) || conforms(to: .flatRTFD) {
            return ClipboardItemType.rtfd
        }

        if conforms(to: .rtf) {
            return ClipboardItemType.rtf
        }

        if conforms(to: .html) {
            return ClipboardItemType.html
        }

        if conforms(to: .json) {
            return ClipboardItemType.json
        }

        if conforms(to: .xml) {
            return ClipboardItemType.xml
        }

        if conforms(to: .vCard) {
            return ClipboardItemType.contact
        }

        if conforms(to: .tabSeparatedText)
            || conforms(to: .commaSeparatedText)
            || conforms(to: .delimitedText) {
            return ClipboardItemType.tabularText
        }

        if conforms(to: .sourceCode) {
            return ClipboardItemType.sourceCode
        }

        if conforms(to: .audio) {
            return ClipboardItemType.audio
        }

        if conforms(to: .movie) || conforms(to: .video) || conforms(to: .audiovisualContent) {
            return ClipboardItemType.video
        }

        if conforms(to: .archive) {
            return ClipboardItemType.archive
        }

        if conforms(to: .text) {
            return ClipboardItemType.text
        }

        if conforms(to: .data) {
            return ClipboardItemType.data
        }

        return ClipboardItemType.unknown
    }
}
