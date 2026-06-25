import SwiftUI
import CoreData

struct MenuBarHistoryMenu: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var clipboardMonitor: ClipboardMonitor
    @ObservedObject var cloudSyncMonitor: CloudSyncMonitor
    @ObservedObject var screenCaptureService: ScreenCaptureService

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ClipboardItem.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var items: FetchedResults<ClipboardItem>

    private var recentItems: [ClipboardItem] {
        Array(items.filter { !$0.isArchived }.prefix(12))
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
                    Label(item.protectedMenuTitle, systemImage: item.systemImageName)
                    Text(item.displayType)
                }
                .labelStyle(.titleAndIcon)
            }
        }

        Divider()

        Menu("Capture") {
            Button("Text from Region") {
                screenCaptureService.capture(.ocrRegion)
            }

            Button("Region") {
                screenCaptureService.capture(.region)
            }

            Button("Window") {
                screenCaptureService.capture(.window)
            }

            Button("Application") {
                screenCaptureService.capture(.application)
            }

            Button("Display") {
                screenCaptureService.capture(.display)
            }
        }
        .disabled(screenCaptureService.isCapturing)

        Label(cloudSyncMonitor.state.title, systemImage: cloudSyncMonitor.state.systemImageName)

        if clipboardMonitor.isMonitoring {
            Menu("Pause Monitoring") {
                Button("5 Minutes") {
                    clipboardMonitor.pause(for: 5 * 60)
                }
                Button("15 Minutes") {
                    clipboardMonitor.pause(for: 15 * 60)
                }
                Button("1 Hour") {
                    clipboardMonitor.pause(for: 60 * 60)
                }
                Button("Until Resumed") {
                    clipboardMonitor.stop()
                }
            }
        } else {
            Button("Resume Monitoring") {
                clipboardMonitor.start()
            }
        }

        if let pausedUntil = clipboardMonitor.pausedUntil {
            Text("Paused until \(pausedUntil.formatted(date: .omitted, time: .shortened))")
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
