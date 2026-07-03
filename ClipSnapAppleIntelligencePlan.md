# ClipSnap Apple Intelligence Plan

## Goal

Integrate Apple Intelligence through the Foundation Models framework to help ClipSnap name, tag, summarize, classify, and organize clipboard items while keeping the feature private, optional, and reversible.

## Design Principles

- Use on-device Apple Intelligence first. Do not send clipboard contents to third-party services for this feature.
- Treat generated metadata as suggestions until the user enables auto-apply.
- Keep model-generated titles, tags, summaries, and collections separate from user-entered metadata so they can be reviewed, reverted, or regenerated.
- Respect privacy rules, excluded applications, sensitive content settings, and local-only sync rules before any model request is made.
- Always check model availability and locale support before showing or running Apple Intelligence features.
- Provide useful fallback behavior when Apple Intelligence is unavailable, disabled, downloading, or unsupported on the current device.

## Foundation Models Notes

Apple's Foundation Models framework exposes the on-device model that powers Apple Intelligence through `SystemLanguageModel` and `LanguageModelSession`.

Relevant implementation points:

- Use `SystemLanguageModel.default` for general metadata generation.
- Consider `SystemLanguageModel(useCase: .contentTagging, guardrails: ...)` for automatic tag suggestions when available.
- Gate all UI and background processing behind `SystemLanguageModel.availability`.
- Handle unavailable states such as device not eligible, Apple Intelligence disabled, model not ready, and unknown failures.
- Check supported languages through `supportsLocale(_:)` or `supportedLanguages`.
- Use structured generation for stable outputs instead of parsing free-form prose.
- Treat guardrails as a safety layer, not as the only privacy control.

## Phase 1: Capability And Settings

- [x] Add an Apple Intelligence settings section under Settings > Automation.
- [x] Add settings for:
  - [x] Enable Apple Intelligence suggestions.
  - [x] Suggest titles.
  - [x] Suggest tags.
  - [x] Suggest collections.
  - [x] Summarize long text and HTML.
  - [x] Describe images and screenshots.
  - [x] Auto-apply suggestions.
  - [x] Require review before applying suggestions from sensitive apps.
  - [x] Exclude specific apps from Apple Intelligence processing.
- [x] Add a small availability status row:
  - [x] Available.
  - [x] Apple Intelligence disabled.
  - [x] Model downloading or not ready.
  - [x] Device not eligible.
  - [ ] Unsupported language.
- [x] Store settings in `ClipboardSettings` using the same pattern as the existing sync and privacy settings.

## Phase 2: Metadata Suggestion Model

- Add a generated metadata structure that can be attached to a clipboard item without overwriting user metadata.
- Suggested fields:
  - `suggestedTitle`
  - `suggestedTags`
  - `suggestedCollection`
  - `summary`
  - `contentCategory`
  - `detectedEntities`
  - `confidence`
  - `generatedAt`
  - `modelVersion`
  - `generationStatus`
  - `failureReason`
- Persist generated metadata separately from manual title, tags, collection, and notes.
- Add merge rules:
  - Never overwrite a non-empty user title unless auto-apply is enabled.
  - Add suggested tags only if they are not already present.
  - Keep rejected suggestions rejected until the source content changes or the user regenerates them.

## Phase 3: Enrichment Pipeline

- [x] Add a background enrichment service that runs after new clipboard items are captured.
- [x] Run only when:
  - [x] Apple Intelligence suggestions are enabled.
  - [x] The model is available, with local fallback.
  - [x] The item type is eligible.
  - [x] The source app is not excluded.
  - [x] Privacy rules allow processing.
- [x] Use background tasks so model requests do not block clipboard monitoring.
- [x] Debounce immediate capture work with a short delay.
- [ ] Prioritize recent visible items, then process older items opportunistically.
- [x] Add manual actions:
  - [x] Generate Suggestions.
  - [x] Regenerate Suggestions.
  - [x] Apply Suggestions.
  - [x] Clear Suggestions.

## Phase 4: Automatic Naming And Tagging

- Generate clear item titles for:
  - Plain text snippets.
  - HTML formatted text.
  - URLs.
  - Images and screenshots.
  - Screen recordings.
  - Files and file lists.
  - OCR captures.
- Generate tags that reflect:
  - Content type.
  - Source app.
  - Intent or topic.
  - Entities such as people, organizations, places, dates, code languages, invoices, receipts, tasks, or links.
- Generate collection suggestions such as:
  - Work.
  - Research.
  - Code.
  - Images.
  - Receipts.
  - Links.
  - Screenshots.
