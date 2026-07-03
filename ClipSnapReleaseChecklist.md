# ClipSnap Release Checklist

Use this before preparing a public build.

## Accessibility

- Verify main history rows expose title, type, and sensitive-content state.
- Verify toolbar/menu buttons have labels or accessibility identifiers.
- Check Settings tabs, setup checklist, diagnostics, and cleanup confirmation dialogs with VoiceOver.
- Confirm image editor controls can be reached by keyboard and announce selected annotation state.

## Keyboard Navigation

- Main window: search, row selection, copy, delete, batch actions, saved filters.
- Quick picker: Command-Shift-V, arrow navigation, Return copy, Escape close.
- Capture: command menu shortcuts and menu bar capture entries.
- Image editor: Undo, redo, delete, arrow movement, object copy/paste/duplicate.

## Localization Readiness

- Review user-facing strings added in SwiftUI views before localization extraction.
- Keep diagnostic exports in English unless localization resources are added.
- Avoid hardcoded date/byte formatting where Foundation formatters are available.

## Signing And Notarization

- Confirm bundle identifier, app category, hardened runtime, and sandbox/iCloud entitlements.
- Archive a Release build from Xcode.
- Validate the archive and run notarization on the exported app or package.
- Staple the notarization ticket before distribution.

## Release Notes

- Summarize capture, recording, annotation, saved filter, health, setup, and diagnostics changes.
- Call out any permission requirements for screen recording and audio capture.
- Include known limitations and migration notes for existing Clipboard Bro/ClipSnap users.
