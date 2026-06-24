//
//  CBApp.swift
//  CB
//
//  Created by Adrian Feeger on 23/6/2026.
//

import SwiftUI
import CoreData

@main
struct ClipboardBroApp: App {
    private let persistenceController: PersistenceController
    @StateObject private var clipboardMonitor: ClipboardMonitor
    @StateObject private var cloudSyncMonitor: CloudSyncMonitor

    init() {
        let persistenceController = PersistenceController.shared
        self.persistenceController = persistenceController
        _clipboardMonitor = StateObject(
            wrappedValue: ClipboardMonitor(context: persistenceController.container.viewContext)
        )
        _cloudSyncMonitor = StateObject(
            wrappedValue: CloudSyncMonitor(container: persistenceController.container)
        )
    }

    var body: some Scene {
        WindowGroup("Clipboard Bro", id: "clipboard") {
            ContentView(clipboardMonitor: clipboardMonitor)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    clipboardMonitor.start()
                    cloudSyncMonitor.start()
                }
        }

        MenuBarExtra("Clipboard Bro", systemImage: "clipboard") {
            MenuBarHistoryMenu(
                clipboardMonitor: clipboardMonitor,
                cloudSyncMonitor: cloudSyncMonitor
            )
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    clipboardMonitor.start()
                    cloudSyncMonitor.start()
                }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(cloudSyncMonitor: cloudSyncMonitor)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    cloudSyncMonitor.start()
                }
        }
    }
}
