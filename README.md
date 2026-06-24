# Clipboard Bro

Clipboard Bro is a native macOS clipboard manager built with SwiftUI, AppKit, Core Data, and CloudKit. It records clipboard history, preserves multiple pasteboard formats, and makes previous items available from the main window or menu bar.

## Features

- Automatic clipboard history monitoring.
- Search, filtering, pinning, favorites, and deletion.
- Menu bar access to recent clipboard items.
- Faithful capture of multiple pasteboard items and representations.
- Support for text, images, files, URLs, RTF, RTFD, HTML, PDF, colors, JSON, XML, source code, tabular data, contacts, audio, video, archives, and unknown formats.
- Native previews for images, PDF documents, rich text, and HTML.
- Drag content into Clipboard Bro from other applications.
- Drag history items from Clipboard Bro into Finder and compatible applications.
- Hash-based duplicate detection and optional duplicate promotion.
- Configurable history count, age, and storage limits.
- Source-application tracking and application exclusions.
- Sensitive-content filtering for common secrets, codes, and payment-card patterns.
- Optional private iCloud synchronization through `NSPersistentCloudKitContainer`.
- CloudKit account, import, export, and error status reporting.

## Requirements

- macOS
- Xcode with the macOS SDK required by the project deployment target
- An Apple Developer account and iCloud container for CloudKit synchronization

Local clipboard history works without an Apple Developer account or CloudKit configuration.

## Building

1. Open `CB.xcodeproj` in Xcode.
2. Select the **Clipboard Bro** scheme.
3. Choose **My Mac** as the run destination.
4. Build and run with `Command-R`.

The target and Swift module retain the internal name `CB` to preserve existing model, test, and bundle identity.

## Using Clipboard Bro

Copy content normally from any macOS application. Clipboard Bro monitors the general pasteboard and adds eligible content to history.

From the main window:

- Select an item to inspect its preview and metadata.
- Use **Copy** to restore it to the system clipboard.
- Pin or favorite important items.
- Search or filter the history.
- Drag items into another application.
- Drop supported content anywhere in the window to add it to history.

From the menu bar:

- Select a recent item to copy it.
- Pause or resume clipboard monitoring.
- Open the main window or Settings.
- Check the current iCloud synchronization state.

## Settings

Clipboard Bro provides settings for:

- Moving repeated items to the top.
- Preserving favorites during cleanup.
- Maximum history count.
- History expiration.
- Maximum local storage.
- Sensitive-content filtering.
- Excluded application bundle identifiers.
- CloudKit account and synchronization status.

Use application bundle identifiers such as `com.example.PasswordManager` when configuring exclusions.

## Privacy

Clipboard data is stored locally in the app's Core Data store. When CloudKit is configured, eligible records synchronize through the user's private iCloud database.

Clipboard Bro:

- Skips pasteboard content marked transient or concealed.
- Can exclude selected source applications.
- Can reject likely one-time codes, private keys, access tokens, API keys, and payment-card values.
- Logs item categories, sizes, and operation results without intentionally logging clipboard contents.

Sensitive-content detection is heuristic and cannot guarantee that every secret is recognized. Exclude password managers and other sensitive applications explicitly.

## iCloud Setup

CloudKit requires a container associated with the app's signed App ID:

1. Open the **Clipboard Bro** target.
2. Select **Signing & Capabilities**.
3. Select an Apple Developer team.
4. Add the **iCloud** capability.
5. Enable **CloudKit** and select a private container.
6. Add **Background Modes**.
7. Enable **Remote notifications**.

See [CloudKitSetup.md](CloudKitSetup.md) for validation and production-schema deployment steps.

Do not invent or manually enter a CloudKit container identifier that is not associated with the App ID in the Apple Developer portal.

## Architecture

Key components:

- `CBApp.swift`: application scenes and shared service ownership.
- `ClipboardMonitor.swift`: pasteboard monitoring, capture, restoration, and dropped-content import.
- `ClipboardDragDropSupport.swift`: external drag source and drop-provider conversion.
- `ClipboardItemSupport.swift`: clipboard item metadata, display helpers, and content identity.
- `ClipboardPolicies.swift`: hashing, privacy rules, and retention policy.
- `Persistence.swift`: Core Data and CloudKit persistent container.
- `CloudSyncMonitor.swift`: iCloud account and persistent CloudKit event monitoring.
- `ContentView.swift`: searchable history and detail interface.
- `SettingsView.swift`: history, privacy, and iCloud preferences.

The Core Data model contains:

- `ClipboardItem`: history metadata and the primary preview representation.
- `ClipboardRepresentation`: ordered pasteboard item/type data used for faithful restoration.

## Testing

The project uses:

- Swift Testing for policy and content-identity tests.
- XCUIAutomation for application launch and UI tests.

Run tests from Xcode with `Command-U`.

The unit tests cover hashing, representation ordering, application exclusions, sensitive-content detection, and retention behavior.

## Known Limitations

- CloudKit must be configured and signed through an Apple Developer team before synchronization works.
- CloudKit synchronization timing is controlled by the system and may be deferred.
- Dragging a clipboard event with multiple pasteboard items exposes the first item as the external drag source; copying from history restores the complete multi-item payload.
- Some application-specific pasteboard formats may not preview even when their raw data is retained.
- Sensitive-content detection is intentionally conservative but is not a substitute for explicit application exclusions.

## Project Documentation

- [ClipboardManagerEnhancementPlan.md](ClipboardManagerEnhancementPlan.md)
- [CloudKitSetup.md](CloudKitSetup.md)
