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

struct CloudSyncEventSummary: Identifiable, Equatable {
    let id: UUID
    let type: String
    let startDate: Date
    let endDate: Date
    let succeeded: Bool
    let errorDescription: String?
}

enum ClipboardSyncProviderKind: String, Codable, CaseIterable, Identifiable {
    case iCloud
    case googleDrive
    case localFolder
    case webDAV

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .iCloud:
            return "iCloud"
        case .googleDrive:
            return "Google Drive"
        case .localFolder:
            return "Local Folder"
        case .webDAV:
            return "WebDAV"
        }
    }

    var systemImageName: String {
        switch self {
        case .iCloud:
            return "icloud"
        case .googleDrive:
            return "externaldrive.connected.to.line.below"
        case .localFolder:
            return "folder"
        case .webDAV:
            return "network"
        }
    }
}

struct ClipboardSyncProviderCapabilities: Codable, Equatable {
    var supportsFileStorage: Bool
    var supportsMetadataStorage: Bool
    var supportsBackgroundSync: Bool
    var supportsDeltaSync: Bool
    var supportsQuotaReporting: Bool
    var supportsExternalSharingLinks: Bool

    static let iCloud = ClipboardSyncProviderCapabilities(
        supportsFileStorage: true,
        supportsMetadataStorage: true,
        supportsBackgroundSync: true,
        supportsDeltaSync: true,
        supportsQuotaReporting: false,
        supportsExternalSharingLinks: false
    )

    static let googleDrive = ClipboardSyncProviderCapabilities(
        supportsFileStorage: true,
        supportsMetadataStorage: true,
        supportsBackgroundSync: false,
        supportsDeltaSync: true,
        supportsQuotaReporting: true,
        supportsExternalSharingLinks: true
    )

    static let localFolder = ClipboardSyncProviderCapabilities(
        supportsFileStorage: true,
        supportsMetadataStorage: true,
        supportsBackgroundSync: false,
        supportsDeltaSync: false,
        supportsQuotaReporting: false,
        supportsExternalSharingLinks: false
    )

    static let webDAV = ClipboardSyncProviderCapabilities(
        supportsFileStorage: true,
        supportsMetadataStorage: true,
        supportsBackgroundSync: false,
        supportsDeltaSync: false,
        supportsQuotaReporting: true,
        supportsExternalSharingLinks: false
    )
}

struct ClipboardSyncProviderDescriptor: Codable, Equatable, Identifiable {
    var id: String
    var kind: ClipboardSyncProviderKind
    var displayName: String
    var capabilities: ClipboardSyncProviderCapabilities
    var isEnabled: Bool

    static let iCloud = ClipboardSyncProviderDescriptor(
        id: ClipboardSyncProviderKind.iCloud.rawValue,
        kind: .iCloud,
        displayName: ClipboardSyncProviderKind.iCloud.title,
        capabilities: .iCloud,
        isEnabled: true
    )

    static let localFolder = ClipboardSyncProviderDescriptor(
        id: ClipboardSyncProviderKind.localFolder.rawValue,
        kind: .localFolder,
        displayName: ClipboardSyncProviderKind.localFolder.title,
        capabilities: .localFolder,
        isEnabled: false
    )
}

enum ClipboardSyncProviderAuthenticationState: Codable, Equatable {
    case notRequired
    case signedOut
    case authenticating
    case signedIn(accountName: String?)
    case expired
    case error(String)

    var title: String {
        switch self {
        case .notRequired:
            return "Ready"
        case .signedOut:
            return "Sign In Required"
        case .authenticating:
            return "Signing In"
        case .signedIn(let accountName):
            return accountName ?? "Signed In"
        case .expired:
            return "Reconnect Required"
        case .error:
            return "Authentication Error"
        }
    }
}

struct ClipboardSyncProviderStatus: Codable, Equatable {
    var descriptor: ClipboardSyncProviderDescriptor
    var authenticationState: ClipboardSyncProviderAuthenticationState
    var lastSuccessfulSync: Date?
    var lastErrorDescription: String?
    var quotaUsedBytes: Int64?
    var quotaLimitBytes: Int64?
}

protocol ClipboardSyncProvider {
    var descriptor: ClipboardSyncProviderDescriptor { get }

