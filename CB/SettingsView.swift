import AppKit
import CoreData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var cloudSyncMonitor: CloudSyncMonitor
    @ObservedObject var screenCaptureService: ScreenCaptureService

    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    )
    private var clipboardItems: FetchedResults<ClipboardItem>

    @AppStorage(ClipboardSettingKey.maximumItemCount)
    private var maximumItemCount = ClipboardSettings.defaults.maximumItemCount

    @AppStorage(ClipboardSettingKey.retentionDays)
    private var retentionDays = ClipboardSettings.defaults.retentionDays

    @AppStorage(ClipboardSettingKey.maximumStorageMegabytes)
    private var maximumStorageMegabytes = ClipboardSettings.defaults.maximumStorageMegabytes

    @AppStorage(ClipboardSettingKey.keepFavorites)
    private var keepFavorites = ClipboardSettings.defaults.keepFavorites

    @AppStorage(ClipboardSettingKey.detectSensitiveContent)
    private var detectSensitiveContent = ClipboardSettings.defaults.detectSensitiveContent

    @AppStorage(ClipboardSettingKey.moveDuplicatesToTop)
    private var moveDuplicatesToTop = ClipboardSettings.defaults.moveDuplicatesToTop

    @AppStorage(ClipboardSettingKey.excludedBundleIdentifiers)
    private var excludedBundleIdentifiers = ""

    @AppStorage(ClipboardSettingKey.protectsSensitivePreviews)
    private var protectsSensitivePreviews = ClipboardSettings.defaults.protectsSensitivePreviews

    @AppStorage(ClipboardSettingKey.sensitiveRetentionMinutes)
    private var sensitiveRetentionMinutes = ClipboardSettings.defaults.sensitiveRetentionMinutes

    @AppStorage(ClipboardSettingKey.textRetentionDays)
    private var textRetentionDays = ClipboardSettings.defaults.textRetentionDays

    @AppStorage(ClipboardSettingKey.imageRetentionDays)
    private var imageRetentionDays = ClipboardSettings.defaults.imageRetentionDays

    @AppStorage(ClipboardSettingKey.fileRetentionDays)
    private var fileRetentionDays = ClipboardSettings.defaults.fileRetentionDays

    @AppStorage(ClipboardSettingKey.mediaRetentionDays)
    private var mediaRetentionDays = ClipboardSettings.defaults.mediaRetentionDays

    @AppStorage(ClipboardSettingKey.otherRetentionDays)
    private var otherRetentionDays = ClipboardSettings.defaults.otherRetentionDays

    @State private var isConfirmingClear = false
    @State private var selectedExcludedBundleIdentifiers: Set<String> = []
    @State private var excludedApplicationErrorMessage: String?

    @AppStorage(ScreenCaptureSettingKey.showsCursor)
    private var screenCaptureShowsCursor = false

    @AppStorage(ScreenCaptureSettingKey.includesWindowShadow)
    private var screenCaptureIncludesWindowShadow = true

    @AppStorage(ScreenCaptureSettingKey.includesChildWindows)
    private var screenCaptureIncludesChildWindows = true

    @AppStorage(ScreenCaptureSettingKey.copiesAfterCapture)
    private var screenCaptureCopiesAfterCapture = false

    @AppStorage(ScreenCaptureSettingKey.copiesOCRText)
    private var screenCaptureCopiesOCRText = true

    @AppStorage(ScreenCapturePostActionKey.automaticallyRecognizesText)
    private var screenCaptureAutomaticallyRecognizesText = ScreenCapturePostActions.defaults.automaticallyRecognizesText

    @AppStorage(ScreenCapturePostActionKey.favoritesCapture)
    private var screenCaptureFavoritesCapture = ScreenCapturePostActions.defaults.favoritesCapture

    @AppStorage(ScreenCapturePostActionKey.pinsCapture)
    private var screenCapturePinsCapture = ScreenCapturePostActions.defaults.pinsCapture

    @AppStorage(ScreenCapturePostActionKey.captureTags)
    private var screenCaptureTags = ""

    @AppStorage(SpotlightSettingKey.indexesClipboardHistory)
    private var indexesClipboardHistory = false

    @AppStorage(ClipboardAutomationSettingKey.trimsWhitespace)
    private var automationTrimsWhitespace = ClipboardAutomationSettings.defaults.trimsWhitespace

    @AppStorage(ClipboardAutomationSettingKey.removesURLTracking)
    private var automationRemovesURLTracking = ClipboardAutomationSettings.defaults.removesURLTracking

    @AppStorage(ClipboardAutomationSettingKey.formatsJSON)
    private var automationFormatsJSON = ClipboardAutomationSettings.defaults.formatsJSON

    @AppStorage(ClipboardAutomationSettingKey.tagsScreenCaptures)
    private var automationTagsScreenCaptures = ClipboardAutomationSettings.defaults.tagsScreenCaptures

    @AppStorage(ClipboardAutomationSettingKey.tagsOCR)
    private var automationTagsOCR = ClipboardAutomationSettings.defaults.tagsOCR

    @AppStorage(ClipboardAutomationSettingKey.tagsCode)
    private var automationTagsCode = ClipboardAutomationSettings.defaults.tagsCode

    var body: some View {
        TabView {
            Form {
                Toggle("Move repeated items to the top", isOn: $moveDuplicatesToTop)
                Toggle("Keep favorites during cleanup", isOn: $keepFavorites)
                Toggle("Show clipboard history in Spotlight", isOn: $indexesClipboardHistory)
                    .onChange(of: indexesClipboardHistory) {
                        ClipboardSpotlightIndexer.shared.rebuild(context: viewContext)
                    }

                Text("Spotlight indexing is off by default. Archived and likely sensitive text are never indexed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gear")
            }

            Form {
                Section("Storage Usage") {
                    LabeledContent("Items") {
                        Text(storageSummary.itemCount.formatted())
                    }
                    LabeledContent("Stored Data") {
                        Text(
                            ByteCountFormatter.string(
                                fromByteCount: storageSummary.byteCount,
                                countStyle: .file
                            )
                        )
                    }
                    if storageSummary.sensitiveItemCount > 0 {
                        LabeledContent("Sensitive Items") {
                            Text(storageSummary.sensitiveItemCount.formatted())
                        }
                    }

                    ForEach(storageSummary.categories.prefix(6)) { category in
                        LabeledContent(displayName(for: category.type)) {
                            Text(
                                "\(category.itemCount) • "
                                    + ByteCountFormatter.string(
                                        fromByteCount: category.byteCount,
                                        countStyle: .file
                                    )
                            )
                        }
                    }

                    Text(
                        "Large binary payloads are managed outside the main SQLite store by Core Data. "
                            + "Their files are removed automatically when their history items are deleted."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Stepper("Maximum items: \(maximumItemCount)", value: $maximumItemCount, in: 50...10_000, step: 50)
                Stepper("Delete after: \(retentionDescription)", value: $retentionDays, in: 0...365)
                Stepper(
                    "Maximum storage: \(maximumStorageMegabytes) MB",
                    value: $maximumStorageMegabytes,
                    in: 25...5_000,
                    step: 25
                )

                Section("Retention by Content Type") {
                    retentionPicker("Text and Code", selection: $textRetentionDays)
                    retentionPicker("Images and Colors", selection: $imageRetentionDays)
                    retentionPicker("Files and Documents", selection: $fileRetentionDays)
                    retentionPicker("Audio and Video", selection: $mediaRetentionDays)
                    retentionPicker("Other Data", selection: $otherRetentionDays)

                    Text("Default uses the global “Delete after” period above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Run Cleanup Now") {
                    HistoryCleanupService().clean(
                        context: viewContext,
                        settings: ClipboardSettings.load()
                    )
                }

                Button("Clear History", role: .destructive) {
                    isConfirmingClear = true
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("History", systemImage: "clock")
            }

            Form {
                Toggle("Skip likely sensitive content", isOn: $detectSensitiveContent)
                Toggle("Conceal sensitive previews", isOn: $protectsSensitivePreviews)
                Stepper(
                    "Delete sensitive items after: \(sensitiveRetentionDescription)",
                    value: $sensitiveRetentionMinutes,
                    in: 0...1_440,
                    step: 15
                )

                Text(
                    detectSensitiveContent
                        ? "Likely passwords, payment cards, private keys, and tokens are discarded."
                        : "Sensitive content is stored. Preview concealment prevents casual exposure but does not encrypt the database."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Section("Excluded Applications") {
                    VStack(spacing: 8) {
                        if excludedApplications.isEmpty {
                            ContentUnavailableView(
                                "No Excluded Applications",
                                systemImage: "app.badge",
                                description: Text("ClipSnap will monitor clipboard changes from every application.")
                            )
                            .frame(minHeight: 120)
                        } else {
                            List(selection: $selectedExcludedBundleIdentifiers) {
                                ForEach(excludedApplications) { application in
                                    ExcludedApplicationRow(application: application)
                                        .tag(application.bundleIdentifier)
                                }
                            }
                            .frame(minHeight: 120)
                        }

                        HStack {
                            Button {
                                addExcludedApplications()
                            } label: {
                                Label("Add Application", systemImage: "plus")
                            }

                            Button {
                                removeSelectedExcludedApplications()
                            } label: {
                                Label("Remove", systemImage: "minus")
                            }
                            .disabled(selectedExcludedBundleIdentifiers.isEmpty)

                            Spacer()
                        }
                    }

                    Text("Add an app to prevent ClipSnap from saving clipboard changes made while that app is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Privacy", systemImage: "hand.raised")
            }

            Form {
                LabeledContent("Screen Recording") {
                    Label(
                        screenCaptureService.hasScreenRecordingAccess ? "Allowed" : "Not Allowed",
                        systemImage: screenCaptureService.hasScreenRecordingAccess
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                }

                if !screenCaptureService.hasScreenRecordingAccess {
                    Button("Open Screen Recording Settings") {
                        screenCaptureService.openScreenRecordingSettings()
                    }
                }

                Toggle("Include pointer", isOn: $screenCaptureShowsCursor)
                Toggle("Include window shadows", isOn: $screenCaptureIncludesWindowShadow)
                Toggle("Include sheets and popovers", isOn: $screenCaptureIncludesChildWindows)
                Toggle("Copy capture to clipboard", isOn: $screenCaptureCopiesAfterCapture)
                Toggle("Copy recognized text to clipboard", isOn: $screenCaptureCopiesOCRText)

                Section("After Capture") {
                    Toggle(
                        "Recognize text automatically",
                        isOn: $screenCaptureAutomaticallyRecognizesText
                    )
                    Toggle("Add to favorites", isOn: $screenCaptureFavoritesCapture)
                    Toggle("Pin capture", isOn: $screenCapturePinsCapture)
                    TextField(
                        "Tags, separated by commas",
                        text: $screenCaptureTags
                    )
                }

                Section {
                    Text(
                        "Screen captures are stored as PNG images. Automatic OCR creates a linked text item when readable text is found."
                    )
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Capture", systemImage: "camera.viewfinder")
            }

            Form {
                Section("Content Rules") {
                    Toggle("Trim surrounding whitespace", isOn: $automationTrimsWhitespace)
                    Toggle("Remove URL tracking parameters", isOn: $automationRemovesURLTracking)
                    Toggle("Detect and format JSON", isOn: $automationFormatsJSON)
                }

                Section("Automatic Tags") {
                    Toggle("Tag screenshots", isOn: $automationTagsScreenCaptures)
                    Toggle("Tag recognized text", isOn: $automationTagsOCR)
                    Toggle("Tag code and structured data", isOn: $automationTagsCode)
                }

                Text("Rules run locally before duplicate detection and sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Automation", systemImage: "wand.and.stars")
            }

            Form {
                LabeledContent("Status") {
                    Label(
                        cloudSyncMonitor.state.title,
                        systemImage: cloudSyncMonitor.state.systemImageName
                    )
                }

                if let lastSuccessfulSync = cloudSyncMonitor.lastSuccessfulSync {
                    LabeledContent("Last Successful Sync") {
                        Text(lastSuccessfulSync.formatted(date: .abbreviated, time: .standard))
                    }
                }

                if let lastSuccessfulExport = cloudSyncMonitor.lastSuccessfulExport {
                    LabeledContent("Last Upload") {
                        Text(lastSuccessfulExport.formatted(date: .abbreviated, time: .standard))
                    }
                }

                if let lastSuccessfulImport = cloudSyncMonitor.lastSuccessfulImport {
                    LabeledContent("Last Download") {
                        Text(lastSuccessfulImport.formatted(date: .abbreviated, time: .standard))
                    }
                }

                if let lastErrorDescription = cloudSyncMonitor.lastErrorDescription {
                    Section("Last Error") {
                        Text(lastErrorDescription)
                            .textSelection(.enabled)
                    }
                }

                if cloudSyncMonitor.containerIdentifiers.isEmpty {
                    Section("Setup") {
                        Text("Add the iCloud capability with CloudKit to the CB target, select a private CloudKit container, and enable Remote notifications.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Containers") {
                        ForEach(cloudSyncMonitor.containerIdentifiers, id: \.self) { identifier in
                            Text(identifier)
                                .textSelection(.enabled)
                        }
                    }

                    Button("Refresh Account Status") {
                        Task {
                            await cloudSyncMonitor.refreshAccountStatus()
                        }
                    }
                }

                if !cloudSyncMonitor.recentEvents.isEmpty {
                    Section("Recent Activity") {
                        ForEach(cloudSyncMonitor.recentEvents) { event in
                            HStack {
                                Image(
                                    systemName: event.succeeded
                                        ? "checkmark.circle.fill"
                                        : "exclamationmark.triangle.fill"
                                )
                                .foregroundStyle(event.succeeded ? .green : .orange)

                                VStack(alignment: .leading) {
                                    Text(event.type)
                                    Text(event.endDate.formatted(date: .omitted, time: .standard))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(
                                    event.endDate.timeIntervalSince(event.startDate),
                                    format: .number.precision(.fractionLength(1))
                                )
                                Text("s")
                            }
                            .help(event.errorDescription ?? event.type)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("iCloud", systemImage: "icloud")
            }
        }
        .frame(width: 520, height: 360)
        .confirmationDialog(
            "Clear Clipboard History?",
            isPresented: $isConfirmingClear
        ) {
            Button("Clear History", role: .destructive, action: clearHistory)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned and favorite items will also be removed.")
        }
        .alert(
            "Excluded Applications",
            isPresented: Binding(
                get: { excludedApplicationErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        excludedApplicationErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(excludedApplicationErrorMessage ?? "")
        }
    }

    private var retentionDescription: String {
        retentionDays == 0 ? "Never" : "\(retentionDays) days"
    }

    private var sensitiveRetentionDescription: String {
        if sensitiveRetentionMinutes == 0 {
            return "Never"
        }
        if sensitiveRetentionMinutes < 60 {
            return "\(sensitiveRetentionMinutes) minutes"
        }
        let hours = sensitiveRetentionMinutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    private var storageSummary: ClipboardStorageSummary {
        ClipboardStorageSummary.make(
            from: clipboardItems.map {
                ClipboardStorageItem(
                    type: $0.type ?? ClipboardItemType.unknown,
                    byteCount: $0.byteCount,
                    isSensitive: $0.isSensitive
                )
            }
        )
    }

    private var excludedApplications: [ExcludedApplication] {
        ClipboardSettings.parseBundleIdentifiers(excludedBundleIdentifiers)
            .map(ExcludedApplication.init(bundleIdentifier:))
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private func displayName(for type: String) -> String {
        switch type {
        case ClipboardItemType.text:
            return "Text"
        case ClipboardItemType.image:
            return "Images"
        case ClipboardItemType.file:
            return "Files"
        case ClipboardItemType.url:
            return "URLs"
        case ClipboardItemType.audio:
            return "Audio"
        case ClipboardItemType.video:
            return "Video"
        case ClipboardItemType.archive:
            return "Archives"
        case ClipboardItemType.pdf:
            return "PDFs"
        default:
            return type.capitalized
        }
    }

    private func retentionPicker(
        _ title: String,
        selection: Binding<Int>
    ) -> some View {
        Picker(title, selection: selection) {
            Text("Default").tag(-1)
            Text("Never").tag(0)
            Text("1 day").tag(1)
            Text("7 days").tag(7)
            Text("30 days").tag(30)
            Text("90 days").tag(90)
            Text("1 year").tag(365)
        }
    }

    private func clearHistory() {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ClipboardItem")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs

        do {
            let result = try viewContext.execute(deleteRequest) as? NSBatchDeleteResult
            let objectIDs = result?.result as? [NSManagedObjectID] ?? []
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                into: [viewContext]
            )
            ClipboardSpotlightIndexer.shared.deleteAll()
        } catch {
            viewContext.rollback()
        }
    }

    private func addExcludedApplications() {
        let panel = NSOpenPanel()
        panel.title = "Choose Applications to Exclude"
        panel.prompt = "Add"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else {
            return
        }

        var identifiers = ClipboardSettings.parseBundleIdentifiers(excludedBundleIdentifiers)
        var skippedApplicationNames: [String] = []

        for url in panel.urls {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if let bundleIdentifier = Bundle(url: url)?.bundleIdentifier?.lowercased() {
                identifiers.insert(bundleIdentifier)
            } else {
                skippedApplicationNames.append(url.deletingPathExtension().lastPathComponent)
            }
        }

        excludedBundleIdentifiers = ClipboardSettings.formattedBundleIdentifiers(identifiers)
        selectedExcludedBundleIdentifiers = selectedExcludedBundleIdentifiers.intersection(identifiers)

        if !skippedApplicationNames.isEmpty {
            excludedApplicationErrorMessage = "Could not read a bundle identifier for: "
                + skippedApplicationNames.joined(separator: ", ")
        }
    }

    private func removeSelectedExcludedApplications() {
        var identifiers = ClipboardSettings.parseBundleIdentifiers(excludedBundleIdentifiers)
        identifiers.subtract(selectedExcludedBundleIdentifiers)
        excludedBundleIdentifiers = ClipboardSettings.formattedBundleIdentifiers(identifiers)
        selectedExcludedBundleIdentifiers.removeAll()
    }
}

private struct ExcludedApplication: Identifiable {
    let bundleIdentifier: String

    var id: String {
        bundleIdentifier
    }

    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    var displayName: String {
        if let applicationURL,
           let name = Bundle(url: applicationURL)?.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
           ) as? String ?? Bundle(url: applicationURL)?.object(
            forInfoDictionaryKey: "CFBundleName"
           ) as? String {
            return name
        }

        return bundleIdentifier
    }

    var icon: NSImage {
        if let applicationURL {
            return NSWorkspace.shared.icon(forFile: applicationURL.path)
        }

        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

private struct ExcludedApplicationRow: View {
    let application: ExcludedApplication

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: application.icon)
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(application.displayName)
                Text(application.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}
