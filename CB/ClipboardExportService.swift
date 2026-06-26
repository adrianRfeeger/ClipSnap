import AppKit
import Foundation
import UniformTypeIdentifiers

enum ClipboardExportFormat: String, CaseIterable, Identifiable {
    case plainText
    case markdown
    case json
    case csv

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .plainText:
            return "Plain Text"
        case .markdown:
            return "Markdown"
        case .json:
            return "JSON"
        case .csv:
            return "CSV"
        }
    }

    var fileExtension: String {
        switch self {
        case .plainText:
            return "txt"
        case .markdown:
            return "md"
        case .json:
            return "json"
        case .csv:
            return "csv"
        }
    }

    var contentType: UTType {
        switch self {
        case .plainText:
            return .plainText
        case .markdown:
            return UTType(filenameExtension: "md") ?? .plainText
        case .json:
            return .json
        case .csv:
            return .commaSeparatedText
        }
    }
}

enum ClipboardExportError: LocalizedError {
    case missingPayload
    case unableToEncode
    case unavailableWindow

    var errorDescription: String? {
        switch self {
        case .missingPayload:
            return "The selected clipboard item has no exportable payload."
        case .unableToEncode:
            return "Clipboard Bro could not encode the selected items."
        case .unavailableWindow:
            return "The sharing menu requires an active Clipboard Bro window."
        }
    }
}

@MainActor
enum ClipboardExportService {
    static func exportNative(_ item: ClipboardItem) throws {
        let payload = try nativePayload(for: item)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = payload.filename
        panel.allowedContentTypes = [payload.contentType]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        try payload.data.write(to: url, options: .atomic)
    }

    static func export(_ items: [ClipboardItem], format: ClipboardExportFormat) throws {
        let data = try aggregateData(for: items, format: format)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Clipboard Export.\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        try data.write(to: url, options: .atomic)
    }

    static func share(_ items: [ClipboardItem]) throws {
        guard let view = NSApp.keyWindow?.contentView else {
            throw ClipboardExportError.unavailableWindow
        }
        let sharingItems = try items.compactMap(sharingItem(for:))
        guard !sharingItems.isEmpty else {
            throw ClipboardExportError.missingPayload
        }
        NSSharingServicePicker(items: sharingItems).show(
            relativeTo: view.bounds,
            of: view,
            preferredEdge: .minY
        )
    }

    static func aggregateData(
        for items: [ClipboardItem],
        format: ClipboardExportFormat
    ) throws -> Data {
        let records = items.map(ClipboardExportRecord.init)
        switch format {
        case .plainText:
            return try encode(
                records.map(\.content).joined(separator: "\n\n")
            )
        case .markdown:
            let markdown = records.enumerated().map { index, record in
                """
                ## \(index + 1). \(record.title)

                \(record.content)
                """
            }.joined(separator: "\n\n---\n\n")
            return try encode(markdown)
        case .json:
            let objects = records.map(\.jsonObject)
            guard JSONSerialization.isValidJSONObject(objects) else {
                throw ClipboardExportError.unableToEncode
            }
            return try JSONSerialization.data(
                withJSONObject: objects,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        case .csv:
            let header = ["title", "type", "source", "createdAt", "tags", "content"]
            let rows = records.map { record in
                [
                    record.title,
                    record.type,
                    record.source,
                    record.createdAt,
                    record.tags,
                    record.content
                ].map(csvField).joined(separator: ",")
            }
            return try encode(([header.joined(separator: ",")] + rows).joined(separator: "\n"))
        }
    }

    private static func nativePayload(
        for item: ClipboardItem
    ) throws -> (data: Data, filename: String, contentType: UTType) {
        if item.type == ClipboardItemType.file,
           let value = item.plainText,
           let url = URL(string: value),
           url.isFileURL {
            return (
                try Data(contentsOf: url),
                url.lastPathComponent,
                UTType(filenameExtension: url.pathExtension) ?? .data
            )
        }

        let data = item.imageData
            ?? item.rawData
            ?? item.plainText?.data(using: .utf8)
        guard let data else {
            throw ClipboardExportError.missingPayload
        }
        let contentType = item.utiType.flatMap(UTType.init) ?? fallbackType(for: item)
        let fileExtension = contentType.preferredFilenameExtension ?? fallbackExtension(for: item)
        let baseName = sanitizedFilename(item.displayTitle)
        return (data, "\(baseName).\(fileExtension)", contentType)
    }

    private static func sharingItem(for item: ClipboardItem) throws -> Any? {
        if item.type == ClipboardItemType.file,
           let value = item.plainText,
           let url = URL(string: value),
           url.isFileURL {
            return url as NSURL
        }
        if item.type == ClipboardItemType.url,
           let value = item.plainText,
           let url = URL(string: value) {
            return url as NSURL
        }
        if let image = item.image {
            return image
        }
        if let text = item.plainText {
            return text as NSString
        }

        let payload = try nativePayload(for: item)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clipboard Bro Sharing", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(payload.filename)
        try payload.data.write(to: url, options: .atomic)
        return url as NSURL
    }

    private static func fallbackType(for item: ClipboardItem) -> UTType {
        switch item.type {
        case ClipboardItemType.image:
            return .png
        case ClipboardItemType.pdf:
            return .pdf
        case ClipboardItemType.json:
            return .json
        case ClipboardItemType.xml:
            return .xml
        default:
            return .data
        }
    }

    private static func fallbackExtension(for item: ClipboardItem) -> String {
        item.type == ClipboardItemType.text ? "txt" : "data"
    }

    private static func sanitizedFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        let components = value.components(separatedBy: invalid)
        let cleaned = components.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Clipboard Item" : String(cleaned.prefix(80))
    }

    private static func encode(_ value: String) throws -> Data {
        guard let data = value.data(using: .utf8) else {
            throw ClipboardExportError.unableToEncode
        }
        return data
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private struct ClipboardExportRecord {
    let title: String
    let type: String
    let source: String
    let createdAt: String
    let tags: String
    let content: String

    init(item: ClipboardItem) {
        title = item.displayTitle
        type = item.displayType
        source = item.sourceApp ?? ""
        createdAt = item.createdAt?.ISO8601Format() ?? ""
        tags = item.tags.joined(separator: ", ")
        content = item.plainText ?? item.previewText ?? ""
    }

    var jsonObject: [String: Any] {
        [
            "title": title,
            "type": type,
            "source": source,
            "createdAt": createdAt,
            "tags": tags,
            "content": content
        ]
    }
}
