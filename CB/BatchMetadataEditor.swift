import SwiftUI

struct BatchMetadataEditor: View {
    let items: [ClipboardItem]
    let saveAction: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var collectionName = ""
    @State private var tagsText = ""

    var body: some View {
        Form {
            Section {
                Text("\(items.count) clipboard items")
                    .foregroundStyle(.secondary)
            }

            TextField("Collection", text: $collectionName)
            TextField("Tags to add, separated by commas", text: $tagsText)

            Section {
                Text("A blank collection leaves existing collections unchanged. Tags are added without removing existing tags.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Apply") {
                    applyChanges()
                    saveAction()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
    }

    private func applyChanges() {
        let collection = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let addedTags = tagsText
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let now = Date()
        for item in items {
            if !collection.isEmpty {
                item.collectionName = collection
            }
            if !addedTags.isEmpty {
                var tags = item.tags
                for tag in addedTags where !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                    tags.append(tag)
                }
                item.tagsText = tags.joined(separator: ", ")
            }
            item.updatedAt = now
        }
    }
}
