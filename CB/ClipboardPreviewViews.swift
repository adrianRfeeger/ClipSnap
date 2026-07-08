import AppKit
import PDFKit
import SwiftUI

struct PDFClipboardPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}

struct RichClipboardPreview: NSViewRepresentable {
    let data: Data
    let documentType: NSAttributedString.DocumentType
    let fallbackText: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        let decodedString = try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        )
        let attributedString = decodedString.flatMap { readableAttributedString($0) }
        textView.textStorage?.setAttributedString(
            attributedString ?? NSAttributedString(
                string: fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Preview unavailable"
                    : fallbackText
            )
        )
    }

    private func readableAttributedString(_ attributedString: NSAttributedString) -> NSAttributedString? {
        guard !attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)
        mutableString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        return mutableString
    }
}

struct HTMLClipboardPreview: NSViewRepresentable {
    let htmlString: String
    let fallbackText: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        let html = Self.previewDocument(from: htmlString, fallbackText: fallbackText)
        guard context.coordinator.loadedHTML != html else {
            return
        }

        context.coordinator.loadedHTML = html
        textView.textStorage?.setAttributedString(
            Self.attributedString(from: html, fallbackText: fallbackText)
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var loadedHTML: String?
    }

    static func normalizedSource(from htmlString: String) -> String {
        decodeTagEntities(in: normalizedClipboardHTML(from: htmlString))
    }

    private static func previewDocument(from htmlString: String, fallbackText: String) -> String {
        let normalizedHTML = normalizedClipboardHTML(from: htmlString)
        let sanitizedHTML = normalizedHTML.replacingOccurrences(
            of: "(?is)<script\\b[^>]*>.*?</script>",
            with: "",
            options: .regularExpression
        )
        let renderableHTML = decodeTagEntities(in: sanitizedHTML)
        let escapedFallback = escapeHTML(fallbackText.trimmingCharacters(in: .whitespacesAndNewlines))
        let style = """
        <style>
        :root { color-scheme: light dark; }
        html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: #1d1d1f;
            font: -apple-system-body, -apple-system, BlinkMacSystemFont, sans-serif;
            overflow-wrap: anywhere;
        }
        body, body * {
            color: #1d1d1f !important;
            background-color: transparent !important;
        }
        body { padding: 16px; }
        img, video, canvas, svg { max-width: 100%; height: auto; }
        table { border-collapse: collapse; max-width: 100%; }
        td, th { border: 1px solid rgba(128, 128, 128, 0.35); padding: 4px 6px; vertical-align: top; }
        pre, code {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            white-space: pre-wrap;
        }
        a { color: -webkit-link; }
        blockquote {
            border-left: 3px solid rgba(128, 128, 128, 0.45);
            margin-left: 0;
            padding-left: 12px;
        }
        .clipsnap-empty {
            color: rgba(128, 128, 128, 0.95);
            font: -apple-system-body, -apple-system, BlinkMacSystemFont, sans-serif;
            white-space: pre-wrap;
        }
        @media (prefers-color-scheme: dark) {
            html, body,
            body, body * {
                color: #f5f5f7 !important;
                background-color: transparent !important;
            }
            a { color: #8ab4f8 !important; }
        }
        </style>
        """
        let fallbackBody = escapedFallback.isEmpty
            ? "<div class=\"clipsnap-empty\">No renderable HTML content.</div>"
            : "<div class=\"clipsnap-empty\">\(escapedFallback)</div>"

        let lowercasedHTML = renderableHTML.lowercased()
        if lowercasedHTML.contains("<html") {
            let htmlWithFallback = renderableHTML.replacingOccurrences(
                of: "(?i)<body([^>]*)>\\s*</body>",
                with: "<body$1>\(fallbackBody)</body>",
                options: .regularExpression
            )
            if lowercasedHTML.contains("</head>") {
                return htmlWithFallback.replacingOccurrences(
                    of: "(?i)</head>",
                    with: "\(style)</head>",
                    options: .regularExpression
                )
            }

            return htmlWithFallback.replacingOccurrences(
                of: "(?i)<html[^>]*>",
                with: "$0<head>\(style)</head>",
                options: .regularExpression
            )
        }

        return """
        <!doctype html>
        <html>
        <head>
        \(style)
        </head>
        <body>
        \(renderableHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackBody : renderableHTML)
        </body>
        </html>
        """
    }

