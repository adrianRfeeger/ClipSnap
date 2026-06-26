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
            richPreview(documentType: .html, title: "HTML")
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
        if let image = item.image {
            VStack(spacing: 12) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

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

    @ViewBuilder
    private func richPreview(
        documentType: NSAttributedString.DocumentType,
        title: String
    ) -> some View {
        if let rawData = item.rawData {
            RichClipboardPreview(data: rawData, documentType: documentType)
        } else {
            ContentUnavailableView("\(title) Unavailable", systemImage: "doc.richtext")
        }
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
