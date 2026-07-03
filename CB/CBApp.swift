//
//  CBApp.swift
//  CB
//
//  Created by Adrian Feeger on 23/6/2026.
//

import SwiftUI
import CoreData
import AppKit

@main
struct ClipSnapApp: App {
    @NSApplicationDelegateAdaptor(ClipSnapDockMenuDelegate.self)
    private var dockMenuDelegate

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
                .background {
                    DockMenuConfigurator(
                        delegate: dockMenuDelegate,
                        context: persistenceController.container.viewContext,
                        clipboardMonitor: clipboardMonitor,
                        cloudSyncMonitor: cloudSyncMonitor,
                        screenCaptureService: screenCaptureService
                    )
                    .frame(width: 0, height: 0)
                }
                .onAppear {
                    if !isUITesting {
                        clipboardMonitor.start()
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
        }
    }
}

private struct DockMenuConfigurator: View {
    @Environment(\.openWindow) private var openWindow

    let delegate: ClipSnapDockMenuDelegate
    let context: NSManagedObjectContext
    let clipboardMonitor: ClipboardMonitor
    let cloudSyncMonitor: CloudSyncMonitor
    let screenCaptureService: ScreenCaptureService

    var body: some View {
        Color.clear
            .onAppear(perform: configure)
            .onChange(of: clipboardMonitor.isMonitoring) { _, _ in
                configure()
            }
    }

    private func configure() {
        delegate.configure(
            context: context,
            clipboardMonitor: clipboardMonitor,
            cloudSyncMonitor: cloudSyncMonitor,
            screenCaptureService: screenCaptureService,
            openClipboard: {
                openWindow(id: "clipboard")
                NSApp.activate(ignoringOtherApps: true)
            }
        )
    }
}

@MainActor
final class ClipSnapDockMenuDelegate: NSObject, NSApplicationDelegate {
    private weak var context: NSManagedObjectContext?
    private weak var clipboardMonitor: ClipboardMonitor?
    private weak var cloudSyncMonitor: CloudSyncMonitor?
    private weak var screenCaptureService: ScreenCaptureService?
    private var openClipboard: (() -> Void)?

