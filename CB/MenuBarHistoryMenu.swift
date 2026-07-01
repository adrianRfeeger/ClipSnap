import AppKit
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
                    Label {
                        Text(item.protectedMenuTitle)
                    } icon: {
                        MenuBarClipboardItemIcon(item: item)
                    }
                    Text(item.displayType)
                }
                .labelStyle(.titleAndIcon)
            }
        }

        Divider()

        if let errorMessage = screenCaptureService.errorMessage {
            Label("Capture Error", systemImage: "exclamationmark.triangle")
            Text(errorMessage)
                .foregroundStyle(.secondary)

            if screenCaptureService.canOpenScreenRecordingSettings {
                Button("Open Screen Recording Settings") {
                    screenCaptureService.openScreenRecordingSettings()
                }
            }

            Button("Dismiss Capture Error") {
                screenCaptureService.errorMessage = nil
            }

            Divider()
        }

        if screenCaptureService.isCapturing || screenCaptureService.statusText != nil {
            MenuBarCaptureStatus(screenCaptureService: screenCaptureService)

            if screenCaptureService.hasActiveRecordingSession {
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

            Divider()
        }

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

private struct MenuBarCaptureStatus: View {
    @ObservedObject var screenCaptureService: ScreenCaptureService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Label(statusTitle(at: context.date), systemImage: statusIconName)
                .foregroundStyle(.secondary)
        }
    }

    private var statusIconName: String {
        if screenCaptureService.isRecording {
            return "record.circle"
        }
        if screenCaptureService.isRecordingPaused {
            return "pause.circle"
        }
        if screenCaptureService.isWaitingForDelayedCapture {
            return "timer"
        }
        return "camera.viewfinder"
    }

    private func statusTitle(at date: Date) -> String {
        if screenCaptureService.isRecording {
            return "Recording \(formatElapsed(screenCaptureService.recordingElapsed(at: date)))"
        }
        if screenCaptureService.isRecordingPaused {
            return "Paused \(formatElapsed(screenCaptureService.recordingElapsed(at: date)))"
        }
        return screenCaptureService.statusText ?? "Capture Active"
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct MenuBarClipboardItemIcon: View {
    @ObservedObject var item: ClipboardItem

    var body: some View {
        if item.shouldProtectPreview {
            Image(systemName: "eye.slash.fill")
        } else if let image = thumbnailImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: item.systemImageName)
        }
    }

    private var thumbnailImage: NSImage? {
        guard item.type == ClipboardItemType.image else {
            return nil
        }

        if let thumbnailData = item.thumbnailData,
           let image = NSImage(data: thumbnailData) {
            return image
        }

        return item.image
    }
}
