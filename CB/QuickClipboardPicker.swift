import CoreData
import SwiftUI

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
    @FocusState private var searchIsFocused: Bool

    private var filteredItems: [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedQuery = ClipboardSearchQuery(query)
        let values = items.filter { item in
            !item.isArchived && parsedQuery.matches(item)
        }
        return Array(values.prefix(40))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

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
                ContentUnavailableView.search(text: searchText)
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
                                    Image(systemName: item.systemImageName)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)

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
                Text("\(filteredItems.count) items")
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
