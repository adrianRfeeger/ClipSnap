import AppKit
import AVFoundation
import CoreData
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var clipboardMonitor: ClipboardMonitor
    @ObservedObject var screenCaptureService: ScreenCaptureService
    @ObservedObject var cloudSyncMonitor: CloudSyncMonitor

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ClipboardItem.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var items: FetchedResults<ClipboardItem>

    @SceneStorage("selectedClipboardItemIdentifier")
    private var selectedItemIdentifier: String?
    @State private var selectedItemIdentifiers: Set<String> = []
    @State private var searchText = ""
    @State private var selectedFilter = ClipboardFilter.all
    @State private var isDropTargeted = false
    @State private var isEditingBatchMetadata = false
    @State private var isManagingSavedFilters = false
    @State private var pendingSavedFilterQuery = ""
    @State private var imageEditingItem: ClipboardItem?
    @State private var exportErrorMessage: String?
    @State private var generatedMetadataRefreshID = UUID()
    @AppStorage(ClipboardSettingKey.hasCompletedSetup)
    private var hasCompletedSetup = false
    @AppStorage(ClipboardSettingKey.savedFilters)
    private var savedFiltersData = ClipboardSettings.formattedSavedFilters([])
    @AppStorage(ClipboardSettingKey.ignoredPasteboardTypes)
    private var ignoredPasteboardTypes = ClipboardSettings.formattedPasteboardTypes(
        ClipboardSettings.defaults.ignoredPasteboardTypes
    )
    @AppStorage(ClipboardSettingKey.excludedBundleIdentifiers)
    private var excludedBundleIdentifiers = ""

    private var filteredItems: [ClipboardItem] {
        _ = generatedMetadataRefreshID
        let query = ClipboardSearchQuery(searchText)
        return items.filter { item in
            selectedFilter.matches(item)
                && query.matches(item)
        }
    }

    private var selectedItem: ClipboardItem? {
        guard selectedItemIdentifiers.count == 1,
              let selectedItemIdentifier = selectedItemIdentifiers.first else {
            return nil
        }

        return items.first { $0.selectionIdentifier == selectedItemIdentifier }
    }

    private var selectedItems: [ClipboardItem] {
        items.filter { selectedItemIdentifiers.contains($0.selectionIdentifier) }
    }

    private var canGenerateSuggestionsForSelection: Bool {
        let settings = ClipboardSettings.load()
        return settings.appleIntelligenceSuggestionsEnabled
            && selectedItems.contains { item in
                !item.skipsAppleIntelligenceSuggestions
                    && !item.isSensitive
                    && item.type != ClipboardItemType.unknown
                    && item.type != ClipboardItemType.data
            }
    }

    private var selectedItemsContainGeneratedMetadata: Bool {
        selectedItems.contains { $0.generatedMetadata?.hasSuggestions == true }
    }

    private var selectedItemsContainApplicableSuggestions: Bool {
        selectedItems.contains { item in
            guard let metadata = item.generatedMetadata else {
                return false
            }
            return metadata.hasSuggestions && metadata.status != .accepted
        }
    }

    private var savedFilters: [ClipboardSavedFilter] {
        ClipboardSettings.parseSavedFilters(savedFiltersData)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItemIdentifiers) {
                ForEach(filteredItems) { item in
                    ClipboardRow(
                        item: item,
                        highlightedTerms: ClipboardSearchQuery(searchText).terms,
                        isCurrentClipboardItem: clipboardMonitor.isCurrentClipboardItem(item)
                    )
                        .contentShape(Rectangle())
                        .tag(item.selectionIdentifier)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                select(item)
                            }
                        )
                        .onDrag {
                            ClipboardDragDropSupport.itemProvider(for: item)
                        } preview: {
                            Label(item.protectedMenuTitle, systemImage: item.systemImageName)
                                .padding(8)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .contextMenu {
                            Button("Copy") {
                                clipboardMonitor.copyToClipboard(item)
                            }

                            Button(item.isPinned ? "Unpin" : "Pin") {
                                toggle(\.isPinned, on: item)
                            }

                            Button(item.isFavorite ? "Unfavorite" : "Favorite") {
                                toggle(\.isFavorite, on: item)
                            }

                            Button(item.isArchived ? "Restore" : "Archive") {
                                toggle(\.isArchived, on: item)
                            }

                            Divider()

                            Button(contextMenuDeleteTitle(for: item), role: .destructive) {
                                deleteContextMenuItems(for: item)
                            }
                        }
                }
                .onDelete(perform: deleteItems)
            }
            .accessibilityIdentifier("clipboard.history.list")
            .navigationTitle("Clipboard")
            .searchable(
                text: $searchText,
                placement: .sidebar,
                prompt: "Search or use app:, type:, tag:, collection:"
            )
            .searchSuggestions {
                Text("Screenshots").searchCompletion("type:image app:Screen Capture")
                Text("OCR text").searchCompletion("app:Screen OCR")
                Text("Favorites").searchCompletion("favorite:true")
                Text("This week").searchCompletion("after:week")
                Text("Archived").searchCompletion("archived:true")
                ForEach(ClipboardSavedFilter.builtIns) { filter in
                    Text(filter.name).searchCompletion(filter.query)
                }
            }
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("Capture Text from Region") {
                            screenCaptureService.capture(.ocrRegion)
                        }
                        .disabled(screenCaptureService.isCapturing)

                        Button("Capture Region") {
                            screenCaptureService.capture(.region)
                        }
                        .disabled(screenCaptureService.isCapturing)

                        Button("Capture Window") {
                            screenCaptureService.capture(.window)
                        }
                        .disabled(screenCaptureService.isCapturing)

                        Button("Capture Application") {
                            screenCaptureService.capture(.application)
                        }
                        .disabled(screenCaptureService.isCapturing)

                        Button("Capture Display") {
                            screenCaptureService.capture(.display)
                        }
                        .disabled(screenCaptureService.isCapturing)

                        Menu("Delayed Capture") {
                            Button("Capture Text from Region") {
                                screenCaptureService.capture(.ocrRegion, delayed: true)
                            }
                            .disabled(screenCaptureService.isCapturing)

                            Button("Capture Region") {
                                screenCaptureService.capture(.region, delayed: true)
                            }
                            .disabled(screenCaptureService.isCapturing)

                            Button("Capture Window") {
                                screenCaptureService.capture(.window, delayed: true)
                            }
                            .disabled(screenCaptureService.isCapturing)

                            Button("Capture Application") {
                                screenCaptureService.capture(.application, delayed: true)
                            }
                            .disabled(screenCaptureService.isCapturing)

                            Button("Capture Display") {
                                screenCaptureService.capture(.display, delayed: true)
                            }
                            .disabled(screenCaptureService.isCapturing)
                        }

                        Button("Cancel Delayed Capture") {
                            screenCaptureService.cancelCapture()
                        }
                        .disabled(!screenCaptureService.isWaitingForDelayedCapture)

                        Divider()

                        Menu("Record Display") {
                            Button("Start") {
                                screenCaptureService.capture(.recording)
                            }
                            .disabled(screenCaptureService.isCapturing)

                            Button("Pause") {
                                screenCaptureService.pauseRecording()
                            }
                            .disabled(!screenCaptureService.isRecording || screenCaptureService.isRecordingPaused)

                            Button("Continue") {
                                screenCaptureService.resumeRecording()
                            }
                            .disabled(!screenCaptureService.isRecordingPaused)

                            Button("Stop") {
                                screenCaptureService.stopRecording()
                            }
                            .disabled(!screenCaptureService.isRecording && !screenCaptureService.isRecordingPaused)

                            Button("Cancel") {
                                screenCaptureService.cancelRecording()
                            }
                            .disabled(!screenCaptureService.isRecording && !screenCaptureService.isRecordingPaused)
                        }
                    } label: {
                        Label("Capture", systemImage: "camera.viewfinder")
                    }
                    .accessibilityIdentifier("clipboard.capture.menu")
                }

                if !selectedItemIdentifiers.isEmpty {
                    ToolbarItem {
                        Menu {
                            Button("Edit Collection and Tags…") {
                                isEditingBatchMetadata = true
                            }

                            if selectedItems.compactMap(\.plainText).count >= 2 {
                                Button("Merge Text Items") {
                                    mergeSelectedTextItems()
                                }
                            }

                            Divider()

                            Menu("Suggestions") {
                                Button("Generate for Selected") {
                                    generateSuggestionsForSelectedItems()
                                }
                                .disabled(!canGenerateSuggestionsForSelection)

                                Button("Apply Suggested Metadata") {
                                    applySuggestionsToSelectedItems()
                                }
                                .disabled(!selectedItemsContainApplicableSuggestions)

                                Button("Reject Suggestions") {
                                    rejectSuggestionsForSelectedItems()
                                }
                                .disabled(!selectedItemsContainGeneratedMetadata)

                                Button("Clear Suggestions") {
                                    clearSuggestionsForSelectedItems()
                                }
                                .disabled(!selectedItemsContainGeneratedMetadata)
                            }

                            Menu("Export") {
                                if let item = selectedItem {
                                    Button("Native Format…") {
                                        performExport {
                                            try ClipboardExportService.exportNative(item)
                                        }
                                    }
                                }

                                ForEach(ClipboardExportFormat.allCases) { format in
                                    Button("\(format.title)…") {
                                        performExport {
                                            try ClipboardExportService.export(
                                                selectedItems,
                                                format: format
                                            )
                                        }
                                    }
                                }
                            }

                            Button("Share…") {
                                performExport {
                                    try ClipboardExportService.share(selectedItems)
                                }
                            }

                            Divider()

                            Button("Favorite Selected") {
                                updateSelectedItems { $0.isFavorite = true }
                            }

                            Button("Pin Selected") {
                                updateSelectedItems { $0.isPinned = true }
                            }

                            Button(selectedFilter == .archived ? "Restore Selected" : "Archive Selected") {
                                updateSelectedItems { $0.isArchived = selectedFilter != .archived }
                            }

                            if selectedItems.count == 1, let item = selectedItems.first {
                                Button(item.isLocalOnly ? "Move to iCloud" : "Keep on This Mac") {
                                    move(item, localOnly: !item.isLocalOnly)
                                }
                            }

                            Divider()

                            Button("Delete Selected", role: .destructive) {
                                delete(selectedItems)
                            }
                        } label: {
                            Label(
                                selectedItemIdentifiers.count == 1
                                    ? "Item Actions"
                                    : "\(selectedItemIdentifiers.count) Items",
                                systemImage: "checkmark.circle"
                            )
                        }
                    }
                }

                ToolbarItem {
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(ClipboardFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }

                ToolbarItem {
                    Menu {
                        Section("Built In") {
                            ForEach(ClipboardSavedFilter.builtIns) { filter in
                                Button(filter.name) {
                                    applySavedFilter(filter)
                                }
                            }
                        }

                        if !savedFilters.isEmpty {
                            Divider()
                            Section("Saved") {
                                ForEach(savedFilters) { filter in
                                    Button(filter.name) {
                                        applySavedFilter(filter)
                                    }
                                }
                            }
                        }

                        Divider()

                        Button("Save Current Search…") {
                            pendingSavedFilterQuery = searchText
                            isManagingSavedFilters = true
                        }
                        .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Manage Filters…") {
                            pendingSavedFilterQuery = ""
                            isManagingSavedFilters = true
                        }
                    } label: {
                        Label("Saved Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityIdentifier("clipboard.savedFilters.menu")
                }
            }
        } detail: {
            if let selectedItem {
                ClipboardDetailView(
                    item: selectedItem,
                    isCurrentClipboardItem: clipboardMonitor.isCurrentClipboardItem(selectedItem),
                    copyAction: {
                        clipboardMonitor.copyToClipboard(selectedItem)
                    },
                    pinAction: {
                        toggle(\.isPinned, on: selectedItem)
                    },
                    favoriteAction: {
                        toggle(\.isFavorite, on: selectedItem)
                    },
                    archiveAction: {
                        toggle(\.isArchived, on: selectedItem)
                    },
                    localOnlyAction: {
                        move(selectedItem, localOnly: !selectedItem.isLocalOnly)
                    },
                    syncState: cloudSyncMonitor.syncState(for: selectedItem),
                    retrySyncAction: {
                        retrySync(for: selectedItem)
                    },
                    saveMetadataAction: {
                        selectedItem.updatedAt = Date()
                        saveContext()
                    },
                    saveTextAction: { text in
                        saveEditedText(text, on: selectedItem)
                    },
                    recognizeTextAction: {
                        screenCaptureService.recognizeText(in: selectedItem)
                    },
                    editImageAction: {
                        imageEditingItem = selectedItem
                    },
                    ignoreTypeAction: {
                        ignorePrimaryPasteboardType(for: selectedItem)
                    },
                    ignoreAppAction: {
                        ignoreSourceApplication(for: selectedItem)
                    },
                    deleteAction: {
                        delete(selectedItem)
                    }
                )
                .id(selectedItem.selectionIdentifier)
            } else {
                ContentUnavailableView(
                    selectedItemIdentifiers.count > 1 ? "\(selectedItemIdentifiers.count) Items Selected" : "No Clipboard Item Selected",
                    systemImage: selectedItemIdentifiers.count > 1 ? "checkmark.circle" : "clipboard",
                    description: Text(
                        selectedItemIdentifiers.count > 1
                            ? "Use the batch actions in the toolbar to organize or update these items."
                            : "Copy text, images, URLs, files, or rich content to start collecting history."
                    )
                )
            }
        }
        .accessibilityIdentifier("clipboard.main")
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .padding(8)
                    .allowsHitTesting(false)
            } else if screenCaptureService.isCapturing,
                      !screenCaptureService.isRecording,
                      !screenCaptureService.isRecordingPaused,
                      let statusText = screenCaptureService.statusText {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(statusText)
                    Button("Cancel") {
                        screenCaptureService.cancelCapture()
                    }
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onDrop(
            of: ClipboardDragDropSupport.acceptedTypes,
            isTargeted: $isDropTargeted
        ) { providers in
            ClipboardDragDropSupport.loadDroppedProviders(providers) { representations in
                clipboardMonitor.importDroppedRepresentations(representations)
            }
        }
        .onChange(of: screenCaptureService.lastCapturedItemIdentifier) { _, identifier in
            if let identifier {
                selectedItemIdentifier = identifier
                selectedItemIdentifiers = [identifier]
            }
        }
        .onChange(of: selectedItemIdentifiers) { _, identifiers in
            selectedItemIdentifier = identifiers.count == 1 ? identifiers.first : nil
        }
        .sheet(isPresented: $isEditingBatchMetadata) {
            BatchMetadataEditor(items: selectedItems) {
                saveContext()
                isEditingBatchMetadata = false
            }
        }
        .sheet(
            isPresented: Binding(
                get: { !hasCompletedSetup && !AppLaunchConfiguration.isUITesting },
                set: { isPresented in
                    if !isPresented {
                        hasCompletedSetup = true
                    }
                }
            )
        ) {
            ClipSnapSetupView(
                cloudSyncMonitor: cloudSyncMonitor,
                screenCaptureService: screenCaptureService
            ) {
                hasCompletedSetup = true
            }
        }
        .sheet(isPresented: $isManagingSavedFilters) {
            SavedFiltersManager(
                filtersData: $savedFiltersData,
                initialQuery: pendingSavedFilterQuery
            )
        }
        .sheet(item: $imageEditingItem) { item in
            if let image = item.image {
                ImageClipboardEditor(image: image) { data in
                    saveEditedImage(data, on: item)
                    imageEditingItem = nil
                }
            }
        }
        .alert(
            "Screen Capture",
            isPresented: Binding(
                get: { screenCaptureService.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        screenCaptureService.errorMessage = nil
                    }
                }
            )
        ) {
            if screenCaptureService.canOpenScreenRecordingSettings {
                Button("Open System Settings") {
                    screenCaptureService.openScreenRecordingSettings()
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(screenCaptureService.errorMessage ?? "")
        }
        .alert(
            "Export",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        exportErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    private func toggle(_ keyPath: ReferenceWritableKeyPath<ClipboardItem, Bool>, on item: ClipboardItem) {
        item[keyPath: keyPath].toggle()
        item.updatedAt = Date()
        saveContext()
    }

    private func select(_ item: ClipboardItem) {
        let identifier = item.selectionIdentifier
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers.contains(.command) {
            if selectedItemIdentifiers.contains(identifier) {
                selectedItemIdentifiers.remove(identifier)
            } else {
                selectedItemIdentifiers.insert(identifier)
            }
            return
        }

        if modifiers.contains(.shift),
           let anchorIdentifier = selectedItemIdentifier,
           let anchorIndex = filteredItems.firstIndex(
            where: { $0.selectionIdentifier == anchorIdentifier }
           ),
           let itemIndex = filteredItems.firstIndex(
            where: { $0.selectionIdentifier == identifier }
           ) {
            let range = min(anchorIndex, itemIndex)...max(anchorIndex, itemIndex)
            selectedItemIdentifiers = Set(
                range.map { filteredItems[$0].selectionIdentifier }
            )
            return
        }

        selectedItemIdentifiers = [identifier]
    }

    private func delete(_ item: ClipboardItem) {
        selectedItemIdentifiers.remove(item.selectionIdentifier)
        if let identifier = item.id?.uuidString {
            ClipboardSpotlightIndexer.shared.deleteIdentifiers([identifier])
        }
        viewContext.delete(item)
        saveContext()
    }

    private func ignorePrimaryPasteboardType(for item: ClipboardItem) {
        guard let utiType = item.utiType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !utiType.isEmpty else {
            return
        }

        var ignoredTypes = ClipboardSettings.parsePasteboardTypes(ignoredPasteboardTypes)
        ignoredTypes.insert(utiType)
        ignoredPasteboardTypes = ClipboardSettings.formattedPasteboardTypes(ignoredTypes)
    }

    private func ignoreSourceApplication(for item: ClipboardItem) {
        guard let bundleIdentifier = item.sourceBundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !bundleIdentifier.isEmpty else {
            return
        }

        var identifiers = ClipboardSettings.parseBundleIdentifiers(excludedBundleIdentifiers)
        identifiers.insert(bundleIdentifier)
        excludedBundleIdentifiers = ClipboardSettings.formattedBundleIdentifiers(identifiers)
    }

    private func delete(_ items: [ClipboardItem]) {
        let itemsToDelete = Array(Set(items))
        guard !itemsToDelete.isEmpty else {
            return
        }

        selectedItemIdentifiers.subtract(
            itemsToDelete.map(\.selectionIdentifier)
        )
        ClipboardSpotlightIndexer.shared.deleteIdentifiers(
            itemsToDelete.compactMap { $0.id?.uuidString }
        )
        itemsToDelete.forEach(viewContext.delete)
        saveContext()
    }

    private func contextMenuDeleteTitle(for item: ClipboardItem) -> String {
        contextMenuDeleteItems(for: item).count > 1 ? "Delete Selected" : "Delete"
    }

    private func deleteContextMenuItems(for item: ClipboardItem) {
        delete(contextMenuDeleteItems(for: item))
    }

    private func contextMenuDeleteItems(for item: ClipboardItem) -> [ClipboardItem] {
        if selectedItemIdentifiers.contains(item.selectionIdentifier),
           selectedItems.count > 1 {
            return selectedItems
        }

        return [item]
    }

    private func updateSelectedItems(_ update: (ClipboardItem) -> Void) {
        let now = Date()
        selectedItems.forEach {
            update($0)
            $0.updatedAt = now
        }
        saveContext()
    }

    private func generateSuggestionsForSelectedItems() {
        let targets = selectedItems.filter {
            !$0.skipsAppleIntelligenceSuggestions
                && !$0.isSensitive
                && $0.type != ClipboardItemType.unknown
                && $0.type != ClipboardItemType.data
        }
        guard !targets.isEmpty else {
            return
        }

        Task {
            let service = ClipboardMetadataSuggestionService()
            for item in targets {
                guard let itemIdentifier = item.id else {
                    continue
                }
                let metadata = await service.suggestions(for: item)
                ClipboardGeneratedMetadataStore.save(metadata, for: itemIdentifier)
            }
            await MainActor.run {
                generatedMetadataRefreshID = UUID()
            }
        }
    }

    private func applySuggestionsToSelectedItems() {
        var changedItems: [ClipboardItem] = []
        for item in selectedItems {
            guard let itemIdentifier = item.id,
                  var metadata = item.generatedMetadata,
                  metadata.hasSuggestions else {
                continue
            }

            if item.applyGeneratedMetadata(metadata) {
                changedItems.append(item)
            }
            metadata.status = .accepted
            ClipboardGeneratedMetadataStore.save(metadata, for: itemIdentifier)
        }

        if !changedItems.isEmpty {
            saveContext()
        }
        generatedMetadataRefreshID = UUID()
    }

    private func rejectSuggestionsForSelectedItems() {
        for item in selectedItems {
            guard let itemIdentifier = item.id,
                  var metadata = item.generatedMetadata else {
                continue
            }
            metadata.status = .rejected
            ClipboardGeneratedMetadataStore.save(metadata, for: itemIdentifier)
        }
        generatedMetadataRefreshID = UUID()
    }

    private func clearSuggestionsForSelectedItems() {
        for item in selectedItems {
            guard let itemIdentifier = item.id else {
                continue
            }
            ClipboardGeneratedMetadataStore.remove(for: itemIdentifier)
        }
        generatedMetadataRefreshID = UUID()
    }

    private func saveEditedText(_ text: String, on item: ClipboardItem) {
        item.plainText = text
        item.previewText = text.clipboardPreview
        item.rawData = Data(text.utf8)
        if item.type == ClipboardItemType.text {
            item.utiType = UTType.utf8PlainText.identifier
        }
        item.updatedAt = Date()

        for representation in item.sortedRepresentations {
            viewContext.delete(representation)
        }
        item.updateContentIdentity()
        saveContext()
    }

    private func saveEditedImage(_ data: Data, on item: ClipboardItem) {
        item.imageData = data
        item.rawData = data
        item.thumbnailData = ClipboardImageEditing.thumbnailData(from: data, maxDimension: 220)
        item.previewText = "Edited Image"
        item.utiType = UTType.png.identifier
        item.updatedAt = Date()

        for representation in item.sortedRepresentations {
            viewContext.delete(representation)
        }
        item.updateContentIdentity()
        saveContext()
    }

    private func mergeSelectedTextItems() {
        let orderedItems = selectedItems.sorted {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
        let mergedText = ClipboardTextMerger.merge(orderedItems.compactMap(\.plainText))
        guard !mergedText.isEmpty else {
            return
        }

        let mergedItem = ClipboardItem.make(
            in: viewContext,
            type: ClipboardItemType.text,
            plainText: mergedText,
            previewText: mergedText.clipboardPreview,
            rawData: Data(mergedText.utf8),
            utiType: UTType.utf8PlainText.identifier,
            sourceApp: "Merged Clipboard Items",
            sourceBundleIdentifier: Bundle.main.bundleIdentifier
        )
        let tags = Set(orderedItems.flatMap(\.tags))
        mergedItem.tagsText = tags.sorted().joined(separator: ", ")
        let collections = Set(orderedItems.compactMap(\.normalizedCollectionName))
        if collections.count == 1 {
            mergedItem.collectionName = collections.first
        }
        mergedItem.updateContentIdentity()
        saveContext()
        selectedItemIdentifiers = [mergedItem.selectionIdentifier]
    }

    private func move(_ item: ClipboardItem, localOnly: Bool) {
        guard let copy = PersistenceStoreRouting.copy(
            item,
            localOnly: localOnly,
            in: viewContext
        ) else {
            return
        }
        let identifier = copy.selectionIdentifier
        viewContext.delete(item)
        saveContext()
        selectedItemIdentifiers = [identifier]
    }

    private func retrySync(for item: ClipboardItem) {
        guard !item.isLocalOnly, !item.isSensitive else {
            return
        }
        item.updatedAt = Date()
        saveContext()
        Task {
            await cloudSyncMonitor.refreshAccountStatus()
        }
    }

    private func performExport(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func deleteItems(offsets: IndexSet) {
        delete(offsets.map { filteredItems[$0] })
    }

    private func applySavedFilter(_ filter: ClipboardSavedFilter) {
        selectedFilter = .all
        searchText = filter.query
        selectedItemIdentifiers = []
    }

    private func saveContext() {
        let changedItems = (viewContext.insertedObjects.union(viewContext.updatedObjects))
            .compactMap { $0 as? ClipboardItem }
        do {
            try viewContext.save()
            changedItems.forEach(ClipboardSpotlightIndexer.shared.indexItem)
        } catch {
            viewContext.rollback()
            NSLog("Failed to save clipboard changes: \(error.localizedDescription)")
        }
    }
}

private extension String {
    func highlighted(terms: [String]) -> AttributedString {
        var result = AttributedString(self)
        for term in terms where !term.isEmpty {
            var searchStart = startIndex
            while searchStart < endIndex,
                  let range = range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<endIndex
                  ) {
                if let attributedRange = Range(range, in: result) {
                    result[attributedRange].backgroundColor = .yellow.opacity(0.45)
                }
                searchStart = range.upperBound
            }
        }
        return result
    }
}

private extension ClipboardItem {
    var selectionIdentifier: String {
        id?.uuidString ?? objectID.uriRepresentation().absoluteString
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let highlightedTerms: [String]
    let isCurrentClipboardItem: Bool

    var body: some View {
        HStack(spacing: 10) {
            ClipboardRowThumbnail(item: item)

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    (item.shouldProtectPreview ? "Sensitive Content" : item.displayTitle)
                        .highlighted(terms: item.shouldProtectPreview ? [] : highlightedTerms)
                )
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.displayType)

                    if let createdAt = item.createdAt {
                        Text(createdAt, style: .relative)
                    }

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                    }

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                    }

                    if item.shouldProtectPreview {
                        Image(systemName: "eye.slash.fill")
                    }

                    if isCurrentClipboardItem {
                        Label("Current", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.green)
                    }

                    if let collectionName = item.normalizedCollectionName {
                        Text(collectionName)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clipboard.item.\(item.selectionIdentifier)")
        .accessibilityLabel(
            item.shouldProtectPreview
                ? "Sensitive Content, \(item.displayType)"
                : "\(item.displayTitle), \(item.displayType)"
        )
    }

}

private struct ClipboardRowThumbnail: View {
    @ObservedObject var item: ClipboardItem
    @State private var generatedVideoThumbnail: NSImage?

    var body: some View {
        Group {
            if item.shouldProtectPreview {
                symbol("eye.slash.fill")
            } else if let image = thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(.separator.opacity(0.5), lineWidth: 0.5)
                    }
            } else {
                symbol(item.systemImageName)
            }
        }
        .frame(width: 38, height: 38)
        .task(id: item.objectID) {
            generatedVideoThumbnail = nil
            guard item.type == ClipboardItemType.video,
                  let data = item.rawData ?? item.sortedRepresentations.compactMap(\.data).first else {
                return
            }

            generatedVideoThumbnail = await makeVideoThumbnail(
                from: data,
                utiIdentifier: item.utiType
            )
        }
    }

    private var thumbnailImage: NSImage? {
        switch item.type {
        case ClipboardItemType.image:
            if let thumbnailData = item.thumbnailData,
               let image = NSImage(data: thumbnailData) {
                return image
            }
            return item.image
        case ClipboardItemType.pdf:
            return pdfThumbnail
        case ClipboardItemType.file:
            return fileIcon
        case ClipboardItemType.video:
            return generatedVideoThumbnail
        default:
            return nil
        }
    }

    private var pdfThumbnail: NSImage? {
        guard let rawData = item.rawData,
              let document = PDFDocument(data: rawData),
              let page = document.page(at: 0) else {
            return nil
        }

        return page.thumbnail(of: NSSize(width: 68, height: 68), for: .cropBox)
    }

    private var fileIcon: NSImage? {
        guard let plainText = item.plainText,
              let url = URL(string: plainText),
              url.isFileURL else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func makeVideoThumbnail(from data: Data, utiIdentifier: String?) async -> NSImage? {
        let fileExtension = utiIdentifier.flatMap { UTType($0)?.preferredFilenameExtension } ?? "mov"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipSnap History Preview \(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        do {
            try data.write(to: url, options: .atomic)
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 120, height: 120)
            let image = try await generator.image(
                at: CMTime(seconds: 0.1, preferredTimescale: 600)
            ).image
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            return nil
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 34)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct ClipboardDetailView: View {
    @ObservedObject var item: ClipboardItem
    let isCurrentClipboardItem: Bool
    let copyAction: () -> Void
    let pinAction: () -> Void
    let favoriteAction: () -> Void
    let archiveAction: () -> Void
    let localOnlyAction: () -> Void
    let syncState: ClipboardItemSyncState
    let retrySyncAction: () -> Void
    let saveMetadataAction: () -> Void
    let saveTextAction: (String) -> Void
    let recognizeTextAction: () -> Void
    let editImageAction: () -> Void
    let ignoreTypeAction: () -> Void
    let ignoreAppAction: () -> Void
    let deleteAction: () -> Void
    @AppStorage("showsClipboardItemMetadata")
    private var showsItemMetadata = true
    @State private var revealsSensitiveContent = false
    @State private var generatedMetadata: ClipboardGeneratedMetadata?
    @State private var isGeneratingMetadata = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if showsItemMetadata {
                    header
                    Divider()
                }

                if item.shouldProtectPreview && !revealsSensitiveContent {
                    ContentUnavailableView {
                        Label("Sensitive Content", systemImage: "eye.slash.fill")
                    } description: {
                        Text("This preview is concealed to reduce accidental exposure.")
                    } actions: {
                        Button("Reveal") {
                            revealsSensitiveContent = true
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ClipboardItemPreview(
                        item: item,
                        saveTextAction: saveTextAction,
                        recognizeTextAction: recognizeTextAction,
                        editImageAction: editImageAction
                    )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                if showsItemMetadata {
                    Divider()
                    generatedMetadataPanel
                    metadata
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .onDrag {
            ClipboardDragDropSupport.itemProvider(for: item)
        } preview: {
            Label(item.protectedMenuTitle, systemImage: item.systemImageName)
                .padding(8)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .navigationTitle(item.displayType)
        .accessibilityIdentifier("clipboard.detail")
        .onChange(of: item.selectionIdentifier) {
            revealsSensitiveContent = false
            loadGeneratedMetadata()
        }
        .onAppear {
            loadGeneratedMetadata()
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: copyAction) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("clipboard.detail.copy")

                Button(action: pinAction) {
                    Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
                }

                Button(action: favoriteAction) {
                    Label(item.isFavorite ? "Unfavorite" : "Favorite", systemImage: item.isFavorite ? "star.slash" : "star")
                }

                Button(action: archiveAction) {
                    Label(item.isArchived ? "Restore" : "Archive", systemImage: item.isArchived ? "tray.and.arrow.up" : "archivebox")
                }

                Button(action: localOnlyAction) {
                    Label(
                        item.isLocalOnly ? "Move to iCloud" : "Keep on This Mac",
                        systemImage: item.isLocalOnly ? "icloud.and.arrow.up" : "macbook"
                    )
                }

                Button {
                    showsItemMetadata.toggle()
                } label: {
                    Label(
                        showsItemMetadata ? "Hide Metadata" : "Show Metadata",
                        systemImage: showsItemMetadata ? "sidebar.right" : "sidebar.right"
                    )
                }

                Button(role: .destructive, action: deleteAction) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "Title",
                text: titleBinding
            )
                .font(.title2)
                .fontWeight(.semibold)
                .textFieldStyle(.plain)
                .onSubmit(saveMetadataAction)

            if isCurrentClipboardItem {
                Label("Current Clipboard", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            TextField(
                "Tags, separated by commas",
                text: Binding(
                    get: { item.tagsText ?? "" },
                    set: { item.tagsText = $0.isEmpty ? nil : $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit(saveMetadataAction)

            TextField(
                "Collection",
                text: Binding(
                    get: { item.collectionName ?? "" },
                    set: { item.collectionName = $0.isEmpty ? nil : $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit(saveMetadataAction)

            TextField(
                "Notes",
                text: Binding(
                    get: { item.notes ?? "" },
                    set: { item.notes = $0.isEmpty ? nil : $0 }
                ),
                axis: .vertical
            )
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
            .onSubmit(saveMetadataAction)

            if let createdAt = item.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .standard))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var titleBinding: Binding<String> {
        Binding {
            item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? item.customTitle ?? ""
                : item.displayTitle
        } set: { value in
            let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
            item.customTitle = title.isEmpty ? nil : title
            item.updatedAt = Date()
        }
    }

    @ViewBuilder
    private var generatedMetadataPanel: some View {
        let settings = ClipboardSettings.load()
        if settings.appleIntelligenceSuggestionsEnabled || generatedMetadata != nil {
            let canGenerateSuggestions = settings.appleIntelligenceSuggestionsEnabled
                && !item.skipsAppleIntelligenceSuggestions
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Suggestions", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Button {
                        generateMetadataSuggestions()
                    } label: {
                        Label(
                            generatedMetadata == nil ? "Generate" : "Regenerate",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .controlSize(.small)
                    .disabled(!canGenerateSuggestions || isGeneratingMetadata)
                }

                if !settings.appleIntelligenceSuggestionsEnabled {
                    Text("Enable Apple Intelligence suggestions in Settings > Automation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if item.skipsAppleIntelligenceSuggestions {
                    Text("Apple Intelligence suggestions are disabled for this source application.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isGeneratingMetadata {
                    ProgressView()
                        .controlSize(.small)
                } else if let generatedMetadata {
                    generatedMetadataSuggestions(metadata: generatedMetadata)
                } else {
                    Text("Generate local suggestions for this item. Apple Intelligence model output will use this same review workflow when enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func generatedMetadataSuggestions(metadata: ClipboardGeneratedMetadata) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let suggestedTitle = metadata.suggestedTitle {
                suggestionRow("Title", suggestedTitle)
            }

            if !metadata.suggestedTags.isEmpty {
                tagSuggestionRow(metadata.suggestedTags)
            }

            if let suggestedCollection = metadata.suggestedCollection {
                suggestionRow("Collection", suggestedCollection)
            }

            if let summary = metadata.summary {
                suggestionRow("Summary", summary)
            }

            if let failureReason = metadata.failureReason {
                suggestionRow("Status", failureReason)
            }

            HStack {
                Button("Apply") {
                    applyGeneratedMetadata()
                }
                .controlSize(.small)
                .disabled(!metadata.hasSuggestions)

                Button("Reject") {
                    rejectGeneratedMetadata()
                }
                .controlSize(.small)
                .disabled(metadata.status == .rejected)

                Button("Clear") {
                    clearGeneratedMetadata()
                }
                .controlSize(.small)

                Spacer()

                Text(metadata.modelVersionDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
    }

    private func suggestionRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    private func tagSuggestionRow(_ tags: [String]) -> some View {
        LabeledContent("Tags") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(tags.prefix(10), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
    }

    private var metadata: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("Format")
                    .foregroundStyle(.secondary)
                Text(item.utiType ?? "Unknown")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Storage")
                    .foregroundStyle(.secondary)
                Label(
                    item.storageLocationDescription,
                    systemImage: item.isLocalOnly ? "macbook" : "icloud"
                )
            }

            GridRow {
                Text("Sync")
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Label(syncState.title, systemImage: syncState.systemImageName)
                    if case .pending = syncState {
                        Button("Retry", action: retrySyncAction)
                            .buttonStyle(.link)
                    } else if case .error = syncState {
                        Button("Retry", action: retrySyncAction)
                            .buttonStyle(.link)
                    }
                }
            }

            if let rawData = item.rawData {
                GridRow {
                    Text("Stored Data")
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(rawData.count), countStyle: .file))
                }
            }

            if item.byteCount > 0 {
                GridRow {
                    Text("Total Size")
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))
                }
            }

            if !item.sortedRepresentations.isEmpty {
                GridRow {
                    Text("Representations")
                        .foregroundStyle(.secondary)
                    Text("\(item.sortedRepresentations.count)")
                }

                ForEach(item.sortedRepresentations.prefix(8), id: \.objectID) { representation in
                    GridRow {
                        Text("Item \(Int(representation.itemIndex) + 1)")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(representation.utiIdentifier ?? "Unknown")
                                .textSelection(.enabled)
                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount: representation.byteCount,
                                    countStyle: .file
                                )
                            )
                            .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if let sourceApp = item.sourceApp {
                GridRow {
                    Text("Source")
                        .foregroundStyle(.secondary)
                    Text(sourceApp)
                }
            }

            if let sourceBundleIdentifier = item.sourceBundleIdentifier {
                GridRow {
                    Text("Bundle ID")
                        .foregroundStyle(.secondary)
                    Text(sourceBundleIdentifier)
                        .textSelection(.enabled)
                }
            }

            if let appRuleDescription {
                GridRow {
                    Text("App Rule")
                        .foregroundStyle(.secondary)
                    Text(appRuleDescription)
                }
            }

            if let recognizedText = item.recognizedText, !recognizedText.isEmpty {
                GridRow {
                    Text("Recognized Text")
                        .foregroundStyle(.secondary)
                    Text(recognizedText)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }

            if let relatedItemIdentifier = item.relatedItemIdentifier {
                GridRow {
                    Text("Source Item")
                        .foregroundStyle(.secondary)
                    Text(relatedItemIdentifier)
                        .textSelection(.enabled)
                }
            }

            if showsCaptureDiagnostics {
                GridRow {
                    Text("Why Captured")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(captureDiagnosticsText)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Ignore This Type", action: ignoreTypeAction)
                                .disabled(item.utiType?.isEmpty != false)

                            Button("Ignore This App", action: ignoreAppAction)
                                .disabled(item.sourceBundleIdentifier?.isEmpty != false)
                        }
                    }
                }
            }
        }
        .font(.caption)
    }

    private var showsCaptureDiagnostics: Bool {
        item.type == ClipboardItemType.unknown || item.type == ClipboardItemType.data
    }

    private var appRuleDescription: String? {
        guard let rule = ClipboardSettings.load().appRule(for: item.sourceBundleIdentifier) else {
            return nil
        }

        var descriptions: [String] = []
        if rule.ignoresClipboard {
            descriptions.append("Ignore future clipboard changes")
        }
        if rule.keepsLocalOnly {
            descriptions.append("Keep local only")
        }
        if rule.concealsPreviews {
            descriptions.append("Conceal previews")
        }
        if rule.skipsAppleIntelligence {
            descriptions.append("Skip Apple Intelligence")
        }
        if !rule.automaticTags.isEmpty {
            descriptions.append("Tags: \(rule.automaticTags)")
        }
        if rule.retentionDays >= 0 {
            descriptions.append(rule.retentionDays == 0 ? "Never expire" : "Retain \(rule.retentionDays) days")
        }

        return descriptions.isEmpty ? nil : descriptions.joined(separator: " - ")
    }

    private var captureDiagnosticsText: String {
        let format = item.utiType ?? "an unknown pasteboard type"
        let source = item.sourceApp ?? "the source app"
        let representationCount = item.sortedRepresentations.count
        return "ClipSnap did not find a standard previewable representation, so it retained \(format) from \(source). \(representationCount) stored representation\(representationCount == 1 ? "" : "s") can still be restored when copied back."
    }

    private func loadGeneratedMetadata() {
        guard let itemIdentifier = item.id else {
            generatedMetadata = nil
            return
        }

        generatedMetadata = ClipboardGeneratedMetadataStore.metadata(for: itemIdentifier)
    }

    private func generateMetadataSuggestions() {
        guard let itemIdentifier = item.id else {
            return
        }

        isGeneratingMetadata = true
        Task {
            let metadata = await ClipboardMetadataSuggestionService().suggestions(for: item)
            ClipboardGeneratedMetadataStore.save(metadata, for: itemIdentifier)
            await MainActor.run {
                generatedMetadata = metadata
                isGeneratingMetadata = false
            }
        }
    }

    private func applyGeneratedMetadata() {
        guard let itemIdentifier = item.id,
              var metadata = generatedMetadata else {
            return
        }

        item.applyGeneratedMetadata(metadata)

        metadata.status = .accepted
        ClipboardGeneratedMetadataStore.save(metadata, for: itemIdentifier)
        generatedMetadata = metadata
        saveMetadataAction()
    }

    private func rejectGeneratedMetadata() {
        guard let itemIdentifier = item.id,
              var metadata = generatedMetadata else {
            return
        }

        metadata.status = .rejected
        ClipboardGeneratedMetadataStore.save(metadata, for: itemIdentifier)
        generatedMetadata = metadata
    }

    private func clearGeneratedMetadata() {
        guard let itemIdentifier = item.id else {
            return
        }

        ClipboardGeneratedMetadataStore.remove(for: itemIdentifier)
        generatedMetadata = nil
    }
}

private struct SavedFiltersManager: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filtersData: String
    let initialQuery: String

    @State private var filters: [ClipboardSavedFilter] = []
    @State private var newFilterName = ""
    @State private var newFilterQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Saved Filters")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button("Done") {
                    saveFilters()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            GroupBox("Built In") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ClipboardSavedFilter.builtIns) { filter in
                        LabeledContent(filter.name) {
                            Text(filter.query)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            GroupBox("Custom") {
                VStack(spacing: 10) {
                    HStack {
                        TextField("Name", text: $newFilterName)
                        TextField("Query", text: $newFilterQuery)
                        Button("Add") {
                            addFilter()
                        }
                        .disabled(!canAddFilter)
                    }

                    if filters.isEmpty {
                        ContentUnavailableView(
                            "No Saved Filters",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Save frequent searches so they are one click away.")
                        )
                        .frame(minHeight: 120)
                    } else {
                        List {
                            ForEach(filters) { filter in
                                SavedFilterRow(
                                    filter: binding(for: filter),
                                    moveUpAction: { move(filter, by: -1) },
                                    moveDownAction: { move(filter, by: 1) },
                                    deleteAction: { delete(filter) }
                                )
                            }
                        }
                        .frame(minHeight: 180)
                    }
                }
            }

            Text("Filters use the same syntax as search, including app:, type:, tag:, favorite:, after:, sync:, and size:.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 460)
        .onAppear {
            filters = ClipboardSettings.parseSavedFilters(filtersData)
            newFilterQuery = initialQuery
            newFilterName = initialQuery.isEmpty ? "" : defaultFilterName(for: initialQuery)
        }
        .onDisappear(perform: saveFilters)
    }

    private var canAddFilter: Bool {
        let name = newFilterName.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = newFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty
            && !query.isEmpty
            && !filters.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func addFilter() {
        guard canAddFilter else {
            return
        }

        filters.append(
            ClipboardSavedFilter(
                name: newFilterName,
                query: newFilterQuery
            ).normalized
        )
        newFilterName = ""
        newFilterQuery = ""
        saveFilters()
    }

    private func binding(for filter: ClipboardSavedFilter) -> Binding<ClipboardSavedFilter> {
        Binding {
            filters.first(where: { $0.id == filter.id }) ?? filter
        } set: { updatedFilter in
            guard let index = filters.firstIndex(where: { $0.id == filter.id }) else {
                return
            }
            filters[index] = updatedFilter.normalized
            saveFilters()
        }
    }

    private func move(_ filter: ClipboardSavedFilter, by offset: Int) {
        guard let sourceIndex = filters.firstIndex(where: { $0.id == filter.id }) else {
            return
        }

        let destinationIndex = sourceIndex + offset
        guard filters.indices.contains(destinationIndex) else {
            return
        }

        filters.swapAt(sourceIndex, destinationIndex)
        saveFilters()
    }

    private func delete(_ filter: ClipboardSavedFilter) {
        filters.removeAll { $0.id == filter.id }
        saveFilters()
    }

    private func saveFilters() {
        filtersData = ClipboardSettings.formattedSavedFilters(filters)
    }

    private func defaultFilterName(for query: String) -> String {
        if let builtIn = ClipboardSavedFilter.builtIns.first(where: { $0.query == query }) {
            return builtIn.name
        }

        return "Saved Search"
    }
}

private struct SavedFilterRow: View {
    @Binding var filter: ClipboardSavedFilter
    let moveUpAction: () -> Void
    let moveDownAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Name", text: $filter.name)
                .textFieldStyle(.roundedBorder)

            TextField("Query", text: $filter.query)
                .textFieldStyle(.roundedBorder)

            Button(action: moveUpAction) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Move Up")

            Button(action: moveDownAction) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Move Down")

            Button(role: .destructive, action: deleteAction) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(.vertical, 3)
    }
}

private enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case images
    case files
    case urls
    case screenshots
    case ocr
    case code
    case colors
    case documents
    case favorites
    case pinned
    case archived

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .text:
            return "Text"
        case .images:
            return "Images"
        case .files:
            return "Files"
        case .urls:
            return "URLs"
        case .screenshots:
            return "Screenshots"
        case .ocr:
            return "OCR"
        case .code:
            return "Code"
        case .colors:
            return "Colors"
        case .documents:
            return "Documents"
        case .favorites:
            return "Favorites"
        case .pinned:
            return "Pinned"
        case .archived:
            return "Archived"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all:
            return !item.isArchived
        case .text:
            return !item.isArchived && (item.type == ClipboardItemType.text
                || item.type == ClipboardItemType.rtf
                || item.type == ClipboardItemType.html
                || item.type == ClipboardItemType.rtfd
                || item.type == ClipboardItemType.json
                || item.type == ClipboardItemType.xml
                || item.type == ClipboardItemType.sourceCode
                || item.type == ClipboardItemType.tabularText
                || item.type == ClipboardItemType.contact)
        case .images:
            return !item.isArchived && item.type == ClipboardItemType.image
        case .files:
            return !item.isArchived && item.type == ClipboardItemType.file
        case .urls:
            return !item.isArchived && item.type == ClipboardItemType.url
        case .screenshots:
            return !item.isArchived && item.isScreenCapture
        case .ocr:
            return !item.isArchived && item.isOCRCapture
        case .code:
            return !item.isArchived
                && (item.type == ClipboardItemType.sourceCode
                    || item.type == ClipboardItemType.json
                    || item.type == ClipboardItemType.xml)
        case .colors:
            return !item.isArchived && item.type == ClipboardItemType.color
        case .documents:
            return !item.isArchived
                && (item.type == ClipboardItemType.pdf
                    || item.type == ClipboardItemType.rtf
                    || item.type == ClipboardItemType.rtfd
                    || item.type == ClipboardItemType.html)
        case .favorites:
            return !item.isArchived && item.isFavorite
        case .pinned:
            return !item.isArchived && item.isPinned
        case .archived:
            return item.isArchived
        }
    }
}

private struct ContentViewPreviewProvider: PreviewProvider {
    static var previews: some View {
        let monitor = ClipboardMonitor(context: PersistenceController.preview.container.viewContext)
        ContentView(
            clipboardMonitor: monitor,
            screenCaptureService: ScreenCaptureService(clipboardMonitor: monitor),
            cloudSyncMonitor: CloudSyncMonitor(
                container: PersistenceController.preview.container
            )
        )
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
