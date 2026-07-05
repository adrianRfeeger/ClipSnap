//
//  CBApp.swift
//  CB
//
//  Created by Adrian Feeger on 23/6/2026.
//

import SwiftUI
import CoreData
import AppKit
import Combine

@main
struct ClipSnapApp: App {
    @NSApplicationDelegateAdaptor(ClipSnapDockMenuDelegate.self)
    private var dockMenuDelegate

    private let persistenceController: PersistenceController
    private let isUITesting: Bool
    @StateObject private var clipboardMonitor: ClipboardMonitor
    @StateObject private var cloudSyncMonitor: CloudSyncMonitor
    @StateObject private var screenCaptureService: ScreenCaptureService
    @StateObject private var localFolderAutomaticSyncController: LocalFolderAutomaticSyncController

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
        _localFolderAutomaticSyncController = StateObject(
            wrappedValue: LocalFolderAutomaticSyncController(
                context: persistenceController.container.viewContext
            )
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
                    ZStack {
                        DockMenuConfigurator(
                            delegate: dockMenuDelegate,
                            context: persistenceController.container.viewContext,
                            clipboardMonitor: clipboardMonitor,
                            cloudSyncMonitor: cloudSyncMonitor,
                            screenCaptureService: screenCaptureService
                        )

                        LocalFolderAutomaticSyncStarter(
                            controller: localFolderAutomaticSyncController
                        )
                    }
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

            ClipSnapHelpCommands()
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

        Window("ClipSnap Help", id: ClipSnapHelpView.sceneID) {
            ClipSnapHelpView()
        }
        .defaultSize(width: 680, height: 620)
    }
}

@MainActor
private final class LocalFolderAutomaticSyncController: ObservableObject {
    private let context: NSManagedObjectContext
    private var task: Task<Void, Never>?
    private var lastSyncDate: Date?

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func start() {
        guard task == nil else {
            return
        }

        task = Task { [weak self] in
            await self?.run()
        }
    }

    private func run() async {
        while !Task.isCancelled {
            await syncIfNeeded()

            do {
                try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            } catch {
                return
            }
        }
    }

    private func syncIfNeeded() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: ClipboardSettingKey.localFolderSyncEnabled),
              defaults.bool(forKey: ClipboardSettingKey.localFolderAutomaticSyncEnabled) else {
            return
        }

        let folderPath = defaults.string(forKey: ClipboardSettingKey.localFolderSyncPath) ?? ""
        guard !folderPath.isEmpty else {
            return
        }

        let storedIntervalMinutes = defaults.integer(
            forKey: ClipboardSettingKey.localFolderAutomaticSyncIntervalMinutes
        )
        let intervalMinutes = max(1, storedIntervalMinutes == 0 ? 10 : storedIntervalMinutes)
        let interval = TimeInterval(intervalMinutes * 60)
        let now = Date()
        if let lastSyncDate,
           now.timeIntervalSince(lastSyncDate) < interval {
            return
        }

        lastSyncDate = now

        let provider = ClipboardLocalFolderSyncProvider(
            folderURL: URL(fileURLWithPath: folderPath, isDirectory: true),
            descriptor: ClipboardSyncProviderDescriptor(
                id: ClipboardSyncProviderKind.localFolder.rawValue,
                kind: .localFolder,
                displayName: "Local Folder",
                capabilities: .localFolder,
                isEnabled: true
            )
        )

        do {
            _ = try await ClipboardLocalFolderSyncService.sync(
                in: context,
                provider: provider
            )
        } catch {
            context.rollback()
        }
    }
}

private struct LocalFolderAutomaticSyncStarter: View {
    @ObservedObject var controller: LocalFolderAutomaticSyncController

    var body: some View {
        Color.clear
            .onAppear {
                controller.start()
            }
    }
}

private struct ClipSnapHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("ClipSnap Help") {
                openWindow(id: ClipSnapHelpView.sceneID)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("?", modifiers: [.command])

            Divider()

            Button("Capture Help") {
                openWindow(id: ClipSnapHelpView.sceneID)
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Sync Help") {
                openWindow(id: ClipSnapHelpView.sceneID)
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}

private struct ClipSnapHelpView: View {
    static let sceneID = "clipsnap-help"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("ClipSnap Help", systemImage: "questionmark.circle")
                        .font(.largeTitle.weight(.semibold))
                    Text("Clipboard history, capture, OCR, annotation, and local sync for macOS.")
                        .foregroundStyle(.secondary)
                }

                HelpSection(
                    title: "Clipboard History",
                    systemImage: "clipboard",
                    rows: [
                        "Copy normally in any app. ClipSnap stores eligible clipboard items automatically.",
                        "Use the main window, menu bar, Dock menu, or quick picker to copy previous items back to the system clipboard.",
                        "A checkmark marks the item that is currently on the system clipboard.",
                        "Pin, favorite, archive, tag, collect, and search items to keep history manageable."
                    ]
                )

                HelpSection(
                    title: "Capture",
                    systemImage: "camera.viewfinder",
                    rows: [
                        "Use Capture from the app menu, menu bar, or Dock menu for region, window, application, and display screenshots.",
                        "Use Delayed Capture when you need time to open a menu or prepare the screen.",
                        "Use Text from Region to run OCR and save recognized text as a clipboard item.",
                        "Display Recording supports Start, Pause, Continue, Stop, and Cancel controls from the Capture menu."
                    ]
                )

                HelpSection(
                    title: "Image Editing",
                    systemImage: "pencil.tip.crop.circle",
                    rows: [
                        "Open an image item and choose Edit Image to crop, rotate, flip, redact, draw shapes, add arrows, highlight, or add text.",
                        "Annotations are editable vector objects while you are working in the editor.",
                        "Save writes the edited image back to the selected clipboard item."
                    ]
                )

                HelpSection(
                    title: "Privacy",
                    systemImage: "hand.raised",
                    rows: [
                        "Exclude apps from Settings > Privacy when their clipboard contents should not be stored.",
                        "Sensitive-content detection can reject likely secrets such as one-time codes, tokens, private keys, and payment-card values.",
                        "Sensitive previews can be concealed to reduce accidental exposure.",
                        "Archived, sensitive, and local-only items are not indexed in Spotlight."
                    ]
                )

                HelpSection(
                    title: "Sync",
                    systemImage: "folder",
                    rows: [
                        "The visible sync option is Local Folder Sync in Settings > Sync.",
                        "Choose a folder, enable Sync automatically for background updates, or use Sync Now, Export Now, and Import Now for explicit control.",
                        "Sensitive and local-only items are skipped by local folder sync."
                    ]
                )

                HelpSection(
                    title: "Apple Intelligence Suggestions",
                    systemImage: "sparkles",
                    rows: [
                        "When available, ClipSnap can suggest titles, tags, collections, and summaries.",
                        "Suggestions stay reviewable unless auto-apply is enabled in Settings > Automation.",
                        "ClipSnap falls back to local rules when Apple Intelligence is unavailable."
                    ]
                )

                HelpSection(
                    title: "Keyboard Shortcuts",
                    systemImage: "keyboard",
                    rows: [
                        "Command-Shift-V opens the Quick Clipboard picker.",
                        "Command-Shift-4 captures a region.",
                        "Command-Shift-5 captures a window.",
                        "Command-Shift-6 captures text from a region.",
                        "Command-? opens this help window."
                    ]
                )
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HelpSection: View {
    let title: String
    let systemImage: String
    let rows: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        Text(row)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .foregroundStyle(.secondary)
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
