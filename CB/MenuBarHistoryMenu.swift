import SwiftUI
import CoreData

struct MenuBarHistoryMenu: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var clipboardMonitor: ClipboardMonitor
    @ObservedObject var cloudSyncMonitor: CloudSyncMonitor
    @ObservedObject var screenCaptureService: ScreenCaptureService
    @AppStorage(ClipboardSettingKey.menuBarItemCount)
    private var menuBarItemCount = ClipboardSettings.defaults.menuBarItemCount

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ClipboardItem.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var items: FetchedResults<ClipboardItem>

    private var recentItems: [ClipboardItem] {
        Array(items.filter { !$0.isArchived }.prefix(max(1, min(menuBarItemCount, 50))))
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
            .disabled(screenCaptureService.isCapturing)

            Button("Region") {
                screenCaptureService.capture(.region)
            }
            .disabled(screenCaptureService.isCapturing)

            Button("Window") {
                screenCaptureService.capture(.window)
            }
            .disabled(screenCaptureService.isCapturing)

            Button("Application") {
                screenCaptureService.capture(.application)
            }
            .disabled(screenCaptureService.isCapturing)

            Button("Display") {
                screenCaptureService.capture(.display)
            }
            .disabled(screenCaptureService.isCapturing)

            Menu("Delayed Capture") {
                Button("Text from Region") {
                    screenCaptureService.capture(.ocrRegion, delayed: true)
                }
                .disabled(screenCaptureService.isCapturing)

                Button("Region") {
                    screenCaptureService.capture(.region, delayed: true)
                }
                .disabled(screenCaptureService.isCapturing)

                Button("Window") {
                    screenCaptureService.capture(.window, delayed: true)
                }
                .disabled(screenCaptureService.isCapturing)

                Button("Application") {
                    screenCaptureService.capture(.application, delayed: true)
                }
                .disabled(screenCaptureService.isCapturing)

                Button("Display") {
                    screenCaptureService.capture(.display, delayed: true)
                }
                .disabled(screenCaptureService.isCapturing)
            }

            Button("Cancel Delayed Capture") {
                screenCaptureService.cancelCapture()
            }
            .disabled(!screenCaptureService.isWaitingForDelayedCapture)

            Divider()

            Button("Record Display") {
                screenCaptureService.capture(.recording)
            }
            .disabled(screenCaptureService.isCapturing)

            Button("Pause Recording") {
                screenCaptureService.pauseRecording()
            }
            .disabled(!screenCaptureService.isRecording || screenCaptureService.isRecordingPaused)

            Button("Continue Recording") {
                screenCaptureService.resumeRecording()
            }
            .disabled(!screenCaptureService.isRecordingPaused)

            Button("Stop Recording") {
                screenCaptureService.stopRecording()
            }
            .disabled(!screenCaptureService.isRecording && !screenCaptureService.isRecordingPaused)

            Button("Cancel Recording") {
                screenCaptureService.cancelRecording()
            }
            .disabled(!screenCaptureService.isRecording && !screenCaptureService.isRecordingPaused)
        }

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

        Button("Quit ClipSnap") {
            NSApp.terminate(nil)
        }
    }
}
