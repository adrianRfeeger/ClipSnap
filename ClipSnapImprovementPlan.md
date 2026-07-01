# ClipSnap Improvement Plan

This plan captures the next set of product improvements for ClipSnap. It is ordered by user value, implementation dependency, and risk.

## Phase 1: Reduce Clipboard Noise

Goal: Keep history focused on user-intended clipboard content.

- [x] Add an "Ignore internal app clipboard metadata" privacy setting.
- [x] Move hardcoded ignored pasteboard types into a configurable policy list.
- [x] Add an advanced ignored type editor for power users.
- [x] Add a "Why was this captured?" diagnostic view for unknown/data items.
- [x] Add one-click actions from an unknown item: ignore this type, ignore this app, or keep capturing.

Acceptance:

- Browser, design-tool, and app-private bookkeeping types do not create standalone history items.
- Real content is still captured when app-private representations accompany standard text, image, URL, or file types.
- Users can understand and tune ignored types without editing code.

## Phase 2: Better Item Titles And Previews

Goal: Make history easier to scan in the sidebar, menu bar, and quick picker.

- [x] Add image dimensions to generic image titles where useful.
- [x] Improve source-aware titles, such as "Image from Safari - 1280x720".
- [x] Add source-aware titles for files, PDFs, videos, and screen recordings.
- [x] Show compact thumbnails for images, PDFs, videos, and captures in the quick picker.
- [x] Consider thumbnail support in the menu bar where it remains readable and performant.

Acceptance:

- Generic rows like "Image / Image" are replaced by useful source and content context.
- Existing custom titles and meaningful generated titles remain unchanged.
- Large histories remain smooth while thumbnails load.

## Phase 3: Capture And Recording Status

Goal: Make capture state visible and controllable from the menu bar.

- [x] Show live delayed-capture countdown in the menu bar menu.
- [x] Show recording elapsed time in the menu bar menu.
- [x] Keep Pause, Continue, Stop, and Cancel recording actions directly reachable while recording.
- [x] Add a visible status row for active OCR, capture, or recording operations.
- [x] Add failure recovery actions for Screen Recording permission and capture errors.

Acceptance:

- Users can tell when ClipSnap is waiting, capturing, recording, paused, or saving.
- Active capture/recording controls are available without opening the main window.
- Capture failures have clear next actions.

## Phase 4: Per-App Rules

Goal: Give users predictable control over capture behavior by source application.

- [x] Extend excluded apps into per-app rules.
- [x] Support rule actions: ignore, local-only, never sync, conceal previews, auto-tag, and custom retention.
- [x] Add app picker management with search and remove controls.
- [x] Show rule effects in item metadata.
- [x] Add tests for rule precedence and migration from existing excluded apps.

Acceptance:

- Users can safely handle sensitive or noisy apps without disabling global monitoring.
- Existing excluded-app settings migrate cleanly.
- Rule behavior is explainable from item metadata.

## Phase 5: Saved Filters And History Views

Goal: Make repeated searches and cleanup workflows fast.

- [x] Add saved filters for common queries.
- [x] Include built-in filters: Images Today, From Mail, Screenshots, Favorites, Unsynced, Large Items, and Unknown/Data.
- [x] Allow users to save the current search as a named filter.
- [x] Add filter management for rename, reorder, and delete.
- [x] Reuse filters in the main window and quick picker where practical.

Acceptance:

- Frequent workflows take one click or one keyboard-driven selection.
- Saved filters use the same query engine as the search field.
- Built-in filters remain useful without adding visual clutter.

## Phase 6: Clipboard Health And Cleanup

Goal: Give users confidence about storage, sync, and cleanup.

- [x] Add a Clipboard Health view.
- [x] Show largest items, duplicate groups, unknown/data items, unsynced items, local-only items, and sensitive item counts.
- [x] Add cleanup actions for large items, old screenshots, duplicates, and unknown data.
- [x] Add safe previews before destructive cleanup.
- [x] Add storage trend and last cleanup status.

Acceptance:

- Users can understand what consumes space and why.
- Cleanup actions are reversible where practical or clearly confirmed.
- Storage reporting aligns with existing history settings.

## Phase 7: Annotation And Image Editing Polish

Goal: Move image editing closer to a lightweight Preview-style annotation tool.

- [x] Add an object inspector for selected vector annotations.
- [x] Support exact position, size, opacity, stroke, fill, font, alignment, and layer order.
- [x] Add keyboard movement and deletion for selected annotations.
- [x] Add copy/paste/duplicate for annotation objects.
- [x] Add undo/redo for image edits.
- [x] Preserve editable annotations until final save where possible.

Acceptance:

- Users can precisely adjust annotations after drawing them.
- Common edit operations work by mouse and keyboard.
- Rasterization only happens at an intentional save/export boundary.

## Phase 8: Onboarding And Setup

Goal: Make first launch and configuration obvious.

- [x] Add a first-run setup checklist.
- [x] Cover Screen Recording permission, iCloud status, privacy defaults, capture settings, and menu bar access.
- [x] Add links to relevant System Settings panes.
- [x] Show setup status without blocking local clipboard history.
- [x] Add a way to reopen setup from Settings.

Acceptance:

- A new user can configure capture and privacy without reading documentation.
- Missing permissions explain what works and what does not.
- Local-only use remains simple.

## Phase 9: Diagnostics And Supportability

Goal: Make tricky clipboard behavior easier to debug without exposing private content.

- [x] Add a diagnostics export that redacts clipboard content by default.
- [x] Include app version, settings summary, ignored types, item counts, sync state, and recent non-content logs.
- [x] Add per-item representation diagnostics for unknown/data items.
- [x] Add a "Copy Diagnostic Summary" action.
- [x] Keep diagnostics local unless the user explicitly exports them.

Acceptance:

- Users can report capture issues without sharing private clipboard contents.
- Unknown pasteboard types can be classified and filtered faster.
- Diagnostics do not create new privacy risk.

## Phase 10: Test And Release Quality

Goal: Keep the expanding feature set stable.

- [x] Add tests for ignored internal pasteboard types.
- [x] Add tests for source-aware titles.
- [x] Add tests for per-app rule matching.
- [ ] Add UI tests for saved filters, capture status, and cleanup flows.
- [ ] Add performance checks for large histories and thumbnail-heavy views.
- [ ] Review accessibility labels, keyboard navigation, localization readiness, signing, notarization, and release notes.

Acceptance:

- New behavior has targeted regression coverage.
- Large histories stay responsive.
- Release preparation is repeatable.
