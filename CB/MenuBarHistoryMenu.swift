import SwiftUI
import CoreData

struct MenuBarHistoryMenu: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var clipboardMonitor: ClipboardMonitor
    @ObservedObject var cloudSyncMonitor: CloudSyncMonitor

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ClipboardItem.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var items: FetchedResults<ClipboardItem>

    private var recentItems: [ClipboardItem] {
        Array(items.prefix(12))
    }

    var body: some View {
        if recentItems.isEmpty {
            Text("No Clipboard History")
                .foregroundStyle(.secondary)
        } else {
            ForEach(recentItems) { item in
                Button {
                    clipboardMonitor.copyToClipboard(item)
                } label: {
                    Label(item.menuTitle, systemImage: item.systemImageName)
                    Text(item.displayType)
                }
                .labelStyle(.titleAndIcon)
            }
        }

        Divider()

        Label(cloudSyncMonitor.state.title, systemImage: cloudSyncMonitor.state.systemImageName)

        Button(clipboardMonitor.isMonitoring ? "Pause Monitoring" : "Resume Monitoring") {
            if clipboardMonitor.isMonitoring {
                clipboardMonitor.stop()
            } else {
                clipboardMonitor.start()
            }
        }

        Button("Open Clipboard") {
            openWindow(id: "clipboard")
            NSApp.activate(ignoringOtherApps: true)
        }

        SettingsLink {
            Text("Settings...")
        }

        Divider()

        Button("Quit Clipboard Bro") {
            NSApp.terminate(nil)
        }
    }
}
