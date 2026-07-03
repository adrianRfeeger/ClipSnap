import AppKit
import CoreData
import UniformTypeIdentifiers
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

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

enum ClipboardGeneratedMetadataStatus: String, Codable, Sendable {
    case pending
    case suggested
    case accepted
    case rejected
    case failed
}

struct ClipboardGeneratedMetadata: Codable, Equatable, Sendable {
    var suggestedTitle: String?
    var suggestedTags: [String]
    var suggestedCollection: String?
    var summary: String?
    var contentCategory: String?
    var detectedEntities: [String]
    var confidence: Double?
    var generatedAt: Date?
    var modelVersion: String?
    var status: ClipboardGeneratedMetadataStatus
    var failureReason: String?

    init(
        suggestedTitle: String? = nil,
        suggestedTags: [String] = [],
        suggestedCollection: String? = nil,
        summary: String? = nil,
        contentCategory: String? = nil,
        detectedEntities: [String] = [],
        confidence: Double? = nil,
        generatedAt: Date? = nil,
        modelVersion: String? = nil,
        status: ClipboardGeneratedMetadataStatus = .pending,
        failureReason: String? = nil
    ) {
        self.suggestedTitle = suggestedTitle?.normalizedGeneratedMetadataText
        self.suggestedTags = suggestedTags.normalizedGeneratedMetadataList
        self.suggestedCollection = suggestedCollection?.normalizedGeneratedMetadataText
        self.summary = summary?.normalizedGeneratedMetadataText
        self.contentCategory = contentCategory?.normalizedGeneratedMetadataText
        self.detectedEntities = detectedEntities.normalizedGeneratedMetadataList
        self.confidence = confidence.map { min(max($0, 0), 1) }
        self.generatedAt = generatedAt
        self.modelVersion = modelVersion?.normalizedGeneratedMetadataText
        self.status = status
        self.failureReason = failureReason?.normalizedGeneratedMetadataText
    }

    var hasSuggestions: Bool {
        suggestedTitle != nil
            || !suggestedTags.isEmpty
            || suggestedCollection != nil
            || summary != nil
            || contentCategory != nil
            || !detectedEntities.isEmpty
    }

    var modelVersionDisplayName: String {
        switch modelVersion {
        case "apple-intelligence-foundationmodels":
            return "Apple Intelligence"
        case "local-rules-v1":
            return "Local rules"
        case let value?:
            return value
        case nil:
            return "Generated"
        }
    }
}

enum ClipboardGeneratedMetadataStore {
    static func metadata(
        for itemIdentifier: UUID,
        defaults: UserDefaults = .standard
    ) -> ClipboardGeneratedMetadata? {
        allMetadata(defaults: defaults)[itemIdentifier.uuidString]
    }

    static func save(
        _ metadata: ClipboardGeneratedMetadata,
        for itemIdentifier: UUID,
        defaults: UserDefaults = .standard
    ) {
        var values = allMetadata(defaults: defaults)
        values[itemIdentifier.uuidString] = metadata
        saveAll(values, defaults: defaults)
    }

    static func remove(
        for itemIdentifier: UUID,
        defaults: UserDefaults = .standard
    ) {
        var values = allMetadata(defaults: defaults)
        values.removeValue(forKey: itemIdentifier.uuidString)
        saveAll(values, defaults: defaults)
    }

    private static func allMetadata(defaults: UserDefaults) -> [String: ClipboardGeneratedMetadata] {
        guard let data = defaults.data(forKey: ClipboardSettingKey.generatedClipboardMetadata),
              let values = try? JSONDecoder().decode([String: ClipboardGeneratedMetadata].self, from: data) else {
            return [:]
        }
        return values
    }

    private static func saveAll(
        _ values: [String: ClipboardGeneratedMetadata],
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(values) else {
            return
        }
        defaults.set(data, forKey: ClipboardSettingKey.generatedClipboardMetadata)
    }
}

