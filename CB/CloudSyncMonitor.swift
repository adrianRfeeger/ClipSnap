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
    case missingUserSelectedReadWriteEntitlement
    case unableToCreateFolder(URL, String)
    case unableToReadFolder(URL, String?)
    case unableToCoordinate(URL, String)

    var errorDescription: String? {
        switch self {
        case .missingUserSelectedReadWriteEntitlement:
            return "This build only has read-only access to user-selected files. In Xcode, set Signing & Capabilities > App Sandbox > User Selected File to Read/Write, then rebuild ClipSnap."
        case .unableToCreateFolder(let url, let reason):
            return "ClipSnap could not create the sync folder at \(url.path): \(reason)"
        case .unableToReadFolder(let url, let reason):
            if let reason {
                return "ClipSnap could not read the sync folder at \(url.path): \(reason)"
            }
            return "ClipSnap could not read the sync folder at \(url.path)."
        case .unableToCoordinate(let url, let reason):
            return "ClipSnap could not access the sync folder at \(url.path): \(reason)"
        }
    }
}

struct ClipboardLocalFolderSyncProvider: ClipboardSyncProvider {
    let folderURL: URL
    let securityScopedBookmarkData: Data?
    var descriptor: ClipboardSyncProviderDescriptor

    init(
        folderURL: URL,
        securityScopedBookmarkData: Data? = nil,
        descriptor: ClipboardSyncProviderDescriptor = .localFolder
    ) {
        self.securityScopedBookmarkData = securityScopedBookmarkData
        self.folderURL = Self.resolvedFolderURL(
            fallbackURL: folderURL,
            bookmarkData: securityScopedBookmarkData
        )
        self.descriptor = descriptor
    }