    func configure(
        context: NSManagedObjectContext,
        clipboardMonitor: ClipboardMonitor,
        cloudSyncMonitor: CloudSyncMonitor,
        screenCaptureService: ScreenCaptureService,
        openClipboard: @escaping () -> Void
    ) {
        self.context = context
        self.clipboardMonitor = clipboardMonitor
        self.cloudSyncMonitor = cloudSyncMonitor
        self.screenCaptureService = screenCaptureService
        self.openClipboard = openClipboard
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "ClipSnap")
        appendRecentItems(to: menu)
        menu.addItem(.separator())
        appendCaptureItems(to: menu)
        appendMonitoringItems(to: menu)
        appendAppItems(to: menu)
        return menu
    }

    private func appendRecentItems(to menu: NSMenu) {
        guard let context, let clipboardMonitor else {
            menu.addDisabledItem(title: "Clipboard Unavailable")
            return
        }

        let request = ClipboardItem.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ClipboardItem.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)
        ]
        request.predicate = NSPredicate(format: "isArchived == NO")
        request.fetchLimit = max(1, min(menuBarItemCount, 50))

        let items = (try? context.fetch(request)) ?? []
        guard !items.isEmpty else {
            menu.addDisabledItem(title: "No Clipboard History")
            return
        }

        for item in items {
            let isCurrent = clipboardMonitor.isCurrentClipboardItem(item)
            let menuItem = NSMenuItem(
                title: item.protectedMenuTitle,
                action: #selector(copyDockMenuItem(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = item.objectID.uriRepresentation()
            menuItem.image = dockIcon(for: item)
            menuItem.state = isCurrent ? .on : .off
            menuItem.toolTip = isCurrent ? "\(item.displayType) • Current Clipboard" : item.displayType
            menu.addItem(menuItem)
        }
    }

    private func appendCaptureItems(to menu: NSMenu) {
        guard let screenCaptureService else {
            return
        }

        if let errorMessage = screenCaptureService.errorMessage {
            let errorItem = menu.addDisabledItem(title: "Capture Error")
            errorItem.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Capture Error")
            menu.addDisabledItem(title: errorMessage)

            if screenCaptureService.canOpenScreenRecordingSettings {
                addItem(
                    "Open Screen Recording Settings",
                    to: menu,
                    action: #selector(openScreenRecordingSettings)
                )
            }

            addItem("Dismiss Capture Error", to: menu, action: #selector(dismissCaptureError))
            menu.addItem(.separator())
        }

        if screenCaptureService.isCapturing || screenCaptureService.statusText != nil {
            let statusItem = menu.addDisabledItem(title: captureStatusTitle)
            statusItem.image = NSImage(
                systemSymbolName: captureStatusIconName,
                accessibilityDescription: captureStatusTitle
            )

            if screenCaptureService.hasActiveRecordingSession {
                addRecordingControls(to: menu)
            }

            menu.addItem(.separator())
        }

        let captureMenu = NSMenu()
        addCaptureMode("Text from Region", mode: .ocrRegion, to: captureMenu)
        addCaptureMode("Region", mode: .region, to: captureMenu)
        addCaptureMode("Window", mode: .window, to: captureMenu)
        addCaptureMode("Application", mode: .application, to: captureMenu)
        addCaptureMode("Display", mode: .display, to: captureMenu)

        let delayedMenu = NSMenu()
        addCaptureMode("Text from Region", mode: .ocrRegion, delayed: true, to: delayedMenu)
        addCaptureMode("Region", mode: .region, delayed: true, to: delayedMenu)
        addCaptureMode("Window", mode: .window, delayed: true, to: delayedMenu)
        addCaptureMode("Application", mode: .application, delayed: true, to: delayedMenu)
        addCaptureMode("Display", mode: .display, delayed: true, to: delayedMenu)
        let delayedItem = NSMenuItem(title: "Delayed Capture", action: nil, keyEquivalent: "")
        delayedItem.submenu = delayedMenu
        captureMenu.addItem(delayedItem)

        addItem(
            "Cancel Delayed Capture",
            to: captureMenu,
            action: #selector(cancelCapture),
            isEnabled: screenCaptureService.isWaitingForDelayedCapture
        )

        captureMenu.addItem(.separator())

        let recordMenu = NSMenu()
        addItem("Start", to: recordMenu, action: #selector(startRecording), isEnabled: !screenCaptureService.isCapturing)
        addRecordingControls(to: recordMenu)
        let recordItem = NSMenuItem(title: "Record Display", action: nil, keyEquivalent: "")
        recordItem.submenu = recordMenu
        captureMenu.addItem(recordItem)

        let captureItem = NSMenuItem(title: "Capture", action: nil, keyEquivalent: "")
        captureItem.submenu = captureMenu
        menu.addItem(captureItem)
    }

    private func appendMonitoringItems(to menu: NSMenu) {
        guard let clipboardMonitor else {
            return
        }

        if clipboardMonitor.isMonitoring {
            let pauseMenu = NSMenu()
            addItem("5 Minutes", to: pauseMenu, action: #selector(pauseMonitoringFiveMinutes))
            addItem("15 Minutes", to: pauseMenu, action: #selector(pauseMonitoringFifteenMinutes))
            addItem("1 Hour", to: pauseMenu, action: #selector(pauseMonitoringOneHour))
            addItem("Until Resumed", to: pauseMenu, action: #selector(stopMonitoring))

            let pauseItem = NSMenuItem(title: "Pause Monitoring", action: nil, keyEquivalent: "")
            pauseItem.submenu = pauseMenu
            menu.addItem(pauseItem)
        } else {
            addItem("Resume Monitoring", to: menu, action: #selector(resumeMonitoring))
        }

        if let pausedUntil = clipboardMonitor.pausedUntil {
            menu.addDisabledItem(
                title: "Paused until \(pausedUntil.formatted(date: .omitted, time: .shortened))"
            )
        }
    }

    private func appendAppItems(to menu: NSMenu) {
        menu.addItem(.separator())
        addItem("Open Clipboard", to: menu, action: #selector(openClipboardWindow))
        addItem("Settings...", to: menu, action: #selector(openSettings))
    }

    private func addCaptureMode(
        _ title: String,
        mode: ScreenCaptureMode,
        delayed: Bool = false,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(
            title: title,
            action: #selector(startCapture(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = DockCaptureRequest(mode: mode, delayed: delayed)
        item.isEnabled = !(screenCaptureService?.isCapturing ?? true)
        menu.addItem(item)
    }

    private func addRecordingControls(to menu: NSMenu) {
        guard let screenCaptureService else {
            return
        }

        addItem(
            "Pause",
            to: menu,
            action: #selector(pauseRecording),
            isEnabled: screenCaptureService.isRecording && !screenCaptureService.isRecordingPaused
        )
        addItem(
            "Continue",
            to: menu,
            action: #selector(resumeRecording),
            isEnabled: screenCaptureService.isRecordingPaused
        )
        addItem(
            "Stop",
            to: menu,
            action: #selector(stopRecording),
            isEnabled: screenCaptureService.isRecording || screenCaptureService.isRecordingPaused
        )
        addItem(
            "Cancel",
            to: menu,
            action: #selector(cancelRecording),
            isEnabled: screenCaptureService.isRecording || screenCaptureService.isRecordingPaused
        )
    }

    @discardableResult
    private func addItem(
        _ title: String,
        to menu: NSMenu,
        action: Selector,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        menu.addItem(item)
        return item
    }

    private var menuBarItemCount: Int {
        if let configuredValue = UserDefaults.standard.object(forKey: ClipboardSettingKey.menuBarItemCount) as? Int {
            return configuredValue
        }
        return ClipboardSettings.defaults.menuBarItemCount
    }

    private var captureStatusTitle: String {
        guard let screenCaptureService else {
            return "Capture Active"
        }
        if screenCaptureService.isRecording {
            return "Recording \(formatElapsed(screenCaptureService.recordingElapsed(at: Date())))"
        }
        if screenCaptureService.isRecordingPaused {
            return "Paused \(formatElapsed(screenCaptureService.recordingElapsed(at: Date())))"
        }
        return screenCaptureService.statusText ?? "Capture Active"
    }

    private var captureStatusIconName: String {
        guard let screenCaptureService else {
            return "camera.viewfinder"
        }
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

    private func dockIcon(for item: ClipboardItem) -> NSImage? {
        let symbolName: String
        switch item.type {
        case ClipboardItemType.image:
            symbolName = "photo"
        case ClipboardItemType.url:
            symbolName = "link"
        case ClipboardItemType.html:
            symbolName = "chevron.left.forwardslash.chevron.right"
        case ClipboardItemType.video:
            symbolName = "film"
        case ClipboardItemType.audio:
            symbolName = "waveform"
        case ClipboardItemType.file:
            symbolName = "doc"
        default:
            symbolName = "text.alignleft"
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: item.displayType)
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    @objc private func copyDockMenuItem(_ sender: NSMenuItem) {
        guard let context,
              let clipboardMonitor,
              let url = sender.representedObject as? URL,
              let objectID = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
              let item = try? context.existingObject(with: objectID) as? ClipboardItem else {
            return
        }
        clipboardMonitor.copyToClipboard(item)
    }

    @objc private func startCapture(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? DockCaptureRequest else {
            return
        }
        screenCaptureService?.capture(request.mode, delayed: request.delayed)
    }

    @objc private func cancelCapture() {
        screenCaptureService?.cancelCapture()
    }

    @objc private func startRecording() {
        screenCaptureService?.capture(.recording)
    }

    @objc private func pauseRecording() {
        screenCaptureService?.pauseRecording()
    }

    @objc private func resumeRecording() {
        screenCaptureService?.resumeRecording()
    }

    @objc private func stopRecording() {
        screenCaptureService?.stopRecording()
    }

    @objc private func cancelRecording() {
        screenCaptureService?.cancelRecording()
    }

    @objc private func openScreenRecordingSettings() {
        screenCaptureService?.openScreenRecordingSettings()
    }

    @objc private func dismissCaptureError() {
        screenCaptureService?.errorMessage = nil
    }

    @objc private func pauseMonitoringFiveMinutes() {
        clipboardMonitor?.pause(for: 5 * 60)
    }

    @objc private func pauseMonitoringFifteenMinutes() {
        clipboardMonitor?.pause(for: 15 * 60)
    }

    @objc private func pauseMonitoringOneHour() {
        clipboardMonitor?.pause(for: 60 * 60)
    }

    @objc private func stopMonitoring() {
        clipboardMonitor?.stop()
    }

    @objc private func resumeMonitoring() {
        clipboardMonitor?.start()
    }

    @objc private func openClipboardWindow() {
        openClipboard?()
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}

private final class DockCaptureRequest: NSObject {
    let mode: ScreenCaptureMode
    let delayed: Bool

    init(mode: ScreenCaptureMode, delayed: Bool) {
        self.mode = mode
        self.delayed = delayed
    }
}

private extension NSMenu {
    @discardableResult
    func addDisabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
        return item
    }
}