    private static func attributedString(from html: String, fallbackText: String) -> NSAttributedString {
        let fallback = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = html.data(using: .utf8),
              let attributedString = try? NSMutableAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ),
              !attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NSAttributedString(string: fallback.isEmpty ? "Preview unavailable" : fallback)
        }

        let fullRange = NSRange(location: 0, length: attributedString.length)
        let textColor = NSColor.labelColor
        attributedString.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            if value == nil {
                attributedString.addAttribute(.foregroundColor, value: textColor, range: range)
            }
        }
        attributedString.addAttribute(.backgroundColor, value: NSColor.clear, range: fullRange)
        return attributedString
    }

    private static func normalizedClipboardHTML(from htmlString: String) -> String {
        let trimmed = htmlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fragment = htmlClipboardFragment(from: trimmed), !fragment.isEmpty {
            return fragment
        }
        if let htmlRange = range(from: trimmed, startKey: "StartHTML", endKey: "EndHTML") {
            return String(trimmed[htmlRange])
        }
        if let documentStart = trimmed.range(
            of: "(?is)<!doctype\\s+html[^>]*>|<html\\b",
            options: .regularExpression
        ) {
            return String(trimmed[documentStart.lowerBound...])
        }
        return trimmed
    }

    private static func htmlClipboardFragment(from htmlString: String) -> String? {
        if let range = range(from: htmlString, startKey: "StartFragment", endKey: "EndFragment") {
            return String(htmlString[range])
        }

        guard let start = htmlString.range(of: "<!--StartFragment-->", options: .caseInsensitive),
              let end = htmlString.range(of: "<!--EndFragment-->", options: .caseInsensitive),
              start.upperBound <= end.lowerBound else {
            return nil
        }

        return String(htmlString[start.upperBound..<end.lowerBound])
    }

    private static func range(from htmlString: String, startKey: String, endKey: String) -> Range<String.Index>? {
        guard let startOffset = clipboardOffset(named: startKey, in: htmlString),
              let endOffset = clipboardOffset(named: endKey, in: htmlString),
              startOffset >= 0,
              endOffset > startOffset,
              let startIndex = htmlString.index(htmlString.startIndex, offsetBy: startOffset, limitedBy: htmlString.endIndex),
              let endIndex = htmlString.index(htmlString.startIndex, offsetBy: endOffset, limitedBy: htmlString.endIndex),
              startIndex <= endIndex else {
            return nil
        }

        return startIndex..<endIndex
    }

    private static func clipboardOffset(named key: String, in htmlString: String) -> Int? {
        guard let range = htmlString.range(
            of: "(?im)^\(key):\\s*(\\d+)",
            options: .regularExpression
        ) else {
            return nil
        }

        let line = String(htmlString[range])
        return line
            .split(separator: ":", maxSplits: 1)
            .last
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func decodeTagEntities(in htmlString: String) -> String {
        var result = ""
        var currentIndex = htmlString.startIndex
        while let tagStart = htmlString[currentIndex...].firstIndex(of: "<"),
              let tagEnd = htmlString[tagStart...].firstIndex(of: ">") {
            result.append(contentsOf: htmlString[currentIndex..<tagStart])
            let tag = String(htmlString[tagStart...tagEnd])
            result.append(decodeHTMLAttributeEntities(tag))
            currentIndex = htmlString.index(after: tagEnd)
        }
        result.append(contentsOf: htmlString[currentIndex...])
        return result
    }

    private static func decodeHTMLAttributeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#x22;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
    }
}
