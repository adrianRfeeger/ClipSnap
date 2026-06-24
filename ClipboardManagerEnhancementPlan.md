# CB Clipboard Manager Enhancement Plan

## Product Direction

Turn the current prototype into a dependable macOS clipboard utility that:

- Preserves clipboard content faithfully across applications.
- Makes recent content fast to find and restore from the menu bar or keyboard.
- Syncs selected history safely through the user's private iCloud database.
- Gives users clear control over privacy, storage, retention, and excluded apps.
- Remains responsive with large histories and large binary clipboard items.

## Current Baseline

The project already includes:

- Clipboard polling through `NSPasteboard.general.changeCount`.
- Core Data persistence using `NSPersistentCloudKitContainer`.
- Text, image, file, URL, rich text, HTML, PDF, color, media, archive, structured text, and unknown type classification.
- Duplicate suppression against the most recent stored item.
- Searchable and filterable clipboard history.
- Copy, pin, favorite, and delete actions.
- A menu bar history menu with pause and resume controls.
- A macOS app icon.

The largest current limitations are:

- Only one primary representation is retained from each pasteboard item.
- CloudKit capabilities, entitlements, account state, and sync status are not completed.
- Source application detection, exclusion rules, cleanup policies, and sensitive-content filtering are missing.
- Binary previews and restoration are incomplete for several supported types.
- There is little automated test coverage or runtime diagnostics.

## Phase 1: Stabilize The Foundation

### 1.1 Refactor By Responsibility

Split the growing files into clear modules:

- `App`: application entry point, app delegate, commands, and scene definitions.
- `Models`: clipboard categories, representation metadata, filters, and settings values.
- `Services`: clipboard monitoring, capture, restore, cleanup, source-app detection, and sync status.
- `Stores`: Core Data access and history operations.
- `Views`: sidebar, history row, detail preview, menu bar content, settings, and onboarding.
- `Support`: formatters, hashing, UTType helpers, logging, and thumbnail generation.

Keep pasteboard parsing independent from Core Data so it can be unit tested with value types.

### 1.2 Replace Timer Target/Selector State

Move monitoring lifecycle ownership to an application-level service.

- Start monitoring once during application launch.
- Prevent duplicate timers when windows or menus appear.
- Use a cancellable async monitoring loop or another lifecycle-safe implementation.
- Record monitoring state and errors through `Logger`.
- Add explicit handling for app termination and sleep/wake transitions.

### 1.3 Add Stable Content Identity

Calculate a content hash from normalized clipboard representations.

- Use the hash for duplicate detection instead of comparing large blobs repeatedly.
- Update the timestamp of a repeated item when the user enables "move duplicates to top."
- Preserve pinned and favorite state when a duplicate is promoted.
- Add a unique constraint or indexed field where appropriate.

### Acceptance Criteria

- Monitoring starts exactly once.
- Copying an existing item does not create an unwanted duplicate.
- Clipboard parsing can be tested without launching the app or writing to Core Data.
- Capture and restore failures appear in structured logs without crashing the app.

## Phase 2: Faithful Multi-Format Capture

### 2.1 Store Every Useful Representation

Replace the single `rawData` and `utiType` assumption with a child entity such as `ClipboardRepresentation`.

Suggested fields:

- `id: UUID`
- `utiIdentifier: String`
- `data: Data?`
- `stringValue: String?`
- `order: Int16`
- `byteCount: Int64`
- `isPrimary: Bool`
- Relationship to `ClipboardItem`

Capture all useful representations from every `NSPasteboardItem`, including multiple pasteboard items in one copy operation.

Examples:

- Plain text plus RTF plus HTML.
- TIFF plus PNG.
- URL plus plain text.
- Multiple selected files.
- Application-specific data plus a standard fallback.

### 2.2 Preserve Pasteboard Item Boundaries

Add an ordered group model so multi-selection clipboard payloads can be restored accurately.

- Preserve the number and order of `NSPasteboardItem` objects.
- Restore every representation to its original pasteboard item.
- Keep a normalized primary representation only for search and preview.

### 2.3 Improve Type-Specific Handling

- Store file bookmarks or validated file URLs without duplicating file contents.
- Preserve animated image data rather than flattening it to one frame.
- Generate previews using Quick Look where supported.
- Render PDFs with PDFKit.
- Render RTF, RTFD, and HTML as attributed content.
- Show media metadata and optional AVKit previews.
- Parse JSON and property lists for formatted previews.
- Present colors as swatches with color-space metadata.

### 2.4 Enforce Size Limits

- Add configurable per-item and total-history limits.
- Avoid syncing oversized representations through CloudKit.
- Generate thumbnails off the main thread.
- Mark skipped representations and explain why they were not retained.

