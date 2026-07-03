# ClipSnap

ClipSnap is a native macOS clipboard and capture manager built with SwiftUI, AppKit, Core Data, ScreenCaptureKit, and Vision. It records clipboard history, preserves multiple pasteboard formats, captures screen content, recognizes text, and makes previous items available from the main window, quick picker, menu bar, or Dock menu.

## Features

- Automatic clipboard history monitoring.
- Search, filtering, pinning, favorites, archiving, batch metadata editing, and deletion.
- Menu bar access to recent clipboard items.
- Dock menu access to recent clipboard items and capture actions.
- Quick clipboard picker with keyboard navigation.
- Current clipboard indicators in the main window, quick picker, menu bar, and Dock menu.
- Faithful capture of multiple pasteboard items and representations.
- Support for text, images, files, URLs, RTF, RTFD, HTML, PDF, colors, JSON, XML, source code, tabular data, contacts, audio, video, archives, and unknown formats.
- Native previews for images, PDF documents, rich text, HTML, media, colors, and archive contents.
- Screen capture for regions, windows, applications, and displays, including delayed capture.
- Display recording with pause, continue, stop, and cancel controls.
- OCR capture and text recognition from screenshots.
- Image editing and annotation tools for crop, rotate, flip, redact, shapes, arrows, highlights, and text.
- Editable text previews with formatting and transformations.
- Drag content into ClipSnap from other applications.
- Drag history items from ClipSnap into Finder and compatible applications.
- Export and sharing for selected history items.
- Hash-based duplicate detection and optional duplicate promotion.
- Configurable history count, age, and storage limits.
- Source-application tracking and application exclusions.
- Sensitive-content filtering for common secrets, codes, and payment-card patterns.
- Optional Spotlight indexing for non-sensitive, non-archived history.
- Local folder sync packages for Dropbox, Syncthing, OneDrive folder sync, NAS shares, external drives, and manual backup/restore.
- Optional Apple Intelligence suggestions for titles, tags, collections, and summaries when available on the Mac.

## Requirements

- macOS
- Xcode with the macOS SDK required by the project deployment target

ClipSnap does not require an Apple Developer Program membership for local clipboard history, capture, OCR, annotation, or local folder sync.

## Building

1. Open the ClipSnap project in Xcode.
2. Select the **ClipSnap** scheme.
3. Choose **My Mac** as the run destination.
4. Build and run with `Command-R`.

Some source folders and the Core Data model retain the internal `CB` name to avoid unnecessary model and project churn.

## Using ClipSnap

Copy content normally from any macOS application. ClipSnap monitors the general pasteboard and adds eligible content to history.

From the main window:

- Select an item to inspect its preview and metadata.
- Use **Copy** to restore it to the system clipboard.
- Pin or favorite important items.
- Search or filter the history.
- Collapse metadata when you want more preview space.
- Edit text items, annotate image items, recognize text in images, or merge selected text items.
- Drag items into another application.
- Drop supported content anywhere in the window to add it to history.

From the menu bar:

- Select a recent item to copy it.
- Capture regions, windows, applications, displays, or OCR text.
- Start, pause, continue, stop, or cancel display recording.
- Pause or resume clipboard monitoring.
- Open the main window or Settings.

From the Dock menu:

- Right-click the Dock icon to copy recent items.
- Use the same capture and recording controls available from the menu bar.
- Open the main window or Settings.

From the quick picker:

- Open the compact picker with the configured keyboard shortcut.
- Search recent history, move through results with the arrow keys, and copy the selected item.

## Settings

ClipSnap provides settings for:

- Moving repeated items to the top.
- Preserving favorites during cleanup.
- Maximum history count.
- History expiration.
- Maximum local storage.
- Retention periods by content type.
- Sensitive-content filtering.
- Sensitive preview concealment.
- Excluded applications selected through an app picker.
- Screen capture options and post-capture actions.
- Automation rules for trimming, URL cleanup, JSON formatting, and automatic tags.
- Apple Intelligence suggestion controls.
- Spotlight indexing.
- Local folder sync.

