import AppKit
import CoreData
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
    @State private var imageEditingItem: ClipboardItem?
    @State private var exportErrorMessage: String?

    private var filteredItems: [ClipboardItem] {
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

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItemIdentifiers) {
                ForEach(filteredItems) { item in
                    ClipboardRow(
                        item: item,
                        highlightedTerms: ClipboardSearchQuery(searchText).terms
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
            }
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("Capture Text from Region") {
                            screenCaptureService.capture(.ocrRegion)
                        }

                        Button("Capture Region") {
                            screenCaptureService.capture(.region)
                        }

                        Button("Capture Window") {
                            screenCaptureService.capture(.window)
                        }

                        Button("Capture Application") {
                            screenCaptureService.capture(.application)
                        }

                        Button("Capture Display") {
                            screenCaptureService.capture(.display)
                        }

                        Divider()

                        Button("Record Display") {
                            screenCaptureService.capture(.recording)
                        }
                    } label: {
                        Label("Capture", systemImage: "camera.viewfinder")
                    }
                    .accessibilityIdentifier("clipboard.capture.menu")
                    .disabled(screenCaptureService.isCapturing)
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
            }
        } detail: {
            if let selectedItem {
                ClipboardDetailView(
                    item: selectedItem,
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
                      let statusText = screenCaptureService.statusText {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(statusText)
                    if screenCaptureService.isRecording || screenCaptureService.isRecordingPaused {
                        HStack(spacing: 8) {
                            Button(screenCaptureService.isRecordingPaused ? "Continue" : "Pause") {
                                if screenCaptureService.isRecordingPaused {
                                    screenCaptureService.resumeRecording()
                                } else {
                                    screenCaptureService.pauseRecording()
                                }
                            }

                            Button("Stop") {
                                screenCaptureService.stopRecording()
                            }
                        }
                    } else {
                        Button("Cancel") {
                            screenCaptureService.cancelCapture()
                        }
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)

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

    private var iconName: String {
        item.systemImageName
    }
}

private struct ClipboardDetailView: View {
    @ObservedObject var item: ClipboardItem
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
    let deleteAction: () -> Void
    @AppStorage("showsClipboardItemMetadata")
    private var showsItemMetadata = true
    @State private var revealsSensitiveContent = false

    var body: some View {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ClipboardItemPreview(
                    item: item,
                    saveTextAction: saveTextAction,
                    recognizeTextAction: recognizeTextAction,
                    editImageAction: editImageAction
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if showsItemMetadata {
                Divider()
                metadata
            }
        }
        .padding(24)
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
                "Custom title",
                text: Binding(
                    get: { item.customTitle ?? "" },
                    set: { item.customTitle = $0.isEmpty ? nil : $0 }
                )
            )
                .font(.title2)
                .fontWeight(.semibold)
                .textFieldStyle(.plain)
                .onSubmit(saveMetadataAction)

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
        }
        .font(.caption)
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