### Acceptance Criteria

- Copying formatted content from Safari, Pages, Finder, Preview, and Xcode restores into those apps with expected formatting.
- Multiple copied files restore as multiple file URLs.
- Large clipboard items do not block the main thread.
- The detail view identifies every stored representation.

## Phase 3: iCloud Sync Completion

### 3.1 Configure Capabilities

- Add the iCloud and CloudKit capabilities to the app target.
- Add the required entitlements file and CloudKit container identifier.
- Enable the App Sandbox with the minimum required entitlements.
- Validate development and production CloudKit schemas.

### 3.2 Define Sync Policy

Add settings for:

- iCloud sync enabled or disabled.
- Sync text only, favorites only, or all eligible content.
- Maximum binary item size for sync.
- Wi-Fi-only behavior where practical.

Keep local history functional when iCloud is unavailable.

### 3.3 Add Sync Status

Expose:

- iCloud account availability.
- Last successful import or export.
- Pending changes.
- Recoverable sync errors.
- A retry action and a link to relevant settings.

Use persistent history processing for deterministic local and remote change handling.

### 3.4 Resolve Conflicts And Deletions

- Use stable IDs and `updatedAt` for metadata conflicts.
- Define pin, favorite, and delete conflict rules.
- Propagate deletions through CloudKit.
- Avoid resurrecting items removed by retention cleanup.

### Acceptance Criteria

- New eligible items appear on a second signed-in Mac.
- Pin, favorite, and delete changes converge correctly.
- Disabling sync retains local history.
- The UI clearly distinguishes offline, disabled, syncing, and error states.

## Phase 4: Privacy And Retention

### 4.1 Detect Source Applications

Record the frontmost application's bundle identifier and display name when content changes.

- Show the source app in history metadata.
- Add per-app exclusions.
- Include common password managers in a recommended exclusion list.
- Allow temporary monitoring suspension.

### 4.2 Sensitive Content Rules

Create a configurable privacy engine that can skip:

- One-time passcodes.
- Credit-card-like values.
- Private keys and recovery phrases.
- Authentication tokens and secrets.
- Content marked transient or concealed by the source application.

Avoid claiming perfect secret detection. Show users which rule excluded an item without storing the sensitive payload.

### 4.3 Retention And Cleanup

Add settings for:

- Maximum item count.
- Maximum total storage.
- Delete after a chosen age.
- Keep pinned or favorite items indefinitely.
- Clear history now.
- Clear everything except pinned items.

Run cleanup after capture, at launch, and periodically in the background.

### 4.4 Local Protection

- Confirm Core Data and binary files use appropriate file protection.
- Avoid writing clipboard payloads to logs.
- Consider optional local-only mode for all history.
- Document what is stored locally and what can sync.

### Acceptance Criteria

- Excluded applications never persist clipboard payloads.
- Cleanup respects pinned and favorite exceptions.
- Users can see and change all privacy-related behavior in Settings.
- No clipboard contents appear in production logs.

## Phase 5: Faster Daily Workflows

### 5.1 Global Shortcut And Clipboard Picker

Add a configurable global keyboard shortcut that opens a compact clipboard picker near the active screen.

- Search immediately on typing.
- Navigate with arrow keys.
- Press Return to copy the selection.
- Optionally paste into the active application after selection.
- Support Escape to dismiss without changing the clipboard.

Use AppKit interop only for the floating panel, focus management, and global shortcut registration.

### 5.2 Menu Bar Improvements

- Add search or grouped submenus where platform behavior remains reliable.
- Separate pinned items from recent history.
- Show thumbnails or concise type indicators where possible.
- Make "Open Clipboard" reliably open or focus the main window.
- Add Settings and Clear History actions.

### 5.3 Main Window Improvements

- Use stable selection with `@SceneStorage`.
- Add keyboard commands for copy, delete, pin, favorite, and search focus.
- Add multi-selection and batch delete or pin.
- Add sort options by recent, source app, size, and type.
- Add richer filters for all supported categories.
- Add an inspector for metadata and stored representations.
- Add drag-out support for text, images, and files.

### 5.4 Editing And Transformations

Optional productivity actions:

- Copy as plain text.
- Strip formatting.
- Trim whitespace.
- Change case.
- Pretty-print JSON.
- URL encode or decode.
- Extract text from images using Vision OCR.
- Create reusable snippets with editable titles.

Transformations should create a new clipboard payload without silently modifying stored history.

### Acceptance Criteria

- The global picker can be opened, searched, and used without leaving the current app.
- Every primary action has a pointer and keyboard path.
- The main window remains usable with thousands of history items.

