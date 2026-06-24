# CloudKit Setup For CB

The app now monitors CloudKit account and synchronization events, but Apple requires the CloudKit container to be created and associated with the app's App ID through a developer team.

## Xcode Capability Setup

1. Open the `CB` target.
2. Select **Signing & Capabilities**.
3. Select the correct Apple Developer team.
4. Add the **iCloud** capability.
5. Enable **CloudKit**.
6. Create or select a private CloudKit container for CB.
7. Add the **Background Modes** capability.
8. Enable **Remote notifications**.

Xcode should generate the entitlements and associate the selected container with the `adrianfeeger.CB` App ID.

Do not manually type a container identifier that has not been created and assigned in the Apple Developer portal. A mismatched identifier causes CloudKit permission failures at runtime.

## Development Validation

1. Run CB while signed into an iCloud account.
2. Open **CB > Settings > iCloud**.
3. Confirm the account status reports **Up to Date** or an active setup/import/export operation.
4. Copy a new text item and wait for an export event.
5. Run CB on a second Mac signed into the same iCloud account.
6. Confirm the item imports and appears in history.

CloudKit synchronization is scheduled by the system and may not happen immediately.

## Schema Deployment

Before distributing a production build:

1. Exercise every Core Data entity and field in the development environment.
2. Open CloudKit Console.
3. Confirm the `ClipboardItem` and `ClipboardRepresentation` record schemas.
4. Deploy the schema to production.
5. Archive and test the signed release build outside Xcode.