struct ClipboardMetadataSuggestionService {
    func suggestions(for item: ClipboardItem) async -> ClipboardGeneratedMetadata {
        let imageAnalysis = imageAnalysis(for: item)

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                return try await appleIntelligenceSuggestions(for: item, imageAnalysis: imageAnalysis)
            } catch {
                var fallback = localSuggestions(for: item, imageAnalysis: imageAnalysis)
                fallback.failureReason = "Apple Intelligence unavailable: \(error.localizedDescription)"
                return fallback
            }
        }
        #endif

        return localSuggestions(for: item, imageAnalysis: imageAnalysis)
    }

    private func localSuggestions(
        for item: ClipboardItem,
        imageAnalysis: ClipboardImageAnalysis = .empty
    ) -> ClipboardGeneratedMetadata {
        let sourceText = readableText(for: item)
        let title = suggestedTitle(for: item, sourceText: sourceText)
        let tags = suggestedTags(for: item, sourceText: sourceText, imageAnalysis: imageAnalysis)
        let collection = suggestedCollection(for: item, sourceText: sourceText)
        let summary = suggestedSummary(for: item, sourceText: sourceText)

        return ClipboardGeneratedMetadata(
            suggestedTitle: title,
            suggestedTags: tags,
            suggestedCollection: collection,
            summary: summary,
            contentCategory: imageAnalysis.primaryLabel ?? item.displayType,
            detectedEntities: detectedEntities(in: sourceText) + imageAnalysis.labels,
            confidence: imageAnalysis.labels.isEmpty
                ? (sourceText.isEmpty ? 0.35 : 0.55)
                : max(0.55, Double(imageAnalysis.topConfidence ?? 0)),
            generatedAt: Date(),
            modelVersion: "local-rules-v1",
            status: .suggested
        )
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func appleIntelligenceSuggestions(
        for item: ClipboardItem,
        imageAnalysis: ClipboardImageAnalysis
    ) async throws -> ClipboardGeneratedMetadata {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw ClipboardMetadataSuggestionError.modelUnavailable
        }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You generate concise clipboard metadata for ClipSnap. Return only valid JSON. Do not include Markdown fences or commentary. Keep titles short, tags lowercase, and summaries factual.
            """
        )
        let response = try await session.respond(to: prompt(for: item, imageAnalysis: imageAnalysis))
        let payload = try decodeAppleIntelligencePayload(from: response.content)

        return sanitizedMetadata(
            ClipboardGeneratedMetadata(
                suggestedTitle: payload.title,
                suggestedTags: payload.tags,
                suggestedCollection: payload.collection,
                summary: payload.summary,
                contentCategory: payload.category,
                detectedEntities: payload.entities,
                confidence: payload.confidence,
                generatedAt: Date(),
                modelVersion: "apple-intelligence-foundationmodels",
                status: .suggested
            ),
            item: item,
            imageAnalysis: imageAnalysis
        )
    }
    #endif

    private func sanitizedMetadata(
        _ metadata: ClipboardGeneratedMetadata,
        item: ClipboardItem,
        imageAnalysis: ClipboardImageAnalysis
    ) -> ClipboardGeneratedMetadata {
        let fallback = localSuggestions(for: item, imageAnalysis: imageAnalysis)
        let genericValues = genericMetadataValues(for: item)
        let title = metadata.suggestedTitle
            .flatMap { genericValues.contains($0.normalizedMetadataComparisonKey) ? nil : $0 }
            ?? fallback.suggestedTitle
        let collection = metadata.suggestedCollection
            .flatMap { genericValues.contains($0.normalizedMetadataComparisonKey) ? nil : $0 }
            ?? fallback.suggestedCollection
        let summary = metadata.summary
            .flatMap { genericValues.contains($0.normalizedMetadataComparisonKey) ? nil : $0 }
        let tags = (metadata.suggestedTags + fallback.suggestedTags)
            .filter { !genericValues.contains($0.normalizedMetadataComparisonKey) || $0 != title }
            .normalizedGeneratedMetadataList

        return ClipboardGeneratedMetadata(
            suggestedTitle: title,
            suggestedTags: tags,
            suggestedCollection: collection,
            summary: summary,
            contentCategory: metadata.contentCategory ?? fallback.contentCategory,
            detectedEntities: (metadata.detectedEntities + fallback.detectedEntities).normalizedGeneratedMetadataList,
            confidence: metadata.confidence ?? fallback.confidence,
            generatedAt: metadata.generatedAt ?? Date(),
            modelVersion: metadata.modelVersion,
            status: .suggested
        )
    }

    private func genericMetadataValues(for item: ClipboardItem) -> Set<String> {
        Set([
            item.displayType,
            item.type ?? "",
            "clipboard item",
            "image",
            "picture",
            "photo",
            "data",
            "unknown"
        ].map(\.normalizedMetadataComparisonKey))
    }

    private func prompt(for item: ClipboardItem, imageAnalysis: ClipboardImageAnalysis) -> String {
        let sourceText = readableText(for: item)
            .singleLineGeneratedMetadataText
            .truncatedGeneratedMetadataText(limit: 2_000)
        let sourceApp = item.sourceApp?.normalizedGeneratedMetadataText ?? "Unknown"
        let utiType = item.utiType?.normalizedGeneratedMetadataText ?? "Unknown"
        let existingTags = item.tags.joined(separator: ", ")
        let imageDescription = imageAnalysis.promptDescription

        return """
        Analyze this clipboard item and suggest metadata.

        Return JSON matching this shape:
        {
          "title": "short title",
          "tags": ["short", "lowercase", "tags"],
          "collection": "optional collection name or null",
          "summary": "optional short summary or null",
          "category": "short category",
          "entities": ["important visible entities"],
          "confidence": 0.0
        }

        Rules:
        - Title must be 8 words or fewer.
        - Use 3 to 8 tags.
        - Never use the item type alone as the title, collection, or summary.
        - For images, use Vision labels, dimensions, OCR text, and source app to make a specific guess.
        - If no specific visual detail is available, return null for summary.
        - Do not invent facts that are not visible in the item.
        - Prefer readable user content over private pasteboard type names.
        - If the content is empty or app-private metadata, use the source app and type.

        Clipboard item:
        Type: \(item.displayType)
        UTI: \(utiType)
        Source app: \(sourceApp)
        Existing tags: \(existingTags.isEmpty ? "None" : existingTags)
        Image analysis: \(imageDescription)
        Text: \(sourceText.isEmpty ? "None" : sourceText)
        """
    }

    private func decodeAppleIntelligencePayload(from response: String) throws -> ClipboardAppleIntelligenceMetadataPayload {
        let json = response.extractedJSONObjectString
        guard let data = json.data(using: .utf8) else {
            throw ClipboardMetadataSuggestionError.invalidModelResponse
        }

        return try JSONDecoder().decode(ClipboardAppleIntelligenceMetadataPayload.self, from: data)
    }

    private func readableText(for item: ClipboardItem) -> String {
        [
            item.plainText,
            item.recognizedText,
            item.previewText
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func suggestedTitle(for item: ClipboardItem, sourceText: String) -> String {
        if !sourceText.isEmpty,
           !isGenericTitle(sourceText, for: item) {
            return sourceText
                .singleLineGeneratedMetadataText
                .truncatedGeneratedMetadataText(limit: 72)
        }

        if let sourceTitle = sourceAwareTitle(for: item) {
            return sourceTitle
        }

        if item.type == ClipboardItemType.image,
           let image = item.image {
            let dimensions = "\(Int(image.size.width))x\(Int(image.size.height))"
            return "Image - \(dimensions)"
        }

        return item.displayType
    }

    private func suggestedTags(
        for item: ClipboardItem,
        sourceText: String,
        imageAnalysis: ClipboardImageAnalysis
    ) -> [String] {
        var tags: [String] = [item.displayType.lowercased()]

        if let sourceApp = item.sourceApp?.normalizedGeneratedMetadataText {
            tags.append(sourceApp)
        }

        if item.isScreenCapture {
            tags.append("screenshot")
        }

        if item.isOCRCapture || item.recognizedText?.isEmpty == false {
            tags.append("ocr")
        }

        if item.type == ClipboardItemType.url {
            tags.append("link")
        }

        if item.type == ClipboardItemType.html {
            tags.append("html")
        }

        if item.type == ClipboardItemType.json || item.type == ClipboardItemType.xml {
            tags.append("structured data")
        }

        if item.type == ClipboardItemType.sourceCode || sourceText.looksLikeCode {
            tags.append("code")
        }

        tags.append(contentsOf: imageAnalysis.labels)

        if sourceText.looksLikeEmailAddress {
            tags.append("email")
        }

        return tags.normalizedGeneratedMetadataList
    }

    private func suggestedCollection(for item: ClipboardItem, sourceText: String) -> String? {
        if item.isScreenCapture {
            return "Screenshots"
        }

        switch item.type {
        case ClipboardItemType.url:
            return "Links"
        case ClipboardItemType.image:
            return "Images"
        case ClipboardItemType.video:
            return "Recordings"
        case ClipboardItemType.sourceCode, ClipboardItemType.json, ClipboardItemType.xml:
            return "Code"
        default:
            if sourceText.looksLikeEmailAddress {
                return "Contacts"
            }
            return nil
        }
    }

    private func suggestedSummary(for item: ClipboardItem, sourceText: String) -> String? {
        guard sourceText.count > 120 else {
            return nil
        }

        return sourceText
            .singleLineGeneratedMetadataText
            .truncatedGeneratedMetadataText(limit: 180)
    }

    private func detectedEntities(in sourceText: String) -> [String] {
        var entities: [String] = []
        if let emailAddress = sourceText.firstEmailAddress {
            entities.append(emailAddress)
        }
        return entities.normalizedGeneratedMetadataList
    }

    private func imageAnalysis(for item: ClipboardItem) -> ClipboardImageAnalysis {
        guard item.type == ClipboardItemType.image,
              let imageData = item.imageData ?? item.thumbnailData else {
            return .empty
        }

        let labels = classifyImage(data: imageData)
        let dimensions = item.image.map { image in
            CGSize(width: image.size.width, height: image.size.height)
        }

        return ClipboardImageAnalysis(
            labels: labels.map(\.identifier),
            topConfidence: labels.first?.confidence,
            dimensions: dimensions
        )
    }

    private func classifyImage(data: Data) -> [ClipboardImageClassification] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(data: data, options: [:])

        do {
            try handler.perform([request])
            return (request.results ?? [])
                .filter { $0.confidence >= 0.1 }
                .prefix(6)
                .map {
                    ClipboardImageClassification(
                        identifier: $0.identifier
                            .replacingOccurrences(of: "_", with: " ")
                            .lowercased(),
                        confidence: $0.confidence
                    )
                }
        } catch {
            return []
        }
    }

    private func sourceAwareTitle(for item: ClipboardItem) -> String? {
        guard let sourceApp = item.sourceApp?.normalizedGeneratedMetadataText else {
            return nil
        }

        switch item.type {
        case ClipboardItemType.image:
            return "Image from \(sourceApp)"
        case ClipboardItemType.video:
            return "Recording from \(sourceApp)"
        case ClipboardItemType.url:
            return "Link from \(sourceApp)"
        default:
            return "\(item.displayType) from \(sourceApp)"
        }
    }

    private func isGenericTitle(_ value: String, for item: ClipboardItem) -> Bool {
        value == item.displayType
            || value == ClipboardItemType.image.capitalized
            || value == ClipboardItemType.video.capitalized
    }
}

private struct ClipboardImageAnalysis {
    static let empty = ClipboardImageAnalysis(labels: [], topConfidence: nil, dimensions: nil)

    var labels: [String]
    var topConfidence: Float?
    var dimensions: CGSize?

    var primaryLabel: String? {
        labels.first
    }

    var promptDescription: String {
        var values: [String] = []
        if let dimensions {
            values.append("\(Int(dimensions.width))x\(Int(dimensions.height)) pixels")
        }
        if !labels.isEmpty {
            values.append("Vision labels: \(labels.joined(separator: ", "))")
        }
        return values.isEmpty ? "None" : values.joined(separator: "; ")
    }
}

private struct ClipboardImageClassification {
    var identifier: String
    var confidence: Float
}

private enum ClipboardMetadataSuggestionError: LocalizedError {
    case modelUnavailable
    case invalidModelResponse

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "the on-device model is not available"
        case .invalidModelResponse:
            return "the model returned an unsupported response"
        }
    }
}

private struct ClipboardAppleIntelligenceMetadataPayload: Decodable {
    var title: String?
    var tags: [String]
    var collection: String?
    var summary: String?
    var category: String?
    var entities: [String]
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case title
        case tags
        case collection
        case summary
        case category
        case entities
        case confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        collection = try container.decodeIfPresent(String.self, forKey: .collection)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        entities = try container.decodeIfPresent([String].self, forKey: .entities) ?? []
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
    }
}

private extension String {
    var normalizedGeneratedMetadataText: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedMetadataComparisonKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var singleLineGeneratedMetadataText: String {
        components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var looksLikeCode: Bool {
        contains("```")
            || contains("func ")
            || contains("let ")
            || contains("var ")
            || contains("class ")
            || contains("struct ")
            || contains("</")
    }

    var looksLikeEmailAddress: Bool {
        firstEmailAddress != nil
    }

    var firstEmailAddress: String? {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        guard let range = range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }
        return String(self[range])
    }

    func truncatedGeneratedMetadataText(limit: Int) -> String {
        guard count > limit else {
            return self
        }

        let endIndex = index(startIndex, offsetBy: max(0, limit - 1))
        return String(self[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    var extractedJSONObjectString: String {
        guard let start = firstIndex(of: "{"),
              let end = lastIndex(of: "}"),
              start <= end else {
            return self
        }

        return String(self[start...end])
    }
}

private extension [String] {
    var normalizedGeneratedMetadataList: [String] {
        var seen: Set<String> = []
        return compactMap(\.normalizedGeneratedMetadataText)
            .filter { value in
                let key = value.lowercased()
                guard !seen.contains(key) else {
                    return false
                }
                seen.insert(key)
                return true
            }
    }
}

extension ClipboardItem {
    @discardableResult
    func applyGeneratedMetadata(
        _ metadata: ClipboardGeneratedMetadata,
        fillsEmptyFieldsOnly: Bool = true
    ) -> Bool {
        var changed = false

        if let suggestedTitle = metadata.suggestedTitle,
           !suggestedTitle.isEmpty,
           !fillsEmptyFieldsOnly || customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            customTitle = suggestedTitle
            changed = true
        }

        if !metadata.suggestedTags.isEmpty {
            var tags = self.tags
            for tag in metadata.suggestedTags where !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                tags.append(tag)
            }
            let newTagsText = tags.isEmpty ? nil : tags.joined(separator: ", ")
            if tagsText != newTagsText {
                tagsText = newTagsText
                changed = true
            }
        }

        if let suggestedCollection = metadata.suggestedCollection,
           !suggestedCollection.isEmpty,
           !fillsEmptyFieldsOnly || collectionName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            collectionName = suggestedCollection
            changed = true
        }

        if changed {
            updatedAt = Date()
        }

        return changed
    }

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

    var skipsAppleIntelligenceSuggestions: Bool {
        ClipboardSettings.load()
            .appRule(for: sourceBundleIdentifier)?
            .skipsAppleIntelligence == true
    }

    var generatedMetadata: ClipboardGeneratedMetadata? {
        guard let id else {
            return nil
        }

        return ClipboardGeneratedMetadataStore.metadata(for: id)
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
