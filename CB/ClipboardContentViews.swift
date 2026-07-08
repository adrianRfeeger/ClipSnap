import AppKit
import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardItemPreview: View {
    @ObservedObject var item: ClipboardItem
    let saveTextAction: (String) -> Void
    let recognizeTextAction: () -> Void
    let editImageAction: () -> Void

    var body: some View {
        switch item.type {
        case ClipboardItemType.image:
            imagePreview
        case ClipboardItemType.text,
            ClipboardItemType.url,
            ClipboardItemType.json,
            ClipboardItemType.xml,
            ClipboardItemType.sourceCode,
            ClipboardItemType.tabularText,
            ClipboardItemType.contact:
            EditableTextPreview(
                text: item.plainText ?? item.previewText ?? "",
                itemType: item.type ?? ClipboardItemType.text,
                saveAction: saveTextAction
            )
        case ClipboardItemType.file:
            ScrollView {
                Text(item.plainText ?? item.previewText ?? "")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case ClipboardItemType.color:
            ColorClipboardPreview(item: item)
        case ClipboardItemType.rtf:
            richPreview(documentType: .rtf, title: "Rich Text")
        case ClipboardItemType.rtfd:
            richPreview(documentType: .rtfd, title: "RTFD")
        case ClipboardItemType.html:
            htmlPreview
        case ClipboardItemType.pdf:
            if let rawData = item.rawData {
                PDFClipboardPreview(data: rawData)
            } else {
                ContentUnavailableView("PDF Unavailable", systemImage: "doc.fill")
            }
        case ClipboardItemType.audio, ClipboardItemType.video:
            if let data = item.rawData ?? item.sortedRepresentations.compactMap(\.data).first {
                MediaClipboardPreview(data: data, utiIdentifier: item.utiType)
            } else {
                ContentUnavailableView(item.displayType, systemImage: item.systemImageName)
            }
        case ClipboardItemType.archive, ClipboardItemType.data:
            if item.type == ClipboardItemType.archive, let data = item.rawData {
                ArchiveClipboardPreview(data: data, utiIdentifier: item.utiType)
            } else {
                ContentUnavailableView(
                    item.displayType,
                    systemImage: "doc",
                    description: Text(item.utiType ?? "Stored binary pasteboard data")
                )
            }
        default:
            ContentUnavailableView(
                "No Preview",
                systemImage: "questionmark.square",
                description: Text(item.utiType ?? "Unknown pasteboard format")
            )
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = previewImage {
            VStack(spacing: 12) {
                ResponsiveImageCanvas(image: image)

                HStack {
                    Button("Edit Image") {
                        editImageAction()
                    }

                    Button("Recognize Text") {
                        recognizeTextAction()
                    }
                    .disabled(item.imageData == nil)
                }
            }
        } else {
            ContentUnavailableView("Image Unavailable", systemImage: "photo")
        }
    }

    private var previewImage: NSImage? {
        if let image = item.image {
            return image
        }

        if let thumbnailData = item.thumbnailData,
           let image = NSImage(data: thumbnailData) {
            return image
        }

        if let rawData = item.rawData,
           let image = NSImage(data: rawData) {
            return image
        }

        for representation in item.sortedRepresentations {
            if let data = representation.data,
               let image = NSImage(data: data) {
                return image
            }
        }

        return nil
    }

    @ViewBuilder
    private func richPreview(
        documentType: NSAttributedString.DocumentType,
        title: String
    ) -> some View {
        if let payload = richTextPayload(for: documentType) {
            RichClipboardPreview(
                data: payload.data,
                documentType: documentType,
                fallbackText: richTextFallbackText
            )
            .frame(minHeight: 180)
            .frame(height: richTextPreviewHeight(for: payload.text))
            .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        } else if !richTextFallbackText.isEmpty {
            ScrollView {
                Text(richTextFallbackText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 180)
            .frame(height: richTextPreviewHeight(for: richTextFallbackText))
            .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        } else {
            ContentUnavailableView("\(title) Unavailable", systemImage: "doc.richtext")
        }
    }

    private var richTextFallbackText: String {
        let directText = [
            item.plainText,
            item.previewText
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "Rich text" && $0 != "RTFD" }

        if let directText {
            return directText
        }

        return item.sortedRepresentations
            .compactMap(representationText)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func richTextPreviewHeight(for text: String) -> CGFloat {
        let lineCount = max(1, text.components(separatedBy: .newlines).count)
        return min(max(CGFloat(lineCount) * 24 + 56, 180), 420)
    }

    private func richTextPayload(for documentType: NSAttributedString.DocumentType) -> RichTextPayload? {
        let preferredTypeIdentifiers: [String]
        switch documentType {
        case .rtf:
            preferredTypeIdentifiers = [
                UTType.rtf.identifier,
                "public.rtf"
            ]
        case .rtfd:
            preferredTypeIdentifiers = [
                UTType.rtfd.identifier,
                UTType.flatRTFD.identifier,
                "com.apple.flat-rtfd",
                "com.apple.rtfd"
            ]
        default:
            preferredTypeIdentifiers = []
        }

        let representationData = item.sortedRepresentations
            .filter { representation in
                guard let identifier = representation.utiIdentifier else {
                    return false
                }

                return preferredTypeIdentifiers.contains(identifier)
            }
            .compactMap(\.data)

        if let rawData = item.rawData,
           let payload = decodedRichTextPayload(rawData, as: documentType) {
            return payload
        }

        return representationData
            .compactMap { decodedRichTextPayload($0, as: documentType) }
            .max { $0.text.count < $1.text.count }
    }

    private func decodedRichTextPayload(
        _ data: Data,
        as documentType: NSAttributedString.DocumentType
    ) -> RichTextPayload? {
        guard let attributedString = try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        ) else {
            return nil
        }

        let text = attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        return RichTextPayload(data: data, text: text)
    }

    private func representationText(_ representation: ClipboardRepresentation) -> String? {
        if let stringValue = representation.stringValue {
            return stringValue
        }

        guard let data = representation.data,
              let identifier = representation.utiIdentifier else {
            return nil
        }

        let textIdentifiers = Set([
            NSPasteboard.PasteboardType.string.rawValue,
            UTType.plainText.identifier,
            UTType.utf8PlainText.identifier,
            "public.utf16-external-plain-text"
        ])

        guard textIdentifiers.contains(identifier) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .ascii)
    }

    @ViewBuilder
    private var htmlPreview: some View {
        if let htmlString {
            HTMLFormattedClipboardPreview(
                htmlString: htmlString,
                plainText: item.plainText ?? item.previewText ?? ""
            )
        } else {
            ContentUnavailableView("HTML Unavailable", systemImage: "chevron.left.forwardslash.chevron.right")
        }
    }

    private var htmlString: String? {
        guard let data = item.rawData else {
            return nil
        }

        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
    }
}

private struct RichTextPayload {
    let data: Data
    let text: String
}

private struct ResponsiveImageCanvas: View {
    let image: NSImage

    var body: some View {
        GeometryReader { proxy in
            let canvasHeight = canvasHeight(for: proxy.size.width)

            Image(nsImage: image)
                .resizable()
                .aspectRatio(imageAspectRatio, contentMode: .fit)
                .frame(
                    width: proxy.size.width,
                    height: canvasHeight,
                    alignment: .center
                )
                .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(minHeight: minimumHeight)
        .frame(height: preferredHeight)
    }

    private var preferredHeight: CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1_200
        return canvasHeight(for: min(screenWidth * 0.58, 900))
    }

    private var imageAspectRatio: CGFloat {
        let size = image.pixelSize
        guard size.width > 0, size.height > 0 else {
            return 1
        }

        return size.width / size.height
    }

    private var minimumHeight: CGFloat {
        240
    }

    private var maximumHeight: CGFloat {
        720
    }

    private func canvasHeight(for width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else {
            return minimumHeight
        }

        return min(max(width / imageAspectRatio, minimumHeight), maximumHeight)
    }
}

private extension NSImage {
    var pixelSize: CGSize {
        if let representation = representations.max(by: {
            ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
        }), representation.pixelsWide > 0, representation.pixelsHigh > 0 {
            return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }

        return size
    }
}

private struct HTMLFormattedClipboardPreview: View {
    enum Mode: String, CaseIterable, Identifiable {
        case rendered
        case text
        case source

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rendered:
                return "Rendered"
            case .text:
                return "Text"
            case .source:
                return "Source"
            }
        }
    }

    let htmlString: String
    let plainText: String

    @State private var mode: Mode = .rendered

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("HTML Preview Mode", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)

            Group {
                switch mode {
                case .rendered:
                    HTMLClipboardPreview(htmlString: htmlString, fallbackText: displayText)
                        .frame(maxWidth: .infinity, minHeight: 280)
                case .text:
                    ScrollView {
                        Text(displayText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                case .source:
                    ScrollView {
                        Text(HTMLClipboardPreview.normalizedSource(from: htmlString))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                }
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var displayText: String {
        let trimmedText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            return trimmedText
        }

        return HTMLTextExtractor.plainText(from: htmlString)
    }
}

private enum HTMLTextExtractor {
    static func plainText(from htmlString: String) -> String {
        var text = htmlString
        text = text.replacingOccurrences(
            of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>",
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</div\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct EditableTextPreview: View {
    let itemType: String
    let saveAction: (String) -> Void

    @State private var text: String
    @State private var savedText: String
    @State private var isEditing = false

    init(text: String, itemType: String, saveAction: @escaping (String) -> Void) {
        self.itemType = itemType
        self.saveAction = saveAction
        _text = State(initialValue: ClipboardTextFormatter.formatted(text, itemType: itemType))
        _savedText = State(initialValue: text)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if isEditing {
                TextEditor(text: $text)
                    .font(.system(.body, design: usesMonospacedFont ? .monospaced : .default))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    Text(ClipboardSyntaxHighlighter.highlighted(text, itemType: itemType))
                        .font(.system(.body, design: usesMonospacedFont ? .monospaced : .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Picker("Mode", selection: $isEditing) {
                    Text("Preview").tag(false)
                    Text("Edit").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)

                if itemType == ClipboardItemType.json || itemType == ClipboardItemType.xml {
                    Button("Format") {
                        text = ClipboardTextFormatter.formatted(text, itemType: itemType)
                    }
                }

                Menu("Transform") {
                    ForEach(ClipboardTextTransformation.allCases) { transformation in
                        Button(transformation.title) {
                            text = transformation.apply(to: text)
                            isEditing = true
                        }
                    }
                }

                Spacer()

                Button("Revert") {
                    text = savedText
                }
                .disabled(text == savedText)

                Button("Save") {
                    saveAction(text)
                    savedText = text
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(text == savedText)
            }
        }
    }

    private var usesMonospacedFont: Bool {
        itemType == ClipboardItemType.json
            || itemType == ClipboardItemType.xml
            || itemType == ClipboardItemType.sourceCode
            || itemType == ClipboardItemType.tabularText
    }

}

enum ClipboardTextFormatter {
    static func formatted(_ text: String, itemType: String) -> String {
        if itemType == ClipboardItemType.json,
           let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let formattedData = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
           ),
           let formatted = String(data: formattedData, encoding: .utf8) {
            return formatted
        }

        if itemType == ClipboardItemType.xml,
           let document = try? XMLDocument(
            xmlString: text,
            options: [.nodePreserveWhitespace]
           ),
           let formatted = String(
            data: document.xmlData(options: [.nodePrettyPrint]),
            encoding: .utf8
           ) {
            return formatted
        }

        return text
    }
}

enum ClipboardTextTransformation: String, CaseIterable, Identifiable {
    case trimWhitespace
    case uppercase
    case lowercase
    case removeBlankLines
    case removeTrackingParameters

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .trimWhitespace:
            return "Trim Whitespace"
        case .uppercase:
            return "Uppercase"
        case .lowercase:
            return "Lowercase"
        case .removeBlankLines:
            return "Remove Blank Lines"
        case .removeTrackingParameters:
            return "Remove URL Tracking Parameters"
        }
    }

    func apply(to text: String) -> String {
        switch self {
        case .trimWhitespace:
            return text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .removeBlankLines:
            return text
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")
        case .removeTrackingParameters:
            guard var components = URLComponents(
                string: text.trimmingCharacters(in: .whitespacesAndNewlines)
            ), components.scheme != nil else {
                return text
            }
            let trackingNames = ["fbclid", "gclid", "dclid", "mc_cid", "mc_eid"]
            components.queryItems = components.queryItems?.filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !trackingNames.contains(name)
            }
            if components.queryItems?.isEmpty == true {
                components.queryItems = nil
            }
            return components.string ?? text
        }
    }
}

enum ClipboardTextMerger {
    static func merge(_ values: [String], separator: String = "\n\n") -> String {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }
}

private enum ClipboardSyntaxHighlighter {
    static func highlighted(_ text: String, itemType: String) -> AttributedString {
        var result = AttributedString(text)

        if itemType == ClipboardItemType.json {
            apply(#""(?:\\.|[^"\\])*""#, color: .green, text: text, result: &result)
            apply(#"\b(?:true|false|null)\b"#, color: .purple, text: text, result: &result)
        } else if itemType == ClipboardItemType.xml {
            apply(#"<[^>]+>"#, color: .blue, text: text, result: &result)
        } else if itemType == ClipboardItemType.sourceCode {
            apply(
                #"\b(?:class|struct|func|let|var|if|else|for|while|return|import|enum|protocol|async|await|throw|throws)\b"#,
                color: .purple,
                text: text,
                result: &result
            )
            apply(#""(?:\\.|[^"\\])*""#, color: .green, text: text, result: &result)
        }

        if itemType == ClipboardItemType.json || itemType == ClipboardItemType.sourceCode {
            apply(#"\b-?\d+(?:\.\d+)?\b"#, color: .orange, text: text, result: &result)
        }
        return result
    }

    private static func apply(
        _ pattern: String,
        color: Color,
        text: String,
        result: inout AttributedString
    ) {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return
        }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in expression.matches(in: text, range: fullRange) {
            guard let stringRange = Range(match.range, in: text),
                  let attributedRange = Range(stringRange, in: result) else {
                continue
            }
            result[attributedRange].foregroundColor = color
        }
    }
}

private struct ColorClipboardPreview: View {
    let item: ClipboardItem

    var body: some View {
        VStack(spacing: 14) {
            if let value = item.plainText,
               let color = Color(hexString: value) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Text(item.plainText ?? item.previewText ?? "Color")
                .font(.system(.title3, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

private struct MediaClipboardPreview: NSViewRepresentable {
    let data: Data
    let utiIdentifier: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        updatePlayer(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard context.coordinator.dataHash != data.hashValue else {
            return
        }
        updatePlayer(view, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        coordinator.removeTemporaryFile()
    }

    private func updatePlayer(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.removeTemporaryFile()
        let fileExtension = utiIdentifier
            .flatMap(UTType.init)?
            .preferredFilenameExtension ?? "media"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        do {
            try data.write(to: url, options: .atomic)
            coordinator.temporaryURL = url
            coordinator.dataHash = data.hashValue
            view.player = AVPlayer(url: url)
        } catch {
            view.player = nil
        }
    }

    final class Coordinator {
        var temporaryURL: URL?
        var dataHash: Int?

        func removeTemporaryFile() {
            if let temporaryURL {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            temporaryURL = nil
            dataHash = nil
        }
    }
}

private extension Color {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 || hex.count == 8,
              let value = UInt64(hex, radix: 16) else {
            return nil
        }

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        if hex.count == 8 {
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        } else {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        }
        self.init(red: red, green: green, blue: blue, opacity: alpha)
    }
}