- Keep tag suggestions short and normalized.
- Avoid adding noisy tags such as generic words, internal UTI names, or app-private metadata identifiers.

## Phase 5: Smart Previews And Summaries

- Replace low-value previews for long, formatted, or noisy content with concise summaries.
- For HTML content:
  - Extract readable text first.
  - Ask the model for a title and summary based on the readable content.
  - Preserve the original HTML representation for paste/export.
- For images:
  - Use OCR output where available.
  - Generate a short visual description.
  - Tag screenshots, diagrams, documents, receipts, forms, charts, and UI captures.
- For videos and screen recordings:
  - Start with filename/source/duration metadata.
  - Add visual frame analysis later only if a separate media-analysis pipeline is added.

## Phase 6: Review UI

- Add a suggestion strip or panel in the item detail view:
  - Suggested title.
  - Suggested tags.
  - Suggested collection.
  - Summary.
  - Apply, reject, regenerate, and clear actions.
- [x] Add batch review for multiple selected items:
  - [x] Generate suggestions for selected items.
  - [x] Apply all safe suggestions.
  - [x] Reject all.
  - [x] Clear all.
  - [ ] Review one-by-one.
- In the item list and menu:
  - Prefer user title.
  - Then suggested title if accepted or auto-applied.
  - Then existing fallback title.
- Add a small visual marker for items with unapplied suggestions.

## Phase 7: Search And Organization

- [x] Use generated titles, tags, summaries, and entities in existing search.
- [ ] Add smart filters:
  - [x] Has suggestions.
  - [x] Needs review.
  - [x] Generated by Apple Intelligence.
  - [ ] Receipts.
  - [x] Links.
  - [x] Screenshots.
  - [x] Code.
- Consider natural-language search as a later phase:
  - Convert user intent into existing search filters.
  - Example: "screenshots from Mail last week about invoices".
  - Keep the query translation visible and editable.

## Phase 8: Automation

- Extend automation rules to use generated metadata.
- Example rules:
  - Auto-tag screenshots from Safari as Research.
  - Move receipts to a Receipts collection.
  - Pin items tagged Important.
  - Auto-delete generated junk or tracking tokens after review.
- Require explicit user approval before enabling automation that deletes, syncs, or exports items based on model output.

## Phase 9: Privacy And Sync

- Add a privacy explanation that generated metadata is produced on device.
- Respect app-level privacy rules before processing content.
- Do not process items marked as sensitive unless the user opts in.
- Avoid model processing for private/internal pasteboard representations unless a human-readable representation is also present.
- Add sync controls:
  - Sync generated metadata.
  - Keep generated metadata local.
  - Sync only accepted suggestions.
- Default to syncing accepted metadata only, not transient suggestions.

## Phase 10: Testing

- Wrap Foundation Models calls behind a protocol so tests can use a deterministic mock service.
- Unit test:
  - [ ] Eligibility rules.
  - [ ] Privacy exclusions.
  - [ ] Availability fallback behavior.
  - [x] Generated metadata normalization and merge rules.
  - [ ] Rejection and regeneration rules.
  - [x] Search matching and filters for generated suggestions.
- UI test:
  - Suggestion review.
  - Apply and undo.
  - Batch apply.
  - Settings availability states.
- Add fixture-based tests for:
  - Plain text.
  - HTML.
  - URLs.
  - Images with OCR text.
  - App-private metadata-only items.

## Phase 11: Rollout

- Start behind an experimental setting.
- Ship suggest-only mode first.
- Add auto-apply after review flows are stable.
- Add automation integration last.
- Include a migration path for future model versions and prompt changes.

## Acceptance Criteria

- Clipboard monitoring remains fast and reliable while suggestions are generated in the background.
- No item from an excluded app is processed by Apple Intelligence.
- A user can inspect, apply, reject, regenerate, and clear generated suggestions.
- User-entered titles, tags, collections, and notes are never overwritten unexpectedly.
- Suggestions improve list and menu readability for HTML, screenshots, URLs, and generic image items.
- The app clearly explains when Apple Intelligence is unavailable and continues to work without it.

## Open Questions

- Should Apple Intelligence settings live under Automation, Privacy, or a dedicated Intelligence tab?
- Should accepted suggestions become normal metadata immediately, or remain visibly generated?
- Should generated summaries be searchable by default?
- Should the app generate suggestions immediately on capture, only when an item is viewed, or both?
- What is the preferred default for syncing accepted generated metadata?
