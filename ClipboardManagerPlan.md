# Clipboard Manager Plan

## Goal

Build a macOS clipboard manager that keeps a searchable local history, restores previous clipboard items, and syncs history through iCloud. It should support text, images, rich content, files, URLs, and unknown pasteboard formats where possible.

## Core Data Model

Create a `ClipboardItem` Core Data entity with fields such as:

- `id: UUID`
- `createdAt: Date`
- `updatedAt: Date`
- `type: String`
- `plainText: String?`
- `previewText: String?`
- `imageData: Data?`
- `thumbnailData: Data?`
- `rawData: Data?`
- `utiType: String?`
- `sourceApp: String?`
- `isPinned: Bool`
- `isFavorite: Bool`

Use `type` values like `text`, `image`, `file`, `url`, `rtf`, `html`, and `unknown`.

## Persistence And iCloud Sync

Update `Persistence.swift` to use `NSPersistentCloudKitContainer`.

Store clipboard history locally first, then sync through the user's private iCloud database. Add CloudKit capabilities and iCloud entitlements in the Xcode target before enabling sync in production.

Use `updatedAt` when resolving conflicts. Keep sync optional through app settings so users can disable iCloud history.

## Clipboard Monitoring

Add a `ClipboardMonitor` service that observes `NSPasteboard.general.changeCount` on a timer.

When the change count changes:

- Read available pasteboard types.
- Extract supported representations.
- Build a `ClipboardItem`.
- Deduplicate against the most recent item.
- Save the item through Core Data.

Pause monitoring briefly when restoring an old item to avoid duplicating the restored content.

## Supported Formats

Text:

- `NSPasteboard.PasteboardType.string`

Images:

- `NSPasteboard.PasteboardType.tiff`
- Convert to PNG or JPEG for storage.
- Generate a thumbnail for list previews.

Rich text:

- `.rtf`
- `.rtfd`

HTML:

- `.html`

URLs and files:

- `.URL`
- `.fileURL`

Unknown or custom formats:

- Store the pasteboard type identifier.
- Store raw `Data` when available.
- Display a generic format label in the UI.

## Restoring Clipboard Items

Add a method such as `copyToClipboard(_ item: ClipboardItem)`.

Restore based on the stored item type:

- Text writes a string.
- Images reconstruct an `NSImage`.
- Rich text and HTML write the original data with the stored pasteboard type.
- URLs and file URLs write URL pasteboard values.
- Unknown formats attempt to write raw data back using `utiType`.

## Main UI

Update `ContentView.swift` into a clipboard history interface.

Suggested layout:

- Search field.
- Filter controls for All, Text, Images, Files, URLs, Favorites, and Pinned.
- Clipboard history list.
- Detail preview area.
- Actions for Copy, Pin, Favorite, and Delete.

Preview behavior:

- Text items show a short snippet.
- Image items show a thumbnail.
- File items show a file name and path preview.
- URL items show the URL string.
- Unknown items show the format identifier.

## History Management

Add user settings for:

- Maximum history count.
- Auto-delete after a selected number of days.
- Pause monitoring.
- Enable or disable iCloud sync.
- Ignore sensitive-looking content.
- Exclude selected apps if source app detection is added.

Run cleanup after new items are saved and when the app launches.

## Privacy And Safety

Default to conservative storage behavior.

Avoid storing obvious sensitive values such as:

- Password-like short strings.
- One-time codes.
- Credit card-like numbers.
- Private keys or tokens.

Make iCloud sync explicit and clearly controlled by the user.

## App Lifecycle

Start clipboard monitoring when the app launches.

Keep the monitoring service separate from SwiftUI views so the app can later support:

- Menu bar access.
- Global keyboard shortcuts.
- Background operation.
- Settings window controls.

## Testing

Unit tests:

- Clipboard type detection.
- Deduplication.
- Cleanup rules.
- Sensitive content filtering.
- Restore payload construction.

UI tests:

- History list appears.
- Search filters results.
- Copy action restores a selected item.
- Delete removes an item.

Manual tests:

- Copy plain text, rich text, HTML, image, URL, file URL, and unknown data.
- Relaunch the app and confirm history persists.
- Test on two Macs signed into the same iCloud account and confirm sync.

## Recommended Build Order

1. Add the Core Data model for clipboard items.
2. Implement local clipboard monitoring.
3. Save clipboard history locally.
4. Build the SwiftUI list and preview UI.
5. Restore selected items to the clipboard.
6. Add image, rich text, file, URL, and raw format support.
7. Add deduplication and cleanup.
8. Convert persistence to `NSPersistentCloudKitContainer`.
9. Add settings and privacy controls.
10. Add unit and UI tests.
