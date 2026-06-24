import CoreData
import SwiftUI

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var cloudSyncMonitor: CloudSyncMonitor

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

    @State private var isConfirmingClear = false

    var body: some View {
        TabView {
            Form {
                Toggle("Move repeated items to the top", isOn: $moveDuplicatesToTop)
                Toggle("Keep favorites during cleanup", isOn: $keepFavorites)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gear")
            }

            Form {
                Stepper("Maximum items: \(maximumItemCount)", value: $maximumItemCount, in: 50...10_000, step: 50)
                Stepper("Delete after: \(retentionDescription)", value: $retentionDays, in: 0...365)
                Stepper(
                    "Maximum storage: \(maximumStorageMegabytes) MB",
                    value: $maximumStorageMegabytes,
                    in: 25...5_000,
                    step: 25
                )

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

                Section("Excluded Applications") {
                    TextEditor(text: $excludedBundleIdentifiers)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)

                    Text("Enter bundle identifiers separated by commas or new lines.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Privacy", systemImage: "hand.raised")
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
    }

    private var retentionDescription: String {
        retentionDays == 0 ? "Never" : "\(retentionDays) days"
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
        } catch {
            viewContext.rollback()
        }
    }
}
