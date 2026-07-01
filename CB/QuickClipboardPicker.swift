import AppKit
import AVFoundation
import CoreData
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct QuickClipboardPicker: View {
    static let sceneID = "quick-clipboard-picker"

    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject var clipboardMonitor: ClipboardMonitor

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ClipboardItem.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var items: FetchedResults<ClipboardItem>

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var selectedFilterIdentifier = ""
    @FocusState private var searchIsFocused: Bool
    @AppStorage(ClipboardSettingKey.savedFilters)
    private var savedFiltersData = ClipboardSettings.formattedSavedFilters([])

    private var filteredItems: [ClipboardItem] {
        let query = combinedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedQuery = ClipboardSearchQuery(query)
        let values = items.filter { item in
            !item.isArchived && parsedQuery.matches(item)
        }
        return Array(values.prefix(40))
    }

    private var savedFilters: [ClipboardSavedFilter] {
        ClipboardSettings.parseSavedFilters(savedFiltersData)
    }

    private var availableFilters: [ClipboardSavedFilter] {
        ClipboardSavedFilter.builtIns + savedFilters
    }

    private var selectedFilter: ClipboardSavedFilter? {
        availableFilters.first { $0.id.uuidString == selectedFilterIdentifier }
    }

    private var combinedQuery: String {
        [selectedFilter?.query, searchText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                Menu {
                    Button("All") {
                        selectedFilterIdentifier = ""
                    }

                    if !availableFilters.isEmpty {
                        Divider()
                    }

                    Section("Built In") {
                        ForEach(ClipboardSavedFilter.builtIns) { filter in
                            Button(filter.name) {
                                selectedFilterIdentifier = filter.id.uuidString
                            }
                        }
                    }

                    if !savedFilters.isEmpty {
                        Divider()
                        Section("Saved") {
                            ForEach(savedFilters) { filter in
                                Button(filter.name) {
                                    selectedFilterIdentifier = filter.id.uuidString
                                }
                            }
                        }
                    }
                } label: {
                    Label(selectedFilter?.name ?? "All", systemImage: "line.3.horizontal.decrease.circle")
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.button)
                .fixedSize()

                TextField("Search clipboard history", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)
                    .onSubmit(copySelection)
                    .accessibilityIdentifier("quickClipboard.search")

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)

            Divider()

            if filteredItems.isEmpty {
                ContentUnavailableView.search(text: combinedQuery)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.objectID) { index, item in
                            Button {
                                selectedIndex = index
                                copySelection()
                            } label: {
                                HStack(spacing: 10) {
                                    QuickClipboardThumbnail(item: item)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.shouldProtectPreview ? "Sensitive Content" : item.displayTitle)
                                            .lineLimit(1)
                                        Text(item.displayType)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if index < 9 {
                                        Text("⌘\(index + 1)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("quickClipboard.item.\(index)")
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(index == selectedIndex ? Color.accentColor.opacity(0.18) : .clear)
                            )
                            .id(index)
                            .keyboardShortcut(
                                index < 9 ? KeyEquivalent(Character(String(index + 1))) : .return,
                                modifiers: index < 9 ? .command : [.command, .option, .shift]
                            )
                        }
                    }
                    .listStyle(.plain)
                    .onMoveCommand { direction in
                        moveSelection(direction)
                        proxy.scrollTo(selectedIndex, anchor: .center)
                    }
                }
            }

            Divider()

            HStack {
                Text("↑↓ Select")
                Text("↩ Copy")
                Text("esc Close")
                Spacer()
                Text(selectedFilter?.name ?? "\(filteredItems.count) items")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(width: 520, height: 430)
        .accessibilityIdentifier("quickClipboard.main")
        .onAppear {
            selectedIndex = 0
            searchIsFocused = true
        }
        .onChange(of: searchText) {
            selectedIndex = 0
        }
        .onChange(of: selectedFilterIdentifier) {
            selectedIndex = 0
        }
        .onExitCommand {
            dismissWindow(id: Self.sceneID)
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !filteredItems.isEmpty else {
            return
        }

        switch direction {
        case .up:
            selectedIndex = max(0, selectedIndex - 1)
        case .down:
            selectedIndex = min(filteredItems.count - 1, selectedIndex + 1)
        default:
            break
        }
    }

    private func copySelection() {
        guard filteredItems.indices.contains(selectedIndex) else {
            return
        }

        clipboardMonitor.copyToClipboard(filteredItems[selectedIndex])
        dismissWindow(id: Self.sceneID)
    }
}

private struct QuickClipboardThumbnail: View {
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
            .appendingPathComponent("ClipSnap Quick Preview \(UUID().uuidString)")
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