    func currentStatus() async -> ClipboardSyncProviderStatus
    func upload(_ package: ClipboardSyncPackage) async throws
    func downloadPackages(since date: Date?) async throws -> [ClipboardSyncPackage]
    func downloadDeleteMarkers(since date: Date?) async throws -> [ClipboardSyncDeleteMarker]
    func deletePackage(itemIdentifier: UUID, updatedAt: Date) async throws
}

struct ClipboardSyncDeleteMarker: Codable, Equatable, Sendable {
    var itemIdentifier: UUID
    var updatedAt: Date
}

enum ClipboardLocalFolderSyncProviderError: LocalizedError {
    case unableToCreateFolder(URL)
    case unableToReadFolder(URL)

    var errorDescription: String? {
        switch self {
        case .unableToCreateFolder(let url):
            return "ClipSnap could not create the sync folder at \(url.path)."
        case .unableToReadFolder(let url):
            return "ClipSnap could not read the sync folder at \(url.path)."
        }
    }
}

struct ClipboardLocalFolderSyncProvider: ClipboardSyncProvider {
    let folderURL: URL
    var descriptor: ClipboardSyncProviderDescriptor

    init(
        folderURL: URL,
        descriptor: ClipboardSyncProviderDescriptor = .localFolder
    ) {
        self.folderURL = folderURL
        self.descriptor = descriptor
    }

    func currentStatus() async -> ClipboardSyncProviderStatus {
        do {
            try ensureFolderStructure()
            let quotaUsedBytes = folderByteCount()
            return ClipboardSyncProviderStatus(
                descriptor: descriptor,
                authenticationState: .notRequired,
                lastSuccessfulSync: nil,
                lastErrorDescription: nil,
                quotaUsedBytes: quotaUsedBytes,
                quotaLimitBytes: nil
            )
        } catch {
            return ClipboardSyncProviderStatus(
                descriptor: descriptor,
                authenticationState: .error(error.localizedDescription),
                lastSuccessfulSync: nil,
                lastErrorDescription: error.localizedDescription,
                quotaUsedBytes: nil,
                quotaLimitBytes: nil
            )
        }
    }

    func upload(_ package: ClipboardSyncPackage) async throws {
        try ensureFolderStructure()
        let url = packageURL(for: package.itemIdentifier)
        try package.encodedData().write(to: url, options: .atomic)
    }

    func downloadPackages(since date: Date?) async throws -> [ClipboardSyncPackage] {
        try ensureFolderStructure()
        guard let enumerator = FileManager.default.enumerator(
            at: itemsFolderURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ClipboardLocalFolderSyncProviderError.unableToReadFolder(itemsFolderURL)
        }

        var packages: [ClipboardSyncPackage] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == Self.packageFileExtension else {
                continue
            }

            if let date,
               let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let modifiedAt = values.contentModificationDate,
               modifiedAt <= date {
                continue
            }

            let data = try Data(contentsOf: url)
            packages.append(try ClipboardSyncPackage.decode(from: data))
        }

        return packages.sorted { $0.item.updatedAt < $1.item.updatedAt }
    }

    func downloadDeleteMarkers(since date: Date?) async throws -> [ClipboardSyncDeleteMarker] {
        try ensureFolderStructure()
        guard let enumerator = FileManager.default.enumerator(
            at: deletedFolderURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ClipboardLocalFolderSyncProviderError.unableToReadFolder(deletedFolderURL)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var markers: [ClipboardSyncDeleteMarker] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == Self.deleteMarkerFileExtension else {
                continue
            }

            if let date,
               let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let modifiedAt = values.contentModificationDate,
               modifiedAt <= date {
                continue
            }

            let data = try Data(contentsOf: url)
            markers.append(try decoder.decode(ClipboardSyncDeleteMarker.self, from: data))
        }

        return markers.sorted { $0.updatedAt < $1.updatedAt }
    }

    func deletePackage(itemIdentifier: UUID, updatedAt: Date) async throws {
        try ensureFolderStructure()
        let packageURL = packageURL(for: itemIdentifier)
        if FileManager.default.fileExists(atPath: packageURL.path) {
            try FileManager.default.removeItem(at: packageURL)
        }

        let marker = ClipboardSyncDeleteMarker(
            itemIdentifier: itemIdentifier,
            updatedAt: updatedAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let markerURL = deletedFolderURL
            .appendingPathComponent(itemIdentifier.uuidString)
            .appendingPathExtension(Self.deleteMarkerFileExtension)
        try encoder.encode(marker).write(to: markerURL, options: .atomic)
    }

    static let packageFileExtension = "clipsnapitem"
    static let deleteMarkerFileExtension = "clipsnapdelete"

    private var itemsFolderURL: URL {
        folderURL.appendingPathComponent("items", isDirectory: true)
    }

    private var deletedFolderURL: URL {
        folderURL.appendingPathComponent("deleted", isDirectory: true)
    }

    private func packageURL(for itemIdentifier: UUID) -> URL {
        itemsFolderURL
            .appendingPathComponent(itemIdentifier.uuidString)
            .appendingPathExtension(Self.packageFileExtension)
    }

    private func ensureFolderStructure() throws {
        do {
            try FileManager.default.createDirectory(
                at: itemsFolderURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: deletedFolderURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw ClipboardLocalFolderSyncProviderError.unableToCreateFolder(folderURL)
        }
    }

    private func folderByteCount() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return enumerator.reduce(Int64(0)) { partialResult, entry in
            guard let url = entry as? URL,
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else {
                return partialResult
            }
            return partialResult + Int64(values.fileSize ?? 0)
        }
    }
}

