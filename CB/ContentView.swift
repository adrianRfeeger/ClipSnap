import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var clipboardMonitor: ClipboardMonitor

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
    @State private var searchText = ""
    @State private var selectedFilter = ClipboardFilter.all
    @State private var isDropTargeted = false

    private var filteredItems: [ClipboardItem] {
        items.filter { item in
            selectedFilter.matches(item)
                && matchesSearch(item)
        }
    }

    private var selectedItem: ClipboardItem? {
        guard let selectedItemIdentifier else {
            return nil
        }

        return items.first { $0.selectionIdentifier == selectedItemIdentifier }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItemIdentifier) {
                ForEach(filteredItems) { item in
                    ClipboardRow(item: item)
                        .contentShape(Rectangle())
                        .tag(item.selectionIdentifier)
                        .onTapGesture {
                            selectedItemIdentifier = item.selectionIdentifier
                        }
                        .onDrag {
                            ClipboardDragDropSupport.itemProvider(for: item)
                        } preview: {
                            Label(item.menuTitle, systemImage: item.systemImageName)
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

                            Divider()

                            Button("Delete", role: .destructive) {
                                delete(item)
                            }
                        }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle("Clipboard")
            .searchable(text: $searchText, placement: .sidebar)
            .toolbar {
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
                    deleteAction: {
                        delete(selectedItem)
                    }
                )
                .id(selectedItem.selectionIdentifier)
            } else {
                ContentUnavailableView(
                    "No Clipboard Item Selected",
                    systemImage: "clipboard",
                    description: Text("Copy text, images, URLs, files, or rich content to start collecting history.")
                )
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .padding(8)
                    .allowsHitTesting(false)
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
    }

    private func matchesSearch(_ item: ClipboardItem) -> Bool {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else {
            return true
        }

        return [
            item.plainText,
            item.previewText,
            item.utiType,
            item.sourceApp,
            item.displayType
        ]
        .compactMap { $0 }
        .contains { $0.localizedCaseInsensitiveContains(trimmedSearch) }
    }

    private func toggle(_ keyPath: ReferenceWritableKeyPath<ClipboardItem, Bool>, on item: ClipboardItem) {
        item[keyPath: keyPath].toggle()
        item.updatedAt = Date()
        saveContext()
    }

    private func delete(_ item: ClipboardItem) {
        if selectedItemIdentifier == item.selectionIdentifier {
            selectedItemIdentifier = nil
        }

        viewContext.delete(item)
        saveContext()
    }

    private func deleteItems(offsets: IndexSet) {
        offsets.map { filteredItems[$0] }.forEach(delete)
    }

    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            NSLog("Failed to save clipboard changes: \(error.localizedDescription)")
        }
    }
}

private extension ClipboardItem {
    var selectionIdentifier: String {
        id?.uuidString ?? objectID.uriRepresentation().absoluteString
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
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
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
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
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            metadata
        }
        .padding(24)
        .onDrag {
            ClipboardDragDropSupport.itemProvider(for: item)
        } preview: {
            Label(item.menuTitle, systemImage: item.systemImageName)
                .padding(8)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .navigationTitle(item.displayType)
        .toolbar {
            ToolbarItemGroup {
                Button(action: copyAction) {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Button(action: pinAction) {
                    Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
                }

                Button(action: favoriteAction) {
                    Label(item.isFavorite ? "Unfavorite" : "Favorite", systemImage: item.isFavorite ? "star.slash" : "star")
                }

                Button(role: .destructive, action: deleteAction) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.displayTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(3)

            if let createdAt = item.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .standard))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.type {
        case ClipboardItemType.image:
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Image Unavailable", systemImage: "photo")
            }
        case ClipboardItemType.text,
            ClipboardItemType.url,
            ClipboardItemType.file,
            ClipboardItemType.json,
            ClipboardItemType.xml,
            ClipboardItemType.sourceCode,
            ClipboardItemType.tabularText,
            ClipboardItemType.contact,
            ClipboardItemType.color:
            ScrollView {
                Text(item.plainText ?? item.previewText ?? "")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case ClipboardItemType.rtf:
            if let rawData = item.rawData {
                RichClipboardPreview(data: rawData, documentType: .rtf)
            } else {
                ContentUnavailableView("Rich Text Unavailable", systemImage: "doc.richtext")
            }
        case ClipboardItemType.rtfd:
            if let rawData = item.rawData {
                RichClipboardPreview(data: rawData, documentType: .rtfd)
            } else {
                ContentUnavailableView("RTFD Unavailable", systemImage: "doc.richtext")
            }
        case ClipboardItemType.html:
            if let rawData = item.rawData {
                RichClipboardPreview(data: rawData, documentType: .html)
            } else {
                ContentUnavailableView("HTML Unavailable", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        case ClipboardItemType.pdf:
            if let rawData = item.rawData {
                PDFClipboardPreview(data: rawData)
            } else {
                ContentUnavailableView("PDF Unavailable", systemImage: "doc.fill")
            }
        case ClipboardItemType.audio,
            ClipboardItemType.video,
            ClipboardItemType.archive,
            ClipboardItemType.data:
            ContentUnavailableView(
                item.displayType,
                systemImage: "doc",
                description: Text(item.utiType ?? "Stored binary pasteboard data")
            )
        default:
            ContentUnavailableView(
                "No Preview",
                systemImage: "questionmark.square",
                description: Text(item.utiType ?? "Unknown pasteboard format")
            )
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
    case favorites
    case pinned

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
        case .favorites:
            return "Favorites"
        case .pinned:
            return "Pinned"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return item.type == ClipboardItemType.text
                || item.type == ClipboardItemType.rtf
                || item.type == ClipboardItemType.html
                || item.type == ClipboardItemType.rtfd
                || item.type == ClipboardItemType.json
                || item.type == ClipboardItemType.xml
                || item.type == ClipboardItemType.sourceCode
                || item.type == ClipboardItemType.tabularText
                || item.type == ClipboardItemType.contact
        case .images:
            return item.type == ClipboardItemType.image
        case .files:
            return item.type == ClipboardItemType.file
        case .urls:
            return item.type == ClipboardItemType.url
        case .favorites:
            return item.isFavorite
        case .pinned:
            return item.isPinned
        }
    }
}

private struct ContentViewPreviewProvider: PreviewProvider {
    static var previews: some View {
        ContentView(clipboardMonitor: ClipboardMonitor(context: PersistenceController.preview.container.viewContext))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