## Phase 6: Settings, Onboarding, And App Lifecycle

### 6.1 Dedicated Settings Scene

Create a native `Settings` scene with sections for:

- General.
- History and storage.
- Privacy and exclusions.
- iCloud sync.
- Shortcuts.
- Advanced diagnostics.

Persist preferences with `@AppStorage` or a dedicated settings store.

### 6.2 Launch Behavior

Add preferences for:

- Launch at login.
- Show or hide the Dock icon.
- Open the main window at launch.
- Start monitoring automatically.
- Show onboarding after first launch or important migrations.

### 6.3 App Commands And Window Management

- Give the main `WindowGroup` a stable identifier.
- Open or focus it from the menu bar and global picker.
- Add native application commands and shortcuts.
- Restore sensible window size, sidebar visibility, and selection.

### Acceptance Criteria

- Menu bar, Dock, login, and window behavior match user preferences.
- The main window can always be reopened after it is closed.
- Settings changes take effect without restarting where practical.

## Phase 7: Performance And Reliability

### 7.1 Background Processing

- Parse and hash large data away from the main actor.
- Use background Core Data contexts for capture and cleanup.
- Keep UI fetches lightweight and paginated.
- Cache thumbnails with explicit invalidation.

### 7.2 Storage Architecture

Evaluate moving large binary payloads to external storage while keeping metadata in Core Data.

- Use Core Data external binary storage or managed files.
- Track orphaned files and remove them during cleanup.
- Measure store size and expose it in Settings.

### 7.3 Error Recovery

- Replace `fatalError` persistence handling with recoverable startup states.
- Add migration tests before changing the production model.
- Detect inaccessible or corrupted stores and offer clear recovery choices.
- Handle CloudKit partial failures without losing local data.

### 7.4 Diagnostics

Add privacy-safe telemetry using unified logging:

- Monitor start and stop.
- Capture category and byte count, never content.
- Save and restore success or failure.
- Cleanup counts.
- CloudKit state transitions.

### Acceptance Criteria

- Capturing a large image does not visibly freeze the app.
- Store load and migration failures show a recoverable UI.
- Memory and disk usage remain bounded by configured limits.

## Phase 8: Testing And Release Readiness

### 8.1 Unit Tests

Use the Swift Testing framework for:

- UTType classification.
- Multi-representation capture.
- Content hashing and deduplication.
- Sensitive-content rules.
- Retention and storage limits.
- Search and filter behavior.
- Conflict resolution.
- Restore payload construction.

### 8.2 Integration Tests

Test round trips for:

- Plain and formatted text.
- HTML.
- PNG, TIFF, and animated images.
- PDF.
- Single and multiple files.
- URLs.
- Colors.
- Custom and unknown pasteboard formats.

### 8.3 UI Tests

Use XCUIAutomation for:

- Search and filtering.
- Pin, favorite, delete, and batch actions.
- Settings changes.
- Main window reopening from the menu bar.
- Keyboard navigation in the global picker.

### 8.4 Manual Compatibility Matrix

Verify capture and restoration with:

- Finder.
- Safari.
- Mail.
- Notes.
- Pages.
- Preview.
- Xcode.
- Terminal.
- Microsoft Office applications where available.

### 8.5 Distribution

- Confirm signing, sandbox, hardened runtime, and entitlements.
- Test a release build outside Xcode.
- Add an application privacy statement.
- Prepare migration and rollback procedures for Core Data and CloudKit schemas.
- Validate archive, notarization, and distribution.

## Recommended Delivery Order

1. Refactor capture and restore into testable value-based services.
2. Add content hashing, source application detection, and structured logging.
3. Introduce the multi-representation Core Data model with migration coverage.
4. Implement faithful capture and restoration for common applications.
5. Add retention, storage limits, exclusions, and sensitive-content controls.
6. Complete CloudKit entitlements, policy, status, and conflict handling.
7. Add a dedicated Settings scene and reliable main-window reopening.
8. Build the global keyboard picker and keyboard command system.
9. Add rich previews, transformations, snippets, and drag-out workflows.
10. Complete automated testing, performance work, signing, and distribution.

## Suggested First Milestone

The first production-focused milestone should include:

- Testable pasteboard capture and restoration services.
- Multiple representations per clipboard item.
- Stable content hashes and duplicate promotion.
- Source application capture and app exclusions.
- Configurable retention and size limits.
- Reliable menu bar and main-window lifecycle.
- Unit tests for capture, restore, deduplication, and cleanup.

CloudKit should follow this milestone. Syncing incomplete or inaccurately restored clipboard records would make data problems propagate between devices.
