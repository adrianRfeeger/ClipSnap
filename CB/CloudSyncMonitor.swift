import CloudKit
import Combine
import CoreData
import Foundation
import OSLog
import Security

enum CloudSyncState: Equatable {
    case configurationRequired
    case checkingAccount
    case noAccount
    case restricted
    case temporarilyUnavailable
    case ready
    case syncing(String)
    case error(String)

    var title: String {
        switch self {
        case .configurationRequired:
            return "Configuration Required"
        case .checkingAccount:
            return "Checking iCloud"
        case .noAccount:
            return "No iCloud Account"
        case .restricted:
            return "iCloud Restricted"
        case .temporarilyUnavailable:
            return "iCloud Unavailable"
        case .ready:
            return "Up to Date"
        case .syncing(let operation):
            return operation
        case .error:
            return "Sync Error"
        }
    }

    var systemImageName: String {
        switch self {
        case .configurationRequired:
            return "exclamationmark.icloud"
        case .checkingAccount, .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .noAccount, .restricted, .temporarilyUnavailable, .error:
            return "icloud.slash"
        case .ready:
            return "checkmark.icloud"
        }
    }
}

@MainActor
final class CloudSyncMonitor: ObservableObject {
    @Published private(set) var state: CloudSyncState = .checkingAccount
    @Published private(set) var lastSuccessfulSync: Date?
    @Published private(set) var lastErrorDescription: String?
    @Published private(set) var containerIdentifiers: [String] = []

    private let container: NSPersistentCloudKitContainer
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CB", category: "CloudSync")
    private var eventTask: Task<Void, Never>?
    private var accountTask: Task<Void, Never>?

    init(container: NSPersistentCloudKitContainer) {
        self.container = container
    }

    func start() {
        guard eventTask == nil, accountTask == nil else {
            return
        }

        containerIdentifiers = Self.currentContainerIdentifiers()
        guard !containerIdentifiers.isEmpty else {
            state = .configurationRequired
            return
        }

        accountTask = Task { [weak self] in
            await self?.refreshAccountStatus()
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard !Task.isCancelled else {
                    return
                }
                await self?.refreshAccountStatus()
            }
        }

        eventTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification
            ) {
                guard !Task.isCancelled else {
                    return
                }
                self?.handle(notification)
            }
        }
    }

    func refreshAccountStatus() async {
        guard !containerIdentifiers.isEmpty else {
            state = .configurationRequired
            return
        }

        state = .checkingAccount
        do {
            let status = try await CKContainer.default().accountStatus()
            switch status {
            case .available:
                state = .ready
            case .noAccount:
                state = .noAccount
            case .restricted:
                state = .restricted
            case .temporarilyUnavailable:
                state = .temporarilyUnavailable
            case .couldNotDetermine:
                state = .error("Could not determine iCloud account status.")
            @unknown default:
                state = .error("Unknown iCloud account status.")
            }
        } catch {
            lastErrorDescription = error.localizedDescription
            state = .error(error.localizedDescription)
            logger.error("Account status check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ notification: Notification) {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else {
            return
        }

        if event.endDate == nil {
            state = .syncing(operationTitle(for: event.type))
            return
        }

        if event.succeeded {
            lastSuccessfulSync = event.endDate
            lastErrorDescription = nil
            state = .ready
            logger.info("CloudKit \(self.operationTitle(for: event.type), privacy: .public) completed")
        } else {
            let description = event.error?.localizedDescription ?? "Unknown CloudKit error"
            lastErrorDescription = description
            state = .error(description)
            logger.error("CloudKit event failed: \(description, privacy: .public)")
        }
    }

    private func operationTitle(for type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup:
            return "Setting Up iCloud"
        case .import:
            return "Downloading History"
        case .export:
            return "Uploading History"
        @unknown default:
            return "Syncing History"
        }
    }

    private static func currentContainerIdentifiers() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-container-identifiers" as CFString,
                nil
              ) else {
            return []
        }

        return value as? [String] ?? []
    }
}