struct SyncProviderRegistry {
    private(set) var providers: [ClipboardSyncProviderDescriptor]

    init(providers: [ClipboardSyncProviderDescriptor] = [.iCloud]) {
        self.providers = providers
    }

    var enabledProviders: [ClipboardSyncProviderDescriptor] {
        providers.filter(\.isEnabled)
    }

    mutating func upsert(_ provider: ClipboardSyncProviderDescriptor) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
    }
}

enum ClipboardItemSyncState: Equatable {
    case localOnly
    case pending
    case synced(Date)
    case unavailable
    case error(String)

    var title: String {
        switch self {
        case .localOnly:
            return "On This Mac"
        case .pending:
            return "Pending Upload"
        case .synced:
            return "Synced"
        case .unavailable:
            return "Sync Unavailable"
        case .error:
            return "Sync Error"
        }
    }

    var systemImageName: String {
        switch self {
        case .localOnly:
            return "macbook"
        case .pending:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle"
        case .unavailable:
            return "arrow.triangle.2.circlepath.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}

@MainActor
final class CloudSyncMonitor: ObservableObject {
    @Published private(set) var state: CloudSyncState = .checkingAccount
    @Published private(set) var lastSuccessfulSync: Date?
    @Published private(set) var lastErrorDescription: String?
    @Published private(set) var containerIdentifiers: [String] = []
    @Published private(set) var lastSuccessfulExport: Date?
    @Published private(set) var lastSuccessfulImport: Date?
    @Published private(set) var recentEvents: [CloudSyncEventSummary] = []

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

    func syncState(for item: ClipboardItem) -> ClipboardItemSyncState {
        if item.isLocalOnly || item.isSensitive {
            return .localOnly
        }
        switch state {
        case .error(let description):
            return .error(description)
        case .configurationRequired, .noAccount, .restricted, .temporarilyUnavailable:
            return .unavailable
        case .checkingAccount, .syncing:
            return .pending
        case .ready:
            guard let lastSuccessfulExport else {
                return .pending
            }
            if let updatedAt = item.updatedAt, updatedAt > lastSuccessfulExport {
                return .pending
            }
            return .synced(lastSuccessfulExport)
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
            if event.type == .export {
                lastSuccessfulExport = event.endDate
            } else if event.type == .import {
                lastSuccessfulImport = event.endDate
            }
            lastErrorDescription = nil
            state = .ready
            logger.info("CloudKit \(self.operationTitle(for: event.type), privacy: .public) completed")
        } else {
            let description = event.error?.localizedDescription ?? "Unknown CloudKit error"
            lastErrorDescription = description
            state = .error(description)
            logger.error("CloudKit event failed: \(description, privacy: .public)")
        }
        record(event)
    }

    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        guard let endDate = event.endDate else {
            return
        }
        let summary = CloudSyncEventSummary(
            id: event.identifier,
            type: operationTitle(for: event.type),
            startDate: event.startDate,
            endDate: endDate,
            succeeded: event.succeeded,
            errorDescription: event.error?.localizedDescription
        )
        recentEvents.removeAll { $0.id == summary.id }
        recentEvents.insert(summary, at: 0)
        recentEvents = Array(recentEvents.prefix(12))
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
