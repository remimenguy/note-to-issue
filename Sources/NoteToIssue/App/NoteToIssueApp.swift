import SwiftUI
import AppKit
import Darwin

@main
struct NoteToIssueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    init() { umask(0o077) }

    var body: some Scene {
        Window("Note to Issue", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 730)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Analyser maintenant") { Task { await model.scan() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.busy || !model.keyConfigured)
            }
        }
        Settings { SettingsView(model: model) }
        MenuBarExtra("Note to Issue", systemImage: model.monitoring ? "note.text.badge.plus" : "note.text") {
            MenuView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
