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

    @AppStorage(ClipboardSettingKey.menuBarItemCount)
    private var menuBarItemCount = ClipboardSettings.defaults.menuBarItemCount

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

    @AppStorage(ClipboardSettingKey.appRules)
    private var appRulesData = ClipboardSettings.formattedAppRules([])

    @AppStorage(ClipboardSettingKey.ignoresInternalPasteboardTypes)
    private var ignoresInternalPasteboardTypes = ClipboardSettings.defaults.ignoresInternalPasteboardTypes

    @AppStorage(ClipboardSettingKey.ignoredPasteboardTypes)
    private var ignoredPasteboardTypes = ClipboardSettings.formattedPasteboardTypes(
        ClipboardSettings.defaults.ignoredPasteboardTypes
    )

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

    @AppStorage(ClipboardSettingKey.lastCleanupDate)
    private var lastCleanupDate = 0.0

    @AppStorage(ClipboardSettingKey.lastCleanupDeletedCount)
    private var lastCleanupDeletedCount = 0

    @State private var isConfirmingClear = false
    @State private var pendingHealthCleanupAction: ClipboardHealthCleanupAction?
    @State private var selectedExcludedBundleIdentifiers: Set<String> = []
    @State private var excludedApplicationErrorMessage: String?
    @State private var diagnosticsErrorMessage: String?
    @State private var applicationRuleSearchText = ""
    @State private var isShowingSetup = false

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

    @AppStorage(ScreenCaptureSettingKey.captureDelaySeconds)
    private var screenCaptureDelaySeconds = 5

    @AppStorage(ScreenCaptureSettingKey.recordingAudioMode)
    private var screenRecordingAudioMode = ScreenRecordingAudioMode.none.rawValue

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
                Stepper("Menu bar items: \(menuBarItemCount)", value: $menuBarItemCount, in: 1...50)
                Toggle("Show clipboard history in Spotlight", isOn: $indexesClipboardHistory)
                    .onChange(of: indexesClipboardHistory) {
                        ClipboardSpotlightIndexer.shared.rebuild(context: viewContext)
                    }

                Text("Spotlight indexing is off by default. Archived and likely sensitive text are never indexed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Setup Checklist…") {
                    isShowingSetup = true
                }

                Section("Diagnostics") {
                    Button("Copy Diagnostic Summary") {
                        ClipboardDiagnosticsService.copySummary(
                            items: Array(clipboardItems),
                            settings: ClipboardSettings.load(),
                            cloudSyncMonitor: cloudSyncMonitor
                        )
                    }

                    Button("Export Diagnostic Summary…") {
                        do {
                            try ClipboardDiagnosticsService.exportSummary(
                                items: Array(clipboardItems),
                                settings: ClipboardSettings.load(),
                                cloudSyncMonitor: cloudSyncMonitor
                            )
                        } catch {
                            diagnosticsErrorMessage = error.localizedDescription
                        }
                    }

                    Text("Diagnostics redact clipboard content and stay local unless you export them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                        StorageCategoryRow(
                            title: displayName(for: category.type),
                            category: category
                        )
                    }

                    Text(
                        "Large binary payloads are managed outside the main SQLite store by Core Data. "
                            + "Their files are removed automatically when their history items are deleted."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                healthSection

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
                    lastCleanupDate = Date().timeIntervalSince1970
                    lastCleanupDeletedCount = 0
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

                Section("Application Rules") {
                    VStack(spacing: 8) {
                        TextField("Search applications", text: $applicationRuleSearchText)
                            .textFieldStyle(.roundedBorder)

                        if excludedApplications.isEmpty {
                            ContentUnavailableView(
                                "No Application Rules",
                                systemImage: "app.badge",
                                description: Text("ClipSnap will monitor clipboard changes from every application.")
                            )
                            .frame(minHeight: 120)
                        } else if filteredExcludedApplications.isEmpty {
                            ContentUnavailableView.search(text: applicationRuleSearchText)
                                .frame(minHeight: 120)
                        } else {
                            List(selection: $selectedExcludedBundleIdentifiers) {
                                ForEach(filteredExcludedApplications) { application in
                                    ExcludedApplicationRow(
                                        application: application,
                                        rule: appRule(for: application.bundleIdentifier)
                                    )
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

                    Text("Add an app to ignore, keep local, conceal, tag, or retain clipboard changes from that source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let selectedApplicationRule {
                    Section("Selected Application Rule") {
                        Toggle(
                            "Ignore clipboard changes",
                            isOn: appRuleBoolBinding(
                                for: selectedApplicationRule.bundleIdentifier,
                                keyPath: \.ignoresClipboard
                            )
                        )

                        Toggle(
                            "Keep captures on this Mac",
                            isOn: appRuleBoolBinding(
                                for: selectedApplicationRule.bundleIdentifier,
                                keyPath: \.keepsLocalOnly
                            )
                        )

                        Toggle(
                            "Conceal previews",
                            isOn: appRuleBoolBinding(
                                for: selectedApplicationRule.bundleIdentifier,
                                keyPath: \.concealsPreviews
                            )
                        )

                        TextField(
                            "Automatic tags, separated by commas",
                            text: appRuleStringBinding(
                                for: selectedApplicationRule.bundleIdentifier,
                                keyPath: \.automaticTags
                            )
                        )

                        Picker(
                            "Retention",
                            selection: appRuleIntBinding(
                                for: selectedApplicationRule.bundleIdentifier,
                                keyPath: \.retentionDays
                            )
                        ) {
                            Text("Default").tag(-1)
                            Text("Never").tag(0)
                            Text("1 day").tag(1)
                            Text("7 days").tag(7)
                            Text("30 days").tag(30)
                            Text("90 days").tag(90)
                            Text("1 year").tag(365)
                        }
                    }
                }

                Section("Internal Clipboard Metadata") {
                    Toggle(
                        "Ignore internal app clipboard metadata",
                        isOn: $ignoresInternalPasteboardTypes
                    )

                    TextEditor(text: $ignoredPasteboardTypes)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 96)
                        .disabled(!ignoresInternalPasteboardTypes)

                    HStack {
                        Text("\(ignoredPasteboardTypeCount) ignored types")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Reset Defaults") {
                            ignoredPasteboardTypes = ClipboardSettings.formattedPasteboardTypes(
                                ClipboardSettings.defaults.ignoredPasteboardTypes
                            )
                        }
                    }

                    Text("Use one pasteboard type per line. Suffix a type with * to ignore a family of private types, such as org.chromium.internal.*.")
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
                Stepper(
                    "Delayed capture: \(captureDelayDescription)",
                    value: $screenCaptureDelaySeconds,
                    in: 1...30
                )

                Section("Screen Recording") {
                    Picker("Audio", selection: $screenRecordingAudioMode) {
                        ForEach(ScreenRecordingAudioMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }

                    Text("If audio capture cannot start, ClipSnap falls back to a screen-only recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
                            CloudSyncEventRow(event: event)
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
        .confirmationDialog(
            pendingHealthCleanupAction?.confirmationTitle ?? "Clean Up Clipboard?",
            isPresented: Binding(
                get: { pendingHealthCleanupAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingHealthCleanupAction = nil
                    }
                }
            )
        ) {
            if let action = pendingHealthCleanupAction {
                let targets = cleanupTargets(for: action)
                Button(action.confirmationButtonTitle, role: .destructive) {
                    performHealthCleanup(action)
                    pendingHealthCleanupAction = nil
                }
                .disabled(targets.isEmpty)
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            if let action = pendingHealthCleanupAction {
                let targets = cleanupTargets(for: action)
                Text(cleanupPreviewDescription(for: action, targets: targets))
            }
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
        .alert(
            "Diagnostics",
            isPresented: Binding(
                get: { diagnosticsErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        diagnosticsErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(diagnosticsErrorMessage ?? "")
        }
        .sheet(isPresented: $isShowingSetup) {
            ClipSnapSetupView(
                cloudSyncMonitor: cloudSyncMonitor,
                screenCaptureService: screenCaptureService
            ) {
                isShowingSetup = false
            }
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

    private var captureDelayDescription: String {
        screenCaptureDelaySeconds == 1 ? "1 second" : "\(screenCaptureDelaySeconds) seconds"
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

    private var healthSection: some View {
        Section("Clipboard Health") {
            healthMetrics
            healthCleanupMenu
            largestItemsDisclosure
        }
    }

    private var healthMetrics: some View {
        Group {
            LabeledContent("Storage Limit") {
                Text(healthSummary.storageLimitDescription)
            }
            if let largestItem = healthSummary.largestItems.first {
                LabeledContent("Largest Item") {
                    Text(largestItem.description)
                }
            }
            LabeledContent("Duplicate Groups") {
                Text(healthSummary.duplicateGroupCount.formatted())
            }
            LabeledContent("Unknown/Data Items") {
                Text(healthSummary.unknownDataCount.formatted())
            }
            LabeledContent("Unsynced Items") {
                Text(healthSummary.unsyncedCount.formatted())
            }
            LabeledContent("Local-Only Items") {
                Text(healthSummary.localOnlyCount.formatted())
            }
            if let lastCleanupDescription {
                LabeledContent("Last Cleanup") {
                    Text(lastCleanupDescription)
                }
            }
        }
    }

    private var healthCleanupMenu: some View {
        Menu("Clean Up") {
            Button("Large Items…") {
                pendingHealthCleanupAction = .largeItems
            }
            .disabled(cleanupTargets(for: .largeItems).isEmpty)

            Button("Old Screenshots…") {
                pendingHealthCleanupAction = .oldScreenshots
            }
            .disabled(cleanupTargets(for: .oldScreenshots).isEmpty)

            Button("Duplicates…") {
                pendingHealthCleanupAction = .duplicates
            }
            .disabled(cleanupTargets(for: .duplicates).isEmpty)

            Button("Unknown/Data Items…") {
                pendingHealthCleanupAction = .unknownData
            }
            .disabled(cleanupTargets(for: .unknownData).isEmpty)
        }
    }

    @ViewBuilder
    private var largestItemsDisclosure: some View {
        if !healthSummary.largestItems.isEmpty {
            DisclosureGroup("Largest Items") {
                ForEach(healthSummary.largestItems) { item in
                    LabeledContent(item.title) {
                        Text(item.sizeDescription)
                    }
                }
            }
        }
    }

    private var healthSummary: ClipboardHealthSummary {
        ClipboardHealthSummary.make(
            from: clipboardItems.map { ClipboardHealthItem(item: $0) },
            storageLimitMegabytes: maximumStorageMegabytes
        )
    }

    private var lastCleanupDescription: String? {
        guard lastCleanupDate > 0 else {
            return nil
        }

        let date = Date(timeIntervalSince1970: lastCleanupDate)
        let suffix = lastCleanupDeletedCount == 1
            ? "1 item removed"
            : "\(lastCleanupDeletedCount) items removed"
        return "\(date.formatted(date: .abbreviated, time: .shortened)) - \(suffix)"
    }

    private var excludedApplications: [ExcludedApplication] {
        let ruleIdentifiers = Set(appRules.map(\.bundleIdentifier))
        let identifiers = ClipboardSettings.parseBundleIdentifiers(excludedBundleIdentifiers)
            .union(ruleIdentifiers)
        return identifiers
            .map(ExcludedApplication.init(bundleIdentifier:))
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private var filteredExcludedApplications: [ExcludedApplication] {
        let query = applicationRuleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return excludedApplications
        }

        return excludedApplications.filter { application in
            let rule = appRule(for: application.bundleIdentifier)
            return application.displayName.localizedCaseInsensitiveContains(query)
                || application.bundleIdentifier.localizedCaseInsensitiveContains(query)
                || rule.automaticTags.localizedCaseInsensitiveContains(query)
                || (rule.ignoresClipboard && "ignore".localizedCaseInsensitiveContains(query))
                || (rule.keepsLocalOnly && "local".localizedCaseInsensitiveContains(query))
                || (rule.concealsPreviews && "conceal".localizedCaseInsensitiveContains(query))
        }
    }

    private var appRules: [ClipboardAppRule] {
        ClipboardSettings.parseAppRules(appRulesData)
    }

    private var selectedApplicationRule: ClipboardAppRule? {
        guard selectedExcludedBundleIdentifiers.count == 1,
              let bundleIdentifier = selectedExcludedBundleIdentifiers.first else {
            return nil
        }

        return appRule(for: bundleIdentifier)
    }

    private var ignoredPasteboardTypeCount: Int {
        ClipboardSettings.parsePasteboardTypes(ignoredPasteboardTypes).count
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
            lastCleanupDate = Date().timeIntervalSince1970
            lastCleanupDeletedCount = objectIDs.count
        } catch {
            viewContext.rollback()
        }
    }

    private func cleanupTargets(for action: ClipboardHealthCleanupAction) -> [ClipboardItem] {
        let protectedItems = clipboardItems.filter { $0.isPinned || $0.isFavorite }
        let protectedIdentifiers = Set(protectedItems.map(\.objectID))

        switch action {
        case .largeItems:
            return clipboardItems.filter {
                !protectedIdentifiers.contains($0.objectID)
                    && $0.byteCount >= ClipboardHealthSummary.largeItemThreshold
            }
        case .oldScreenshots:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
            return clipboardItems.filter {
                !protectedIdentifiers.contains($0.objectID)
                    && $0.isScreenCapture
                    && ($0.createdAt ?? .distantFuture) < cutoff
            }
        case .unknownData:
            return clipboardItems.filter {
                !protectedIdentifiers.contains($0.objectID)
                    && ($0.type == ClipboardItemType.unknown || $0.type == ClipboardItemType.data)
            }
        case .duplicates:
            return duplicateCleanupTargets(excluding: protectedIdentifiers)
        }
    }

    private func duplicateCleanupTargets(excluding protectedIdentifiers: Set<NSManagedObjectID>) -> [ClipboardItem] {
        let grouped = Dictionary(
            grouping: clipboardItems.compactMap { item -> ClipboardItem? in
                guard let contentHash = item.contentHash,
                      !contentHash.isEmpty else {
                    return nil
                }
                return item
            },
            by: { $0.contentHash ?? "" }
        )

        return grouped.values.flatMap { group in
            let sortedGroup = group.sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            return sortedGroup.dropFirst().filter {
                !protectedIdentifiers.contains($0.objectID)
            }
        }
    }

    private func cleanupPreviewDescription(
        for action: ClipboardHealthCleanupAction,
        targets: [ClipboardItem]
    ) -> String {
        let byteCount = targets.reduce(Int64(0)) { $0 + $1.byteCount }
        let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        let itemDescription = targets.count == 1 ? "1 item" : "\(targets.count) items"
        return "\(action.previewDescription) ClipSnap will delete \(itemDescription), freeing about \(size). Pinned and favorite items are kept."
    }

    private func performHealthCleanup(_ action: ClipboardHealthCleanupAction) {
        let targets = cleanupTargets(for: action)
        guard !targets.isEmpty else {
            return
        }

        ClipboardSpotlightIndexer.shared.deleteIdentifiers(
            targets.compactMap { $0.id?.uuidString }
        )
        targets.forEach(viewContext.delete)

        do {
            try viewContext.save()
            lastCleanupDate = Date().timeIntervalSince1970
            lastCleanupDeletedCount = targets.count
        } catch {
            viewContext.rollback()
        }
    }

    private func appRule(for bundleIdentifier: String) -> ClipboardAppRule {
        if let rule = appRules.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return rule
        }

        return ClipboardAppRule(
            bundleIdentifier: bundleIdentifier,
            ignoresClipboard: ClipboardSettings.parseBundleIdentifiers(excludedBundleIdentifiers)
                .contains(bundleIdentifier)
        )
    }

    private func updateAppRule(_ rule: ClipboardAppRule) {
        let normalizedRule = rule.normalized
        var rules = appRules.filter { $0.bundleIdentifier != normalizedRule.bundleIdentifier }
        var excludedIdentifiers = ClipboardSettings.parseBundleIdentifiers(excludedBundleIdentifiers)
        excludedIdentifiers.remove(normalizedRule.bundleIdentifier)

        if normalizedRule.hasActions {
            rules.append(normalizedRule)
        }

        appRulesData = ClipboardSettings.formattedAppRules(rules)
        excludedBundleIdentifiers = ClipboardSettings.formattedBundleIdentifiers(excludedIdentifiers)
    }

    private func appRuleBoolBinding(
        for bundleIdentifier: String,
        keyPath: WritableKeyPath<ClipboardAppRule, Bool>
    ) -> Binding<Bool> {
        Binding {
            appRule(for: bundleIdentifier)[keyPath: keyPath]
        } set: { value in
            var rule = appRule(for: bundleIdentifier)
            rule[keyPath: keyPath] = value
            updateAppRule(rule)
        }
    }

    private func appRuleStringBinding(
        for bundleIdentifier: String,
        keyPath: WritableKeyPath<ClipboardAppRule, String>
    ) -> Binding<String> {
        Binding {
            appRule(for: bundleIdentifier)[keyPath: keyPath]
        } set: { value in
            var rule = appRule(for: bundleIdentifier)
            rule[keyPath: keyPath] = value
            updateAppRule(rule)
        }
    }

    private func appRuleIntBinding(
        for bundleIdentifier: String,
        keyPath: WritableKeyPath<ClipboardAppRule, Int>
    ) -> Binding<Int> {
        Binding {
            appRule(for: bundleIdentifier)[keyPath: keyPath]
        } set: { value in
            var rule = appRule(for: bundleIdentifier)
            rule[keyPath: keyPath] = value
            updateAppRule(rule)
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

        let remainingRules = appRules.filter {
            !selectedExcludedBundleIdentifiers.contains($0.bundleIdentifier)
        }
        appRulesData = ClipboardSettings.formattedAppRules(remainingRules)
        selectedExcludedBundleIdentifiers.removeAll()
    }
}

struct ClipSnapSetupView: View {
    @ObservedObject var cloudSyncMonitor: CloudSyncMonitor
    @ObservedObject var screenCaptureService: ScreenCaptureService
    let completionAction: () -> Void

    @AppStorage(ClipboardSettingKey.ignoresInternalPasteboardTypes)
    private var ignoresInternalPasteboardTypes = ClipboardSettings.defaults.ignoresInternalPasteboardTypes

    @AppStorage(ClipboardSettingKey.protectsSensitivePreviews)
    private var protectsSensitivePreviews = ClipboardSettings.defaults.protectsSensitivePreviews

    @AppStorage(ScreenCaptureSettingKey.captureDelaySeconds)
    private var screenCaptureDelaySeconds = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ClipSnap Setup")
                        .font(.title2.weight(.semibold))
                    Text("Review capture, privacy, sync, and menu bar access.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    completionAction()
                }
                .keyboardShortcut(.defaultAction)
            }

            VStack(spacing: 12) {
                setupRow(
                    title: "Screen Recording Permission",
                    detail: "Required for display, window, region, OCR, and recording capture.",
                    systemImage: "rectangle.dashed.badge.record",
                    status: screenCaptureService.canOpenScreenRecordingSettings ? "Needs Review" : "Ready or Not Requested"
                ) {
                    Button("Open System Settings") {
                        screenCaptureService.openScreenRecordingSettings()
                    }
                }

                setupRow(
                    title: "iCloud Sync",
                    detail: "Local clipboard history works even when iCloud is unavailable.",
                    systemImage: cloudSyncMonitor.state.systemImageName,
                    status: cloudSyncMonitor.state.title
                ) {
                    Button("Refresh") {
                        Task {
                            await cloudSyncMonitor.refreshAccountStatus()
                        }
                    }
                }

                setupRow(
                    title: "Privacy Defaults",
                    detail: "Internal app metadata is ignored and sensitive previews can stay concealed.",
                    systemImage: "hand.raised",
                    status: privacyStatus
                )

                setupRow(
                    title: "Capture Settings",
                    detail: "Delayed captures wait \(screenCaptureDelaySeconds) seconds before selecting the target.",
                    systemImage: "camera.viewfinder",
                    status: "Configured"
                )

                setupRow(
                    title: "Menu Bar Access",
                    detail: "Use the ClipSnap menu bar icon for recent items, capture, recording, quick picker, and Settings.",
                    systemImage: "menubar.rectangle",
                    status: "Available"
                )
            }
        }
        .padding(22)
        .frame(width: 620)
        .task {
            await cloudSyncMonitor.refreshAccountStatus()
        }
    }

    private var privacyStatus: String {
        switch (ignoresInternalPasteboardTypes, protectsSensitivePreviews) {
        case (true, true):
            return "Recommended"
        case (true, false):
            return "Metadata Ignored"
        case (false, true):
            return "Sensitive Previews Protected"
        case (false, false):
            return "Review Suggested"
        }
    }

    private func setupRow<Action: View>(
        title: String,
        detail: String,
        systemImage: String,
        status: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            action()
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func setupRow(
        title: String,
        detail: String,
        systemImage: String,
        status: String
    ) -> some View {
        setupRow(
            title: title,
            detail: detail,
            systemImage: systemImage,
            status: status
        ) {
            EmptyView()
        }
    }
}

private enum ClipboardHealthCleanupAction: String, Identifiable {
    case largeItems
    case oldScreenshots
    case duplicates
    case unknownData

    var id: String {
        rawValue
    }

    var confirmationTitle: String {
        switch self {
        case .largeItems:
            return "Delete Large Items?"
        case .oldScreenshots:
            return "Delete Old Screenshots?"
        case .duplicates:
            return "Delete Duplicate Items?"
        case .unknownData:
            return "Delete Unknown/Data Items?"
        }
    }

    var confirmationButtonTitle: String {
        switch self {
        case .largeItems:
            return "Delete Large Items"
        case .oldScreenshots:
            return "Delete Old Screenshots"
        case .duplicates:
            return "Delete Duplicates"
        case .unknownData:
            return "Delete Unknown/Data"
        }
    }

    var previewDescription: String {
        switch self {
        case .largeItems:
            return "Large items are clipboard entries of 10 MB or more."
        case .oldScreenshots:
            return "Old screenshots are screen captures older than 7 days."
        case .duplicates:
            return "Duplicate cleanup keeps the newest item in each duplicate group."
        case .unknownData:
            return "Unknown/data items have no standard previewable representation."
        }
    }
}

private struct ClipboardHealthSummary {
    static let largeItemThreshold: Int64 = 10 * 1_024 * 1_024

    let itemCount: Int
    let byteCount: Int64
    let storageLimitMegabytes: Int
    let duplicateGroupCount: Int
    let unknownDataCount: Int
    let unsyncedCount: Int
    let localOnlyCount: Int
    let sensitiveCount: Int
    let largestItems: [LargestClipboardItem]

    var storageLimitDescription: String {
        let limit = Int64(storageLimitMegabytes) * 1_024 * 1_024
        guard limit > 0 else {
            return "No limit"
        }

        let percent = Double(byteCount) / Double(limit)
        return "\(percent.formatted(.percent.precision(.fractionLength(0)))) of \(storageLimitMegabytes) MB"
    }

    static func make(
        from items: [ClipboardHealthItem],
        storageLimitMegabytes: Int
    ) -> ClipboardHealthSummary {
        let duplicateGroups = Dictionary(
            grouping: items.filter { !$0.contentHash.isEmpty },
            by: \.contentHash
        )
        .values
        .filter { $0.count > 1 }

        return ClipboardHealthSummary(
            itemCount: items.count,
            byteCount: items.reduce(0) { $0 + $1.byteCount },
            storageLimitMegabytes: storageLimitMegabytes,
            duplicateGroupCount: duplicateGroups.count,
            unknownDataCount: items.filter { $0.type == ClipboardItemType.unknown || $0.type == ClipboardItemType.data }.count,
            unsyncedCount: items.filter { $0.isLocalOnly || $0.isSensitive }.count,
            localOnlyCount: items.filter(\.isLocalOnly).count,
            sensitiveCount: items.filter(\.isSensitive).count,
            largestItems: items
                .sorted { $0.byteCount > $1.byteCount }
                .prefix(5)
                .map { LargestClipboardItem($0) }
        )
    }
}

private struct ClipboardHealthItem {
    let title: String
    let type: String
    let sourceApp: String?
    let byteCount: Int64
    let contentHash: String
    let isLocalOnly: Bool
    let isSensitive: Bool

    init(item: ClipboardItem) {
        title = item.displayTitle
        type = item.type ?? ClipboardItemType.unknown
        sourceApp = item.sourceApp
        byteCount = item.byteCount
        contentHash = item.contentHash ?? ""
        isLocalOnly = item.isLocalOnly
        isSensitive = item.isSensitive
    }
}

private struct LargestClipboardItem: Identifiable {
    let id = UUID()
    let title: String
    let type: String
    let sourceApp: String?
    let byteCount: Int64

    init(_ item: ClipboardHealthItem) {
        title = item.title
        type = item.type
        sourceApp = item.sourceApp
        byteCount = item.byteCount
    }

    var description: String {
        [title, sourceApp].compactMap { value in
            guard let value,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return value
        }
        .joined(separator: " - ")
    }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

private struct CloudSyncEventRow: View {
    let event: CloudSyncEventSummary

    var body: some View {
        HStack {
            Image(systemName: event.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
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

private struct StorageCategoryRow: View {
    let title: String
    let category: ClipboardStorageSummary.Category

    var body: some View {
        LabeledContent(title) {
            Text(
                "\(category.itemCount) • "
                    + ByteCountFormatter.string(
                        fromByteCount: category.byteCount,
                        countStyle: .file
                    )
            )
        }
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
    let rule: ClipboardAppRule

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
                Text(ruleSummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var ruleSummary: String {
        var actions: [String] = []
        if rule.ignoresClipboard {
            actions.append("Ignore")
        }
        if rule.keepsLocalOnly {
            actions.append("Local only")
        }
        if rule.concealsPreviews {
            actions.append("Conceal")
        }
        if !rule.automaticTags.isEmpty {
            actions.append("Tags")
        }
        if rule.retentionDays >= 0 {
            actions.append("Retention")
        }

        return actions.isEmpty ? "No active actions" : actions.joined(separator: " - ")
    }
}
