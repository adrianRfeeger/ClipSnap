import CoreData
import Foundation

enum ClipboardAutomationSettingKey {
    static let trimsWhitespace = "automationTrimsWhitespace"
    static let removesURLTracking = "automationRemovesURLTracking"
    static let formatsJSON = "automationFormatsJSON"
    static let tagsScreenCaptures = "automationTagsScreenCaptures"
    static let tagsOCR = "automationTagsOCR"
    static let tagsCode = "automationTagsCode"
}

struct ClipboardAutomationSettings {
    var trimsWhitespace: Bool
    var removesURLTracking: Bool
    var formatsJSON: Bool
    var tagsScreenCaptures: Bool
    var tagsOCR: Bool
    var tagsCode: Bool

    static let defaults = ClipboardAutomationSettings(
        trimsWhitespace: false,
        removesURLTracking: false,
        formatsJSON: false,
        tagsScreenCaptures: true,
        tagsOCR: true,
        tagsCode: true
    )

    static func load(from defaults: UserDefaults = .standard) -> ClipboardAutomationSettings {
        let fallback = Self.defaults
        return ClipboardAutomationSettings(
            trimsWhitespace: defaults.object(
                forKey: ClipboardAutomationSettingKey.trimsWhitespace
            ) as? Bool ?? fallback.trimsWhitespace,
            removesURLTracking: defaults.object(
                forKey: ClipboardAutomationSettingKey.removesURLTracking
            ) as? Bool ?? fallback.removesURLTracking,
            formatsJSON: defaults.object(
                forKey: ClipboardAutomationSettingKey.formatsJSON
            ) as? Bool ?? fallback.formatsJSON,
            tagsScreenCaptures: defaults.object(
                forKey: ClipboardAutomationSettingKey.tagsScreenCaptures
            ) as? Bool ?? fallback.tagsScreenCaptures,
            tagsOCR: defaults.object(
                forKey: ClipboardAutomationSettingKey.tagsOCR
            ) as? Bool ?? fallback.tagsOCR,
            tagsCode: defaults.object(
                forKey: ClipboardAutomationSettingKey.tagsCode
            ) as? Bool ?? fallback.tagsCode
        )
    }
}

struct ClipboardAutomationResult: Equatable {
    let contentChanged: Bool
    let appliedRules: [String]
}

enum ClipboardAutomation {
    @MainActor
    static func apply(
        to item: ClipboardItem,
        settings: ClipboardAutomationSettings
    ) -> ClipboardAutomationResult {
        var appliedRules: [String] = []
        var contentChanged = false

        if var text = item.plainText {
            if settings.trimsWhitespace {
                let transformed = ClipboardTextTransformation.trimWhitespace.apply(to: text)
                if transformed != text {
                    text = transformed
                    contentChanged = true
                    appliedRules.append("Trimmed whitespace")
                }
            }

            if settings.removesURLTracking, item.type == ClipboardItemType.url {
                let transformed = ClipboardTextTransformation.removeTrackingParameters.apply(to: text)
                if transformed != text {
                    text = transformed
                    contentChanged = true
                    appliedRules.append("Removed URL tracking")
                }
            }

            if settings.formatsJSON, isJSONObject(text) {
                let transformed = ClipboardTextFormatter.formatted(
                    text,
                    itemType: ClipboardItemType.json
                )
                if transformed != text || item.type != ClipboardItemType.json {
                    text = transformed
                    item.type = ClipboardItemType.json
                    item.utiType = "public.json"
                    contentChanged = true
                    appliedRules.append("Formatted JSON")
                }
            }

            if contentChanged {
                item.plainText = text
                item.previewText = text.clipboardPreview
                item.rawData = Data(text.utf8)
            }
        }

        var tags = Set(item.tags)
        if settings.tagsScreenCaptures, item.isScreenCapture {
            tags.insert("screenshot")
        }
        if settings.tagsOCR, item.isOCRCapture {
            tags.insert("ocr")
        }
        if settings.tagsCode,
           item.type == ClipboardItemType.sourceCode
            || item.type == ClipboardItemType.json
            || item.type == ClipboardItemType.xml {
            tags.insert("code")
        }
        let updatedTags = tags.sorted()
        if updatedTags != item.tags.sorted() {
            item.tagsText = updatedTags.joined(separator: ", ")
            appliedRules.append("Added tags")
        }

        if !appliedRules.isEmpty {
            item.updatedAt = Date()
        }
        return ClipboardAutomationResult(
            contentChanged: contentChanged,
            appliedRules: appliedRules
        )
    }

    private static func isJSONObject(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return object is [String: Any] || object is [Any]
    }
}
