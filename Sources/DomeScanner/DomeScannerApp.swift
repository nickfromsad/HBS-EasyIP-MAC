import AppKit
import SwiftUI

@main
struct DomeScannerApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = ScannerModel()

    var body: some Scene {
        Window("Dome Scanner", id: "main") {
            ContentView()
                .environment(model)
                .task { model.start() }
        }
        .defaultSize(width: 1000, height: 520)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Search for Cameras") { Task { await model.search() } }
                    .keyboardShortcut("r")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when started as a bare binary (`swift run`) instead of from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
