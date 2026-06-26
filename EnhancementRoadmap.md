# Clipboard Bro Enhancement Roadmap

This document is the implementation contract for extending Clipboard Bro. Work is ordered by dependency and risk; completed work is checked off.

## Milestone 1 — Capture reliability and quick access

- [x] Harden multi-display region selection and cancellation.
- [x] Show region-selection instructions and live dimensions.
- [x] Expose capture/OCR progress and actionable Screen Recording permission UI.
- [x] Improve OCR cancellation and error handling.
- [x] Add a keyboard-first quick clipboard picker.
- [x] Add focused unit/UI coverage.

## Milestone 2 — Organization and search

- [x] Add tags, collections, custom titles, notes, archive, and batch actions.
- [x] Add smart filters for OCR, screenshots, code, colors, and documents.
- [x] Add date, source-app, content-type, favorite, pinned, collection, and tag search filters.
- [x] Highlight matches and optionally index searchable content with Core Spotlight.

## Milestone 3 — Preview and editing

- [x] Add media, archive, syntax-highlighted code, and structured JSON/XML previews.
- [x] Associate OCR text with its source image and support re-running OCR.
- [x] Add text editing, screenshot crop/annotation/redaction, transformations, and merging.

## Milestone 4 — Privacy and storage

- [x] Add per-application policies, temporary pause, local-only items, and sensitive-preview protection.
- [x] Add automatic expiry for sensitive items.
- [x] Move large binary payloads to managed files while retaining metadata in Core Data.
- [x] Add per-type retention, storage reporting, and orphan-file cleanup.

## Milestone 5 — Sync

- [ ] Add per-item CloudKit state, retry, diagnostics, conflict handling, and offline/account-change tests. *(Per-item state, retry, event diagnostics, and account-change monitoring implemented.)*
- [x] Exclude local-only and sensitive content from sync.
- [ ] Review encryption requirements before syncing sensitive payloads.

## Milestone 6 — Automation and export

- [x] Add rules for JSON formatting, URL cleanup, whitespace normalization, automatic OCR, and tagging.
- [x] Add configurable post-capture actions.
- [x] Add file/archive export, sharing services, and Markdown/JSON/CSV/plain-text export.

## Milestone 7 — Shipping quality

- [ ] Expand unit, UI, CloudKit, multi-display, scaling, large-payload, and performance coverage. *(Deterministic launch, history selection/search, quick-picker, automation, storage, and image-editing coverage implemented.)*
- [ ] Audit sandbox entitlements, onboarding, accessibility, localization, signing, notarization, diagnostics, and release notes.

## Completed foundation

- [x] Clipboard history persistence, deduplication, cleanup, drag/drop, previews, and CloudKit container monitoring.
- [x] Display, application, window, and rectangular screenshot capture.
- [x] Region OCR using on-device Vision recognition.
- [x] Capture commands, menu-bar actions, settings, and clipboard-history integration.
