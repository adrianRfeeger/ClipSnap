# ClipSnap Storage And Sync Provider Plan

Goal: make ClipSnap support multiple storage and sync backends alongside iCloud, starting with Google Drive and leaving a clear path for other providers.

## Principles

- Keep iCloud as the default native sync option.
- Add providers without changing the clipboard capture model or user-facing history behavior.
- Keep provider-specific authentication, file layout, conflict handling, and rate-limit behavior isolated.
- Never sync sensitive or local-only items unless the user explicitly changes those rules.
- Prefer portable encrypted export packages over provider-specific database coupling.

## Phase 1: Sync Architecture

- [x] Define a `ClipboardSyncProvider` protocol for provider identity, capabilities, authentication state, upload, download, delete, and conflict reporting.
- [x] Add provider capability flags for file storage, metadata storage, background sync, delta sync, quota reporting, and external sharing links.
- [x] Create a `SyncProviderRegistry` that owns enabled providers and exposes current status to Settings and diagnostics.
- [ ] Refactor iCloud-facing sync state into an iCloud provider adapter where practical.
- [ ] Add provider-neutral sync events so current iCloud event reporting can also represent Google Drive and future providers.

Acceptance:

- App code can ask for enabled providers without knowing whether the backend is iCloud, Google Drive, local folder, or another service.
- Current iCloud behavior remains unchanged.

## Phase 2: Portable Sync Package Format

- [x] Define a versioned package format for clipboard items, metadata, representations, thumbnails, and attachments.
- [x] Store each synced item as a manifest plus binary payload files rather than coupling external providers to Core Data internals.
- [x] Include content hash, item UUID, created/updated timestamps, source app metadata, tags, collection, sensitivity/local-only flags, and representation UTIs.
- [ ] Add optional package encryption before writing to third-party storage.
- [ ] Add migration/version handling for future package changes.

Acceptance:

- A provider can upload/download a clipboard item using only the portable package.
- Sensitive/private fields are either omitted or encrypted according to settings.

## Phase 3: Google Drive Provider

- [ ] Add Google Drive authentication flow and token storage using Keychain.
- [ ] Create or locate a ClipSnap app folder in the user’s Drive.
- [ ] Upload item packages, thumbnails, and delete markers into the app folder.
- [ ] Poll or page Drive changes to import updates from other devices.
- [ ] Handle Drive quota, revoked auth, network failures, and API rate limits.
- [ ] Add Google Drive status, account, quota, and reconnect actions in Settings.

Acceptance:

- A user can enable Google Drive sync without disabling iCloud.
- Clipboard items synced through Drive appear on another ClipSnap install using the same account.

## Phase 4: Provider Selection And Rules

- [x] Add Settings UI for enabled sync providers.
- [ ] Allow global default provider selection: iCloud, Google Drive, both, or local-only.
- [ ] Extend per-app rules to choose allowed providers or force local-only.
- [ ] Add per-item provider status in metadata.
- [ ] Keep “sensitive preview concealment” and “local-only” rules above provider rules.

Acceptance:

- Users can choose where data goes.
- Privacy rules remain explainable from item metadata.

## Phase 5: Conflict Resolution

- [x] Define conflict identity using stable item UUID and content hash.
- [x] Prefer newest metadata when payload hash is unchanged.
- [x] Preserve both copies when payload differs and both were edited independently.
- [x] Add conflict diagnostics and optional user-facing conflict markers.
- [x] Ensure delete markers do not remove newer edited copies.

Acceptance:

- Multi-device edits do not silently lose data.
- Conflict behavior is deterministic and diagnosable.

## Phase 6: Other Storage Options

- [x] Add a local folder provider for users who want to sync with Dropbox, Syncthing, OneDrive folder sync, NAS shares, or external drives.
- [ ] Add a WebDAV provider if a broad standards-based remote option is worthwhile.
- [ ] Evaluate direct Dropbox/OneDrive providers only if local-folder sync is insufficient.
- [ ] Keep provider adapters small and testable.

Acceptance:

- Users can sync through common storage workflows without every provider requiring a first-party integration.

## Phase 7: Security And Privacy

- [ ] Store OAuth tokens only in Keychain.
- [ ] Add optional end-to-end encryption for third-party provider packages.
- [ ] Redact synced diagnostic exports by default.
- [ ] Document what metadata is stored externally.
- [x] Add provider-specific privacy warnings where needed.

Acceptance:

- Third-party storage does not create a hidden privacy regression.
- Users understand what is stored locally, in iCloud, and in other providers.

## Phase 8: Testing

- [x] Add unit tests for package encoding/decoding.
- [ ] Add tests for package version migration.
- [x] Add provider contract tests with fake providers.
- [x] Add conflict resolution tests.
- [ ] Add Google Drive adapter tests around auth, paging, upload, delete, and retry behavior using mocks.
- [ ] Add UI tests for provider setup, status, and per-app provider rules.
- [ ] Add performance tests for large histories and many binary payloads.

Acceptance:

- Provider behavior can be tested without real cloud accounts.
- Sync regressions are caught before release.

## Phase 9: Rollout

- [x] Ship local folder provider first as a lower-risk package-format validation path.
- [ ] Add Google Drive behind an experimental setting.
- [ ] Collect redacted diagnostics for sync failures when users explicitly export them.
- [ ] Promote Google Drive to stable after conflict handling, retry behavior, and quota handling are reliable.
- [ ] Update README and release notes with setup steps and limitations.

Acceptance:

- New sync options can be introduced without destabilizing existing iCloud users.
- Users have clear setup and troubleshooting guidance.
