import SwiftUI
import AppKit

struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.monitoring ? "Surveillance active" : "Surveillance en pause")
        Text("\(model.publishedCount) issue(s) publiée(s)")
        Divider()
        Button("Ouvrir Note to Issue") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Analyser maintenant") { Task { await model.scan() } }.disabled(model.busy || !model.keyConfigured)
        Button(model.monitoring ? "Mettre en pause" : "Reprendre") { model.monitoring ? model.pause() : model.start() }
            .disabled(!model.keyConfigured)
        SettingsLink { Text("Réglages…") }
        Divider()
        Text("Fermer la fenêtre garde l'app active.")
        Button("Quitter Note to Issue") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
