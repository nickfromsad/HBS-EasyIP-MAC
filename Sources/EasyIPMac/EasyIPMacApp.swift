import AppKit
import SwiftUI

@main
struct EasyIPMacApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = ScannerModel()

    var body: some Scene {
        Window("HBS // EasyIP MAC", id: "main") {
            ContentView()
                .environment(model)
                .task {
                    appDelegate.model = model
                    model.start()
                }
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Search for Cameras") { Task { await model.search() } }
                    .keyboardShortcut("r")
            }
            CommandGroup(replacing: .help) {
                Link("HBS // EasyIP MAC Documentation", destination: HBS.helpURL)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: ScannerModel?

    /// Removes extra IP addresses added by "Join Subnet" (asks for the password once).
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let model, !model.aliases.isEmpty {
            try? model.removeAliases(model.aliases)
        }
        return .terminateNow
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when started as a bare binary (`swift run`) instead of from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
