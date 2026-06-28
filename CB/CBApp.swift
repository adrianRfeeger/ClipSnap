//
//  CBApp.swift
//  CB
//
//  Created by Adrian Feeger on 23/6/2026.
//

import SwiftUI
import CoreData

@main
struct ClipSnapApp: App {
    private let persistenceController: PersistenceController
    private let isUITesting: Bool
    @StateObject private var clipboardMonitor: ClipboardMonitor
    @StateObject private var cloudSyncMonitor: CloudSyncMonitor
    @StateObject private var screenCaptureService: ScreenCaptureService

    init() {
        let isUITesting = AppLaunchConfiguration.isUITesting
        self.isUITesting = isUITesting
        let persistenceController = isUITesting
            ? PersistenceController(inMemory: true)
            : PersistenceController.shared
        self.persistenceController = persistenceController
        if isUITesting {
            AppLaunchConfiguration.seedUITestData(
                in: persistenceController.container.viewContext
            )
        }
        let clipboardMonitor = ClipboardMonitor(context: persistenceController.container.viewContext)
        _clipboardMonitor = StateObject(wrappedValue: clipboardMonitor)
        _cloudSyncMonitor = StateObject(
            wrappedValue: CloudSyncMonitor(container: persistenceController.container)
        )
        _screenCaptureService = StateObject(
            wrappedValue: ScreenCaptureService(clipboardMonitor: clipboardMonitor)
        )
    }

    var body: some Scene {
        WindowGroup("ClipSnap", id: "clipboard") {
            ContentView(
                clipboardMonitor: clipboardMonitor,
                screenCaptureService: screenCaptureService,
                cloudSyncMonitor: cloudSyncMonitor
            )
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    if !isUITesting {
                        clipboardMonitor.start()
                        cloudSyncMonitor.start()
                    }
                }
        }
        .commands {
            CommandMenu("Capture") {
                Button("Capture Text from Region") {
                    screenCaptureService.capture(.ocrRegion)
                }
                .keyboardShortcut("6", modifiers: [.command, .shift])
                .disabled(screenCaptureService.isCapturing)

                Button("Capture Region") {
                    screenCaptureService.capture(.region)
                }
                .keyboardShortcut("4", modifiers: [.command, .shift])
                .disabled(screenCaptureService.isCapturing)

                Button("Capture Window") {
                    screenCaptureService.capture(.window)
                }
                .keyboardShortcut("5", modifiers: [.command, .shift])
                .disabled(screenCaptureService.isCapturing)

                Button("Capture Application") {
                    screenCaptureService.capture(.application)
                }
                .disabled(screenCaptureService.isCapturing)

                Button("Capture Display") {
                    screenCaptureService.capture(.display)
                }
                .disabled(screenCaptureService.isCapturing)

                Menu("Delayed Capture") {
                    Button("Capture Text from Region") {
                        screenCaptureService.capture(.ocrRegion, delayed: true)
                    }
                    .disabled(screenCaptureService.isCapturing)

                    Button("Capture Region") {
                        screenCaptureService.capture(.region, delayed: true)
                    }
                    .disabled(screenCaptureService.isCapturing)

                    Button("Capture Window") {
                        screenCaptureService.capture(.window, delayed: true)
                    }
                    .disabled(screenCaptureService.isCapturing)

                    Button("Capture Application") {
                        screenCaptureService.capture(.application, delayed: true)
                    }
                    .disabled(screenCaptureService.isCapturing)

                    Button("Capture Display") {
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
        }

        MenuBarExtra("ClipSnap", systemImage: "clipboard") {
            MenuBarHistoryMenu(
                clipboardMonitor: clipboardMonitor,
                cloudSyncMonitor: cloudSyncMonitor,
                screenCaptureService: screenCaptureService
            )
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    if !isUITesting {
                        clipboardMonitor.start()
                        cloudSyncMonitor.start()
                    }
                }
        }
        .menuBarExtraStyle(.menu)

        UtilityWindow("Quick Clipboard", id: QuickClipboardPicker.sceneID) {
            QuickClipboardPicker(clipboardMonitor: clipboardMonitor)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(
                cloudSyncMonitor: cloudSyncMonitor,
                screenCaptureService: screenCaptureService
            )
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    if !isUITesting {
                        cloudSyncMonitor.start()
                    }
                }
        }
    }
}