    func currentStatus() async -> ClipboardSyncProviderStatus {
        do {
            try Self.validateUserSelectedReadWriteEntitlement()
            let quotaUsedBytes = try withSecurityScopedAccess {
                try runDirectlyThenCoordinateWriting(folderURL) {
                    try ensureFolderStructure()
                    return folderByteCount()
                }
            }
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
        try Self.validateUserSelectedReadWriteEntitlement()
        try withSecurityScopedAccess {
            let url = packageURL(for: package.itemIdentifier)
            try runDirectlyThenCoordinateWriting(folderURL) {
                try ensureFolderStructure()
                try writeData(package.encodedData(), to: url)
            }
        }
    }

    func downloadPackages(since date: Date?) async throws -> [ClipboardSyncPackage] {
        try withSecurityScopedAccess {
            try runDirectlyThenCoordinateReading(folderURL) {
                try ensureFolderStructure()
                return try readPackages(since: date)
            }
        }
    }

    func downloadDeleteMarkers(since date: Date?) async throws -> [ClipboardSyncDeleteMarker] {
        try withSecurityScopedAccess {
            try runDirectlyThenCoordinateReading(folderURL) {
                try ensureFolderStructure()
                return try readDeleteMarkers(since: date)
            }
        }
    }

    func deletePackage(itemIdentifier: UUID, updatedAt: Date) async throws {
        try Self.validateUserSelectedReadWriteEntitlement()
        try withSecurityScopedAccess {
            try runDirectlyThenCoordinateWriting(folderURL) {
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
                try writeData(try encoder.encode(marker), to: markerURL)
            }
        }
    }

    static let packageFileExtension = "clipsnapitem"
    static let deleteMarkerFileExtension = "clipsnapdelete"

    static var canWriteUserSelectedFiles: Bool {
        !boolEntitlement("com.apple.security.app-sandbox")
            || boolEntitlement("com.apple.security.files.user-selected.read-write")
    }

    private static func validateUserSelectedReadWriteEntitlement() throws {
        guard canWriteUserSelectedFiles else {
            throw ClipboardLocalFolderSyncProviderError.missingUserSelectedReadWriteEntitlement
        }
    }

    private static func resolvedFolderURL(fallbackURL: URL, bookmarkData: Data?) -> URL {
        guard let bookmarkData,
              !bookmarkData.isEmpty else {
            return fallbackURL
        }

        var isStale = false
        do {
            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            return fallbackURL
        }
    }

    private func readPackages(since date: Date?) throws -> [ClipboardSyncPackage] {
        guard let enumerator = FileManager.default.enumerator(
            at: itemsFolderURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ClipboardLocalFolderSyncProviderError.unableToReadFolder(itemsFolderURL, nil)
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

    private func readDeleteMarkers(since date: Date?) throws -> [ClipboardSyncDeleteMarker] {
        guard let enumerator = FileManager.default.enumerator(
            at: deletedFolderURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ClipboardLocalFolderSyncProviderError.unableToReadFolder(deletedFolderURL, nil)
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

    private var itemsFolderURL: URL {
        usesFlatFolderLayout
            ? folderURL
            : folderURL.appendingPathComponent("items", isDirectory: true)
    }

    private var deletedFolderURL: URL {
        usesFlatFolderLayout
            ? folderURL
            : folderURL.appendingPathComponent("deleted", isDirectory: true)
    }

    private func packageURL(for itemIdentifier: UUID) -> URL {
        itemsFolderURL
            .appendingPathComponent(itemIdentifier.uuidString)
            .appendingPathExtension(Self.packageFileExtension)
    }

    private func withSecurityScopedAccess<T>(_ operation: () throws -> T) throws -> T {
        let didStartAccessing = securityScopedBookmarkData != nil
            && folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        return try operation()
    }

    private func runDirectlyThenCoordinateReading<T>(_ url: URL, operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let directError {
            do {
                return try coordinateReading(url) {
                    do {
                        return try operation()
                    } catch let coordinatedError {
                        throw combinedAccessError(
                            url: url,
                            directError: directError,
                            coordinatedError: coordinatedError
                        )
                    }
                }
            } catch let coordinatedError {
                throw combinedAccessError(
                    url: url,
                    directError: directError,
                    coordinatedError: coordinatedError
                )
            }
        }
    }

    private func runDirectlyThenCoordinateWriting<T>(_ url: URL, operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let directError {
            do {
                return try coordinateWriting(url) {
                    do {
                        return try operation()
                    } catch let coordinatedError {
                        throw combinedAccessError(
                            url: url,
                            directError: directError,
                            coordinatedError: coordinatedError
                        )
                    }
                }
            } catch let coordinatedError {
                throw combinedAccessError(
                    url: url,
                    directError: directError,
                    coordinatedError: coordinatedError
                )
            }
        }
    }

    private func coordinateReading<T>(_ url: URL, operation: () throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationResult: Result<T, Error>?

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { _ in
            operationResult = Result {
                try operation()
            }
        }

        if let operationResult {
            return try operationResult.get()
        }

        throw ClipboardLocalFolderSyncProviderError.unableToCoordinate(
            url,
            coordinationError?.localizedDescription ?? "The folder could not be coordinated for reading."
        )
    }

    private func coordinateWriting<T>(_ url: URL, operation: () throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationResult: Result<T, Error>?

        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { _ in
            operationResult = Result {
                try operation()
            }
        }

        if let operationResult {
            return try operationResult.get()
        }

        throw ClipboardLocalFolderSyncProviderError.unableToCoordinate(
            url,
            coordinationError?.localizedDescription ?? "The folder could not be coordinated for writing."
        )
    }

    private func combinedAccessError(
        url: URL,
        directError: Error,
        coordinatedError: Error
    ) -> ClipboardLocalFolderSyncProviderError {
        let providerHint = isFileProviderBacked
            ? " This folder is inside CloudStorage; use Grant Access in ClipSnap, and make sure the folder is available offline in Finder. If OneDrive still denies writes, choose a normal local folder and let OneDrive sync that folder after ClipSnap writes to it."
            : ""
        return ClipboardLocalFolderSyncProviderError.unableToCoordinate(
            url,
            "Direct access failed with \(directError.localizedDescription). Coordinated access failed with \(coordinatedError.localizedDescription).\(providerHint)"
        )
    }

    private var isFileProviderBacked: Bool {
        folderURL.path.contains("/Library/CloudStorage/")
    }

    private var usesFlatFolderLayout: Bool {
        isFileProviderBacked
    }

    private static func boolEntitlement(_ key: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) else {
            return false
        }

        return (value as? Bool) == true
    }

    private func ensureFolderStructure() throws {
        do {
            if usesFlatFolderLayout {
                try FileManager.default.createDirectory(
                    at: folderURL,
                    withIntermediateDirectories: true
                )
                return
            }

            try FileManager.default.createDirectory(
                at: itemsFolderURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: deletedFolderURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw ClipboardLocalFolderSyncProviderError.unableToCreateFolder(
                folderURL,
                error.localizedDescription
            )
        }
    }

    private func writeData(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            try data.write(to: url)
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

struct ClipboardLocalFolderSyncSummary: Equatable {
    var exportedCount = 0
    var insertedCount = 0
    var updatedCount = 0
    var deletedCount = 0
    var conflictCount = 0
    var keptNewerLocalCount = 0

    var exportMessage: String {
        exportedCount == 1
            ? "Exported 1 item to local folder."
            : "Exported \(exportedCount) items to local folder."
    }

    var importMessage: String {
        "Imported \(insertedCount), updated \(updatedCount), deleted \(deletedCount), preserved \(conflictCount) conflict\(conflictCount == 1 ? "" : "s"), kept \(keptNewerLocalCount) newer local."
    }

    var syncMessage: String {
        "\(importMessage) \(exportMessage)"
    }
}

enum ClipboardLocalFolderSyncService {
    @MainActor
    static func exportItems(
        in context: NSManagedObjectContext,
        provider: ClipboardLocalFolderSyncProvider,
        defaults: UserDefaults = .standard
    ) async throws -> ClipboardLocalFolderSyncSummary {
        try await ClipboardLocalFolderDeletionQueue.flush(
            using: provider,
            defaults: defaults
        )
        let items = try fetchClipboardItems(in: context)
        let exportableItems = items.filter {
            !$0.isLocalOnly && !$0.isSensitive
        }

        for item in exportableItems {
            try await provider.upload(ClipboardSyncPackage(item: item))
        }

        return ClipboardLocalFolderSyncSummary(exportedCount: exportableItems.count)
    }

    @MainActor
    static func importItems(
        in context: NSManagedObjectContext,
        provider: ClipboardLocalFolderSyncProvider,
        defaults: UserDefaults = .standard
    ) async throws -> ClipboardLocalFolderSyncSummary {
        try await ClipboardLocalFolderDeletionQueue.flush(
            using: provider,
            defaults: defaults
        )
        let items = try fetchClipboardItems(in: context)
        let deleteMarkers = try await provider.downloadDeleteMarkers(since: nil)
        let packages = try await provider.downloadPackages(since: nil)
        let newestDeleteMarkers = deleteMarkers.reduce(
            into: [UUID: ClipboardSyncDeleteMarker]()
        ) { result, marker in
            guard marker.updatedAt > (result[marker.itemIdentifier]?.updatedAt ?? .distantPast) else {
                return
            }
            result[marker.itemIdentifier] = marker
        }
        var existingItems = Dictionary(
            uniqueKeysWithValues: items.compactMap { item in
                item.id.map { ($0, item) }
            }
        )
        var changedItems: [ClipboardItem] = []
        var deletedItemSnapshots: [ClipboardDeletionSnapshot] = []
        var summary = ClipboardLocalFolderSyncSummary()

        for marker in newestDeleteMarkers.values {
            if let existingItem = existingItems[marker.itemIdentifier],
               existingItem.isLocalOnly || existingItem.isSensitive {
                continue
            }
            let resolution = ClipboardSyncConflictResolver.resolveDeleteMarker(
                marker,
                existingItem: existingItems[marker.itemIdentifier]
            )
            switch resolution {
            case .deleteLocal:
                if let item = existingItems[marker.itemIdentifier] {
                    deletedItemSnapshots.append(
                        ClipboardDeletionCoordinator.snapshot([item])
                    )
                    context.delete(item)
                    existingItems.removeValue(forKey: marker.itemIdentifier)
                    summary.deletedCount += 1
                }
            case .keepNewerLocal:
                summary.keptNewerLocalCount += 1
            case .missingLocal:
                break
            }
        }

        for package in packages {
            if let marker = newestDeleteMarkers[package.itemIdentifier],
               marker.updatedAt >= package.item.updatedAt {
                continue
            }
            if let existingItem = existingItems[package.itemIdentifier],
               existingItem.isLocalOnly || existingItem.isSensitive {
                continue
            }
            guard existingItems[package.itemIdentifier]?.isDeleted != true else {
                continue
            }
            let merge = ClipboardSyncConflictResolver.merge(
                package: package,
                existingItem: existingItems[package.itemIdentifier],
                in: context
            )
            if let item = merge.item,
               merge.result != .unchanged {
                changedItems.append(item)
            }

            switch merge.result {
            case .inserted:
                summary.insertedCount += 1
            case .updatedMetadata:
                summary.updatedCount += 1
            case .preservedConflict:
                summary.conflictCount += 1
            case .unchanged:
                break
            }
        }

        try context.save()
        deletedItemSnapshots.forEach {
            ClipboardDeletionCoordinator.finalize(
                $0,
                enqueueLocalFolderTombstones: false,
                defaults: defaults
            )
        }
        changedItems.forEach(ClipboardSpotlightIndexer.shared.indexItem)
        return summary
    }

    @MainActor
    static func sync(
        in context: NSManagedObjectContext,
        provider: ClipboardLocalFolderSyncProvider,
        defaults: UserDefaults = .standard
    ) async throws -> ClipboardLocalFolderSyncSummary {
        var summary = try await importItems(
            in: context,
            provider: provider,
            defaults: defaults
        )
        let exportSummary = try await exportItems(
            in: context,
            provider: provider,
            defaults: defaults
        )
        summary.exportedCount = exportSummary.exportedCount
        return summary
    }

    @MainActor
    private static func fetchClipboardItems(in context: NSManagedObjectContext) throws -> [ClipboardItem] {
        let request = ClipboardItem.fetchRequest()
        return try context.fetch(request)
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