## Privacy

Clipboard data is stored locally in the app's Core Data store. Local folder sync exports portable ClipSnap packages only when the user enables it and chooses a folder.

ClipSnap:

- Skips pasteboard content marked transient or concealed.
- Can exclude selected source applications.
- Can reject likely one-time codes, private keys, access tokens, API keys, and payment-card values.
- Keeps sensitive items local-only when they are retained.
- Avoids Spotlight indexing for archived, sensitive, and local-only items.
- Logs item categories, sizes, and operation results without intentionally logging clipboard contents.

Sensitive-content detection is heuristic and cannot guarantee that every secret is recognized. Exclude password managers and other sensitive applications explicitly from Settings.

## Sync

The visible sync option is **Local Folder Sync**. Choose a folder in Settings > Sync, then use Export Now and Import Now to move portable ClipSnap packages through a folder-backed service or storage location.

Good folder targets include:

- Dropbox
- Syncthing
- OneDrive folder sync
- NAS shares
- External drives
- A manual backup folder

CloudKit/iCloud sync code remains in the project for future use, but it is not exposed as a user-facing option in the current GitHub-friendly build.

## Architecture

Key components:

- `CBApp.swift`: application scenes and shared service ownership.
- `ClipboardMonitor.swift`: pasteboard monitoring, capture import, restoration, and dropped-content import.
- `ScreenCaptureService.swift`: ScreenCaptureKit capture, region selection, and OCR integration.
- `ImageClipboardEditor.swift`: image crop, redaction, and annotation tools.
- `ClipboardDragDropSupport.swift`: external drag source and drop-provider conversion.
- `ClipboardItemSupport.swift`: clipboard item metadata, display helpers, and content identity.
- `ClipboardPolicies.swift`: hashing, privacy rules, and retention policy.
- `Persistence.swift`: Core Data persistent container.
- `CloudSyncMonitor.swift`: sync provider models, local folder sync packages, and dormant CloudKit monitoring support.
- `ContentView.swift`: searchable history and detail interface.
- `SettingsView.swift`: general, history, privacy, capture, automation, and sync preferences.
- `QuickClipboardPicker.swift`: compact keyboard-driven history picker.

The Core Data model contains:

- `ClipboardItem`: history metadata and the primary preview representation.
- `ClipboardRepresentation`: ordered pasteboard item/type data used for faithful restoration.

## Testing

The project uses:

- Swift Testing for policy and content-identity tests.
- XCUIAutomation for application launch and UI tests.

Run tests from Xcode with `Command-U`.

The unit tests cover hashing, representation ordering, application exclusions, sensitive-content detection, and retention behavior.
They also cover screen-capture imports, OCR imports, export encoding, image editing, archive parsing, automation rules, generated metadata, and sync package behavior.

## Known Limitations

- Dragging a clipboard event with multiple pasteboard items exposes the first item as the external drag source; copying from history restores the complete multi-item payload.
- Some application-specific pasteboard formats may not preview even when their raw data is retained.
- Sensitive-content detection is intentionally conservative but is not a substitute for explicit application exclusions.
- Screen capture and OCR require the appropriate macOS Screen Recording permission.
- Apple Intelligence suggestions require supported hardware, OS availability, and system configuration. ClipSnap falls back to local rules when unavailable.
- Local folder sync is explicit import/export rather than always-on background sync.

## Project Documentation

- [ClipSnapImprovementPlan.md](ClipSnapImprovementPlan.md)
- [ClipSnapAppleIntelligencePlan.md](ClipSnapAppleIntelligencePlan.md)
- [ClipSnapStorageSyncPlan.md](ClipSnapStorageSyncPlan.md)
- [ClipSnapReleaseChecklist.md](ClipSnapReleaseChecklist.md)
- [ClipboardManagerEnhancementPlan.md](ClipboardManagerEnhancementPlan.md)
